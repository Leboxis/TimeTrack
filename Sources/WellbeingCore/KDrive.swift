import Foundation

/// Credentials for the Infomaniak kDrive API. The token is pasted by the user; the
/// reference app stores both in `@AppStorage` and this port keeps that model.
public struct KDriveConfig: Equatable {
    public let token: String
    public let driveID: String

    public init(token: String, driveID: String) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.driveID = driveID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drive ids are numeric. A pasted id carrying a space, a slash or a query marker
    /// is a paste mistake, and it used to reach `URL(string:)!` and trap. It is refused
    /// here, where the UI can turn it into a message, instead of crashing on the first
    /// folder listing.
    public var isValidDriveID: Bool {
        guard !driveID.isEmpty, driveID.count <= 20 else { return false }
        return driveID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }

    public var isComplete: Bool { !token.isEmpty && isValidDriveID }
}

public enum KDriveError: LocalizedError, Equatable {
    case invalidConfiguration, invalidURL, authenticationFailed, driveNotFound, serverError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Renseigne le jeton API et l’ID du Drive (chiffres) dans les Réglages."
        case .invalidURL:
            return "URL de requête kDrive invalide."
        case .authenticationFailed:
            return "Échec d’authentification : vérifie le jeton API Infomaniak."
        case .driveNotFound:
            return "Drive introuvable : vérifie l’ID du kDrive."
        case .serverError(let code, let message):
            return code == 0 ? "Erreur kDrive : \(message)" : "Erreur serveur (\(code)) : \(message)"
        }
    }
}

public enum KDriveMediaKind {
    case image, video, audio
}

public struct KDriveItem: Identifiable, Decodable, Hashable {
    public let id: Int
    public let name: String
    public let type: String?
    public let size: Int?
    public let mimeType: String?
    public let lastModifiedAt: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, size, mimeType = "mime_type", lastModifiedAt = "last_modified_at"
    }

    public init(id: Int, name: String, type: String? = nil, size: Int? = nil,
                mimeType: String? = nil, lastModifiedAt: Int? = nil) {
        self.id = id; self.name = name; self.type = type
        self.size = size; self.mimeType = mimeType; self.lastModifiedAt = lastModifiedAt
    }

    /// Positive evidence only. The reference treats a nil `type` as a directory in one
    /// place and as a file in another; a single browser needs one rule, and calling an
    /// unknown-type item a directory hides files.
    public var isDirectory: Bool { type == "dir" || type == "directory" }

    public var mediaKind: KDriveMediaKind? { KDriveClient.mediaKind(of: name) }
}

/// A page of listing results, with the cursor needed to ask for the next one.
public struct KDrivePage {
    public let items: [KDriveItem]
    public let hasMore: Bool
    public let cursor: String?
}

private struct KDriveAPIErrorBody: Decodable {
    let code: String?
    let description: String?
}

private struct KDriveEnvelope<T: Decodable>: Decodable {
    let result: String
    let data: T?
    let error: KDriveAPIErrorBody?
    let hasMore: Bool?
    let cursor: String?

    private enum CodingKeys: String, CodingKey {
        case result, data, error, hasMore = "has_more", cursor
    }
}

/// The `temporary_url` route answers with a small JSON envelope whose only payload is
/// the signed URL. Kept apart from the transport so it can be tested on its own.
private struct KDriveSignedURLEnvelope: Decodable {
    struct Payload: Decodable {
        let temporaryURL: String?

        private enum CodingKeys: String, CodingKey {
            case temporaryURL = "temporary_url"
        }
    }

    let data: Payload?
}

public enum KDriveClient {
    static let base = "https://api.infomaniak.com"
    static let pageLimit = 200

    /// Assembled from a path rather than a concatenated string: the path component is
    /// percent-encoded for us, so a malformed id can neither reshape the route nor
    /// produce a nil URL that something downstream would have to force-unwrap.
    private static func url(_ path: String, percentEncodedQuery query: String? = nil) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.path = path
        if let query { components.percentEncodedQuery = query }
        return components.url
    }

    public static func driveURL(config: KDriveConfig) -> URL? {
        url("/2/drive/\(config.driveID)")
    }

    public static func listURL(config: KDriveConfig, directoryID: String, cursor: String?) -> URL? {
        var query = "limit=\(pageLimit)"
        if let cursor, !cursor.isEmpty {
            // Strict encoding: URLQueryItem would leave `+` literal, and many servers
            // read `+` in a query as a space, which would corrupt an opaque cursor.
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: strictQueryAllowed) ?? cursor
            query += "&cursor=\(encoded)"
        }
        return url("/3/drive/\(config.driveID)/files/\(directoryID)/files", percentEncodedQuery: query)
    }

    private static let strictQueryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    /// Not present in the reference app: it has no download, stream or thumbnail path.
    /// The OpenAPI spec has no /3/ download route at all — download is v2, with the file
    /// id between `files` and `download`. Answers with a redirect to a signed URL.
    public static func downloadURL(config: KDriveConfig, fileID: Int) -> URL? {
        url("/2/drive/\(config.driveID)/files/\(fileID)/download")
    }

    public static func thumbnailURL(config: KDriveConfig, fileID: Int) -> URL? {
        url("/2/drive/\(config.driveID)/files/\(fileID)/thumbnail")
    }

    /// Signed alternative to `downloadURL`, used when the direct call answers with
    /// bytes rather than a redirect.
    public static func temporaryURL(config: KDriveConfig, fileID: Int, duration: Int) -> URL? {
        let clamped = max(60, min(86_400, duration))
        return url("/2/drive/\(config.driveID)/files/\(fileID)/temporary_url",
                   percentEncodedQuery: "duration=\(clamped)")
    }

    /// The signed, self-authorizing URL carried by a `temporary_url` envelope. Returns
    /// nil for anything that is not one — a media body in particular, which the caller
    /// must never mistake for a streamable URL.
    public static func signedURL(in data: Data) -> URL? {
        guard let envelope = try? JSONDecoder().decode(KDriveSignedURLEnvelope.self, from: data),
              let raw = envelope.data?.temporaryURL,
              let parsed = URL(string: raw),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return parsed
    }

    /// Credential failures also arrive inside the JSON body, so the HTTP status is not
    /// the only place a bad token shows up. Reporting those as "server error (0)" sent
    /// the user to check their Drive id instead of their token.
    private static let authenticationCodes: Set<String> = [
        "unauthorized", "unauthenticated", "forbidden", "invalid_token", "invalid_credentials", "401",
    ]

    public static func decodePage(_ data: Data) throws -> KDrivePage {
        let envelope = try JSONDecoder().decode(KDriveEnvelope<[KDriveItem]>.self, from: data)
        if envelope.result == "error", let error = envelope.error {
            if authenticationCodes.contains(error.code ?? "") {
                throw KDriveError.authenticationFailed
            }
            let detail = [error.code, error.description]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            throw KDriveError.serverError(0, detail.isEmpty ? "erreur inconnue" : detail.joined(separator: " — "))
        }
        return KDrivePage(items: envelope.data ?? [],
                          hasMore: envelope.hasMore ?? false,
                          cursor: envelope.cursor)
    }

    public static func mediaKind(of name: String) -> KDriveMediaKind? {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tif", "tiff": return .image
        case "mp4", "m4v", "mov", "mkv", "webm": return .video
        case "m4a", "mp3", "aac", "wav", "caf", "aiff", "flac": return .audio
        default: return nil
        }
    }

    /// Walks the `cursor` / `has_more` pagination. The reference loops forever when the
    /// server says `has_more` with a null cursor; this breaks instead. Pages can also
    /// overlap, so items are de-duplicated by id: a repeat would render as a second,
    /// identical tile in the grid.
    public static func listAll(config: KDriveConfig, directoryID: String,
                               page: (String?) async throws -> KDrivePage) async throws -> [KDriveItem] {
        var all: [KDriveItem] = []
        var seenIDs = Set<Int>()
        var cursor: String?
        var seenCursors = Set<String>()
        while true {
            let result = try await page(cursor)
            for item in result.items where seenIDs.insert(item.id).inserted { all.append(item) }
            guard result.hasMore else { break }
            guard let next = result.cursor, !next.isEmpty, seenCursors.insert(next).inserted else { break }
            cursor = next
        }
        return all
    }
}
