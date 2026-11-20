//
//  FindInPageActionBar.swift
//  Reynard
//
//  Created by Minh Ton on 12/8/26.
//

import UIKit

final class FindInPageActionBar: UIView, UITextFieldDelegate {
    private enum UX {
        static let contentLeadingInset: CGFloat = 12
        static let contentMaximumWidth: CGFloat = 650
        static var searchBarToControlsSpacing: CGFloat {
            if #available(iOS 26.0, *) { return 8 }
            return 12
        }
        // The field's text follows the text size, and the row grows with it.
        static var controlsHeight: CGFloat {
            if #available(iOS 26.0, *) { return 48 + BarMetrics.addressBarGrowth }
            return 38 + BarMetrics.addressBarGrowth
        }
        static let searchContentInset: CGFloat = 12
        static var resultLabelWidth: CGFloat { return BarMetrics.scaled(52) }
        static let resultFontSize: CGFloat = 16
        static let resultLabelSpacing: CGFloat = 10
        static var controlsWidth: CGFloat { return controlButtonWidth * 2 + separatorWidth }
        static var controlButtonWidth: CGFloat {
            if #available(iOS 26.0, *) { return TouchTarget.minimumSideLength }
            return 55
        }
        static let separatorWidth: CGFloat = 1
        static var controlsCornerRadius: CGFloat { return controlsHeight / 2 }
        static let controlSymbolPointSize: CGFloat = 14
        // The checkmark sits on glass tinted with the system's blue, where the system's own prominent
        // buttons draw their symbols in white.
        static let doneSymbolColor = UIColor.white
        static var contentTrailingInset: CGFloat {
            if #available(iOS 26.0, *) { return 12 }
            return 53
        }
        static let backgroundAlpha: CGFloat = 0.34
        static let disabledAlpha: CGFloat = 0.32
        static let shadowOpacity: Float = 0.14
        static let shadowRadius: CGFloat = 8
        static let shadowOffset = CGSize(width: 0, height: 3)
        static let borderWidth: CGFloat = 0.5
    }
    
    var onFind: ((_ query: String?, _ backwards: Bool) async -> (current: Int, total: Int)?)?
    var onClear: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        return view
    }()
    
    private let searchContentView: UIView = {
        let view: UIView
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = UX.searchBarToControlsSpacing
            view = UIVisualEffectView(effect: effect)
        } else {
            view = UIView()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let searchField: FindInPageTextField = {
        let field = FindInPageTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.placeholder = NSLocalizedString("Find", comment: "Find in page search placeholder")
        field.textColor = .label
        field.font = BarMetrics.font(ofSize: BarMetrics.addressBarTextSize)
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityLabel = NSLocalizedString("Find in Page", comment: "")
        field.accessibilityIdentifier = AccessibilityIdentifier.FindInPage.textField
        field.clearButtonMode = .never
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .search
        return field
    }()
    
    private let resultLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: UX.resultFontSize, weight: .regular),
            maximumPointSize: UX.resultFontSize * BarMetrics.maximumTextScale
        )
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = AccessibilityIdentifier.FindInPage.count
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.lineBreakMode = .byClipping
        label.isHidden = true
        return label
    }()
    
    private let searchBarShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        view.layer.shadowColor = UIColor.black.cgColor
        return view
    }()
    
    private let searchBarBackground: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor { traitCollection in
            let backgroundColor: UIColor = traitCollection.userInterfaceStyle == .dark
            ? .tertiarySystemBackground.withAlphaComponent(0.8)
            : .systemBackground.withAlphaComponent(0.8)
            return backgroundColor.resolvedColor(with: traitCollection)
        }
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = AccessibilityAppearance.hairlineColor.cgColor
        view.clipsToBounds = true
        return view
    }()
    
    private let controlsShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        view.layer.shadowColor = UIColor.black.cgColor
        return view
    }()
    
    private let controlsBackground: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor { traitCollection in
            let backgroundColor: UIColor = traitCollection.userInterfaceStyle == .dark
            ? .tertiarySystemBackground.withAlphaComponent(0.8)
            : .systemBackground.withAlphaComponent(0.8)
            return backgroundColor.resolvedColor(with: traitCollection)
        }
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = AccessibilityAppearance.hairlineColor.cgColor
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var previousMatchButton = makeControlButton(
        imageName: "reynard.chevron.up",
        title: NSLocalizedString("Previous Match", comment: "The button that goes to the previous place the searched text is found in the page"),
        identifier: AccessibilityIdentifier.FindInPage.previous,
        action: #selector(previousMatchTapped)
    )
    
    private lazy var nextMatchButton = makeControlButton(
        imageName: "reynard.chevron.down",
        title: NSLocalizedString("Next Match", comment: "The button that goes to the next place the searched text is found in the page"),
        identifier: AccessibilityIdentifier.FindInPage.next,
        action: #selector(nextMatchTapped)
    )
    
    private let separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()
    
    private var doneToolbar: UIToolbar?
    private var requestID = 0
    private var lastAnnouncedResult: String?
    private var controlsHeightConstraints: [NSLayoutConstraint] = []
    private var controlButtonWidthConstraints: [NSLayoutConstraint] = []
    private var resultLabelWidthConstraint: NSLayoutConstraint!
    private var searchContentViewCenterConstraint: NSLayoutConstraint!
    private var searchContentViewLeadingConstraint: NSLayoutConstraint!
    private var searchContentViewTrailingConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        searchField.delegate = self
        searchField.onDismiss = { [weak self] in
            self?.onDismiss?()
        }
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        updateNavigationButtons()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        
        controlsHeightConstraints.forEach { $0.constant = UX.controlsHeight }
        resultLabelWidthConstraint.constant = UX.resultLabelWidth
        if #unavailable(iOS 26.0) {
            for view in [searchBarShadowView, searchBarBackground, controlsShadowView, controlsBackground] {
                view.layer.cornerRadius = UX.controlsCornerRadius
            }
        }
        setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateSearchContentLayout()
        [searchBarShadowView, controlsShadowView].forEach { view in
            view.layer.shadowPath = UIBezierPath(
                roundedRect: view.bounds,
                cornerRadius: UX.controlsCornerRadius
            ).cgPath
        }
    }
    
    // MARK: - Presentation
    
    @available(iOS 26.0, *)
    func setModernContentHidden(_ hidden: Bool) {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        for view in [searchBarBackground, controlsBackground] {
            view.effect = hidden ? nil : effect
            view.contentView.alpha = hidden ? 0 : 1
        }
        effect.tintColor = .systemBlue
        (doneToolbar?.superview?.superview as? UIVisualEffectView)?.effect = hidden ? nil : effect
        doneToolbar?.alpha = hidden ? 0 : 1
    }
    
    func prepareForPresentation(query: String?) {
        requestID += 1
        onClear?()
        searchField.text = query
        
        if let query, !query.isEmpty {
            searchTextChanged()
        } else {
            setResultText(nil)
            updateNavigationButtons()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.searchField.becomeFirstResponder()
        }
    }
    
    func prepareForDismissal() {
        requestID += 1
        onClear?()
        searchField.resignFirstResponder()
        searchField.text = nil
        setResultText(nil)
        updateNavigationButtons()
    }
    
    private func setResult(current: Int, total: Int) {
        guard !(searchField.text ?? "").isEmpty else {
            setResultText(nil)
            return
        }
        
        let currentText = max(current, 0)
        let totalText = total >= 0 ? String(total) : "?"
        setResultText("\(currentText)/\(totalText)")
        
        // "3/12" is read as a fraction. VoiceOver gets the count in words, and hears it when it changes:
        // the matches are found while the keyboard has the focus.
        let spoken = total >= 0
        ? String.localizedStringWithFormat(
            NSLocalizedString("Match %1$d of %2$d", comment: "Find in page: which match is shown, and how many there are"),
            currentText,
            total
        )
        : resultLabel.text
        resultLabel.accessibilityLabel = spoken
        if spoken != lastAnnouncedResult {
            lastAnnouncedResult = spoken
            UIAccessibility.post(notification: .announcement, argument: spoken)
        }
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        nextMatchTapped()
        return false
    }
    
    // MARK: - Actions
    
    @objc private func doneTapped() {
        onDismiss?()
    }
    
    @objc private func searchTextChanged() {
        let query = searchField.text ?? ""
        setResultText(query.isEmpty ? nil : "0/0")
        updateNavigationButtons()
        guard !query.isEmpty else {
            requestID += 1
            onClear?()
            return
        }
        
        find(query: query, backwards: false)
    }
    
    @objc private func previousMatchTapped() {
        find(query: nil, backwards: true)
    }
    
    @objc private func nextMatchTapped() {
        find(query: nil, backwards: false)
    }
    
    private func find(query: String?, backwards: Bool) {
        guard let onFind else {
            return
        }
        
        requestID += 1
        let currentRequestID = requestID
        Task { @MainActor [weak self] in
            let result = await onFind(query, backwards)
            guard let self, self.requestID == currentRequestID else {
                return
            }
            
            self.setResult(
                current: result?.current ?? 0,
                total: result?.total ?? 0
            )
        }
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        accessibilityIdentifier = AccessibilityIdentifier.FindInPage.bar
        if #available(iOS 26.0, *) {
            backgroundView.isHidden = true
            separator.isHidden = true
            for view in [searchBarBackground, controlsBackground] {
                view.contentView.backgroundColor = .clear
                view.layer.borderWidth = 0
                view.layer.cornerRadius = 0
                view.cornerConfiguration = .capsule()
                view.clipsToBounds = false
            }
            for view in [searchBarShadowView, controlsShadowView] {
                view.layer.shadowOpacity = 0
            }
        }
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        addSubview(searchContentView)
        let contentView = (searchContentView as? UIVisualEffectView)?.contentView ?? searchContentView
        if #available(iOS 26.0, *) {
            let background = UIVisualEffectView()
            background.translatesAutoresizingMaskIntoConstraints = false
            background.cornerConfiguration = .capsule()
            contentView.addSubview(background)
            let toolbar = UIToolbar()
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            let configuration = UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
                .applying(UIImage.SymbolConfiguration(weight: .medium))
            let image = UIImage(systemName: "checkmark", withConfiguration: configuration)?
                .withTintColor(UX.doneSymbolColor, renderingMode: .alwaysOriginal)
            let doneItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(doneTapped))
            
            doneItem.accessibilityLabel = NSLocalizedString("Done", comment: "")
            doneItem.accessibilityIdentifier = AccessibilityIdentifier.FindInPage.done
            doneItem.hidesSharedBackground = true
            toolbar.items = [doneItem]
            background.contentView.addSubview(toolbar)
            doneToolbar = toolbar
            
            NSLayoutConstraint.activate([
                background.topAnchor.constraint(equalTo: toolbar.topAnchor),
                background.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
                background.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            ])
            
            setModernContentHidden(false)
        }
        
        contentView.addSubview(searchBarShadowView)
        contentView.addSubview(searchBarBackground)
        searchBarBackground.contentView.addSubview(searchField)
        searchBarBackground.contentView.addSubview(resultLabel)
        contentView.addSubview(controlsShadowView)
        contentView.addSubview(controlsBackground)
        
        [previousMatchButton, separator, nextMatchButton].forEach {
            controlsBackground.contentView.addSubview($0)
        }
    }
    
    private func configureConstraints() {
        let leading = doneToolbar == nil ? leadingAnchor : safeAreaLayoutGuide.leadingAnchor
        let trailing = doneToolbar == nil ? trailingAnchor : safeAreaLayoutGuide.trailingAnchor
        if let doneToolbar {
            NSLayoutConstraint.activate([
                doneToolbar.leadingAnchor.constraint(equalTo: searchContentView.leadingAnchor),
                doneToolbar.centerYAnchor.constraint(equalTo: searchContentView.centerYAnchor),
                doneToolbar.widthAnchor.constraint(equalToConstant: UX.controlsHeight),
                doneToolbar.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
            ])
        }
        controlsHeightConstraints = [
            searchContentView.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
            searchBarShadowView.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
            controlsShadowView.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
        ]
        NSLayoutConstraint.activate(controlsHeightConstraints)
        resultLabelWidthConstraint = resultLabel.widthAnchor.constraint(equalToConstant: UX.resultLabelWidth)
        let preferredContentWidth = searchContentView.widthAnchor.constraint(
            equalToConstant: UX.contentMaximumWidth
        )
        preferredContentWidth.priority = .defaultHigh
        searchContentViewCenterConstraint = searchContentView.centerXAnchor.constraint(
            equalTo: doneToolbar == nil ? centerXAnchor : safeAreaLayoutGuide.centerXAnchor
        )
        searchContentViewLeadingConstraint = searchContentView.leadingAnchor.constraint(
            equalTo: leading,
            constant: UX.contentLeadingInset
        )
        searchContentViewTrailingConstraint = searchContentView.trailingAnchor.constraint(
            equalTo: trailing,
            constant: -UX.contentTrailingInset
        )
        
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            searchContentViewCenterConstraint,
            searchContentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchContentView.leadingAnchor.constraint(
                greaterThanOrEqualTo: leading,
                constant: UX.contentLeadingInset
            ),
            searchContentView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailing,
                constant: -UX.contentTrailingInset
            ),
            searchContentView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.contentMaximumWidth),
            preferredContentWidth,
            
            searchBarShadowView.leadingAnchor.constraint(
                equalTo: doneToolbar?.trailingAnchor ?? searchContentView.leadingAnchor,
                constant: doneToolbar == nil ? 0 : UX.searchBarToControlsSpacing
            ),
            searchBarShadowView.centerYAnchor.constraint(equalTo: searchContentView.centerYAnchor),
            searchBarShadowView.trailingAnchor.constraint(
                equalTo: controlsShadowView.leadingAnchor,
                constant: -UX.searchBarToControlsSpacing
            ),
            
            searchBarBackground.topAnchor.constraint(equalTo: searchBarShadowView.topAnchor),
            searchBarBackground.leadingAnchor.constraint(equalTo: searchBarShadowView.leadingAnchor),
            searchBarBackground.trailingAnchor.constraint(equalTo: searchBarShadowView.trailingAnchor),
            searchBarBackground.bottomAnchor.constraint(equalTo: searchBarShadowView.bottomAnchor),
            
            searchField.topAnchor.constraint(equalTo: searchBarBackground.contentView.topAnchor),
            searchField.leadingAnchor.constraint(
                equalTo: searchBarBackground.contentView.leadingAnchor,
                constant: UX.searchContentInset
            ),
            searchField.trailingAnchor.constraint(equalTo: resultLabel.leadingAnchor, constant: -UX.resultLabelSpacing),
            searchField.bottomAnchor.constraint(equalTo: searchBarBackground.contentView.bottomAnchor),
            
            resultLabel.trailingAnchor.constraint(
                equalTo: searchBarBackground.contentView.trailingAnchor,
                constant: -UX.searchContentInset
            ),
            resultLabel.centerYAnchor.constraint(equalTo: searchBarBackground.contentView.centerYAnchor),
            resultLabelWidthConstraint,
            
            controlsShadowView.trailingAnchor.constraint(equalTo: searchContentView.trailingAnchor),
            controlsShadowView.centerYAnchor.constraint(equalTo: searchContentView.centerYAnchor),
            controlsShadowView.widthAnchor.constraint(equalToConstant: UX.controlsWidth),
            
            controlsBackground.topAnchor.constraint(equalTo: controlsShadowView.topAnchor),
            controlsBackground.leadingAnchor.constraint(equalTo: controlsShadowView.leadingAnchor),
            controlsBackground.trailingAnchor.constraint(equalTo: controlsShadowView.trailingAnchor),
            controlsBackground.bottomAnchor.constraint(equalTo: controlsShadowView.bottomAnchor),
            
            previousMatchButton.leadingAnchor.constraint(equalTo: controlsBackground.contentView.leadingAnchor),
            previousMatchButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            previousMatchButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            previousMatchButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
            
            separator.leadingAnchor.constraint(equalTo: previousMatchButton.trailingAnchor),
            separator.centerYAnchor.constraint(equalTo: controlsBackground.contentView.centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: UX.separatorWidth),
            separator.heightAnchor.constraint(equalTo: controlsBackground.contentView.heightAnchor, multiplier: 0.42),
            
            nextMatchButton.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            nextMatchButton.trailingAnchor.constraint(equalTo: controlsBackground.contentView.trailingAnchor),
            nextMatchButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            nextMatchButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            nextMatchButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
        ])
    }
    
    private func updateSearchContentLayout() {
        let horizontalSafeArea = doneToolbar == nil ? 0 : safeAreaInsets.left + safeAreaInsets.right
        let availableWidth = bounds.width - horizontalSafeArea - UX.contentLeadingInset - UX.contentTrailingInset
        let shouldCenter = availableWidth >= UX.contentMaximumWidth
        guard searchContentViewCenterConstraint.isActive != shouldCenter else {
            return
        }
        
        searchContentViewCenterConstraint.isActive = shouldCenter
        searchContentViewLeadingConstraint.isActive = !shouldCenter
        searchContentViewTrailingConstraint.isActive = !shouldCenter
    }
    
    private func setResultText(_ text: String?) {
        resultLabel.text = text
        resultLabel.isHidden = text == nil
    }
    
    private func updateNavigationButtons() {
        let enabled = !(searchField.text ?? "").isEmpty
        previousMatchButton.isEnabled = enabled
        nextMatchButton.isEnabled = enabled
        previousMatchButton.alpha = enabled ? 1 : UX.disabledAlpha
        nextMatchButton.alpha = enabled ? 1 : UX.disabledAlpha
    }
    
    private func makeControlButton(
        imageName: String,
        title: String,
        identifier: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.enableLargeContentViewer(title: title, image: UIImage(named: imageName))
        button.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(
            pointSize: UX.controlSymbolPointSize,
            weight: .regular
        )
        button.setImage(UIImage(named: imageName, in: .main, with: configuration), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
