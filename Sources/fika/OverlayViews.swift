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

    private var card: some View {
        VStack(spacing: fullscreen ? 18 : 10) {
            Text(engine.isLongBreak ? "🌙" : "☕️")
                .font(.system(size: fullscreen ? 64 : 34))
            Text(engine.isLongBreak ? "긴 휴식 시간이에요" : "잠깐 쉬어 가요")
                .font(fullscreen ? .largeTitle.bold() : .headline)
            Text("일어나서 몸을 펴고, 먼 곳을 바라보세요.")
                .font(fullscreen ? .title3 : .caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(BreakEngine.mmss(engine.remaining))
                .font(.system(size: fullscreen ? 80 : 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.vertical, fullscreen ? 6 : 2)
            HStack(spacing: 12) {
                Button("\(Int(engine.settings.snoozeMinutes))분 연기") { engine.snooze() }
                Button("건너뛰기") { engine.skipBreak() }
                    .keyboardShortcut(.cancelAction)
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
            Image(systemName: "hourglass")
                .font(.title2)
                .symbolEffect(.pulse, options: .repeating)
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
