import SwiftUI

struct SyncStatusBar: View {
    let lastSync: Date?
    let pending: Int
    let isOnline: Bool

    var body: some View {
        HStack {
            Image(systemName: isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
            Text(isOnline ? "Online" : "Offline")
                .font(.caption)
            Spacer()
            Text("Pending: \(pending)")
                .font(.caption)
            if let lastSync {
                Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
