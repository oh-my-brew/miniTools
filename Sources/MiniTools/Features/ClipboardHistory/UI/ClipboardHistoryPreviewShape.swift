import CoreGraphics

/// One outline shared by the material mask and border: no seam across the pointer base.
enum ClipboardHistoryPreviewShape {
    static let pointerHeight: CGFloat = 12

    static func path(size: CGSize, pointerX: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inset: CGFloat = 0.5
        guard size.width > 2, size.height > pointerHeight + 2 else { return path }
        let body = CGRect(
            x: inset, y: pointerHeight,
            width: size.width - inset * 2,
            height: size.height - pointerHeight - inset
        )
        let radius = min(18, min(body.width, body.height) / 2)
        let halfWidth = min(14, (body.width - radius * 2) / 2)
        guard halfWidth >= 4 else {
            path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)
            return path
        }
        let center = min(
            max(pointerX, body.minX + radius + halfWidth),
            body.maxX - radius - halfWidth
        )
        let shoulder = halfWidth * 2 / 7
        let leftInner = CGPoint(x: center - halfWidth + shoulder, y: body.minY - 2)
        let rightInner = CGPoint(x: center + halfWidth - shoulder, y: body.minY - 2)

        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: center - halfWidth, y: body.minY))
        path.addQuadCurve(
            to: leftInner,
            control: CGPoint(x: center - halfWidth + shoulder / 2, y: body.minY)
        )
        path.addArc(
            tangent1End: CGPoint(x: center, y: inset),
            tangent2End: rightInner,
            radius: 2
        )
        path.addLine(to: rightInner)
        path.addQuadCurve(
            to: CGPoint(x: center + halfWidth, y: body.minY),
            control: CGPoint(x: center + halfWidth - shoulder / 2, y: body.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius
        )
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.minY), radius: radius
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius
        )
        path.closeSubpath()
        return path
    }
}
