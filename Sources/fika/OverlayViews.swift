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

/// 작업이 시작됐음을 알리는 토스트. 커피 친구가 격려한다. (닫기 버튼 + 초록 글로우)
struct StartToastView: View {
    @ObservedObject var engine: BreakEngine
    let onClose: () -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 11) {
            if let cut = MascotCut.image("work") {
                cut.resizable().interpolation(.high).scaledToFit().frame(width: 34, height: 34)
            } else {
                Text("🌱").font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("이제 시작해볼까요?")
                    .font(.caption).foregroundStyle(Color(red: 0.30, green: 0.50, blue: 0.30))
                Text("\(Int(engine.settings.workMinutes))분, 열심히 해봐요")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.30, blue: 0.18))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.30, green: 0.50, blue: 0.30).opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 440)
        .background(Color(red: 0.93, green: 0.96, blue: 0.90),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))   // 연한 민트크림
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color(red: 0.42, green: 0.68, blue: 0.42), lineWidth: 1.5))   // 초록
        .shadow(color: Color(red: 0.40, green: 0.80, blue: 0.40).opacity(0.6), radius: 18)  // 초록 아웃글로우
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shown = true }
        }
    }
}

/// 작업 중 마이크로 브레이크 동작 알림 토스트. (클릭 통과)
/// 커피 마스코트 + 밝은 크림 배경 — 다크모드 화면에서도 잘 보이게.
struct StretchToastView: View {
    let text: String
    let onClose: () -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 11) {
            if let cut = MascotCut.image("work") {
                cut.resizable().interpolation(.high).scaledToFit().frame(width: 34, height: 34)
            } else {
                Text("☕").font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("잠깐, 이거 해볼까요?")
                    .font(.caption).foregroundStyle(Color(red: 0.55, green: 0.40, blue: 0.25))
                Text(text)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.15, blue: 0.08))
                    .fixedSize(horizontal: false, vertical: true)   // 여러 줄 wrap
                    .lineLimit(3)
            }
            Spacer(minLength: 6)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.55, green: 0.40, blue: 0.25).opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 440)
        .background(Color(red: 0.97, green: 0.93, blue: 0.85),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color(red: 0.80, green: 0.60, blue: 0.30), lineWidth: 1.5))
        .shadow(color: Color(red: 0.98, green: 0.78, blue: 0.42).opacity(0.6), radius: 18)  // 따뜻한 아웃글로우
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shown = true }
        }
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
