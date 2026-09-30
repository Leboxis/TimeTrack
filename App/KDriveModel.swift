import Foundation
import Observation
import WellbeingCore

/// Reads kDrive folders over the Infomaniak API. Streaming only: media is resolved to
/// a signed URL and played in place, never written to disk by the app.
@MainActor @Observable
final class KDriveModel {
    private(set) var items: [KDriveItem] = []
    private(set) var loading = false
    var errorMessage: String?
    @ObservationIgnored private var streamCache: [Int: URL] = [:]

    @ObservationIgnored var config = KDriveConfig(
        token: UserDefaults.standard.string(forKey: "kDriveToken") ?? "",
        driveID: UserDefaults.standard.string(forKey: "kDriveDriveID") ?? "")

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func request(_ url: URL, config: KDriveConfig? = nil) async throws -> Data {
        let credentials = config ?? self.config
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KDriveError.invalidURL }
        if http.statusCode == 401 { throw KDriveError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else {
            throw KDriveError.serverError(http.statusCode, "HTTP \(http.statusCode)")
        }
        return data
    }

    /// Cheap proof the token and drive id work, without walking a folder.
    func testConnection() async -> String? {
        await testConnection(for: config)
    }

    func testConnection(for config: KDriveConfig) async -> String? {
        guard config.isComplete else { return KDriveError.invalidConfiguration.localizedDescription }
        do {
            let data = try await request(KDriveClient.driveURL(config: config), config: config)
            let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])??["name"] as? String
            return "Connecté : \(name ?? config.driveID)"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func load(directoryID: String) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        guard config.isComplete else {
            errorMessage = KDriveError.invalidConfiguration.localizedDescription
            items = []
            return
        }
        do {
            items = try await KDriveClient.listAll(config: config, directoryID: directoryID) { cursor in
                try await KDriveClient.decodePage(
                    try await self.request(KDriveClient.listURL(config: self.config, directoryID: directoryID, cursor: cursor)))
            }.sorted { left, right in
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        } catch is CancellationError {
            // Superseded by another navigation.
        } catch {
            items = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// A signed, self-authorizing URL for one file. Nothing is downloaded: the player
    /// and the image loader stream straight from kDrive. kDrive redirects the direct
    /// download route to exactly such a URL, so the direct route is tried first and
    /// the documented `temporary_url` route is the fallback.
    func streamURL(for item: KDriveItem) async throws -> URL {
        if let cached = streamCache[item.id] { return cached }
        if let resolved = try? await signedURL(from: KDriveClient.downloadURL(config: config, fileID: item.id)) {
            streamCache[item.id] = resolved
            return resolved
        }
        let resolved = try await signedURL(from: KDriveClient.temporaryURL(config: config, fileID: item.id, duration: 3600))
        streamCache[item.id] = resolved
        return resolved
    }

    /// Warms the signed URLs of the first few videos so a tap starts playing at once
    /// instead of waiting on an API round trip.
    func prewarm(_ items: [KDriveItem], limit: Int = 6) {
        for item in items.filter({ $0.mediaKind == .video }).prefix(limit) where streamCache[item.id] == nil {
            Task { [weak self] in _ = try? await self?.streamURL(for: item) }
        }
    }

    /// The download route may answer 200 with bytes. In that case it is not a URL and
    /// the caller must use `temporary_url` instead.
    private func signedURL(from url: URL) async throws -> URL {
        let (data, response) = try await raw(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(status) {
            struct Wrapper: Decodable { let data: Payload? }
            struct Payload: Decodable { let temporary_url: String? }
            if let signed = try? JSONDecoder().decode(Wrapper.self, from: data).data?.temporary_url,
               let parsed = URL(string: signed) {
                return parsed
            }
            throw KDriveError.serverError(status, "Réponse binaire : URL signée indisponible")
        }
        guard let http = response as? HTTPURLResponse else { throw KDriveError.invalidURL }
        throw KDriveError.serverError(http.statusCode, "HTTP \(http.statusCode)")
    }

    private func raw(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KDriveError.invalidURL }
        if http.statusCode == 401 { throw KDriveError.authenticationFailed }
        return (data, response)
    }

    private func fetch(_ url: URL, authorized: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        if authorized { request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw KDriveError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, "HTTP")
        }
        return data
    }
}
