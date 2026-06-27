import AppKit

/// 메뉴바용 커피 잔 아이콘을 코드로 그린다. (에셋 불필요)
/// `level`(0~1)만큼 커피가 차 있고, 위로 김이 흔들리며 피어오른다.
/// 김의 진폭·속도는 `warning`(0~1, 휴식 임박도)이 커질수록 강해진다.
enum CoffeeIcon {
    static func image(level: Double, steamPhase: Double, away: Bool, paused: Bool, warning: Double) -> NSImage {
        let w: CGFloat = 20, h: CGFloat = 19
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()

        let stroke = NSColor.labelColor
        let coffee = NSColor(srgbRed: 0.36, green: 0.22, blue: 0.11, alpha: 1)
        let coffeeTop = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.18, alpha: 1)

        // 컵 몸통
        let body = NSRect(x: 4, y: 3, width: 10.5, height: 10.5)
        let cup = NSBezierPath(roundedRect: body, xRadius: 1.6, yRadius: 1.6)

        // 커피 채우기 (컵 안쪽으로 클립)
        NSGraphicsContext.saveGraphicsState()
        cup.addClip()
        let lvl = max(0, min(1, level))
        let fillH = body.height * CGFloat(lvl)
        if fillH > 0 {
            coffee.setFill()
            NSRect(x: body.minX, y: body.minY, width: body.width, height: fillH).fill()
            if fillH > 1.4 {                       // 수면 살짝 밝게
                coffeeTop.setFill()
                NSRect(x: body.minX, y: body.minY + fillH - 1.3, width: body.width, height: 1.3).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // 손잡이
        let handle = NSBezierPath()
        handle.appendArc(withCenter: NSPoint(x: 14.6, y: 8.2), radius: 3.1, startAngle: -68, endAngle: 68)
        handle.lineWidth = 1.4
        stroke.setStroke()
        handle.stroke()

        // 컵 외곽선
        cup.lineWidth = 1.4
        stroke.setStroke()
        cup.stroke()

        // 김 (자리비움·일시정지 땐 멈춤 = 식은 커피)
        if !away && !paused {
            let steamColor = warning > 0
                ? NSColor.systemOrange.withAlphaComponent(0.85)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.8)
            steamColor.setStroke()
            let amp: CGFloat = 1.0 + 1.6 * CGFloat(warning)   // 임박할수록 크게 흔들림
            let speed: Double = 1.0 + 2.2 * warning            // 임박할수록 빠르게
            for i in 0..<2 {
                let baseX = body.minX + 3.2 + CGFloat(i) * 4
                let p = NSBezierPath()
                let botY = body.maxY + 0.5
                let topY = h - 1.0
                var y = botY
                var first = true
                while y <= topY {
                    let t = Double(y) * 0.85 + steamPhase * speed + Double(i) * 1.7
                    let x = baseX + amp * CGFloat(sin(t))
                    let pt = NSPoint(x: x, y: y)
                    if first { p.move(to: pt); first = false } else { p.line(to: pt) }
                    y += 1
                }
                p.lineWidth = 1.2
                p.lineCapStyle = .round
                p.stroke()
            }
        }

        img.unlockFocus()
        img.isTemplate = false   // 커피 색을 유지해야 하므로 템플릿 아님
        return img
    }
}
