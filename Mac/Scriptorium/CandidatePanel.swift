import Cocoa

/// Horizontal candidate bar under the cursor, modelled on Apple's own
/// (Pinyin / Japanese) candidate window: Liquid Glass on macOS 26+ (menu
/// material before that), small grey index numbers, accent-coloured pill
/// on the selection, click to choose.
final class CandidatePanel: NSPanel {
    var onSelect: ((Int) -> Void)?

    private let stack = NSStackView()
    private var legacyBorder: NSVisualEffectView?
    private var cells: [CandidateCell] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 34),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

        if #available(macOS 26.0, *) {
            // Liquid Glass: the glass view draws its own edge, highlight and shadow
            let glass = NSGlassEffectView()
            glass.cornerRadius = 14
            glass.style = .regular
            glass.contentView = stack
            contentView = glass
            hasShadow = false
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 9
            effect.layer?.masksToBounds = true
            effect.layer?.borderWidth = 0.5
            effect.layer?.borderColor = NSColor.separatorColor.cgColor
            stack.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                stack.topAnchor.constraint(equalTo: effect.topAnchor),
                stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            contentView = effect
            legacyBorder = effect
        }
    }

    override var canBecomeKey: Bool { false }

    func show(_ candidates: [String], selected: Int, below rect: NSRect) {
        guard !candidates.isEmpty else { orderOut(nil); return }
        while cells.count < candidates.count {
            let c = CandidateCell()
            c.onClick = { [weak self] i in self?.onSelect?(i) }
            cells.append(c)
        }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, text) in candidates.enumerated() {
            let c = cells[i]
            c.configure(index: i, text: text, selected: i == selected)
            stack.addArrangedSubview(c)
        }
        legacyBorder?.layer?.borderColor = NSColor.separatorColor.cgColor   // follow appearance changes
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize

        // just below the line; above it if the screen ends; never off the right edge
        var origin = NSPoint(x: rect.minX - 6, y: rect.minY - size.height - 3)
        let screen = NSScreen.screens.first { $0.frame.contains(rect.origin) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            origin.x = max(vf.minX, min(origin.x, vf.maxX - size.width))
            if origin.y < vf.minY { origin.y = rect.maxY + 3 }
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFront(nil)
    }
}

private final class CandidateCell: NSView {
    var onClick: ((Int) -> Void)?
    private let number = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private var index = 0
    private var isSelected = false
    private var hovering = false { didSet { refresh() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.font = .systemFont(ofSize: 16)
        for v in [number, label] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            number.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            label.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, text: String, selected: Bool) {
        self.index = index
        isSelected = selected
        number.stringValue = "\(index + 1)"
        label.stringValue = text
        hovering = false
        refresh()
    }

    private func refresh() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            label.textColor = .alternateSelectedControlTextColor
            number.textColor = NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75)
        } else {
            layer?.backgroundColor = hovering ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : .clear
            label.textColor = .labelColor
            number.textColor = .tertiaryLabelColor
        }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { onClick?(index) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
