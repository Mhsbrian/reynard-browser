//
//  HomepageEmptyStateViewController.swift
//  Reynard
//

import UIKit

/// What the homepage shows when it has nothing else to show: no favorites, no frequently visited sites, no
/// recently closed tabs, or all three turned off. It says what belongs here and where to change it, in place
/// of a blank page.
final class HomepageEmptyStateViewController: UIViewController {
    private enum UX {
        static let verticalInset: CGFloat = 40
        static let horizontalInset: CGFloat = 24
        static let spacing: CGFloat = 8
        static let symbolPointSize: CGFloat = 48
        static let symbolBottomSpacing: CGFloat = 16
        static let buttonTopSpacing: CGFloat = 16
        static let maximumTextWidth: CGFloat = 420
    }
    
    weak var delegate: HomepageSectionDelegate?
    
    private let symbolView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "reynard.star"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: UX.symbolPointSize, weight: .regular)
        // The words under it say everything the symbol does.
        imageView.isAccessibilityElement = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = HomepageTextMetrics.headingFont(ofSize: 22)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("Nothing Here Yet", comment: "Homepage: title shown when no section has anything to show")
        label.accessibilityTraits = .header
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString(
            "Favorites, websites you visit often and tabs you closed recently appear here.",
            comment: "Homepage: message shown when no section has anything to show"
        )
        return label
    }()
    
    private lazy var settingsButton: UIButton = {
        let button = MinimumTouchTargetButton(type: .system)
        button.setTitle(NSLocalizedString("Open Settings", comment: ""), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.tintColor = .label
        if #available(iOS 13.4, *) {
            button.isPointerInteractionEnabled = true
        }
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let stackView = TouchTargetExtendingStackView(arrangedSubviews: [symbolView, titleLabel, messageLabel, settingsButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = UX.spacing
        stackView.setCustomSpacing(UX.symbolBottomSpacing, after: symbolView)
        stackView.setCustomSpacing(UX.buttonTopSpacing, after: messageLabel)
        view.addSubview(stackView)
        
        let preferredWidth = stackView.widthAnchor.constraint(equalToConstant: UX.maximumTextWidth)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: UX.verticalInset),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.verticalInset),
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: UX.horizontalInset),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -UX.horizontalInset),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumTextWidth),
            preferredWidth,
        ])
    }
    
    @objc private func openSettings() {
        delegate?.homepageSectionDidSelectSettings(self)
    }
}
