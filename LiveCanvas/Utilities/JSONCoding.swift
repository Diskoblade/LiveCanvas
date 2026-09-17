import Foundation

/// Shared JSON encoder/decoder configuration.
///
/// Dates use ISO 8601 **with fractional seconds**. Plain `.iso8601` truncates to whole
/// seconds, which made two backups created in the same second indistinguishable and their
/// ordering non-deterministic — exactly the wrong property for "restore the latest backup".
enum JSONCoding {
    static let dateFormat: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func encoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormat.string(from: date))
        }
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = dateFormat.date(from: text) { return date }
            // Accept whole-second timestamps written by earlier builds.
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Unrecognised date: \(text)")
        }
        return d
    }
}
