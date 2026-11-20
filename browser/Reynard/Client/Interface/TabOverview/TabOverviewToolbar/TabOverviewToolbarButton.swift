//
//  TabOverviewToolbarButton.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewToolbarButton: UIButton {
    private enum UX {
        static let toolbarButtonSideLength: CGFloat = TouchTarget.minimumSideLength
        static let toolbarButtonCornerRadius: CGFloat = toolbarButtonSideLength / 2
        static let toolbarButtonBorderWidth: CGFloat = 1
        static let toolbarButtonSymbolPointSize: CGFloat = 17
        static let disabledToolbarButtonAlpha: CGFloat = 0.35
    }
    
    enum Action {
        case clear
        case add
        case done
        
        /// The name of the action, for the buttons that show it as a symbol.
        var title: String {
            switch self {
            case .clear: return NSLocalizedString("Close Tabs", comment: "The button in the tab overview that opens the menu for closing tabs")
            case .add: return NSLocalizedString("New Tab", comment: "")
            case .done: return NSLocalizedString("Done", comment: "")
            }
        }
        
        /// Gives a bar button item that shows the action as a symbol its name.
        func name(_ item: UIBarButtonItem) {
            item.accessibilityLabel = title
            item.accessibilityIdentifier = accessibilityIdentifier
            item.largeContentSizeImage = item.image
            item.title = item.title ?? title
        }
        
        var accessibilityIdentifier: String {
            switch self {
            case .clear: return AccessibilityIdentifier.TabOverview.closeTabs
            case .add: return AccessibilityIdentifier.TabOverview.newTab
            case .done: return AccessibilityIdentifier.TabOverview.done
            }
        }
    }
    
    private let action: Action
    private var legacyMenuDelegate: LegacyMenuDelegate?
    
    init(action: Action) {
        self.action = action
        super.init(frame: .zero)
        if #available(iOS 13.4, *) {
            isPointerInteractionEnabled = true
        }
        configureAppearance()
        configureImage()
        configureConstraints()
        accessibilityLabel = action.title
        accessibilityIdentifier = action.accessibilityIdentifier
        enableLargeContentViewer(title: action.title, image: UIImage(named: symbolName))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setActionEnabled(_ enabled: Bool) {
        isEnabled = enabled
        // The system dims a disabled glass button by itself.
        if #unavailable(iOS 26.0) {
            alpha = enabled ? 1 : UX.disabledToolbarButtonAlpha
        }
    }
    
    func installMenu(_ menu: UIMenu?) {
        if #available(iOS 14.0, *) {
            self.menu = menu
            showsMenuAsPrimaryAction = menu != nil
        } else {
            if legacyMenuDelegate == nil {
                let delegate = LegacyMenuDelegate()
                addInteraction(UIContextMenuInteraction(delegate: delegate))
                addTarget(self, action: #selector(presentLegacyMenu), for: .touchUpInside)
                legacyMenuDelegate = delegate
            }
            legacyMenuDelegate?.menu = menu
        }
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            // The system's glass buttons, one for each action. They were items in a toolbar 146 points wide,
            // and a toolbar that narrow now moves its items into an overflow menu; a row of buttons cannot.
            var configuration = action == .done
            ? UIButton.Configuration.prominentGlass()
            : UIButton.Configuration.glass()
            configuration.image = UIImage(named: symbolName)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: UX.toolbarButtonSymbolPointSize,
                weight: action == .done ? .semibold : .regular
            )
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = action == .done ? .label : nil
            // Done is the label colour with its symbol in the background colour, as it was before glass. The
            // system gives a button on a light surface a light appearance of its own, in which the
            // background colour would be the surface's own colour: so the symbol's colour is resolved for the
            // window the button is in.
            if action == .done {
                configuration.imageColorTransformer = UIConfigurationColorTransformer { [weak self] _ in
                    let traits = self?.window?.traitCollection ?? UITraitCollection.current
                    return UIColor.systemBackground.resolvedColor(with: traits)
                }
            } else {
                configuration.baseForegroundColor = .label
            }
            configuration.contentInsets = .zero
            self.configuration = configuration
            tintColor = .label
            return
        }
        
        tintColor = action == .done ? .systemBackground : .label
        backgroundColor = action == .done ? .label : .quaternarySystemFill
        layer.borderWidth = action == .done ? 0 : UX.toolbarButtonBorderWidth
        layer.borderColor = action == .done ? UIColor.clear.cgColor : UIColor.systemFill.cgColor
        layer.cornerCurve = .continuous
        layer.cornerRadius = UX.toolbarButtonCornerRadius
    }
    
    private func configureImage() {
        if #available(iOS 26.0, *) {
            return
        }
        
        setImage(UIImage(named: symbolName), for: .normal)
        setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.toolbarButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
    }
    
    private func configureConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UX.toolbarButtonSideLength),
            heightAnchor.constraint(equalTo: widthAnchor),
        ])
    }
    
    private var symbolName: String {
        switch action {
        case .clear: return "reynard.trash"
        case .add: return "reynard.plus"
        case .done: return "reynard.checkmark"
        }
    }
    
    @objc private func presentLegacyMenu() {
        guard let interaction = interactions.compactMap({ $0 as? UIContextMenuInteraction }).first else {
            return
        }
        
        let selector = NSSelectorFromString("_presentMenuAtLocation:")
        guard interaction.responds(to: selector) else {
            return
        }
        
        let center = NSValue(cgPoint: CGPoint(x: bounds.midX, y: bounds.midY))
        _ = interaction.perform(selector, with: center)
    }
}

@available(iOS 13.0, *)
private final class LegacyMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    var menu: UIMenu?
    
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            menu
        }
    }
}
