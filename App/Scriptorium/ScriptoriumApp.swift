import ClassicalKeyboardEngine
import SwiftUI

@main
struct ScriptoriumApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var s = KeyboardSettings.load()
    @State private var test = ""
    /// App Group available (paid account)? Otherwise settings cannot reach the keyboards.
    private let sharedSettings = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: KeyboardSettings.group) != nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard… → Latīna / Ἑλληνική. No Full Access needed: nothing leaves the phone.")
                        .font(.callout)
                    Button("Open Settings") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }
                if !sharedSettings {
                    Section {
                        Text("This build uses a free developer account, so the keyboards keep their own settings: **long-press the space bar** on a keyboard to change them. (The switches below only work with a paid account.)")
                            .font(.callout)
                    }
                }
                Section("Try it") {
                    TextField("Scribe hīc… / γράφε ἐνθάδε…", text: $test, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("General") {
                    Toggle("Autocorrect & accent restoration", isOn: $s.autocorrect)
                }
                Section("Latīna") {
                    Toggle("Macrons (rōsā)", isOn: $s.latinMacrons)
                    Toggle("Consonantal v (vir, not uir)", isOn: $s.latinConsonantalV)
                    Toggle("Consonantal j (jam, not iam)", isOn: $s.latinJ)
                }
                Section("Ἑλληνική") {
                    Toggle("Macrons on long α ι υ (χώρᾱ)", isOn: $s.greekQuantities)
                    Toggle("Grave before a following word (καλὸς)", isOn: $s.greekAutoGrave)
                }
                Section("Credits") {
                    Text("Word forms, macrons and accents: Wiktionary, via kaikki.org (wiktextract, T. Ylonen). Greek frequencies: Perseus Digital Library, Tufts University. Both CC BY-SA 4.0; the lexicons are adapted from them and shared under CC BY-SA 4.0. Latin frequencies: The Latin Library (public domain), packaged by the Classical Language Toolkit.")
                        .font(.footnote)
                    Link("Licence: CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                        .font(.footnote)
                }
                Section {
                    Text("Long-press a vowel for ā ă / ᾱ ἀ ἁ ά ᾶ ᾳ…; the ¯ key toggles a macron on the letter just typed; the ´ key (long-press for more) adds Greek accents and breathings. Backspace right after an autocorrection restores what you typed, and the keyboard remembers it. Long-press the space bar for the keyboard's settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scriptorium")
            .onChange(of: s) { $0.save() }
        }
    }
}
