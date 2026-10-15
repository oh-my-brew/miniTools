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

    static func centeredFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: round(visibleFrame.midX - frame.width / 2),
            y: round(visibleFrame.midY - frame.height / 2),
            width: frame.width,
            height: frame.height
        )
    }

    static func composedPlacementTarget(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        placement: ComposedWindowPlacement
    ) -> ComposedWindowPlacementTarget? {
        let strictFullWidth = dimensionIsClose(
            currentFrame.width,
            to: visibleFrame.width,
            availableLength: visibleFrame.width,
            relativeTolerance: 0.05
        )
        let strictFullHeight = dimensionIsClose(
            currentFrame.height,
            to: visibleFrame.height,
            availableLength: visibleFrame.height,
            relativeTolerance: 0.05
        )
        let placementFullWidth = dimensionIsClose(
            currentFrame.width,
            to: visibleFrame.width,
            availableLength: visibleFrame.width,
            relativeTolerance: 0.10
        )
        let halfHeight = dimensionIsClose(
            currentFrame.height,
            to: visibleFrame.height * 0.5,
            availableLength: visibleFrame.height,
            relativeTolerance: 0.15
        )
        let knownNarrowWidth = [0.5, 1.0 / 3.0].contains { ratio in
            dimensionIsClose(
                currentFrame.width,
                to: visibleFrame.width * ratio,
                availableLength: visibleFrame.width,
                relativeTolerance: 0.10
            )
        }

        if strictFullWidth, strictFullHeight {
            return nil
        }

        if placementFullWidth, halfHeight {
            switch placement {
            case .leading:
                return placementTarget(
                    currentFrame,
                    x: visibleFrame.minX,
                    y: visibleFrame.minY,
                    id: "position.top",
                    title: "上半屏"
                )
            case .trailing:
                return placementTarget(
                    currentFrame,
                    x: visibleFrame.minX,
                    y: visibleFrame.maxY - currentFrame.height,
                    id: "position.bottom",
                    title: "下半屏"
                )
            case .center:
                return nil
            }
        }

        if halfHeight, knownNarrowWidth {
            let topY = visibleFrame.minY
            let bottomY = visibleFrame.maxY - currentFrame.height
            switch placement {
            case .leading:
                let leftX = visibleFrame.minX
                let isLeft = originsAreClose(currentFrame.minX, leftX, visibleFrame.width)
                let isTop = originsAreClose(currentFrame.minY, topY, visibleFrame.height)
                let targetY = isLeft && isTop ? bottomY : topY
                return placementTarget(
                    currentFrame,
                    x: leftX,
                    y: targetY,
                    id: targetY == topY ? "position.topLeft" : "position.bottomLeft",
                    title: targetY == topY ? "左上区域" : "左下区域"
                )
            case .trailing:
                let rightX = visibleFrame.maxX - currentFrame.width
                let isRight = originsAreClose(currentFrame.minX, rightX, visibleFrame.width)
                let isTop = originsAreClose(currentFrame.minY, topY, visibleFrame.height)
                let targetY = isRight && isTop ? bottomY : topY
                return placementTarget(
                    currentFrame,
                    x: rightX,
                    y: targetY,
                    id: targetY == topY ? "position.topRight" : "position.bottomRight",
                    title: targetY == topY ? "右上区域" : "右下区域"
                )
            case .center:
                let centered = centeredFrame(currentFrame, in: visibleFrame)
                return ComposedWindowPlacementTarget(
                    frame: centered,
                    statisticsID: "position.center",
                    title: "窗口居中"
                )
            }
        }

        switch placement {
        case .leading:
            return placementTarget(
                currentFrame,
                x: visibleFrame.minX,
                y: round(visibleFrame.midY - currentFrame.height / 2),
                id: "position.left",
                title: "窗口移至左侧"
            )
        case .trailing:
            return placementTarget(
                currentFrame,
                x: visibleFrame.maxX - currentFrame.width,
                y: round(visibleFrame.midY - currentFrame.height / 2),
                id: "position.right",
                title: "窗口移至右侧"
            )
        case .center:
            let centered = centeredFrame(currentFrame, in: visibleFrame)
            return ComposedWindowPlacementTarget(
                frame: centered,
                statisticsID: "position.center",
                title: "窗口居中"
            )
        }
    }

    private static func placementTarget(
        _ currentFrame: CGRect,
        x: CGFloat,
        y: CGFloat,
        id: String,
        title: String
    ) -> ComposedWindowPlacementTarget {
        ComposedWindowPlacementTarget(
            frame: CGRect(
                x: round(x),
                y: round(y),
                width: currentFrame.width,
                height: currentFrame.height
            ),
            statisticsID: id,
            title: title
        )
    }

    private static func dimensionIsClose(
        _ actual: CGFloat,
        to expected: CGFloat,
        availableLength: CGFloat,
        relativeTolerance: CGFloat
    ) -> Bool {
        // Applications can enforce a size that differs slightly from the
        // requested AXSize because of toolbars and minimum content constraints.
        // Keep preset recognition proportional to the screen so H/L still uses
        // the placement rules for that preset.
        abs(actual - expected) <= max(24, availableLength * relativeTolerance)
    }

    private static func originsAreClose(
        _ actual: CGFloat,
        _ expected: CGFloat,
        _ availableLength: CGFloat
    ) -> Bool {
        abs(actual - expected) <= max(10, availableLength * 0.01)
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
