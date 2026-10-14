import ClassicalKeyboardEngine

/// Principal class of the Latin keyboard extension (see NSExtensionPrincipalClass).
final class LatinKeyboardViewController: ClassicalKeyboardViewController {
    override var language: Language { .latin }
    override var lexiconName: String { "latin" }
}
