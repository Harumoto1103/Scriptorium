import ClassicalKeyboardEngine

/// Principal class of the Greek keyboard extension (see NSExtensionPrincipalClass).
final class GreekKeyboardViewController: ClassicalKeyboardViewController {
    override var language: Language { .greek }
    override var lexiconName: String { "greek" }
}
