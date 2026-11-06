import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var config: EnvironmentConfig
    @EnvironmentObject private var syncEngine: SyncEngine

    @StateObject private var diagnostics = DiagnosticsViewModel()
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("workplaceHapticsEnabled") private var hapticsEnabled = true
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var requestingNotifications = false
    @State private var notificationError: String?
    @State private var showSignOutConfirmation = false

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                HStack(spacing: 14) {
                    if !textSize.isAccessibilitySize { WorkplaceIcon(symbol: "person.crop.circle") }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(authStore.user?.name ?? "Your account").font(.title3.weight(.semibold))
                        Text(authStore.user?.login ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                if let activeCompanyId = authStore.activeCompanyId,
                   let company = authStore.companies.first(where: { $0.id == activeCompanyId }) {
                    Label(company.name, systemImage: "building.2").font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Sign out", role: .destructive) {
                    showSignOutConfirmation = true
                }
                .frame(minHeight: 44)
            }

            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                switch notificationStatus {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications allowed", systemImage: "bell.badge")
                    Button("Manage notifications") { openSystemSettings() }.frame(minHeight: 44)
                case .denied:
                    Label("Notifications off", systemImage: "bell.slash")
                    Button("Open notification settings") { openSystemSettings() }.frame(minHeight: 44)
                default:
                    Button { Task { await enableNotifications() } } label: {
                        HStack {
                            if requestingNotifications { ProgressView().accessibilityHidden(true) }
                            Label("Enable assignment notifications", systemImage: "bell.badge")
                        }.frame(minHeight: 44)
                    }.disabled(requestingNotifications)
                }
                if let notificationError {
                    WorkplaceNotice(title: "Notifications couldn’t be enabled", message: notificationError,
                                    symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Allow alerts for assigned work. You can change notification permissions in iPhone Settings.")
            }

            Section(header: Text("Server")) {
                LabeledContent("Workplace", value: config.baseURL?.host ?? "Not set")
                DisclosureGroup("Connection details") {
                    Text(config.baseURL?.absoluteString ?? "Not set").font(.footnote.monospaced()).textSelection(.enabled)
                    LabeledContent("Database", value: config.database).font(.footnote)
                }
            }

            Section(header: Text("Sync and support")) {
                NavigationLink("Test barcode scanner") { ScannerTestView() }
                LabeledContent("Last synced", value: diagnostics.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                LabeledContent("Waiting to sync", value: "\(diagnostics.outboxCount)").monospacedDigit()
                if syncEngine.failedOutboxCount > 0 {
                    WorkplaceNotice(title: "Saved operations need review", message: "\(syncEngine.failedOutboxCount) operations need review. Open the affected transfers and verify quantities before entering them again.", symbol: "exclamationmark.triangle")
                }
                DisclosureGroup("Technical details") {
                    LabeledContent("Sync cursor", value: "\(diagnostics.cursor)").font(.footnote.monospaced())
                    if !diagnostics.diagnosticReport.isEmpty {
                        Text(diagnostics.diagnosticReport).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink("Share diagnostic report", item: diagnostics.diagnosticReport)
                    } else {
                        Label("No recorded request failures", systemImage: "checkmark.circle").foregroundStyle(WorkplaceTheme.success)
                    }
                }
                Button("Refresh status") {
                    diagnostics.refresh()
                }
                .frame(minHeight: 44)
            }
        }
        .workplaceScreen()
        .navigationTitle("Settings")
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
        .confirmationDialog("Sign out of this workplace?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { authStore.clear() }
            Button("Cancel", role: .cancel) { }
        }
        .onReceive(syncEngine.$lastSync) { _ in
            diagnostics.refresh()
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func enableNotifications() async {
        requestingNotifications = true
        notificationError = nil
        defer { requestingNotifications = false }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
            await refreshNotificationStatus()
        } catch {
            notificationError = error.localizedDescription
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
