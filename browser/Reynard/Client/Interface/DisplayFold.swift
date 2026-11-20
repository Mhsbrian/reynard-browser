//
//  DisplayFold.swift
//  Reynard
//

import UIKit

/// The fold of an iPhone Duo where it crosses a view.
///
/// The system reports it as a reserved region of kind `.division` (`UIView.reservedRegions(kind:options:)`)
/// and keeps its own alerts, menus, sheets and split views out of it. A view that places its own content
/// asks for the fold in its own coordinates and, while the phone is partly open, keeps each thing it places
/// on one side.
///
/// Every other device, the cover display of an iPhone Duo, and systems before iOS 27.1 report no fold, and
/// a view that is given none lays out as it always has.
///
/// A web page is not one of these views. It stays as wide as the display and is drawn across the fold, as
/// Safari draws it: the page's layout is its author's, a page reflowed into half the width every time the
/// hinge moves would lose its place, and the system's own scrolling views run through the fold too.
struct DisplayFold: Equatable {
    /// The band to keep clear, in the coordinates of the view that asked. It includes the margins the
    /// system wants around the fold, so content may come right up to its edges.
    let frame: CGRect

    /// Whether the phone is partly open, and the band has to be kept clear. Fully open the fold is still
    /// reported, so that a layout can be one that will divide there without rearranging.
    let isActive: Bool

    /// True for a phone held like a book: the fold runs from top to bottom and content sits on its left and
    /// right. False for one standing like a laptop, with content above and below.
    var isVertical: Bool {
        return frame.height >= frame.width
    }
}

extension UIView {
    /// The fold where it crosses this view, in use or not, or nil.
    ///
    /// Read it in `updateConstraints()` or `layoutSubviews()`: UIKit notes the read and runs the method
    /// again when the fold changes.
    var displayFold: DisplayFold? {
        guard #available(iOS 27.1, *) else {
            return nil
        }

        let regions = reservedRegions(kind: .division, options: .includeInactive)
        guard let region = regions.first(where: { !$0.frame.isEmpty }) else {
            return nil
        }
        return DisplayFold(frame: region.frame, isActive: region.isActive)
    }

    /// The fold where it runs from top to bottom through `rect`, a rectangle in this view's coordinates,
    /// in use or not. A grid that it crosses has an even number of columns.
    func verticalDisplayFold(crossing rect: CGRect) -> DisplayFold? {
        guard let fold = displayFold,
              fold.isVertical,
              fold.frame.maxX > rect.minX,
              fold.frame.minX < rect.maxX,
              fold.frame.maxY > rect.minY,
              fold.frame.minY < rect.maxY else {
            return nil
        }
        return fold
    }

    /// The band to keep clear where the fold runs from top to bottom through `rect` and the phone is partly
    /// open: its left and right edges in this view's coordinates, kept within `rect`.
    func activeFoldBand(crossing rect: CGRect) -> ClosedRange<CGFloat>? {
        guard let fold = verticalDisplayFold(crossing: rect), fold.isActive else {
            return nil
        }

        let lowerBound = max(fold.frame.minX, rect.minX)
        return lowerBound...max(lowerBound, min(fold.frame.maxX, rect.maxX))
    }

    /// What covers part of `rect` in this view: the inner camera of an iPhone Duo while it is in use. The
    /// system reports these as reserved regions of kind `.occlusion`.
    func displayOcclusions(crossing rect: CGRect) -> [CGRect] {
        guard #available(iOS 27.1, *) else {
            return []
        }
        return reservedRegions(kind: .occlusion)
            .map { $0.frame }
            .filter { !$0.isEmpty && $0.intersects(rect) }
    }
}

/// The columns of a grid either side of the fold.
///
/// Each side holds its share of the columns and spreads them from its outer edge to the edge of the band, so
/// that the grid divides at the fold and nothing lies in it. With no band the columns spread across the
/// whole width, which is the grid every other device has.
struct FoldedColumns: Equatable {
    let itemWidth: CGFloat
    /// The left edge of each column.
    let origins: [CGFloat]

    /// - Parameters:
    ///   - span: The left and right edges the columns lie between.
    ///   - band: The band to keep clear, in the same coordinates, where there is one.
    ///   - spacing: The least room between two columns.
    ///   - maximumItemWidth: The widest a column may be. Room left over goes between the columns.
    init(
        count: Int,
        span: ClosedRange<CGFloat>,
        band: ClosedRange<CGFloat>?,
        spacing: CGFloat,
        maximumItemWidth: CGFloat = .greatestFiniteMagnitude
    ) {
        let count = max(count, 1)
        var sides = [(span: span, count: count)]
        if let band, band.lowerBound > span.lowerBound, band.upperBound < span.upperBound, count > 1 {
            let leftWidth = band.lowerBound - span.lowerBound
            let rightWidth = span.upperBound - band.upperBound
            var leftCount = Int((CGFloat(count) * leftWidth / (leftWidth + rightWidth)).rounded())
            leftCount = min(max(leftCount, 1), count - 1)
            sides = [
                (span.lowerBound...band.lowerBound, leftCount),
                (band.upperBound...span.upperBound, count - leftCount),
            ]
        } else if let band, band.upperBound > span.lowerBound, band.lowerBound <= span.lowerBound {
            // The band lies over the left edge: everything starts after it.
            sides = [(min(band.upperBound, span.upperBound)...span.upperBound, count)]
        } else if let band, band.lowerBound < span.upperBound, band.upperBound >= span.upperBound {
            sides = [(span.lowerBound...max(band.lowerBound, span.lowerBound), count)]
        }

        let width = sides.map { side -> CGFloat in
            let room = side.span.upperBound - side.span.lowerBound
            return (room - CGFloat(side.count - 1) * spacing) / CGFloat(side.count)
        }.min() ?? 0
        let itemWidth = max(1, min(maximumItemWidth, width))
        var origins: [CGFloat] = []
        for side in sides {
            let room = side.span.upperBound - side.span.lowerBound
            let gap = side.count > 1
            ? max((room - CGFloat(side.count) * itemWidth) / CGFloat(side.count - 1), 0)
            : 0
            for column in 0..<side.count {
                origins.append(side.span.lowerBound + CGFloat(column) * (itemWidth + gap))
            }
        }
        self.itemWidth = itemWidth
        self.origins = origins
    }
}

/// A clear view that follows the fold for whatever it is laid over, for content placed by a view
/// controller or by constraints, which has no layout method of its own to read the fold in.
///
/// Laid over a container, it offers `sideGuide`: the whole container while there is no fold to avoid, and
/// the wider side of it, the leading one where both are alike, while an iPhone Duo is partly open. Content
/// pinned to the guide in place of the container keeps to one side. `onChange` reports the fold in this
/// view's coordinates, for content that divides at it.
final class DisplayFoldReader: UIView {
    struct Reading: Equatable {
        /// The band to keep clear where the fold runs from top to bottom through this view, if any.
        let band: ClosedRange<CGFloat>?
        /// Whether a fold crosses this view at all, in use or not.
        let hasFold: Bool
        let width: CGFloat
    }

    let sideGuide = UILayoutGuide()
    var onChange: ((Reading) -> Void)?
    private(set) var reading = Reading(band: nil, hasFold: false, width: 0)

    private let tracker = DisplayFoldTracker<Reading>()
    private var sideLeftConstraint: NSLayoutConstraint!
    private var sideRightConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        addLayoutGuide(sideGuide)
        sideLeftConstraint = sideGuide.leftAnchor.constraint(equalTo: leftAnchor)
        sideRightConstraint = sideGuide.rightAnchor.constraint(equalTo: rightAnchor)
        NSLayoutConstraint.activate([
            sideLeftConstraint,
            sideRightConstraint,
            sideGuide.topAnchor.constraint(equalTo: topAnchor),
            sideGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lays the reader over `container`, behind what the container already holds.
    func install(over container: UIView, in guide: UILayoutGuide? = nil) {
        container.insertSubview(self, at: 0)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide?.topAnchor ?? container.topAnchor),
            leadingAnchor.constraint(equalTo: guide?.leadingAnchor ?? container.leadingAnchor),
            trailingAnchor.constraint(equalTo: guide?.trailingAnchor ?? container.trailingAnchor),
            bottomAnchor.constraint(equalTo: guide?.bottomAnchor ?? container.bottomAnchor),
        ])
    }

    override func updateConstraints() {
        update()
        super.updateConstraints()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        update()
    }

    private func update() {
        let value = resolvedReading()
        let isFoldChange = tracker.applied.map { $0.width == value.width && $0.band != value.band } ?? false
        tracker.update(
            in: self,
            value: value,
            animated: isFoldChange,
            current: { [weak self] in self?.resolvedReading() ?? value },
            apply: { [weak self] in self?.apply($0) }
        )
    }

    private func resolvedReading() -> Reading {
        return Reading(
            band: activeFoldBand(crossing: bounds),
            hasFold: verticalDisplayFold(crossing: bounds) != nil,
            width: bounds.width
        )
    }

    private func apply(_ value: Reading) {
        reading = value
        var left: CGFloat = 0
        var right: CGFloat = 0
        if let band = value.band {
            let leftWidth = band.lowerBound
            let rightWidth = value.width - band.upperBound
            let prefersLeft = effectiveUserInterfaceLayoutDirection == .leftToRight
            let usesLeft = abs(leftWidth - rightWidth) <= 1 ? prefersLeft : leftWidth > rightWidth
            if usesLeft {
                right = value.width - band.lowerBound
            } else {
                left = band.upperBound
            }
        }
        sideLeftConstraint.constant = left
        sideRightConstraint.constant = -right
        onChange?(value)
    }
}

/// Follows the fold for one view, and moves what the view places with the system's spring when the fold
/// comes or goes under a window that is otherwise still.
///
/// The view works out where its content goes from the fold it reads in `updateConstraints()` or
/// `layoutSubviews()` and hands the answer to `update(in:value:animated:current:apply:)`. A first answer, an
/// answer the view does not want animated, and one that arrives inside an animation the system is already
/// running (a rotation, a move to the other display) are applied at once: they are part of that pass and
/// cost it nothing more. Otherwise the change is made on the next turn of the run loop, inside an animation
/// of its own, because constraints changed during a layout pass take effect without one.
final class DisplayFoldTracker<Value: Equatable> {
    /// What the view's content was last laid out for.
    private(set) var applied: Value?
    private var isChangeScheduled = false

    /// Notes a value the view applied itself, outside `update(in:value:animated:current:apply:)`.
    func noteApplied(_ value: Value) {
        applied = value
    }

    /// - Parameters:
    ///   - view: The view whose content moves.
    ///   - value: Where the content goes, worked out from the fold just read in `view`.
    ///   - animated: Whether a change from `applied` to `value` is the fold coming or going, which is
    ///     animated, and not the view changing size.
    ///   - current: Works `value` out again, for the animated change a moment later.
    ///   - apply: Moves the content by changing constraints. Layout follows.
    func update(
        in view: UIView,
        value: Value,
        animated: Bool,
        current: @escaping () -> Value,
        apply: @escaping (Value) -> Void
    ) {
        guard value != applied else {
            return
        }

        guard animated,
              applied != nil,
              view.window != nil,
              UIView.areAnimationsEnabled,
              UIView.inheritedAnimationDuration == 0,
              !UIAccessibility.isReduceMotionEnabled,
              #available(iOS 17.0, *) else {
            applied = value
            apply(value)
            return
        }

        guard !isChangeScheduled else {
            return
        }

        isChangeScheduled = true
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self else {
                return
            }

            self.isChangeScheduled = false
            guard let view else {
                return
            }

            let value = current()
            guard value != self.applied else {
                return
            }

            self.applied = value
            guard view.window != nil else {
                apply(value)
                return
            }

            UIView.animate(
                springDuration: DisplayFoldAnimation.springDuration,
                bounce: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                apply(value)
                // What moved may have changed the size of what holds it, as wrapped text does.
                (view.window ?? view).layoutIfNeeded()
            }
        }
    }
}

private enum DisplayFoldAnimation {
    static let springDuration: TimeInterval = 0.4
}
