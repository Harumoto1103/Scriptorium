import ClassicalKeyboardEngine
import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyTapped(_ key: KeySpec)
    func variantChosen(_ text: String, of key: KeySpec)
    func suggestionTapped(_ index: Int)
    func spaceLongPressed()
    func moreSuggestionChosen(_ text: String)
    /// The controller, whose handleInputModeList(from:with:) drives the globe key.
    var inputController: UIInputViewController? { get }
}

/// Draws the suggestion bar and keys; reports taps. All text logic is in the controller.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?
    var rows: [[KeySpec]] = [] { didSet { rebuild() } }
    var shifted = false { didSet { relabel() } }

    private let bar = UIStackView()
    private var suggestionButtons: [UIButton] = []
    private var keyViews: [(KeySpec, KeyCap)] = []

    static let barHeight: CGFloat = 44
    static let rowHeight: CGFloat = 54

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        for i in 0..<3 {
            let b = UIButton(type: .system)
            b.tag = i
            b.titleLabel?.font = .systemFont(ofSize: 18)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.setTitleColor(.label, for: .normal)
            b.addTarget(self, action: #selector(suggestion(_:)), for: .touchUpInside)
            bar.addArrangedSubview(b)
            suggestionButtons.append(b)
        }
        addSubview(bar)
        moreButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        moreButton.tintColor = .secondaryLabel
        moreButton.isHidden = true
        moreButton.addAction(UIAction { [weak self] _ in self?.toggleMore() }, for: .touchUpInside)
        addSubview(moreButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// texts: up to 3; `highlight` is the slot that space will insert.
    // MARK: more suggestions (▾)

    private let moreButton = UIButton(type: .system)
    private var more: [String] = []
    private var grid: UIScrollView?

    /// Suggestions beyond the three in the bar; shows the ▾ button when there are any.
    func setMore(_ items: [String]) {
        more = items
        moreButton.isHidden = items.isEmpty
        if items.isEmpty { closeMore() } else if grid != nil { buildGrid() }
    }

    private func toggleMore() { grid == nil ? buildGrid() : closeMore() }

    func closeMore() {
        grid?.removeFromSuperview(); grid = nil
        moreButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    }

    /// A scrollable grid over the keys, like the candidate grids of CJK keyboards.
    private func buildGrid() {
        grid?.removeFromSuperview()
        let g = UIScrollView(frame: CGRect(x: 0, y: Self.barHeight, width: bounds.width,
                                           height: bounds.height - Self.barHeight))
        g.backgroundColor = .secondarySystemBackground
        g.autoresizingMask = [.flexibleWidth]
        let cols = 3, h: CGFloat = 46, w = (bounds.width - 8) / CGFloat(cols)
        for (i, t) in more.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(t, for: .normal)
            b.setTitleColor(.label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 19)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.frame = CGRect(x: 4 + CGFloat(i % cols) * w, y: CGFloat(i / cols) * h, width: w, height: h)
                .insetBy(dx: 2, dy: 2)
            b.backgroundColor = .systemBackground
            b.layer.cornerRadius = 8
            b.addAction(UIAction { [weak self] _ in
                self?.closeMore()
                self?.delegate?.moreSuggestionChosen(t)
            }, for: .touchUpInside)
            g.addSubview(b)
        }
        g.contentSize = CGSize(width: bounds.width, height: CGFloat((more.count + cols - 1) / cols) * h + 8)
        addSubview(g)
        grid = g
        moreButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
    }

    func setSuggestions(_ texts: [String], highlight: Int?) {
        for (i, b) in suggestionButtons.enumerated() {
            let t = i < texts.count ? texts[i] : ""
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = i == highlight ? .boldSystemFont(ofSize: 18) : .systemFont(ofSize: 18)
            b.backgroundColor = i == highlight && !t.isEmpty ? UIColor.systemGray4.withAlphaComponent(0.6) : .clear
            b.layer.cornerRadius = 6
        }
    }

    @objc private func suggestion(_ b: UIButton) { delegate?.suggestionTapped(b.tag) }

    private func rebuild() {
        endAllTouches()
        keyViews.forEach { $0.1.removeFromSuperview() }
        keyViews = []
        for row in rows {
            for spec in row {
                // caps only draw; all touches are tracked by this view (see "Touch handling")
                let cap = KeyCap(spec: spec)
                cap.isUserInteractionEnabled = false
                addSubview(cap)
                keyViews.append((spec, cap))
            }
        }
        relabel()
        setNeedsLayout()
    }

    private func relabel() {
        for (spec, cap) in keyViews {
            if case .char(let c) = spec.kind { cap.title = shifted ? c.uppercased() : c }
            if spec.kind == .shift { cap.isOn = shifted }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bar.frame = CGRect(x: 4, y: 0, width: bounds.width - 8 - 36, height: Self.barHeight)
        moreButton.frame = CGRect(x: bounds.width - 40, y: 0, width: 36, height: Self.barHeight)
        let pad: CGFloat = 3
        let unit = bounds.width / 10
        var y = Self.barHeight
        var i = 0
        for row in rows {
            let total = row.reduce(0) { $0 + $1.width }
            var x = (bounds.width - total * unit) / 2        // centre short rows (a s d …)
            for spec in row {
                let w = spec.width * unit
                keyViews[i].1.frame = CGRect(x: x + pad, y: y + pad * 2, width: w - pad * 2, height: Self.rowHeight - pad * 4)
                x += w; i += 1
            }
            y += Self.rowHeight
        }
    }

    var preferredHeight: CGFloat { Self.barHeight + CGFloat(rows.count) * Self.rowHeight }

    // MARK: Touch handling
    //
    // One view tracks every finger, like Apple's keyboard, instead of one control
    // per key. Per-key controls lose letters in fast typing: when thumbs overlap
    // or iOS cancels a touch (system edge / home-indicator gestures), the key
    // never sees "touch up inside". Here:
    //  * a touch goes to the nearest key (no dead zones between keys);
    //  * a new finger landing commits any key still held (rollover);
    //  * a cancelled short tap still counts;
    //  * long-press opens variants (vowels) or settings (space); ⌫ repeats.

    private final class Tracked {
        let cap: KeyCap
        let start = Date()
        var timer: Timer?
        var repeater: Timer?
        var callout: VariantCallout?
        var done = false            // already fired (rollover, ⌫ on touch-down, long-press)
        init(cap: KeyCap) { self.cap = cap }
    }
    private var touches: [ObjectIdentifier: Tracked] = [:]

    private func nearestKey(to point: CGPoint) -> KeyCap? {
        let row = Int((point.y - Self.barHeight) / Self.rowHeight)
        let inRow = keyViews.map(\.1).filter { Int(($0.frame.midY - Self.barHeight) / Self.rowHeight) == row }
        func distance(_ v: UIView) -> CGFloat {
            let f = v.frame
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            return dx * dx + dy * dy
        }
        return (inRow.isEmpty ? keyViews.map(\.1) : inRow).min { distance($0) < distance($1) }
    }

    private func fire(_ t: Tracked) {
        guard !t.done else { return }
        t.done = true
        UIDevice.current.playInputClick()
        delegate?.keyTapped(t.cap.spec)
    }

    private func finish(_ t: Tracked) {
        t.timer?.invalidate(); t.repeater?.invalidate()
        t.callout?.removeFromSuperview()
        t.cap.isHighlighted = false
    }

    private func endAllTouches() {
        touches.values.forEach(finish)
        touches = [:]
    }

    override func touchesBegan(_ set: Set<UITouch>, with event: UIEvent?) {
        for touch in set {
            let p = touch.location(in: self)
            guard p.y >= Self.barHeight, let cap = nearestKey(to: p) else { continue }
            // rollover: a new finger commits every earlier key still down (not long-presses in progress)
            for (id, t) in touches where t.callout == nil && t.cap.spec.kind != .backspace {
                fire(t); finish(t); touches[id] = nil
            }
            let t = Tracked(cap: cap)
            touches[ObjectIdentifier(touch)] = t
            cap.isHighlighted = true

            switch cap.spec.kind {
            case .globe:
                if let e = event { delegate?.inputController?.handleInputModeList(from: self, with: e) }
                t.done = true
            case .backspace:
                fire(t)                                         // delete on touch-down, then repeat
                t.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    t.repeater = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                        self?.delegate?.keyTapped(t.cap.spec)
                    }
                }
            case .space:
                t.timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                    t.done = true
                    self?.delegate?.spaceLongPressed()
                }
            default:
                if !cap.spec.variants.isEmpty {
                    t.timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                        self?.openCallout(for: t)
                    }
                }
            }
        }
    }

    override func touchesMoved(_ set: Set<UITouch>, with event: UIEvent?) {
        for touch in set {
            guard let t = touches[ObjectIdentifier(touch)] else { continue }
            if t.cap.spec.kind == .globe {
                if let e = event { delegate?.inputController?.handleInputModeList(from: self, with: e) }
            } else if let c = t.callout {
                c.select(at: touch.location(in: c))
            }
        }
    }

    override func touchesEnded(_ set: Set<UITouch>, with event: UIEvent?) {
        for touch in set {
            let id = ObjectIdentifier(touch)
            guard let t = touches[id] else { continue }
            touches[id] = nil
            if t.cap.spec.kind == .globe {
                if let e = event { delegate?.inputController?.handleInputModeList(from: self, with: e) }
            } else if let c = t.callout {
                if let v = c.selected { delegate?.variantChosen(v, of: t.cap.spec) }
                t.done = true
            } else {
                fire(t)
            }
            finish(t)
        }
    }

    override func touchesCancelled(_ set: Set<UITouch>, with event: UIEvent?) {
        // iOS took the touch away (system gesture). A quick tap was still a tap.
        for touch in set {
            let id = ObjectIdentifier(touch)
            guard let t = touches[id] else { continue }
            touches[id] = nil
            if t.callout == nil && t.cap.spec.kind != .globe && Date().timeIntervalSince(t.start) < 0.35 { fire(t) }
            finish(t)
        }
    }

    private func openCallout(for t: Tracked) {
        let options = t.cap.spec.variants.map { shifted ? $0.uppercased() : $0 }
        let c = VariantCallout(options: options)
        c.isUserInteractionEnabled = false          // the finger that opened it keeps driving it
        let w = CGFloat(options.count) * 40
        let x = min(max(4, t.cap.frame.midX - 20), bounds.width - w - 4)
        c.frame = CGRect(x: x, y: max(0, t.cap.frame.minY - 50), width: w, height: 46)
        addSubview(c)
        t.callout = c
    }
}

final class KeyCap: UIControl {
    let spec: KeySpec
    private let label = UILabel()
    var title: String { get { label.text ?? "" } set { label.text = newValue } }
    var isOn = false { didSet { refresh() } }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        layer.cornerRadius = 6
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        label.textAlignment = .center
        label.font = spec.isFunction ? .systemFont(ofSize: 16) : .systemFont(ofSize: 23)
        label.adjustsFontSizeToFitWidth = true
        label.text = spec.label ?? { if case .char(let c) = spec.kind { return c }; return "" }()
        if !spec.variants.isEmpty, !spec.isFunction {
            // small hint that a long-press exists
            let dot = UILabel()
            dot.text = "·"; dot.font = .systemFont(ofSize: 10); dot.textColor = .secondaryLabel
            dot.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
            dot.autoresizingMask = [.flexibleLeftMargin]
            addSubview(dot)
        }
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 2)
        subviews.first { $0 !== label }?.frame.origin = CGPoint(x: bounds.width - 10, y: 1)
    }

    override var isHighlighted: Bool { didSet { refresh() } }

    private func refresh() {
        let fn = spec.isFunction
        backgroundColor = isHighlighted || isOn
            ? (fn ? .systemBackground : .systemGray3)
            : (fn ? .systemGray3 : .systemBackground)
        label.textColor = .label
    }
}

final class VariantCallout: UIView {
    private let options: [String]
    private var labels: [UILabel] = []
    private(set) var selected: String?

    init(options: [String]) {
        self.options = options
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        for o in options {
            let l = UILabel()
            // ◌ + combining mark: show the mark on a dotted circle
            l.text = o
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 24)
            l.layer.cornerRadius = 6
            l.clipsToBounds = true
            addSubview(l); labels.append(l)
        }
        select(index: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, l) in labels.enumerated() { l.frame = CGRect(x: CGFloat(i) * 40 + 2, y: 3, width: 36, height: 40) }
    }

    func select(at p: CGPoint) { select(index: max(0, min(options.count - 1, Int(p.x / 40)))) }

    private func select(index: Int) {
        selected = options[index]
        for (i, l) in labels.enumerated() {
            l.backgroundColor = i == index ? .systemBlue : .clear
            l.textColor = i == index ? .white : .label
        }
    }
}
