import ClassicalKeyboardEngine
import UIKit

/// Settings inside the keyboard itself (long-press the space bar). Needed on a
/// free developer account, where the app cannot share settings with the
/// keyboards (no App Group); harmless with one.
final class SettingsOverlay: UIView {
    private var settings: KeyboardSettings
    private let onChange: (KeyboardSettings) -> Void
    private let onClose: () -> Void

    init(language: Language, settings: KeyboardSettings,
         onChange: @escaping (KeyboardSettings) -> Void, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.onClose = onClose
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let header = UIStackView()
        let title = UILabel()
        title.text = language == .latin ? "Latīna" : "Ἑλληνική"
        title.font = .preferredFont(forTextStyle: .headline)
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(done)
        stack.addArrangedSubview(header)

        func row(_ label: String, _ kp: WritableKeyPath<KeyboardSettings, Bool>) {
            let r = UIStackView()
            r.alignment = .center
            let l = UILabel()
            l.text = label
            l.font = .preferredFont(forTextStyle: .subheadline)
            l.adjustsFontSizeToFitWidth = true
            let sw = UISwitch()
            sw.isOn = settings[keyPath: kp]
            sw.addAction(UIAction { [weak self] a in
                guard let self, let s = a.sender as? UISwitch else { return }
                self.settings[keyPath: kp] = s.isOn
                self.onChange(self.settings)
            }, for: .valueChanged)
            r.addArrangedSubview(l)
            r.addArrangedSubview(sw)
            stack.addArrangedSubview(r)
        }
        row("Autocorrect & accent restoration", \.autocorrect)
        switch language {
        case .latin:
            row("Macrons (rōsā)", \.latinMacrons)
            row("Consonantal v (vir, not uir)", \.latinConsonantalV)
            row("Consonantal j (jam, not iam)", \.latinJ)
        case .greek:
            row("Macrons on long α ι υ (χώρᾱ)", \.greekQuantities)
            row("Grave & enclitic accents (καλὸς)", \.greekAutoGrave)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
