import Foundation

public enum SaveAction: String {
    case save, unsave
}

public struct RedditAccount: Equatable {
    public let username: String
    /// Anti-CSRF token. Reddit requires it on write endpoints when the request is
    /// authenticated by cookie rather than OAuth, and `/api/save` is a write endpoint.
    public let modhash: String

    public init(username: String, modhash: String) {
        self.username = username
        self.modhash = modhash
    }

    private struct Envelope: Decodable {
        struct Data: Decodable { let name: String?; let modhash: String? }
        let data: Data?
    }

    /// `GET /api/me.json` returns an error envelope for an anonymous request, so a
    /// missing payload is a failure rather than an empty account.
    public static func decode(_ data: Data) throws -> RedditAccount {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let payload = envelope.data, let name = payload.name, let modhash = payload.modhash,
              !modhash.isEmpty else {
            throw RedditAccountError.anonymous
        }
        return RedditAccount(username: name, modhash: modhash)
    }

    public static func meURL() -> URL { URL(string: "https://www.reddit.com/api/me.json")! }

    public static func actionURL(_ action: SaveAction) -> URL {
        URL(string: "https://www.reddit.com/api/\(action.rawValue)")!
    }

    public func actionURL(_ action: SaveAction) -> URL { Self.actionURL(action) }

    /// Form body for the write call: `id` is the thing fullname (`t3_…`), `uh` the modhash.
    public func saveBody(fullname: String) throws -> String {
        try Self.saveBody(fullname: fullname, modhash: modhash)
    }

    public static func saveBody(fullname: String, modhash: String) throws -> String {
        guard let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+")) else {
            throw RedditAccountError.anonymous
        }
        func encode(_ value: String) throws -> String {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed)
            guard let encoded else { throw RedditAccountError.anonymous }
            return encoded
        }
        return "id=\(try encode(fullname))&uh=\(try encode(modhash))"
    }

    public static func savedSet(from json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let set = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return set
    }

    public static func encodeSavedSet(_ set: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(set) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum RedditAccountError: LocalizedError {
    case anonymous, refused(Int), notSaved

    public var errorDescription: String? {
        switch self {
        case .anonymous:
            return "Connexion Reddit requise. Connecte-toi dans les Réglages."
        case .refused(let code):
            return "Reddit a refusé la demande (HTTP \(code))."
        case .notSaved:
            return "Le post n’a pas pu être enregistré dans tes sauvegardes Reddit."
        }
    }
}
