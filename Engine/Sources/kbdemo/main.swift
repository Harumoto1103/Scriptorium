import ClassicalKeyboardEngine
import Foundation

// Simulates the keyboard on the command line.
//
//   swift run kbdemo latin "gallia est omnis diuisa in partes tres"
//   swift run kbdemo greek "ανδρα μοι εννεπε μουσα"
//   swift run kbdemo latin --macrons "arma uirumque cano"
//   swift run kbdemo greek            (interactive: one line per sentence)
//
// Every word is "typed" letter by letter; we print what the bar would show
// after the last letter, then press space and accept the autocorrect.

var args = Array(CommandLine.arguments.dropFirst())
guard let langArg = args.first else {
    print("usage: kbdemo latin|greek [--macrons] [--uv] [sentence]"); exit(2)
}
args.removeFirst()
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../out").standardized
let path = root.appendingPathComponent(langArg.hasPrefix("l") ? "latin.lex" : "greek.lex").path
let lex = try Lexicon(path: path)
let p = Predictor(lexicon: lex)
if let i = args.firstIndex(of: "--macrons") { p.latinStyle.macrons = true; args.remove(at: i) }
if let i = args.firstIndex(of: "--uv") { p.latinStyle.consonantalV = false; args.remove(at: i) }

func simulate(_ sentence: String) {
    var prev: String? = nil
    var output: [String] = []
    for raw in sentence.split(separator: " ").map(String.init) {
        let t0 = Date()
        var pred = p.predict(previous: prev, typed: "")
        let nextGuess = pred.suggestions.prefix(3).map(\.text)
        var worst = 0.0
        for n in 1...raw.count {
            let s = Date()
            pred = p.predict(previous: prev, typed: String(raw.prefix(n)))
            worst = max(worst, Date().timeIntervalSince(s))
        }
        let committed = pred.autocorrect?.text ?? (lex.language == .greek ? Greek.finalSigma(raw) : raw)
        let bar = pred.suggestions.prefix(3).map { $0.text == pred.autocorrect?.text ? "[\($0.text)]" : $0.text }
        print(String(format: "%-14@ → %-16@ bar: %-40@ next-guess: %@   (%.0f ms/key max, %.0f ms total)",
                     raw as NSString, committed as NSString, bar.joined(separator: "  ") as NSString,
                     nextGuess.joined(separator: " ") as NSString, worst * 1000, Date().timeIntervalSince(t0) * 1000))
        output.append(committed)
        prev = committed
    }
    // Greek: oxytones before another word take the grave
    if lex.language == .greek {
        output = output.enumerated().map { i, w in i < output.count - 1 ? Greek.toGrave(w) : w }
    }
    print("⇒ " + output.joined(separator: " ") + "\n")
}

if args.isEmpty {
    while let line = readLine(), !line.isEmpty { simulate(line) }
} else {
    simulate(args.joined(separator: " "))
}
