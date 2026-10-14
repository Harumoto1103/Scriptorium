import Foundation

/// Preferences shared by the app (where they are edited) and both keyboards.
/// Lives in the App Group; without the entitlement (free signing) the suite
/// silently falls back to per-process storage and defaults apply.
struct KeyboardSettings: Equatable {
    static let group = "group.uk.harukita.scriptorium"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    var autocorrect = true
    var latinMacrons = true          // rōsā
    var latinConsonantalV = true     // vir (off: uir)
    var latinJ = false               // iam (on: jam)
    var greekQuantities = true       // χώρᾱ
    var greekAutoGrave = true        // καλὸς before another word
    var diagnostics = false          // live tap counters in the suggestion bar

    static func load() -> KeyboardSettings {
        let d = defaults
        var s = KeyboardSettings()
        func b(_ k: String, _ v: inout Bool) { if d.object(forKey: k) != nil { v = d.bool(forKey: k) } }
        b("autocorrect", &s.autocorrect)
        b("latinMacrons", &s.latinMacrons)
        b("latinConsonantalV", &s.latinConsonantalV)
        b("latinJ", &s.latinJ)
        b("greekQuantities", &s.greekQuantities)
        b("greekAutoGrave", &s.greekAutoGrave)
        b("diagnostics", &s.diagnostics)
        return s
    }

    func save() {
        let d = Self.defaults
        d.set(autocorrect, forKey: "autocorrect")
        d.set(latinMacrons, forKey: "latinMacrons")
        d.set(latinConsonantalV, forKey: "latinConsonantalV")
        d.set(latinJ, forKey: "latinJ")
        d.set(greekQuantities, forKey: "greekQuantities")
        d.set(greekAutoGrave, forKey: "greekAutoGrave")
        d.set(diagnostics, forKey: "diagnostics")
    }

    /// Where each keyboard keeps what it has learned about the user.
    static func userModelURL(_ lang: String) -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("user-\(lang).json")
    }
}
