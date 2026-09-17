import Foundation

/// "1 entry" / "3 entries" — keeps user-facing counts out of "entry(ies)" territory.
enum Pluralize {
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        n == 1 ? "1 \(singular)" : "\(n) \(plural ?? singular + "s")"
    }
}
