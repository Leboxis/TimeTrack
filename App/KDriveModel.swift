import Foundation
import Observation
import WellbeingCore

/// Reads kDrive folders over the Infomaniak API. Streaming only: a remote file is
/// fetched into the temporary directory so AVPlayer or an image loader can read it.
@MainActor @Observable
final class KDriveModel {
    private(set) var items: [KDriveItem] = []
    private(set) var loading = false
    var errorMessage: String?

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

    /// Fetches a remote file into the temporary directory. kDrive answers the download
    /// endpoint with a redirect, so following it lands on the real bytes.
    func localFile(for item: KDriveItem) async throws -> URL {
        var request = URLRequest(url: KDriveClient.downloadURL(config: config, fileID: item.id))
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw KDriveError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0,
                                          "Lecture du fichier impossible")
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "kdrive-\(item.id).\(item.name.split(separator: ".").last.map(String.init) ?? "bin")")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
