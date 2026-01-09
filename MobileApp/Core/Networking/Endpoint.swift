import Foundation

struct Endpoint {
    let path: String
    let method: String
    var queryItems: [URLQueryItem] = []
    var body: Data? = nil

    func url(baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = baseURL.path.isEmpty ? "" : baseURL.path
        let endpointPath = path.hasPrefix("/") ? path : "/" + path
        let finalPath = basePath.hasSuffix("/") && endpointPath.hasPrefix("/") 
            ? String(basePath.dropLast()) + endpointPath 
            : basePath + endpointPath
        components?.path = finalPath
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url ?? baseURL.appendingPathComponent(path)
    }
}
