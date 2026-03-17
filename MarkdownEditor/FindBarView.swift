import AppKit

final class FindBarView: NSView {
    var onSearchTextChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = NSTextField()
    private let matchLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    private let borderLayer = CALayer()
    private var searchDebounceItem: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    var searchText: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    func focusSearchField() {
        searchField.window?.makeFirstResponder(searchField)
    }

    func updateMatchLabel(current: Int, total: Int) {
        if total == 0 {
            matchLabel.stringValue = searchField.stringValue.isEmpty ? "" : "0 matches"
        } else {
            matchLabel.stringValue = "\(current + 1) of \(total)"
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        borderLayer.backgroundColor = NSColor.separatorColor.cgColor
        layer?.addSublayer(borderLayer)

        // Search field
        searchField.placeholderString = "Find"
        searchField.font = .systemFont(ofSize: 12)
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.delegate = self
        searchField.lineBreakMode = .byTruncatingTail
        searchField.cell?.sendsActionOnEndEditing = false

        // Match label
        matchLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.setContentHuggingPriority(.required, for: .horizontal)
        matchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Buttons with SF Symbols
        configureButton(previousButton, symbolName: "chevron.up", action: #selector(previousTapped))
        configureButton(nextButton, symbolName: "chevron.down", action: #selector(nextTapped))
        configureButton(closeButton, symbolName: "xmark", action: #selector(closeTapped))

        previousButton.toolTip = "Previous Match (⇧↩)"
        nextButton.toolTip = "Next Match (↩)"
        closeButton.toolTip = "Close Find Bar (Esc)"

        // Layout
        let views = [searchField, matchLabel, previousButton, nextButton, closeButton]
        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        // The search field should not drive the window width — keep hugging low
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            previousButton.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 2),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 0),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 2),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    private func configureButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.bezelStyle = .inline
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 33)
    }

    override func layout() {
        super.layout()
        borderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        borderLayer.backgroundColor = NSColor.separatorColor.cgColor
    }

    @objc private func searchFieldChanged() {
        onSearchTextChanged?(searchField.stringValue)
    }

    @objc private func previousTapped() {
        onPrevious?()
    }

    @objc private func nextTapped() {
        onNext?()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}

// MARK: - NSTextFieldDelegate (Return / Shift+Return / Escape)

extension FindBarView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        searchDebounceItem?.cancel()
        let query = searchField.stringValue
        let item = DispatchWorkItem { [weak self] in
            self?.onSearchTextChanged?(query)
        }
        searchDebounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
}
