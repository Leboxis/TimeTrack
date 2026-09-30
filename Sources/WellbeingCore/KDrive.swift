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

    public var isComplete: Bool { !token.isEmpty && !driveID.isEmpty }
}

public enum KDriveError: LocalizedError {
    case invalidConfiguration, invalidURL, authenticationFailed, driveNotFound, serverError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Renseigne le jeton API et l’ID du Drive dans les Réglages."
        case .invalidURL:
            return "URL de requête kDrive invalide."
        case .authenticationFailed:
            return "Échec d’authentification : vérifie le jeton API Infomaniak."
        case .driveNotFound:
            return "Drive introuvable : vérifie l’ID du kDrive."
        case .serverError(let code, let message):
            return "Erreur serveur (\(code)) : \(message)"
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

public enum KDriveClient {
    static let base = "https://api.infomaniak.com"
    static let pageLimit = 200

    public static func driveURL(config: KDriveConfig) -> URL {
        URL(string: "\(base)/2/drive/\(config.driveID)")!
    }

    public static func listURL(config: KDriveConfig, directoryID: String, cursor: String?) -> URL {
        var components = URLComponents(string: "\(base)/3/drive/\(config.driveID)/files/\(directoryID)/files")!
        var items = [URLQueryItem(name: "limit", value: String(pageLimit))]
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        return components.url!
    }

    /// Not present in the reference app: it has no download, stream or thumbnail path.
    /// Derived from the shapes it does use, so it is the one assumption in this feature.
    public static func downloadURL(config: KDriveConfig, fileID: Int) -> URL {
        URL(string: "\(base)/3/drive/\(config.driveID)/files/download/\(fileID)")!
    }

    public static func decodePage(_ data: Data) throws -> KDrivePage {
        let envelope = try JSONDecoder().decode(KDriveEnvelope<[KDriveItem]>.self, from: data)
        if envelope.result == "error", let error = envelope.error {
            throw KDriveError.serverError(0, error.description ?? error.code ?? "erreur inconnue")
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
    /// server says `has_more` with a null cursor; this breaks instead.
    public static func listAll(config: KDriveConfig, directoryID: String,
                               page: (String?) async throws -> KDrivePage) async throws -> [KDriveItem] {
        var all: [KDriveItem] = []
        var cursor: String?
        var seen = Set<String>()
        while true {
            let result = try await page(cursor)
            all.append(contentsOf: result.items)
            guard result.hasMore else { break }
            guard let next = result.cursor, !next.isEmpty, seen.insert(next).inserted else { break }
            cursor = next
        }
        return all
    }
}
