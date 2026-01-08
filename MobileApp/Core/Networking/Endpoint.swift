import Foundation

struct Endpoint {
    let path: String
    let method: String
    var queryItems: [URLQueryItem] = []
    var body: Data? = nil

    func url(baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = baseURL.path + path
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url ?? baseURL.appendingPathComponent(path)
    }
}
