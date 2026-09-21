import SwiftUI

struct SyncStatusBar: View {
    let lastSync: Date?
    let pending: Int
    let isOnline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isOnline ? "Connected" : "You’re offline", systemImage: isOnline ? "wifi" : "wifi.slash")
                .font(.subheadline.weight(.semibold))
            if pending > 0 {
                Text("\(pending) changes waiting to sync")
                    .font(.subheadline)
            }
            if !isOnline {
                Text("Reconnect to load the latest information.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let lastSync {
                Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
