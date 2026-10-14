import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct LexiconError: Error, CustomStringConvertible {
    public let description: String
}

/// Read-only view of a `.lex` file (see tools/build_lexicon.py).
///
/// Opened `immutable=1` and memory-mapped: pages are clean file-backed memory,
/// which iOS can evict at will instead of charging the ~50 MB keyboard budget.
public final class Lexicon {
    public struct Entry: Hashable {
        public let key: String
        public let word: String
        public let freq: Int        // corpus count × 100
    }

    private var db: OpaquePointer?
    private var exactStmt: OpaquePointer?
    private var prefixStmt: OpaquePointer?
    private var topStmt: OpaquePointer?
    private var biStmt: OpaquePointer?
    private var hasStmt: OpaquePointer?
    public let language: Language

    public init(path: String) throws {
        let uri = "file:\(path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw LexiconError(description: "cannot open \(path)")
        }
        sqlite3_exec(db, "PRAGMA mmap_size = 268435456; PRAGMA cache_size = -2000;", nil, nil, nil)
        var lang: Language = .latin
        if let s = Lexicon.prepare(db, "SELECT v FROM meta WHERE k='lang'") {
            if sqlite3_step(s) == SQLITE_ROW, let v = sqlite3_column_text(s, 0) {
                lang = Language(rawValue: String(cString: v)) ?? .latin
            }
            sqlite3_finalize(s)
        }
        language = lang
        exactStmt = Lexicon.prepare(db, "SELECT word, freq FROM lex WHERE key = ?1 ORDER BY freq DESC LIMIT 8")
        prefixStmt = Lexicon.prepare(db, "SELECT key, word, freq FROM lex WHERE key >= ?1 AND key < ?2 ORDER BY freq DESC LIMIT ?3")
        topStmt = Lexicon.prepare(db, "SELECT words FROM top WHERE prefix = ?1")
        biStmt = Lexicon.prepare(db, "SELECT next, n FROM bi WHERE prev = ?1 ORDER BY n DESC")
        hasStmt = Lexicon.prepare(db, "SELECT max(freq) FROM lex WHERE key = ?1")
        guard exactStmt != nil, prefixStmt != nil, topStmt != nil, biStmt != nil, hasStmt != nil else {
            throw LexiconError(description: "\(path) is not a lexicon (schema 1)")
        }
    }

    deinit {
        for s in [exactStmt, prefixStmt, topStmt, biStmt, hasStmt] { sqlite3_finalize(s) }
        sqlite3_close(db)
    }

    private static func prepare(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var s: OpaquePointer?
        return sqlite3_prepare_v3(db, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &s, nil) == SQLITE_OK ? s : nil
    }

    private func run(_ s: OpaquePointer?, _ binds: [Any], _ row: (OpaquePointer) -> Void) {
        guard let s else { return }
        sqlite3_reset(s)
        for (i, b) in binds.enumerated() {
            if let t = b as? String { sqlite3_bind_text(s, Int32(i + 1), t, -1, SQLITE_TRANSIENT) }
            else if let n = b as? Int { sqlite3_bind_int64(s, Int32(i + 1), sqlite3_int64(n)) }
        }
        while sqlite3_step(s) == SQLITE_ROW { row(s) }
    }

    private static func text(_ s: OpaquePointer, _ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
    }

    /// All spellings typed with exactly this key, most frequent first
    /// (Greek: the accent/breathing restorations; Latin: macron variants).
    public func exact(_ key: String) -> [Entry] {
        var out: [Entry] = []
        run(exactStmt, [key]) { s in
            out.append(Entry(key: key, word: Self.text(s, 0), freq: Int(sqlite3_column_int64(s, 1))))
        }
        return out
    }

    /// Highest frequency for a key, or nil if the key is not a word at all.
    public func maxFreq(_ key: String) -> Int? {
        var f: Int?
        run(hasStmt, [key]) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { f = Int(sqlite3_column_int64(s, 0)) }
        }
        return f
    }

    /// Completions of a key prefix. 1–3 letter prefixes come precomputed
    /// (scanning e.g. every Latin word in "con…" per keystroke is too slow).
    public func complete(_ prefix: String, limit: Int = 24) -> [Entry] {
        if prefix.count <= 3 {
            var words: [String] = []
            run(topStmt, [prefix]) { s in words = Self.text(s, 0).split(separator: "\t").map(String.init) }
            return words.map { w in
                let k = Folding.key(w, language)
                return Entry(key: k, word: w, freq: exact(k).first { $0.word == w }?.freq ?? 1)
            }
        }
        var out: [Entry] = []
        run(prefixStmt, [prefix, prefix + "\u{10FFFF}", limit]) { s in
            out.append(Entry(key: Self.text(s, 0), word: Self.text(s, 1), freq: Int(sqlite3_column_int64(s, 2))))
        }
        return out
    }

    /// Next-word counts after `prev` (Latin: keys, Greek: exact acute-normalised forms).
    public func following(_ prev: String) -> [(String, Int)] {
        var out: [(String, Int)] = []
        run(biStmt, [prev]) { s in out.append((Self.text(s, 0), Int(sqlite3_column_int64(s, 1)))) }
        return out
    }
}
