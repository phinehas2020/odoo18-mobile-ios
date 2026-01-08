import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var config: EnvironmentConfig
    @EnvironmentObject private var syncEngine: SyncEngine

    @StateObject private var diagnostics = DiagnosticsViewModel()

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Text(authStore.user?.name ?? "Unknown")
                Text(authStore.user?.login ?? "")
                if let activeCompanyId = authStore.activeCompanyId,
                   let company = authStore.companies.first(where: { $0.id == activeCompanyId }) {
                    Text("Company: \(company.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("Sign Out") {
                    authStore.clear()
                }
                .foregroundColor(.red)
            }

            Section(header: Text("Server")) {
                Text(config.baseURL?.absoluteString ?? "Not set")
                Text(config.database)
            }

            Section(header: Text("Diagnostics")) {
                Text("Last Sync: \(diagnostics.lastSync?.formatted() ?? "Never")")
                Text("Cursor: \(diagnostics.cursor)")
                Text("Outbox Pending: \(diagnostics.outboxCount)")
                if let error = diagnostics.lastError {
                    Text("Last Error: \(error.endpoint)")
                    if let log = error.logURL {
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Button("Refresh Diagnostics") {
                    diagnostics.refresh()
                }
            }
        }
        .navigationTitle("Settings")
        .onReceive(syncEngine.$lastSync) { _ in
            diagnostics.refresh()
        }
    }
}
