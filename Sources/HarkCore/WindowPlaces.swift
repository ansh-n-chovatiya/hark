import CoreGraphics
import Foundation

/// Where a window can be put on a screen.
public enum WindowPlace: String, CaseIterable, Sendable {
    case left, right, top, bottom
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
    case leftThird = "left_third"
    case middleThird = "middle_third"
    case rightThird = "right_third"
    case leftTwoThirds = "left_two_thirds"
    case rightTwoThirds = "right_two_thirds"
    case full
    case centre
    case nextScreen = "next_screen"
}

/// Window geometry. Every rectangle here has its origin at the top left with y growing downwards,
/// as Accessibility reports windows; `topLeft(fromBottomLeft:mainHeight:)` converts a screen frame.
public enum WindowPlaces {
    /// The part of a screen a tiled place covers, as fractions of its width and height.
    private struct Span {
        let x: ClosedRange<CGFloat>
        let y: ClosedRange<CGFloat>
    }

    private static let third: CGFloat = 1.0 / 3
    private static let twoThirds: CGFloat = 2.0 / 3

    private static func span(of place: WindowPlace) -> Span? {
        switch place {
        case .left: Span(x: 0...0.5, y: 0...1)
        case .right: Span(x: 0.5...1, y: 0...1)
        case .top: Span(x: 0...1, y: 0...0.5)
        case .bottom: Span(x: 0...1, y: 0.5...1)
        case .topLeft: Span(x: 0...0.5, y: 0...0.5)
        case .topRight: Span(x: 0.5...1, y: 0...0.5)
        case .bottomLeft: Span(x: 0...0.5, y: 0.5...1)
        case .bottomRight: Span(x: 0.5...1, y: 0.5...1)
        case .leftThird: Span(x: 0...third, y: 0...1)
        case .middleThird: Span(x: third...twoThirds, y: 0...1)
        case .rightThird: Span(x: twoThirds...1, y: 0...1)
        case .leftTwoThirds: Span(x: 0...twoThirds, y: 0...1)
        case .rightTwoThirds: Span(x: third...1, y: 0...1)
        case .full: Span(x: 0...1, y: 0...1)
        case .centre, .nextScreen: nil
        }
    }

    /// The frame a window takes at a place on the screen whose usable area is `screen`. A place
    /// that names no spot on this screen (`nextScreen`) leaves the window where it is.
    public static func frame(for place: WindowPlace, window: CGRect, in screen: CGRect) -> CGRect {
        if let span = span(of: place) { return tile(span, of: screen) }
        return place == .centre ? centred(window.size, in: screen) : window
    }

    /// Edges are rounded rather than sizes, so neighbouring places meet without a gap or overlap.
    private static func tile(_ span: Span, of screen: CGRect) -> CGRect {
        let left = screen.minX + (screen.width * span.x.lowerBound).rounded()
        let right = screen.minX + (screen.width * span.x.upperBound).rounded()
        let top = screen.minY + (screen.height * span.y.lowerBound).rounded()
        let bottom = screen.minY + (screen.height * span.y.upperBound).rounded()
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func centred(_ size: CGSize, in screen: CGRect) -> CGRect {
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        return CGRect(
            x: screen.minX + ((screen.width - width) / 2).rounded(),
            y: screen.minY + ((screen.height - height) / 2).rounded(),
            width: width, height: height)
    }

    /// The screen a window is mostly on, or the nearest one when it is on none. Nil with no screens.
    public static func screenIndex(of window: CGRect, in screens: [CGRect]) -> Int? {
        let overlaps = screens.map { area(of: $0.intersection(window)) }
        if let most = overlaps.max(), most > 0 { return overlaps.firstIndex(of: most) }
        let distances = screens.map { distance(from: $0, to: window) }
        return distances.min().flatMap(distances.firstIndex(of:))
    }

    /// The screen after this one, wrapping round. Nil when there is no other screen.
    public static func nextIndex(after index: Int, count: Int) -> Int? {
        count > 1 ? (index + 1) % count : nil
    }

    /// The same relative place and share of the screen on another screen.
    public static func frame(of window: CGRect, movedFrom old: CGRect, to new: CGRect) -> CGRect {
        guard old.width > 0, old.height > 0 else { return centred(window.size, in: new) }
        let width = min((window.width / old.width * new.width).rounded(), new.width)
        let height = min((window.height / old.height * new.height).rounded(), new.height)
        let x = new.minX + ((window.minX - old.minX) / old.width * new.width).rounded()
        let y = new.minY + ((window.minY - old.minY) / old.height * new.height).rounded()
        return CGRect(
            x: min(max(x, new.minX), new.maxX - width),
            y: min(max(y, new.minY), new.maxY - height),
            width: width, height: height)
    }

    /// AppKit measures screens from the bottom left of the main display with y growing upwards.
    public static func topLeft(fromBottomLeft rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether a window ended up where it was sent, allowing for apps that snap their size.
    public static func isClose(_ frame: CGRect, to wanted: CGRect, within points: CGFloat) -> Bool {
        abs(frame.minX - wanted.minX) <= points && abs(frame.minY - wanted.minY) <= points
            && abs(frame.width - wanted.width) <= points && abs(frame.height - wanted.height) <= points
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(from screen: CGRect, to window: CGRect) -> CGFloat {
        hypot(screen.midX - window.midX, screen.midY - window.midY)
    }
}
