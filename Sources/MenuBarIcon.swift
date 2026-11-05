import AppKit

/// Ícone da barra: a gota do antigo `drop-empty.svg`, desenhada em código, com a água
/// subindo de baixo para cima conforme o progresso do dia, de topo reto e encostada
/// no contorno. Imagem template, então o macOS pinta de preto ou branco conforme o tema.
enum MenuBarIcon {
    static let size: CGFloat = 18

    static func image(progress: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(progress: progress)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Gota"
        return image
    }

    static func draw(progress: Double) {
        let outline = dropPath()
        let level = DropShape.fillLevel(progress: progress)

        if level > 0, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            outline.addClip()
            let bottomY = point(0, DropShape.bottom).y - 1
            let topY = point(0, DropShape.bottom - level * DropShape.height).y
            NSRect(x: 0, y: bottomY, width: size, height: topY - bottomY).fill()
            context.restoreGraphicsState()
        }

        outline.lineWidth = 48.9 * svgScale
        outline.stroke()
    }

    // MARK: - Geometria

    /// Mesmo enquadramento do SVG: `translate(-37.149,-38.511) scale(0.1702128)` numa
    /// caixa de 100, reduzida a 18 pt e com o eixo y virado (AppKit cresce para cima).
    private static let svgScale: CGFloat = 0.1702128 * size / 100

    private static func point(_ x: Double, _ y: Double) -> NSPoint {
        NSPoint(x: (CGFloat(x) * 0.1702128 - 37.149) * size / 100,
                y: size - (CGFloat(y) * 0.1702128 - 38.511) * size / 100)
    }

    private static func dropPath() -> NSBezierPath {
        let s = DropShape.self
        let tip = point(s.tip.x, s.tip.y)
        let path = NSBezierPath()
        path.move(to: tip)
        path.curve(to: point(s.center.x - s.radius, s.center.y),
                   controlPoint1: tip, controlPoint2: point(s.control.x, s.control.y))
        // Semicírculo de baixo, da esquerda para a direita passando pelo fundo.
        path.appendArc(withCenter: point(s.center.x, s.center.y), radius: CGFloat(s.radius) * svgScale,
                       startAngle: 180, endAngle: 360, clockwise: false)
        path.curve(to: tip,
                   controlPoint1: point(2 * s.center.x - s.control.x, s.control.y), controlPoint2: tip)
        path.close()
        return path
    }
}
