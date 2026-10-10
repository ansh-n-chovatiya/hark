import Foundation
import HarkCore

enum ModelCatalogError: LocalizedError {
    case keyRefused, noList, unreachable(String), empty

    var errorDescription: String? {
        switch self {
        case .keyRefused: "The service did not accept this key. Check that it is copied in full."
        case .noList: "This address does not list its models. Type the model name instead."
        case .unreachable(let host): "Hark could not reach \(host). Check the address and your connection."
        case .empty: "The service listed no models that can chat. Type the model name instead."
        }
    }
}

/// Asks a service which models it offers. The key goes only to the address the user chose, the same
/// place their commands go, and nothing about the user's Mac is sent.
enum ModelCatalog {
    static func models(address: String, key: String) async throws -> [String] {
        let base = address.hasSuffix("/") ? String(address.dropLast()) : address
        guard let url = URL(string: base + "/models") else { throw ModelCatalogError.noList }
        var request = URLRequest(url: url, timeoutInterval: 8)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ModelCatalogError.unreachable(url.host() ?? "the service")
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401, 403: throw ModelCatalogError.keyRefused
        default: throw ModelCatalogError.noList
        }
        let names = ModelList.parse(data)
        guard !names.isEmpty else { throw ModelCatalogError.empty }
        return names
    }
}
