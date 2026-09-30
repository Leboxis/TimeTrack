import Foundation
import Observation
import WellbeingCore

/// One session for the app's whole life. `KDriveModel` used to compute this per
/// request, so every call built a fresh `URLSession` — and a fresh connection pool —
/// while the previous ones were never invalidated.
private let kDriveSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
}()

/// Captures the first redirect target and stops the chain right there. A kDrive
/// `download` route answers with a 302 to a signed CDN URL: reading that target and
/// never following it is precisely what keeps the file itself out of the app.
private final class KDriveRedirectCatcher: NSObject, URLSessionTaskDelegate {
    private(set) var target: URL?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if target == nil { target = request.url }
        completionHandler(nil)
    }
}

/// Reads kDrive folders over the Infomaniak API. Streaming only: media is resolved to
/// a signed URL and played in place, never written to disk by the app.
@MainActor @Observable
final class KDriveModel {
    private(set) var items: [KDriveItem] = []
    private(set) var loading = false
    /// Distinguishes "still loading" from "loaded and genuinely empty", so opening a
    /// folder does not flash the empty state before the first response lands.
    private(set) var hasLoaded = false
    var errorMessage: String?

    @ObservationIgnored var config = KDriveConfig(
        token: UserDefaults.standard.string(forKey: "kDriveToken") ?? "",
        driveID: UserDefaults.standard.string(forKey: "kDriveDriveID") ?? "")

    /// Guards against a slow folder answering after the user has navigated on: without
    /// it, the folder they left behind wins and lands in the folder they are looking at.
    private var loadGeneration = 0

    /// The `temporary_url` envelope is a few hundred bytes of JSON. Nothing larger is
    /// ever read from a media route.
    private static let envelopeByteLimit = 8_192

    /// A response inspected without pulling its body: at most `bodyLimit` bytes are
    /// consumed and the redirect chain is stopped at the first hop.
    private struct Peek {
        let status: Int
        let redirectTarget: URL?
        let body: Data
    }

    private func request(_ url: URL, config credentials: KDriveConfig? = nil) async throws -> Data {
        let auth = credentials ?? config
        var request = URLRequest(url: url)
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await kDriveSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KDriveError.invalidURL }
        if http.statusCode == 401 { throw KDriveError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else {
            throw KDriveError.serverError(http.statusCode, "HTTP \(http.statusCode)")
        }
        return data
    }

    private func peek(_ url: URL, bodyLimit: Int) async throws -> Peek {
        let catcher = KDriveRedirectCatcher()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        // `bytes` hands back the response as soon as the headers land, and the body is
        // read only if this method iterates it. That single difference is the whole
        // point: it is what separates a zero-byte probe from a downloaded video.
        let (bytes, response) = try await kDriveSession.bytes(for: request, delegate: catcher)
        guard let http = response as? HTTPURLResponse else { throw KDriveError.invalidURL }
        if http.statusCode == 401 { throw KDriveError.authenticationFailed }
        if (300..<400).contains(http.statusCode) {
            return Peek(status: http.statusCode, redirectTarget: catcher.target, body: Data())
        }
        guard (200...299).contains(http.statusCode) else {
            throw KDriveError.serverError(http.statusCode, "HTTP \(http.statusCode)")
        }
        var body = Data()
        if bodyLimit > 0 {
            for try await byte in bytes.prefix(bodyLimit) { body.append(byte) }
        }
        return Peek(status: http.statusCode, redirectTarget: catcher.target, body: body)
    }

    /// Cheap proof the token and drive id work, without walking a folder.
    func testConnection() async -> String? {
        await testConnection(for: config)
    }

    func testConnection(for config: KDriveConfig) async -> String? {
        guard config.isComplete else { return KDriveError.invalidConfiguration.localizedDescription }
        guard let url = KDriveClient.driveURL(config: config) else {
            return KDriveError.invalidURL.localizedDescription
        }
        do {
            let data = try await request(url, config: config)
            let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])??["name"] as? String
            return "Connecté : \(name ?? config.driveID)"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The browser keeps one model for its whole life, so a token pasted in the
    /// settings after the browser was pushed has to be picked up explicitly.
    func reloadConfig() {
        config = KDriveConfig(
            token: UserDefaults.standard.string(forKey: "kDriveToken") ?? "",
            driveID: UserDefaults.standard.string(forKey: "kDriveDriveID") ?? "")
    }

    func load(directoryID: String) async {
        loadGeneration &+= 1
        let mine = loadGeneration
        loading = true
        errorMessage = nil
        // The previous folder's tiles must not stay on screen behind the new folder's
        // spinner: the view only shows its progress state while `items` is empty.
        items = []
        defer { if loadGeneration == mine { loading = false } }
        guard config.isComplete else {
            errorMessage = KDriveError.invalidConfiguration.localizedDescription
            hasLoaded = true
            return
        }
        do {
            let listed = try await KDriveClient.listAll(config: config, directoryID: directoryID) { cursor in
                guard let url = KDriveClient.listURL(config: self.config,
                                                     directoryID: directoryID,
                                                     cursor: cursor) else {
                    throw KDriveError.invalidURL
                }
                return try KDriveClient.decodePage(try await self.request(url))
            }
            guard loadGeneration == mine else { return }
            items = listed.sorted { left, right in
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        } catch is CancellationError {
            // Superseded by another navigation.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // A cancelled URLSession task reports URLError.cancelled, which is *not* a
            // CancellationError. Without this branch, a quick folder-to-folder tap
            // surfaced a connection error for a request nobody was waiting for.
        } catch {
            guard loadGeneration == mine else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if loadGeneration == mine { hasLoaded = true }
    }

    /// A signed, self-authorizing URL for one file, resolved without ever transferring
    /// the file. Two routes, and neither of them reads media bytes:
    ///
    /// 1. The `download` route, probed with a zero-byte budget. kDrive answers with a
    ///    302 whose target *is* the signed CDN URL, so the redirect is read and the
    ///    chain is abandoned there.
    /// 2. The documented `temporary_url` route, whose body is a few hundred bytes of
    ///    JSON naming the same kind of URL.
    ///
    /// The player then streams straight from kDrive. Nothing of the media ever passes
    /// through the app, whatever the size of the file.
    func streamURL(for item: KDriveItem) async throws -> URL {
        if let probe = KDriveClient.downloadURL(config: config, fileID: item.id),
           let signed = try? await redirectTarget(of: probe) {
            return signed
        }
        guard let envelope = KDriveClient.temporaryURL(config: config, fileID: item.id, duration: 3600) else {
            throw KDriveError.invalidURL
        }
        let response = try await peek(envelope, bodyLimit: Self.envelopeByteLimit)
        if let hop = response.redirectTarget { return hop }
        if let signed = KDriveClient.signedURL(in: response.body) { return signed }
        throw KDriveError.serverError(response.status, "URL signée indisponible")
    }

    private func redirectTarget(of url: URL) async throws -> URL {
        guard let target = try await peek(url, bodyLimit: 0).redirectTarget else {
            throw KDriveError.serverError(0, "aucune redirection signée")
        }
        return target
    }
}
