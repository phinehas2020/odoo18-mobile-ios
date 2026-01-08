import Foundation

final class EnvironmentConfig: ObservableObject {
    @Published var baseURL: URL? {
        didSet { save() }
    }
    @Published var database: String {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard

    init() {
        if let urlString = defaults.string(forKey: "server_url"),
           let url = URL(string: urlString) {
            baseURL = url
        } else {
            baseURL = nil
        }
        database = defaults.string(forKey: "server_db") ?? ""
    }

    private func save() {
        if let url = baseURL {
            defaults.set(url.absoluteString, forKey: "server_url")
        }
        defaults.set(database, forKey: "server_db")
    }
}
