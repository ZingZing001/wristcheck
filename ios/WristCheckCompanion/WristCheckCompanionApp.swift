import SwiftUI
import UserNotifications

@main
struct WristCheckCompanionApp: App {
    @StateObject private var client = CompanionClient()
    init() {
        NotificationCoordinator.shared.configure()
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

    private var pollTask: Task<Void, Never>?

    func startPolling() {
        guard pollTask == nil else { return }
        isPolling = true
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

    func decide(_ decision: String) async {
        guard let request else { return }
        await DecisionSender.send(serverURL: serverURL, requestID: request.id, decision: decision, actor: "iPhone companion")
        self.request = nil
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
        content.body = "\(request.summary)\n\(request.preview)"
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
    @ObservedObject var client: CompanionClient

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CompanionHeroView(isPolling: client.isPolling, message: client.message)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }

                Section("Mac server") {
                    TextField("http://192.168.0.193:8787", text: $client.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)

                    HStack {
                        Label("Use the LAN URL from wristcheck doctor", systemImage: "network")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Button {
                        Task { await client.refresh() }
                    } label: {
                        Label("Test connection", systemImage: "bolt.horizontal.circle")
                    }
                }

                Section("Bridge") {
                    Button {
                        if client.isPolling {
                            client.stopPolling()
                        } else {
                            client.startPolling()
                        }
                    } label: {
                        Label(
                            client.isPolling ? "Stop bridge" : "Start bridge",
                            systemImage: client.isPolling ? "pause.circle.fill" : "play.circle.fill"
                        )
                    }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(client.isPolling ? .orange : .green)

                    Text(client.isPolling ? "The iPhone checks your Mac every 5 seconds and surfaces actionable notifications." : "Start the bridge when you begin a coding session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let request = client.request {
                    RequestCard(request: request) { decision in
                        Task { await client.decide(decision) }
                    }
                } else {
                    Section("Status") {
                        ContentUnavailableView(
                            "No approvals pending",
                            systemImage: "checkmark.seal",
                            description: Text("When Copilot or Claude asks for approval, it will appear here and as a notification.")
                        )
                    }
                }

                Section("Developer setup") {
                    SetupStep(number: 1, title: "Run the Mac server", detail: "npm start -- --host 0.0.0.0 --port 8787")
                    SetupStep(number: 2, title: "Enter the LAN URL", detail: "Use the URL printed by wristcheck doctor.")
                    SetupStep(number: 3, title: "Start bridge", detail: "Keep this app available during coding sessions.")
                }
            }
            .navigationTitle("WristCheck")
        }
    }
}

struct CompanionHeroView: View {
    let isPolling: Bool
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.orange.gradient)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isPolling ? "Bridge active" : "Ready to bridge")
                        .font(.title3.bold())
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(isPolling ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(isPolling ? "Watching for approval requests" : "Paused")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isPolling ? .green : .secondary)
            }
        }
    }
}

struct RequestCard: View {
    let request: ApprovalRequest
    let decide: (String) -> Void

    var body: some View {
        Section("Current approval") {
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

            HStack {
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
