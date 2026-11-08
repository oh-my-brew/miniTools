import AppKit
import CoreGraphics

struct WindowLayoutScreenGeometry: Equatable, Sendable {
    let fullFrame: CGRect
    let visibleFrame: CGRect

    init(
        fullFrame: CGRect,
        visibleFrame: CGRect
    ) {
        self.fullFrame = fullFrame
        self.visibleFrame = visibleFrame
    }
}

enum WindowFrameMutationOrder: Equatable, Sendable {
    case positionThenSize
    case sizeThenPosition
}

enum WindowFrameFollowUp: Equatable, Sendable {
    case complete
    case correctPosition
    case settleAndRetrySize
}

struct WindowFrameSettlementTracker {
    private let initialSize: CGSize
    private let tolerance: CGFloat
    private let requiredStableSamples: Int
    private var previousSize: CGSize
    private var observedWidthChange: Bool
    private var observedHeightChange: Bool
    private var stableSampleCount = 0

    init(
        initialFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 1,
        requiredStableSamples: Int = 8
    ) {
        initialSize = initialFrame.size
        self.tolerance = tolerance
        self.requiredStableSamples = requiredStableSamples
        previousSize = initialFrame.size
        observedWidthChange = Self.dimensionsAreClose(
            initialFrame.width,
            targetFrame.width,
            tolerance: tolerance
        )
        observedHeightChange = Self.dimensionsAreClose(
            initialFrame.height,
            targetFrame.height,
            tolerance: tolerance
        )
    }

    mutating func record(_ frame: CGRect) -> Bool {
        let currentSize = frame.size
        if !Self.dimensionsAreClose(
            currentSize.width,
            initialSize.width,
            tolerance: tolerance
        ) {
            observedWidthChange = true
        }
        if !Self.dimensionsAreClose(
            currentSize.height,
            initialSize.height,
            tolerance: tolerance
        ) {
            observedHeightChange = true
        }

        if observedWidthChange,
           observedHeightChange,
           Self.sizesAreClose(currentSize, previousSize, tolerance: tolerance) {
            stableSampleCount += 1
        } else {
            stableSampleCount = 0
        }
        previousSize = currentSize

        return observedWidthChange
            && observedHeightChange
            && stableSampleCount >= requiredStableSamples
    }

    private static func sizesAreClose(
        _ lhs: CGSize,
        _ rhs: CGSize,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func dimensionsAreClose(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}

enum WindowGeometry {
    static func frameFollowUp(
        actualFrame: CGRect,
        targetFrame: CGRect
    ) -> WindowFrameFollowUp {
        if correctedSizeAfterApplyingFrame(
            actualFrame: actualFrame,
            targetFrame: targetFrame
        ) != nil {
            return .settleAndRetrySize
        }
        if correctedOriginAfterApplyingFrame(
            actualFrame: actualFrame,
            targetFrame: targetFrame
        ) != nil {
            return .correctPosition
        }
        return .complete
    }

    static func frameMutationOrder(
        currentFrame: CGRect,
        targetFrame: CGRect,
        visibleFrame: CGRect,
        tolerance: CGFloat = 1
    ) -> WindowFrameMutationOrder {
        let permittedFrame = visibleFrame.insetBy(dx: -tolerance, dy: -tolerance)
        let targetSizeAtCurrentOrigin = CGRect(
            origin: currentFrame.origin,
            size: targetFrame.size
        )
        let currentSizeAtTargetOrigin = CGRect(
            origin: targetFrame.origin,
            size: currentFrame.size
        )

        // Move first only when the requested size would hit a screen edge at
        // the current origin and the existing window can safely move to the
        // target origin. If the existing size cannot fit there (for example,
        // shrinking a full-width window into the right half), shrink first.
        if !permittedFrame.contains(targetSizeAtCurrentOrigin),
           permittedFrame.contains(currentSizeAtTargetOrigin) {
            return .positionThenSize
        }
        return .sizeThenPosition
    }

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

    static func correctedSizeAfterApplyingFrame(
        actualFrame: CGRect,
        targetFrame: CGRect,
        tolerance: CGFloat = 8
    ) -> CGSize? {
        guard
            abs(actualFrame.width - targetFrame.width) > tolerance
                || abs(actualFrame.height - targetFrame.height) > tolerance
        else {
            return nil
        }
        return targetFrame.size
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

        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        return candidates.firstIndex { candidate in
            // 只有窗口确实位于该候选所在区域时才继续循环。窗口在别的区域
            // 但尺寸恰好相近时（例如整块左半屏按右上区域快捷键），应当从
            // 第一个候选（半宽）重新开始。
            guard contains(center, in: candidate, margin: tolerance) else { return false }

            return varyingComponents.allSatisfy { component, spread in
                let allowedDifference = max(tolerance, spread * 0.1)
                return abs(component(currentFrame) - component(candidate)) <= allowedDifference
            }
        }
    }

    private static func contains(_ point: CGPoint, in rect: CGRect, margin: CGFloat) -> Bool {
        let inset = rect.insetBy(dx: margin, dy: margin)
        return (inset.isEmpty ? rect : inset).contains(point)
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

    /// Normalize against usable logical coordinates, not physical display pixels.
    static func frameByScaling(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0,
              destination.width > 0, destination.height > 0 else {
            return frameByMoving(frame, from: source, to: destination)
        }
        let width = min(1, max(0, frame.width / source.width))
        let height = min(1, max(0, frame.height / source.height))
        let x = min(max(0, (frame.minX - source.minX) / source.width), 1 - width)
        let y = min(max(0, (frame.minY - source.minY) / source.height), 1 - height)
        // Round edges together so full-width/right/bottom targets stay anchored.
        let left = round(destination.minX + x * destination.width)
        let top = round(destination.minY + y * destination.height)
        let right = round(destination.minX + (x + width) * destination.width)
        let bottom = round(destination.minY + (y + height) * destination.height)
        return CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
    }

    static func centeredFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: round(visibleFrame.midX - frame.width / 2),
            y: round(visibleFrame.midY - frame.height / 2),
            width: frame.width,
            height: frame.height
        )
    }

    /// Compare corresponding corners in AX (top-left origin) coordinates.
    /// Both axes must match; a single touching edge does not select a corner.
    static func composedResizeAnchor(currentFrame: CGRect, visibleFrame: CGRect,
                                     tolerance: CGFloat = 8) -> ComposedWindowPlacement {
        let left = abs(currentFrame.minX - visibleFrame.minX) <= tolerance
        let right = abs(currentFrame.maxX - visibleFrame.maxX) <= tolerance
        let top = abs(currentFrame.minY - visibleFrame.minY) <= tolerance
        let bottom = abs(currentFrame.maxY - visibleFrame.maxY) <= tolerance
        if left && top { return .upperLeft }
        if left && bottom { return .lowerLeft }
        if right && top { return .upperRight }
        if right && bottom { return .lowerRight }
        return .center
    }

    static func composedSizePlacement(currentFrame: CGRect, visibleFrame: CGRect) -> WindowFramePlacement {
        WindowFramePlacement(resizing: composedResizeAnchor(currentFrame: currentFrame, visibleFrame: visibleFrame),
                             currentFrame: currentFrame, visible: visibleFrame)
    }

    /// Same-size commands leave both position and size alone. Otherwise keep
    /// the first matching corner, or center if no corner is within 8pt.
    static func composedSizeTargetFrame(
        currentFrame: CGRect,
        size: ComposedWindowSizeTarget,
        visibleFrame: CGRect
    ) -> CGRect? {
        let target = targetFrame(for: size.frame, in: visibleFrame)
        guard correctedSizeAfterApplyingFrame(actualFrame: currentFrame, targetFrame: target) != nil else {
            return nil
        }
        let placement = composedSizePlacement(currentFrame: currentFrame, visibleFrame: visibleFrame)
        return CGRect(origin: placement.origin(for: target.size), size: target.size)
    }

    static func composedPlacementTarget(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        placement: ComposedWindowPlacement
    ) -> ComposedWindowPlacementTarget {
        let metadata: (String, String)
        switch placement {
        case .upperLeft: metadata = ("position.topLeft", "左上对齐")
        case .lowerLeft: metadata = ("position.bottomLeft", "左下对齐")
        case .upperRight: metadata = ("position.topRight", "右上对齐")
        case .lowerRight: metadata = ("position.bottomRight", "右下对齐")
        case .center: metadata = ("position.center", "窗口居中")
        }
        return ComposedWindowPlacementTarget(
            frame: CGRect(
                origin: WindowFramePlacement(composed: placement, visible: visibleFrame).origin(for: currentFrame.size),
                size: currentFrame.size
            ),
            statisticsID: metadata.0,
            title: metadata.1
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
            return WindowLayoutScreenGeometry(
                fullFrame: appKitToAccessibility(screen.frame, primaryScreenMaxY: primaryMaxY),
                visibleFrame: appKitToAccessibility(screen.visibleFrame, primaryScreenMaxY: primaryMaxY)
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
