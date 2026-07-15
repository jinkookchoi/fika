import SwiftUI

/// 휴식 화면 본문. fullscreen=true면 화면 전체, false면 카드만.
struct BreakView: View {
    @ObservedObject var engine: BreakEngine
    let fullscreen: Bool
    let showCard: Bool

    var body: some View {
        ZStack {
            if fullscreen {
                Color.black.opacity(0.55)
                Rectangle().fill(.ultraThinMaterial)
            }
            if showCard {
                card
            }
        }
        .ignoresSafeArea()
    }

    private var isHold: Bool { engine.phase == .breakHold }
    private var cutName: String { isHold ? "done" : "resting" }

    private var card: some View {
        VStack(spacing: fullscreen ? 18 : 10) {
            if let cut = MascotCut.image(cutName) {
                cut.resizable().interpolation(.high).scaledToFit()
                    .frame(width: fullscreen ? 132 : 60, height: fullscreen ? 132 : 60)
            } else {
                Text(isHold ? "✅" : (engine.isLongBreak ? "🌙" : "☕️"))
                    .font(.system(size: fullscreen ? 64 : 34))
            }
            Text(isHold ? "다 쉬었어요!" : (engine.isLongBreak ? "긴 휴식 시간이에요" : "잠깐 쉬어 가요"))
                .font(fullscreen ? .largeTitle.bold() : .headline)
            Text(isHold
                 ? "준비되면 시작하세요 — 키보드나 마우스를 움직이면 자동으로 시작됩니다."
                 : "일어나서 몸을 펴고, 먼 곳을 바라보세요.")
                .font(fullscreen ? .title3 : .caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !isHold {
                Text(BreakEngine.mmss(engine.remaining))
                    .font(.system(size: fullscreen ? 80 : 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.vertical, fullscreen ? 6 : 2)
            }
            HStack(spacing: 12) {
                if isHold {
                    Button("작업 시작") { engine.skipBreak() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("\(Int(engine.settings.snoozeMinutes))분 연기") { engine.snooze() }
                    Button("건너뛰기") { engine.skipBreak() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(fullscreen ? .large : .regular)
        }
        .padding(fullscreen ? 40 : 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
        .shadow(radius: 20)
        .padding(fullscreen ? 0 : 4)
    }
}

// MARK: - 토스트 공통 템플릿

/// 토스트 한 장의 내용 명세. 종류별 차이(마스코트·문구·강조색·버튼)는 전부 여기 담기고,
/// 겉모습(카드·글로우·등장 모션)은 ToastView 한 벌이 그린다. Notice → spec 변환은 post()에서.
struct ToastSpec {
    var cut: String                 // 마스코트 컷 이름 (cuts/<name>.png)
    var emoji: String               // 컷이 없을 때 폴백 이모지
    var theme: ToastTheme = .warm
    var caption: String? = nil      // 강조줄 위 작은 안내
    var title: String               // 강조줄(본문)
    var subtitle: String? = nil     // 강조줄 아래 작은 안내
    var heroNumber: String? = nil   // 숫자 강조 모드(남은 시간) — 있으면 caption/title 대신 표시
    var heroSuffix: String = ""
    var cups: (filled: Int, total: Int)? = nil   // 남은 시간 커피잔 (1잔=10분): 채워진 잔=남은 시간
    var buttonLabel: String? = nil  // 행동 버튼 (예: "오늘은 그만")
    var buttonAction: () -> Void = {}
}

/// 토스트 강조색 테마 — 카드/테두리/글로우/글자색 묶음.
enum ToastTheme {
    case warm    // 크림 + 캐러멜 (기본)
    case green   // 민트크림 + 초록 (작업 시작)
    case amber   // 임박 오렌지 (남은 시간 "임박 강조" 옵션)

    private static let orange = Color(red: 0.878, green: 0.439, blue: 0.122)

    var card: Color {
        switch self {
        case .warm:  return Color(red: 0.97, green: 0.93, blue: 0.85)
        case .green: return Color(red: 0.93, green: 0.96, blue: 0.90)
        case .amber: return Color(red: 0.965, green: 0.902, blue: 0.788)
        }
    }
    var border: Color {
        switch self {
        case .warm:  return Color(red: 0.80, green: 0.60, blue: 0.30)
        case .green: return Color(red: 0.42, green: 0.68, blue: 0.42)
        case .amber: return Self.orange
        }
    }
    var glow: Color {
        switch self {
        case .warm:  return Color(red: 0.98, green: 0.78, blue: 0.42).opacity(0.6)
        case .green: return Color(red: 0.40, green: 0.80, blue: 0.40).opacity(0.6)
        case .amber: return Self.orange.opacity(0.5)
        }
    }
    var caption: Color {
        switch self {
        case .warm, .amber: return Color(red: 0.55, green: 0.40, blue: 0.25)
        case .green:        return Color(red: 0.30, green: 0.50, blue: 0.30)
        }
    }
    var title: Color {
        switch self {
        case .warm:  return Color(red: 0.24, green: 0.15, blue: 0.08)
        case .green: return Color(red: 0.18, green: 0.30, blue: 0.18)
        case .amber: return Color(red: 0.35, green: 0.18, blue: 0.05)
        }
    }
    var heroNumber: Color {
        switch self {
        case .amber: return Self.orange
        default:     return title
        }
    }
}

/// 모든 토스트의 공통 템플릿. 폭 고정(기본 440, "크게" 500)·높이는 내용에 따라 가변.
/// 크게/모션/펄스는 전 토스트 공통 설정(기존 timeNotice* 키 재사용).
/// 창 크기는 post()가 표시 전에 fittingSize로 실측한다 — 표시 후 리사이즈 금지(macOS 26 함정).
struct ToastView: View {
    let spec: ToastSpec
    let big: Bool
    let motion: ToastMotion
    let pulse: Bool
    let onClose: () -> Void
    @State private var shown = false
    @State private var pulseScale: CGFloat = 1

    // 등장 모션 (여백 68px 안에서 움직이도록 offset ≤ 34)
    private var startOffsetY: CGFloat { switch motion { case .spring: 0; case .slide: -34; case .bounce: -30 } }
    private var startScale: CGFloat { switch motion { case .spring: 0.9; case .slide: 1; case .bounce: 0.96 } }
    private var entryAnim: Animation {
        switch motion {
        case .spring: .spring(response: 0.4, dampingFraction: 0.7)
        case .slide:  .spring(response: 0.45, dampingFraction: 0.85)
        case .bounce: .spring(response: 0.5, dampingFraction: 0.5)
        }
    }

    /// 남은 시간 커피잔 줄 — 채워진 잔(남음) + 빈 잔 윤곽(지남). 많이 남았으면 잔이 많다.
    @ViewBuilder private var cupsRow: some View {
        if let cups = spec.cups, cups.total > 1 {
            HStack(spacing: 2) {
                ForEach(0..<cups.total, id: \.self) { i in
                    Image(systemName: i < cups.filled ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: big ? 12 : 11))
                        .foregroundStyle(i < cups.filled ? spec.theme.border : spec.theme.caption.opacity(0.35))
                }
            }
            .padding(.top, 3)
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            if let cut = MascotCut.image(spec.cut) {
                // 강조 모드(heroNumber)에선 글자 대신 마스코트를 한 단계 키워 부각한다.
                let side: CGFloat = spec.heroNumber != nil ? (big ? 52 : 46) : (big ? 40 : 34)
                cut.resizable().interpolation(.high).scaledToFit()
                    .frame(width: side, height: side)
            } else {
                Text(spec.emoji).font(big ? .largeTitle : .title2)
            }
            if let n = spec.heroNumber {
                // 숫자 강조 모드 — 폰트는 본문과 동일, 숫자만 색으로 강조. (큰 숫자는 통일 템플릿에서 너무 튀었음)
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = spec.caption {
                        Text(caption)
                            .font(big ? .callout : .caption).foregroundStyle(spec.theme.caption)
                    }
                    // 숫자 부분만 같은 크기에서 라운디드+볼드+강조색으로 살짝 다른 표정을 준다.
                    (Text(n).fontDesign(.rounded).fontWeight(.bold).foregroundStyle(spec.theme.heroNumber)
                     + Text(spec.heroSuffix).foregroundStyle(spec.theme.title))
                        .font((big ? Font.title3 : Font.callout).weight(.semibold))
                    cupsRow
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = spec.caption {
                        Text(caption)
                            .font(big ? .callout : .caption).foregroundStyle(spec.theme.caption)
                    }
                    Text(spec.title)
                        .font((big ? Font.title3 : Font.callout).weight(.semibold))
                        .foregroundStyle(spec.theme.title)
                        .fixedSize(horizontal: false, vertical: true)   // 여러 줄 wrap
                        .lineLimit(3)
                    if let subtitle = spec.subtitle {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(spec.theme.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let label = spec.buttonLabel {
                        Button(action: spec.buttonAction) {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Color(red: 0.83, green: 0.59, blue: 0.22), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    cupsRow
                }
            }
            Spacer(minLength: 6)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(spec.theme.caption.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, big ? 20 : 16).padding(.vertical, big ? 15 : 12)
        .frame(width: big ? 500 : 440)
        .background(spec.theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(spec.theme.border, lineWidth: 1.5))
        .shadow(color: spec.theme.glow, radius: big ? 22 : 18)
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? pulseScale : startScale)
        .offset(y: shown ? 0 : startOffsetY)
        .onAppear {
            withAnimation(entryAnim) { shown = true }
            if pulse {
                withAnimation(.easeInOut(duration: 0.26).delay(0.42)) {
                    pulseScale = 1.05
                } completion: {
                    withAnimation(.easeInOut(duration: 0.26)) { pulseScale = 1 }
                }
            }
        }
    }
}

/// 메뉴바에서 시간을 감췄을 때, 아이콘에 마우스를 올리면 뜨는 작은 호버 팁.
/// (OS 툴팁 대신 우리 스타일로. engine 을 관찰해 남은 시간이 실시간 갱신된다.)
struct HoverTipView: View {
    @ObservedObject var engine: BreakEngine
    @State private var shown = false

    var body: some View {
        HStack(spacing: 9) {
            if let cut = MascotCut.image(engine.mascotCut) {
                cut.resizable().interpolation(.high).scaledToFit().frame(width: 26, height: 26)
            } else {
                Text("☕").font(.body)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.phaseLabel)
                    .font(.caption2).foregroundStyle(Color(red: 0.55, green: 0.40, blue: 0.25))
                Text(engine.menuTimeString)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(red: 0.24, green: 0.15, blue: 0.08))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(red: 0.97, green: 0.93, blue: 0.85),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color(red: 0.80, green: 0.60, blue: 0.30), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.20), radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.92, anchor: .top)
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { shown = true } }
    }
}

/// soft 스타일: 화면 가장자리에 숨쉬듯 번지는 글로우.
struct VignetteView: View {
    @ObservedObject var engine: BreakEngine
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(
                LinearGradient(colors: [.teal.opacity(0.0), .teal.opacity(0.9)],
                               startPoint: .center, endPoint: .top),
                lineWidth: pulse ? 90 : 40
            )
            .blur(radius: 40)
            .opacity(pulse ? 0.85 : 0.45)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// 작업이 곧 끝남을 알리는 상단 예고 배너. 임박할수록 색이 강해짐.
struct WarningView: View {
    @ObservedObject var engine: BreakEngine

    private var color: Color {
        // 노랑 → 주황 → 빨강
        let i = engine.warningIntensity
        return Color(hue: 0.13 - 0.13 * i, saturation: 0.9, brightness: 1.0)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let cut = MascotCut.image("warning") {
                cut.resizable().interpolation(.high).scaledToFit().frame(width: 44, height: 44)
            } else {
                Image(systemName: "hourglass")
                    .font(.title2)
                    .symbolEffect(.pulse, options: .repeating)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("곧 휴식 시간이에요")
                    .font(.headline)
                Text("\(BreakEngine.mmss(engine.remaining)) 후 시작")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("\(Int(engine.settings.snoozeMinutes))분 연기") { engine.snooze() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(color, lineWidth: 2 + 3 * engine.warningIntensity)
        )
        .shadow(radius: 10)
        .padding(6)
    }
}
