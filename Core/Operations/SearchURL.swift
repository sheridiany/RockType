import Foundation

public enum SearchURL {
    /// The engine is a trusted settings template, with exactly one placeholder in its query.
    public static func make(query: String, engine: String) throws -> URL {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw OperationFailure.emptyInput }
        guard engine.components(separatedBy: "{query}").count == 2,
              let marker = engine.range(of: "{query}"), let queryStart = engine.firstIndex(of: "?"),
              marker.lowerBound > queryStart,
              engine.firstIndex(of: "#").map({ marker.lowerBound < $0 }) ?? true,
              let escaped = query.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")),
              let url = URL(string: engine.replacingOccurrences(of: "{query}", with: escaped)),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.isEmpty == false, parts.user == nil, parts.password == nil
        else { throw OperationFailure.invalidSearchURL }
        return url
    }
}
