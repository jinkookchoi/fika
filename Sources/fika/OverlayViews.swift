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

/// 작업이 시작됐음을 잠깐 알리는 작은 캡슐 토스트. (클릭은 통과)
struct StartToastView: View {
    @ObservedObject var engine: BreakEngine
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            if let cut = MascotCut.image("work") {
                cut.resizable().interpolation(.high).scaledToFit().frame(width: 34, height: 34)
            } else {
                Text("🌱").font(.title2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("작업 시작").font(.headline)
                Text("\(Int(engine.settings.workMinutes))분 집중해요")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.green.opacity(0.45), lineWidth: 1.5))
        .shadow(radius: 10)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.85)
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
