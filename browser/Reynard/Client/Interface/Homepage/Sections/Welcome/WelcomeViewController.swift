//
//  WelcomeViewController.swift
//  Reynard
//

import UIKit

/// The first thing a new install shows: what Reynard is, and three things worth knowing, on the homepage.
///
/// It is a card and not a sequence of screens. Nothing has to be set up before browsing, so the address bar
/// and the favorites under the card work from the first second, and the card is gone for good as soon as it
/// is dismissed or a page is opened. The Human Interface Guidelines ask for onboarding that is fast and
/// optional, and that lets people into the app before it asks anything of them.
final class WelcomeViewController: UIViewController, HomepageRecommendationViewController {
    private enum UX {
        static let horizontalInset: CGFloat = 2
        static let sectionBottomSpacing: CGFloat = 24
        static let cornerRadius: CGFloat = 17
        static let labelSpacing: CGFloat = 8
        static let pointsTopSpacing: CGFloat = 18
        static let pointSpacing: CGFloat = 14
        static let pointIconSpacing: CGFloat = 14
        static let pointIconSize: CGFloat = 22
        static let pointIconColumnWidth: CGFloat = 30
        static let maximumStackedIconSide: CGFloat = 44
        static let pointTextSpacing: CGFloat = 2
        static let buttonTopSpacing: CGFloat = 22
        static let buttonHeight: CGFloat = 50
        static let buttonCornerRadius: CGFloat = 14
        static let titleFontSize: CGFloat = 28
        static let titleMaximumFontSize: CGFloat = 40
        static let narrowContentInset: CGFloat = 22
        static let wideContentInset: CGFloat = 28
        static let expandedContentInset: CGFloat = 32
        static let maximumButtonWidth: CGFloat = 360
    }

    private struct Point {
        let symbol: String
        let title: String
        let detail: String
    }

    weak var delegate: HomepageSectionDelegate?

    private var contentMode: HomepageContentMode = .embeddedNarrow
    private var isPrivateBrowsing = false

    private static let points = [
        Point(
            symbol: "reynard.globe",
            title: NSLocalizedString("A Different Engine", comment: "Welcome card: heading of the point about the Gecko engine"),
            detail: NSLocalizedString(
                "Reynard runs on Gecko, the engine behind Firefox.",
                comment: "Welcome card: the point about the Gecko engine"
            )
        ),
        Point(
            symbol: "reynard.puzzlepiece.extension",
            title: NSLocalizedString("Add-ons", comment: ""),
            detail: NSLocalizedString(
                "Install Firefox add-ons, content blockers included.",
                comment: "Welcome card: the point about add-ons"
            )
        ),
        Point(
            symbol: "reynard.lock.fill",
            title: NSLocalizedString("Private From the Start", comment: "Welcome card: heading of the point about tracking protection"),
            detail: NSLocalizedString(
                "Enhanced Tracking Protection is already on.",
                comment: "Welcome card: the point about tracking protection"
            )
        ),
    ]

    static func isShown(isPrivateBrowsing: Bool, contentMode: HomepageContentMode) -> Bool {
        return !Prefs.HomepageSettings.hasSeenWelcome && !isPrivateBrowsing && !contentMode.isDetached
    }

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.cornerRadius
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()

    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    /// Keeps the card's words and button on one side of the fold of an iPhone Duo that is partly open.
    private let foldReader = DisplayFoldReader()

    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = UX.labelSpacing
        return stackView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        // A title is large to begin with. It grows with the text size until a long word would no longer
        // fit a phone's width, and the text under it goes on growing.
        label.font = UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: .systemFont(ofSize: UX.titleFontSize, weight: .bold),
            maximumPointSize: UX.titleMaximumFontSize
        )
        label.text = NSLocalizedString("Welcome to Reynard", comment: "Welcome card: title")
        label.textColor = .label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityTraits = .header
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.text = NSLocalizedString(
            "Search or enter an address to start browsing.",
            comment: "Welcome card: the sentence under the title"
        )
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let pointsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = UX.pointSpacing
        return stackView
    }()

    // The one prominent button, drawn as the error page draws its own: the system's prominent glass where
    // there is glass, and the label colour before that. Its title wraps at the largest text sizes.
    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        let title = NSLocalizedString("Start Browsing", comment: "Welcome card: the button that dismisses it")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.prominentGlass()
            configuration.title = title
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.titleAlignment = .center
            configuration.baseBackgroundColor = .label
            configuration.cornerStyle = .capsule
            configuration.buttonSize = .large
            button.configuration = configuration
        } else {
            button.setTitle(title, for: .normal)
            button.backgroundColor = .label
            button.setTitleColor(.systemBackground, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.layer.cornerCurve = .continuous
            button.layer.cornerRadius = UX.buttonCornerRadius
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        }
        button.accessibilityIdentifier = AccessibilityIdentifier.Homepage.welcomeDismiss
        if #available(iOS 13.4, *) {
            button.isPointerInteractionEnabled = true
        }
        button.addTarget(self, action: #selector(dismissWelcome), for: .touchUpInside)
        return button
    }()

    private let buttonContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureConstraints()
        updateContentInsets()
        updateVisibility()
        view.accessibilityIdentifier = AccessibilityIdentifier.Homepage.welcome
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVisibility()
    }

    func setContentMode(_ contentMode: HomepageContentMode) {
        guard self.contentMode != contentMode else {
            return
        }

        self.contentMode = contentMode
        if isViewLoaded {
            updateContentInsets()
            updateVisibility()
        }
    }

    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        guard self.isPrivateBrowsing != isPrivateBrowsing else {
            return
        }

        self.isPrivateBrowsing = isPrivateBrowsing
        if isViewLoaded {
            updateVisibility()
        }
    }

    // MARK: - Configuration

    private func configureHierarchy() {
        view.backgroundColor = .clear
        view.addSubview(cardView)
        cardView.addSubview(backgroundView)
        cardView.addSubview(contentStackView)
        foldReader.install(over: cardView, in: cardView.layoutMarginsGuide)

        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(pointsStackView)
        contentStackView.addArrangedSubview(buttonContainerView)
        contentStackView.setCustomSpacing(UX.pointsTopSpacing, after: messageLabel)
        contentStackView.setCustomSpacing(UX.buttonTopSpacing, after: pointsStackView)

        Self.points.forEach { pointsStackView.addArrangedSubview(makePointView($0)) }
        buttonContainerView.addSubview(continueButton)
    }

    private func configureConstraints() {
        // The button's width comes from the card and never from its own title: as wide as the text column on a
        // phone, and no wider than is comfortable on a larger display.
        let fillsColumn = continueButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor)
        fillsColumn.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -UX.sectionBottomSpacing),

            backgroundView.topAnchor.constraint(equalTo: cardView.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: cardView.layoutMarginsGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: foldReader.sideGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: foldReader.sideGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: cardView.layoutMarginsGuide.bottomAnchor),

            continueButton.topAnchor.constraint(equalTo: buttonContainerView.topAnchor),
            continueButton.bottomAnchor.constraint(equalTo: buttonContainerView.bottomAnchor),
            continueButton.leadingAnchor.constraint(equalTo: buttonContainerView.leadingAnchor),
            continueButton.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumButtonWidth),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.buttonHeight),
            fillsColumn,
        ])
    }

    /// A symbol with a heading and a sentence beside it. VoiceOver reads the two as one element.
    ///
    /// Every size here comes from a constraint. The symbol's box is a fixed square for the text size in use,
    /// so nothing in the row is sized by an image's own measurements, and the labels get their width from the
    /// row alone.
    private func makePointView(_ point: Point) -> UIView {
        let metrics = UIFontMetrics(forTextStyle: .body)
        let scaledIconSide = metrics.scaledValue(for: UX.pointIconColumnWidth)
        
        let iconView = UIImageView(image: UIImage(named: point.symbol))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        iconView.tintColor = .label
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: min(metrics.scaledValue(for: UX.pointIconSize), UX.maximumStackedIconSide * 0.8),
            weight: .regular
        )
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = point.title
        
        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = point.detail
        
        let row = UIView()
        row.addSubview(iconView)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        
        // At the accessibility text sizes the words need the whole width of the card, so the symbol goes
        // above them instead of beside them.
        let stacksVertically = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let iconSide = stacksVertically ? min(scaledIconSide, UX.maximumStackedIconSide) : scaledIconSide
        if stacksVertically {
            iconView.contentMode = .scaleAspectFit
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: UX.pointTextSpacing * 3),
            ])
        } else {
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: UX.pointIconSpacing),
                titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
                iconView.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: row.topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSide),
            iconView.heightAnchor.constraint(equalToConstant: iconSide),
            
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: UX.pointTextSpacing),
            detailLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(point.title), \(point.detail)"
        row.accessibilityTraits = .staticText
        return row
    }
    
    // MARK: - Actions

    @objc private func dismissWelcome() {
        Prefs.HomepageSettings.hasSeenWelcome = true
    }

    // MARK: - Layout

    private func updateVisibility() {
        view.isHidden = !Self.isShown(isPrivateBrowsing: isPrivateBrowsing, contentMode: contentMode)
    }

    private func updateContentInsets() {
        let inset: CGFloat
        switch contentMode {
        case .embeddedNarrow, .detachedNarrow:
            inset = UX.narrowContentInset
        case .embeddedWide, .detachedWide:
            inset = UX.wideContentInset
        case .embeddedExpanded:
            inset = UX.expandedContentInset
        }
        cardView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
    }
}
