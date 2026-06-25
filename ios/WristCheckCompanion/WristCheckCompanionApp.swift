import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

@main
struct WristCheckCompanionApp: App {
    @StateObject private var client = CompanionClient()

    init() {
        NotificationCoordinator.shared.configure()
        BackgroundApprovalRefresh.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            CompanionView(client: client)
        }
    }
}

struct ApprovalRequest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let preview: String
    let source: String
    let status: String
    let createdAt: String
    let expiresAt: String
}

@MainActor
final class CompanionClient: ObservableObject {
    @Published var request: ApprovalRequest?
    @Published var message = "Waiting for approvals..."
    @Published var isPolling = false
    @AppStorage("serverURL") var serverURL = "http://127.0.0.1:8787"
    @AppStorage("bridgeEnabled") private var bridgeEnabled = false

    private var pollTask: Task<Void, Never>?
    private var backgroundPollTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func startPolling() {
        guard pollTask == nil else { return }
        bridgeEnabled = true
        isPolling = true
        BackgroundApprovalRefresh.shared.schedule()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        bridgeEnabled = false
        endBackgroundPollingGracePeriod()
    }

    func refresh() async {
        do {
            guard let url = URL(string: "\(serverURL)/api/requests/next?watchType=apple-watch") else {
                message = "Invalid server URL"
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let nextRequest = try JSONDecoder().decode(ApprovalRequest?.self, from: data)
            request = nextRequest
            message = nextRequest == nil ? "No pending approvals" : "Forwarded to Apple Watch"
            if let nextRequest {
                NotificationCoordinator.shared.postApprovalNotification(for: nextRequest)
            }
        } catch {
            message = "Cannot reach WristCheck server"
        }
    }

    func resumeBridgeIfNeeded() {
        if bridgeEnabled {
            startPolling()
        }
    }

    func prepareForBackground() {
        BackgroundApprovalRefresh.shared.schedule()
        guard bridgeEnabled else { return }
        startBackgroundPollingGracePeriod()
    }

    func returnToForeground() {
        endBackgroundPollingGracePeriod()
        resumeBridgeIfNeeded()
        Task { await refresh() }
    }

    func decide(_ decision: String) async {
        guard let request else { return }
        await DecisionSender.send(serverURL: serverURL, requestID: request.id, decision: decision, actor: "iPhone companion")
        self.request = nil
    }

    func pasteServerURLFromClipboard() {
        guard let clipboardValue = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardValue.isEmpty
        else {
            message = "Clipboard does not contain a server address"
            return
        }

        serverURL = normalizedServerURL(from: clipboardValue)
        message = "Server URL pasted from clipboard"
    }

    private func normalizedServerURL(from value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") {
            normalized = "http://\(normalized)"
        }

        guard var components = URLComponents(string: normalized) else {
            return normalized
        }

        if components.port == nil, components.path.isEmpty || components.path == "/" {
            components.port = 8787
        }

        return components.string ?? normalized
    }

    func copyServerURLToClipboard() {
        UIPasteboard.general.string = serverURL
        message = "Server URL copied to clipboard"
    }

    private func startBackgroundPollingGracePeriod() {
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WristCheck approval bridge") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundPollingGracePeriod()
            }
        }

        backgroundPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func endBackgroundPollingGracePeriod() {
        backgroundPollTask?.cancel()
        backgroundPollTask = nil

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}

final class BackgroundApprovalRefresh {
    static let shared = BackgroundApprovalRefresh()

    private let taskIdentifier = "com.wristcheck.WristCheckCompanion.refresh"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            self.handle(task)
        }
    }

    func schedule() {
        guard UserDefaults.standard.bool(forKey: "bridgeEnabled") else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("WristCheck background refresh scheduling failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()

        let refreshTask = Task {
            let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
            do {
                guard let url = URL(string: "\(serverURL)/api/requests/next?watchType=apple-watch") else {
                    task.setTaskCompleted(success: false)
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                if let request = try JSONDecoder().decode(ApprovalRequest?.self, from: data) {
                    NotificationCoordinator.shared.postApprovalNotification(for: request)
                }
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}

enum DecisionSender {
    static func send(serverURL: String, requestID: String, decision: String, actor: String) async {
        guard let url = URL(string: "\(serverURL)/api/requests/\(requestID)/decision") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode([
            "decision": decision,
            "actor": actor,
            "watchType": "apple-watch"
        ])

        _ = try? await URLSession.shared.data(for: request)
    }
}

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private let categoryIdentifier = "WRISTCHECK_APPROVAL"
    private let approveActionIdentifier = "WRISTCHECK_APPROVE"
    private let denyActionIdentifier = "WRISTCHECK_DENY"
    private let requestIDKey = "requestID"
    private var notifiedRequestIDs = Set<String>()

    private override init() {}

    func configure() {
        let approveAction = UNNotificationAction(identifier: approveActionIdentifier, title: "Approve", options: [])
        let denyAction = UNNotificationAction(identifier: denyActionIdentifier, title: "Deny", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("WristCheck notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func postApprovalNotification(for request: ApprovalRequest) {
        guard !notifiedRequestIDs.contains(request.id) else { return }
        notifiedRequestIDs.insert(request.id)

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.summary
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [requestIDKey: request.id]

        let notificationRequest = UNNotificationRequest(
            identifier: "wristcheck-iphone-\(request.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(notificationRequest)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard
            let requestID = response.notification.request.content.userInfo[requestIDKey] as? String,
            let decision = decision(for: response.actionIdentifier)
        else {
            completionHandler()
            return
        }

        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        Task {
            await DecisionSender.send(serverURL: serverURL, requestID: requestID, decision: decision, actor: "iPhone notification")
            completionHandler()
        }
    }

    private func decision(for actionIdentifier: String) -> String? {
        switch actionIdentifier {
        case approveActionIdentifier:
            return "approved"
        case denyActionIdentifier:
            return "denied"
        default:
            return nil
        }
    }
}

struct CompanionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var client: CompanionClient
    @State private var showsSetup = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let horizontalPadding = CompanionLayout.horizontalPadding(for: geometry.size.width)

                ScrollView {
                    LazyVStack(spacing: CompanionLayout.sectionSpacing(for: geometry.size.width)) {
                        CompanionHeroView(
                            isPolling: client.isPolling,
                            message: client.message
                        ) {
                            if client.isPolling {
                                client.stopPolling()
                            } else {
                                client.startPolling()
                            }
                        }

                        if let request = client.request {
                            RequestCard(request: request) { decision in
                                Task { await client.decide(decision) }
                            }
                        }

                        ServerSettingsCard(client: client)

                        CardSection {
                            DisclosureGroup(isExpanded: $showsSetup) {
                                VStack(alignment: .leading, spacing: 14) {
                                    SetupStep(number: 1, title: "Run the Mac server", detail: "npm start -- --host 0.0.0.0 --port 8787")
                                    SetupStep(number: 2, title: "Enter the LAN URL", detail: "Use the URL printed by wristcheck doctor.")
                                    SetupStep(number: 3, title: "Start bridge", detail: "The iPhone polls while open, keeps polling briefly after backgrounding, and schedules best-effort background checks.")
                                }
                                .padding(.top, 12)
                            } label: {
                                Label("Developer setup", systemImage: "terminal")
                                    .font(.headline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("WristCheck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await client.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh approvals")
                }
            }
            .onAppear {
                client.resumeBridgeIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    client.returnToForeground()
                case .background:
                    client.prepareForBackground()
                default:
                    break
                }
            }
        }
    }
}

enum CompanionLayout {
    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<380:
            return 12
        case ..<600:
            return 16
        default:
            return 24
        }
    }

    static func sectionSpacing(for width: CGFloat) -> CGFloat {
        width < 380 ? 12 : 16
    }
}

struct CardSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ServerSettingsCard: View {
    @ObservedObject var client: CompanionClient

    var body: some View {
        CardSection("Mac server") {
            TextField("http://192.168.0.193:8787", text: $client.serverURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                Text("Use the LAN URL from wristcheck doctor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    serverButtons
                }

                VStack {
                    serverButtons
                }
            }
        }
    }

    private var serverButtons: some View {
        Group {
            Button {
                client.copyServerURLToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                client.pasteServerURLFromClipboard()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                Task { await client.refresh() }
            } label: {
                Label("Test", systemImage: "bolt.horizontal.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct CompanionHeroView: View {
    let isPolling: Bool
    let message: String
    let toggleBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.orange.gradient)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isPolling ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(isPolling ? "Bridge active" : "Bridge paused")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isPolling ? .green : .secondary)
                    }

                    Text(isPolling ? "Ready for approvals" : "Start when coding")
                        .font(.title2.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: toggleBridge) {
                Label(
                    isPolling ? "Stop bridge" : "Start bridge",
                    systemImage: isPolling ? "pause.circle.fill" : "play.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .tint(isPolling ? .orange : .green)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct RequestCard: View {
    let request: ApprovalRequest
    let decide: (String) -> Void

    var body: some View {
        CardSection("Current approval") {
            VStack(alignment: .leading, spacing: 10) {
                Label(request.source, systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(request.title)
                    .font(.title3.bold())

                if !request.summary.isEmpty {
                    Text(request.summary)
                        .foregroundStyle(.secondary)
                }

                if !request.preview.isEmpty {
                    Text(request.preview)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(8)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    decisionButtons
                }

                VStack {
                    decisionButtons
                }
            }
        }
    }

    private var decisionButtons: some View {
        Group {
            Button(role: .destructive) {
                decide("denied")
            } label: {
                Label("Deny", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                decide("approved")
            } label: {
                Label("Approve", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
