import Foundation

/// Physical key geometry, used for two things: cheap substitutions between
/// neighbouring keys in the corrector, and (in the app) drawing the keyboard.
public struct Layout: Sendable {
    public let rows: [[Character]]
    /// horizontal offset of each row, in key widths
    public let offsets: [Double]

    public static let latin = Layout(
        rows: [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")],
        offsets: [0, 0.5, 1.5])

    /// Same arrangement as Apple's Greek keyboard (; ς ε ρ τ υ θ ι ο π …),
    /// so muscle memory carries over.
    public static let greek = Layout(
        rows: [Array(";ςερτυθιοπ"), Array("ασδφγηξκλ"), Array("ζχψωβνμ")],
        offsets: [0, 0.5, 1.5])

    public static func `for`(_ lang: Language) -> Layout { lang == .latin ? .latin : .greek }

    private func position(_ c: Character) -> (Double, Double)? {
        let c = c == "ς" ? "σ" : c       // ς and σ share a key slot in our model
        for (r, row) in rows.enumerated() {
            if let i = row.firstIndex(of: c) ?? (c == "σ" ? row.firstIndex(of: "ς") : nil) {
                return (Double(i) + offsets[r], Double(r))
            }
        }
        return nil
    }

    /// Are two letters adjacent on the keyboard (a likely fat-finger)?
    public func adjacent(_ a: Character, _ b: Character) -> Bool {
        guard let p = position(a), let q = position(b) else { return false }
        return abs(p.0 - q.0) <= 1.1 && abs(p.1 - q.1) <= 1.0 && (p != q)
    }
}
