import Foundation
import SwiftUI
import UserNotifications

@main
struct WristCheckApp: App {
    init() {
        NotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ApprovalListView()
        }
    }
}

struct ApprovalRequest: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let preview: String
    let source: String
    let status: String
    let createdAt: String
    let expiresAt: String
}

enum ApprovalPoller {
    static var serverURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
    }

    static func nextPendingRequest(serverURL: String = serverURL) async throws -> ApprovalRequest? {
        guard let url = URL(string: "\(serverURL)/api/requests/next?watchType=apple-watch") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ApprovalRequest?.self, from: data)
    }

    static func postNotificationForNextPendingRequest() async {
        do {
            if let request = try await nextPendingRequest() {
                NotificationCoordinator.shared.postApprovalNotification(for: request)
            }
        } catch {
            print("WristCheck background poll failed: \(error.localizedDescription)")
        }
    }
}

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private let categoryIdentifier = "WRISTCHECK_APPROVAL"
    private let approveActionIdentifier = "WRISTCHECK_APPROVE"
    private let denyActionIdentifier = "WRISTCHECK_DENY"
    private let requestIDKey = "requestID"
    private let notificationLock = NSLock()
    private var notifiedRequestIDs = Set<String>()

    private override init() {}

    func configure() {
        let approveAction = UNNotificationAction(
            identifier: approveActionIdentifier,
            title: "Approve",
            options: []
        )
        let denyAction = UNNotificationAction(
            identifier: denyActionIdentifier,
            title: "Deny",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("WristCheck notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                print("WristCheck notification authorization was not granted")
            }
        }
    }

    func postApprovalNotification(for request: ApprovalRequest) {
        notificationLock.lock()
        let shouldNotify = !notifiedRequestIDs.contains(request.id)
        if shouldNotify {
            notifiedRequestIDs.insert(request.id)
        }
        notificationLock.unlock()

        guard shouldNotify else { return }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.summary
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [requestIDKey: request.id]

        let notificationRequest = UNNotificationRequest(
            identifier: "wristcheck-\(request.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(notificationRequest) { error in
            if let error {
                print("WristCheck notification failed: \(error.localizedDescription)")
            }
        }
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

        Task {
            await sendDecision(requestID: requestID, decision: decision)
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

    private func sendDecision(requestID: String, decision: String) async {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        guard let url = URL(string: "\(serverURL)/api/requests/\(requestID)/decision") else {
            print("WristCheck notification action failed: invalid server URL")
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        do {
            urlRequest.httpBody = try JSONEncoder().encode([
                "decision": decision,
                "actor": "Apple Watch notification",
                "watchType": "apple-watch"
            ])
            _ = try await URLSession.shared.data(for: urlRequest)
        } catch {
            print("WristCheck notification action failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class ApprovalClient: ObservableObject {
    @Published var request: ApprovalRequest?
    @Published var message = "Waiting for Copilot steps..."
    @AppStorage("serverURL") var serverURL = "http://127.0.0.1:8787"

    func refresh() async {
        do {
            let nextRequest = try await ApprovalPoller.nextPendingRequest(serverURL: serverURL)
            request = nextRequest
            message = request == nil ? "No pending steps" : "Pending approval"
            if let nextRequest {
                NotificationCoordinator.shared.postApprovalNotification(for: nextRequest)
            }
        } catch URLError.badURL {
            message = "Invalid server URL"
        } catch {
            message = "Cannot reach WristCheck server"
        }
    }

    func decide(_ decision: String) async {
        guard let request else { return }
        guard let url = URL(string: "\(serverURL)/api/requests/\(request.id)/decision") else { return }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try? JSONEncoder().encode([
            "decision": decision,
            "actor": "Apple Watch",
            "watchType": "apple-watch"
        ])

        do {
            _ = try await URLSession.shared.data(for: urlRequest)
            self.request = nil
            message = decision == "approved" ? "Approved" : "Denied"
        } catch {
            message = "Decision failed"
        }
    }
}

struct ApprovalListView: View {
    @StateObject private var client = ApprovalClient()
    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        if #available(watchOS 9.0, *) {
            NavigationStack {
                Group {
                    if let request = client.request {
                        PendingApprovalView(request: request, client: client)
                    } else {
                        EmptyStateView(client: client)
                    }
                }
                .navigationTitle("WristCheck")
                .toolbar {
                    NavigationLink {
                        SettingsView(client: client)
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                .task {
                    await client.refresh()
                }
                .onReceive(refreshTimer) { _ in
                    Task { await client.refresh() }
                }
                .refreshable {
                    await client.refresh()
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }

    struct SettingsView: View {
        @ObservedObject var client: ApprovalClient

        var body: some View {
            GeometryReader { geometry in
                let isCompact = geometry.size.height < 220 || geometry.size.width < 180

                Form {
                    Section("Server URL") {
                        TextField("http://192.168.1.20:8787", text: $client.serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(isCompact ? .caption2 : .caption)

                        Text(isCompact ? "Use the LAN URL from doctor." : "Use the LAN URL from `wristcheck doctor` on the Mac you want this Watch to control.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button(isCompact ? "Save & Test" : "Save & Test Connection") {
                            Task { await client.refresh() }
                        }
                        Text(client.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    struct EmptyStateView: View {
        @ObservedObject var client: ApprovalClient

        var body: some View {
            GeometryReader { geometry in
                let isCompact = geometry.size.height < 220 || geometry.size.width < 180

                List {
                    Section {
                        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                Text("Ready")
                                    .font(isCompact ? .subheadline.bold() : .headline)
                            }

                            Text(client.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(isCompact ? 1 : 2)
                                .minimumScaleFactor(0.75)

                            Text(client.serverURL)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(isCompact ? 1 : 2)
                                .truncationMode(.middle)
                        }
                    }

                    Section {
                        NavigationLink {
                            SettingsView(client: client)
                        } label: {
                            Label(isCompact ? "Change URL" : "Change Server URL", systemImage: "network")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Button(isCompact ? "Test" : "Test Connection") {
                            Task { await client.refresh() }
                        }
                    }
                }
            }
        }
    }

    struct PendingApprovalView: View {
        let request: ApprovalRequest
        @ObservedObject var client: ApprovalClient

        var body: some View {
            GeometryReader { geometry in
                let isCompact = geometry.size.height < 220 || geometry.size.width < 180

                List {
                    Section {
                        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                            Label("Approval needed", systemImage: "exclamationmark.shield.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)

                            Text(request.title)
                                .font(isCompact ? .headline : .title3.bold())
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)

                            if !request.summary.isEmpty {
                                Text(request.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(isCompact ? 2 : 3)
                            }

                            Text(request.source)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !request.preview.isEmpty {
                        Section("Preview") {
                            Text(request.preview)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(isCompact ? 4 : 8)
                        }
                    }

                    Section {
                        Button {
                            Task { await client.decide("approved") }
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                        }
                        .tint(.green)

                        Button(role: .destructive) {
                            Task { await client.decide("denied") }
                        } label: {
                            Label("Deny", systemImage: "xmark")
                        }
                    }
                }
            }
        }
    }
}
