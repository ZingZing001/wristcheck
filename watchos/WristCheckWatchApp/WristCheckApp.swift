import SwiftUI

@main
struct WristCheckApp: App {
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

@MainActor
final class ApprovalClient: ObservableObject {
    @Published var request: ApprovalRequest?
    @Published var message = "Waiting for Copilot steps..."
    @AppStorage("serverURL") var serverURL = "http://127.0.0.1:8787"

    func refresh() async {
        guard let url = URL(string: "\(serverURL)/api/requests/next?watchType=apple-watch") else {
            message = "Invalid server URL"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            request = try JSONDecoder().decode(ApprovalRequest?.self, from: data)
            message = request == nil ? "No pending steps" : "Pending approval"
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

    var body: some View {
        NavigationStack {
            Group {
                if let request = client.request {
                    List {
                        Section("Step") {
                            Text(request.title).font(.headline)
                            Text(request.summary)
                            Text(request.source).foregroundStyle(.secondary)
                        }

                        Section("Preview") {
                            Text(request.preview.isEmpty ? "No preview provided." : request.preview)
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
                } else {
                    VStack(spacing: 8) {
                        Text(client.message)
                        Text("Set serverURL in AppStorage or companion settings to your Mac LAN URL.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
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
            .refreshable {
                await client.refresh()
            }
        }
    }

    struct SettingsView: View {
        @ObservedObject var client: ApprovalClient

        var body: some View {
            Form {
                Section("Server URL") {
                    TextField("http://192.168.1.20:8787", text: $client.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Test connection") {
                        Task { await client.refresh() }
                    }
                    Text(client.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
