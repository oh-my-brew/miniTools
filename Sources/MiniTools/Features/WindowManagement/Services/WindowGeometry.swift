import AppKit
import CoreGraphics

struct WindowLayoutScreenGeometry: Equatable, Sendable {
    let fullFrame: CGRect
    let visibleFrame: CGRect
    let localizedName: String
    let isBuiltIn: Bool

    init(
        fullFrame: CGRect,
        visibleFrame: CGRect,
        localizedName: String = "",
        isBuiltIn: Bool = false
    ) {
        self.fullFrame = fullFrame
        self.visibleFrame = visibleFrame
        self.localizedName = localizedName
        self.isBuiltIn = isBuiltIn
    }
}

struct WindowFrameSettlementTracker {
    private let initialSize: CGSize
    private let tolerance: CGFloat
    private let requiredStableSamples: Int
    private var previousSize: CGSize
    private var observedResize: Bool
    private var stableSampleCount = 0

    init(
        initialFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 1,
        requiredStableSamples: Int = 4
    ) {
        initialSize = initialFrame.size
        self.tolerance = tolerance
        self.requiredStableSamples = requiredStableSamples
        previousSize = initialFrame.size
        observedResize = Self.sizesAreClose(
            initialFrame.size,
            targetFrame.size,
            tolerance: tolerance
        )
    }

    mutating func record(_ frame: CGRect) -> Bool {
        let currentSize = frame.size
        if !Self.sizesAreClose(currentSize, initialSize, tolerance: tolerance) {
            observedResize = true
        }

        if observedResize,
           Self.sizesAreClose(currentSize, previousSize, tolerance: tolerance) {
            stableSampleCount += 1
        } else {
            stableSampleCount = 0
        }
        previousSize = currentSize

        return observedResize && stableSampleCount >= requiredStableSamples
    }

    private static func sizesAreClose(
        _ lhs: CGSize,
        _ rhs: CGSize,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

enum WindowGeometry {
    static func targetFrame(for unitFrame: UnitWindowFrame, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: round(visibleFrame.minX + visibleFrame.width * unitFrame.x),
            y: round(visibleFrame.minY + visibleFrame.height * unitFrame.y),
            width: round(visibleFrame.width * unitFrame.width),
            height: round(visibleFrame.height * unitFrame.height)
        )
    }

    static func nextTarget(
        currentFrame: CGRect,
        candidates: [CGRect],
        tolerance: CGFloat = 10
    ) -> CGRect? {
        guard let first = candidates.first else { return nil }
        guard candidates.count > 1 else { return first }

        if let currentIndex = candidates.firstIndex(where: {
            framesAreClose(currentFrame, $0, tolerance: tolerance)
        }) {
            return candidates[(currentIndex + 1) % candidates.count]
        }

        if let currentIndex = constrainedCandidateIndex(
            currentFrame: currentFrame,
            candidates: candidates,
            tolerance: tolerance
        ) {
            return candidates[(currentIndex + 1) % candidates.count]
        }
        return first
    }

    static func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    static func correctedOriginAfterApplyingFrame(
        actualFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 10
    ) -> CGPoint? {
        guard
            abs(actualFrame.minX - targetFrame.minX) > tolerance
                || abs(actualFrame.minY - targetFrame.minY) > tolerance
        else {
            return nil
        }
        return targetFrame.origin
    }

    private static func constrainedCandidateIndex(
        currentFrame: CGRect,
        candidates: [CGRect],
        tolerance: CGFloat
    ) -> Int? {
        let components: [(CGRect) -> CGFloat] = [
            { $0.minX }, { $0.minY }, { $0.width }, { $0.height }
        ]
        let varyingComponents = components.compactMap { component -> ((CGRect) -> CGFloat, CGFloat)? in
            let values = candidates.map(component)
            guard let minimum = values.min(), let maximum = values.max() else { return nil }
            let spread = maximum - minimum
            return spread > tolerance ? (component, spread) : nil
        }
        guard !varyingComponents.isEmpty else { return nil }

        return candidates.firstIndex { candidate in
            varyingComponents.allSatisfy { component, spread in
                let allowedDifference = max(tolerance, spread * 0.1)
                return abs(component(currentFrame) - component(candidate)) <= allowedDifference
            }
        }
    }

    static func appKitToAccessibility(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func frameByMoving(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let targetSize = CGSize(
            width: min(frame.width, destination.width),
            height: min(frame.height, destination.height)
        )
        let sourceTravelX = max(0, source.width - frame.width)
        let sourceTravelY = max(0, source.height - frame.height)
        let relativeX = sourceTravelX > 0
            ? min(max((frame.minX - source.minX) / sourceTravelX, 0), 1)
            : 0.5
        let relativeY = sourceTravelY > 0
            ? min(max((frame.minY - source.minY) / sourceTravelY, 0), 1)
            : 0.5
        let destinationTravelX = max(0, destination.width - targetSize.width)
        let destinationTravelY = max(0, destination.height - targetSize.height)

        return CGRect(
            x: round(destination.minX + relativeX * destinationTravelX),
            y: round(destination.minY + relativeY * destinationTravelY),
            width: round(targetSize.width),
            height: round(targetSize.height)
        )
    }

    static func centeredFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: round(visibleFrame.midX - frame.width / 2),
            y: round(visibleFrame.midY - frame.height / 2),
            width: frame.width,
            height: frame.height
        )
    }

    static func screenIndex(
        containing point: CGPoint,
        geometries: [WindowLayoutScreenGeometry]
    ) -> Int {
        if let index = geometries.firstIndex(where: { $0.fullFrame.contains(point) }) {
            return index
        }
        return geometries.enumerated().min { lhs, rhs in
            lhs.element.fullFrame.distance(to: point) < rhs.element.fullFrame.distance(to: point)
        }?.offset ?? 0
    }

    @MainActor
    static func screenGeometries() -> [WindowLayoutScreenGeometry] {
        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        return screens.map { screen in
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
            WindowLayoutScreenGeometry(
                fullFrame: appKitToAccessibility(screen.frame, primaryScreenMaxY: primaryMaxY),
                visibleFrame: appKitToAccessibility(screen.visibleFrame, primaryScreenMaxY: primaryMaxY),
                localizedName: screen.localizedName,
                isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.fullFrame.minX - rhs.fullFrame.minX) > 1 {
                return lhs.fullFrame.minX < rhs.fullFrame.minX
            }
            return lhs.fullFrame.minY < rhs.fullFrame.minY
        }
    }

    static func screenGeometry(
        for windowFrame: CGRect,
        geometries: [WindowLayoutScreenGeometry]
    ) -> WindowLayoutScreenGeometry {
        if let containing = geometries.first(where: { $0.fullFrame.contains(windowFrame.center) }) {
            return containing
        }
        return geometries.max { lhs, rhs in
            lhs.fullFrame.intersectionArea(with: windowFrame)
                < rhs.fullFrame.intersectionArea(with: windowFrame)
        } ?? WindowLayoutScreenGeometry(fullFrame: windowFrame, visibleFrame: windowFrame)
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    fileprivate func intersectionArea(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }

    fileprivate func distance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return hypot(dx, dy)
    }
}
