import Foundation

/// Forma da gota do ícone da barra, nas coordenadas do `drop-empty.svg` original
/// (y cresce para baixo). A metade de cima é uma curva de Bézier saindo da ponta;
/// a de baixo é um semicírculo.
///
/// É puro (só Foundation) para a regra "progresso → altura da água" ser testável
/// sem AppKit.
enum DropShape {
    static let tip = (x: 512.0, y: 285.0)
    /// Ponto de controle da curva de cima (o outro coincide com a ponta).
    static let control = (x: 342.8, y: 416.6)
    /// Centro e raio do semicírculo de baixo; a curva de cima termina na altura do centro.
    static let center = (x: 512.0, y: 585.8)
    static let radius = 169.2

    static var top: Double { tip.y }
    static var bottom: Double { center.y + radius }
    static var height: Double { bottom - top }

    /// Altura da água, de 0 (fundo) a 1 (ponta), para que a área cheia seja `progress`
    /// da área da gota. Como a gota é mais larga embaixo, a água sobe menos que o
    /// progresso no começo e mais perto do fim.
    static func fillLevel(progress: Double) -> Double {
        let p = min(1, max(0, progress))
        if p == 0 { return 0 }
        if p == 1 { return 1 }
        let target = p * cumulativeArea[slices]
        // Busca binária na área acumulada (do fundo para cima) e interpola dentro da fatia.
        var lo = 0, hi = slices
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulativeArea[mid] < target { lo = mid } else { hi = mid }
        }
        let a0 = cumulativeArea[lo], a1 = cumulativeArea[hi]
        let frac = a1 > a0 ? (target - a0) / (a1 - a0) : 0
        return (Double(lo) + frac) / Double(slices)
    }

    /// Meia largura da gota na altura `y` (coordenadas do SVG).
    static func halfWidth(atY y: Double) -> Double {
        if y <= top || y >= bottom { return 0 }
        if y >= center.y {
            let dy = y - center.y
            return (radius * radius - dy * dy).squareRoot()
        }
        // y(t) da curva de cima cresce com t: acha t por bisseção.
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if curve(mid).y < y { lo = mid } else { hi = mid }
        }
        return tip.x - curve((lo + hi) / 2).x
    }

    /// Curva de cima: ponta → (ponta, controle, base esquerda) → base esquerda.
    private static func curve(_ t: Double) -> (x: Double, y: Double) {
        let p0 = tip, p1 = tip, p2 = control, p3 = (x: center.x - radius, y: center.y)
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return (a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    private static let slices = 1000

    /// `cumulativeArea[i]` = área da gota entre o fundo e `i / slices` da altura.
    private static let cumulativeArea: [Double] = {
        var result = [0.0]
        let step = height / Double(slices)
        for i in 0..<slices {
            let y = bottom - (Double(i) + 0.5) * step
            result.append(result[i] + 2 * halfWidth(atY: y) * step)
        }
        return result
    }()
}
