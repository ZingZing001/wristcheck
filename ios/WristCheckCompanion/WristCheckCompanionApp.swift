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
            Form {
                Section("Mac server") {
                    TextField("http://192.168.0.193:8787", text: $client.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Test now") {
                        Task { await client.refresh() }
                    }
                }

                Section("Bridge") {
                    Button(client.isPolling ? "Stop polling" : "Start coding session") {
                        if client.isPolling {
                            client.stopPolling()
                        } else {
                            client.startPolling()
                        }
                    }

                    Text(client.message)
                        .foregroundStyle(.secondary)
                }

                if let request = client.request {
                    Section("Current request") {
                        Text(request.title).font(.headline)
                        Text(request.summary)
                        Text(request.preview)
                            .font(.system(.caption, design: .monospaced))
                    }

                    Section {
                        Button("Approve") {
                            Task { await client.decide("approved") }
                        }
                        .tint(.green)

                        Button("Deny", role: .destructive) {
                            Task { await client.decide("denied") }
                        }
                    }
                }
            }
            .navigationTitle("WristCheck")
        }
    }
}
