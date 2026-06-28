import SwiftUI
import AppKit

// MARK: - 공통 스타일

/// BetterMouse 풍의 외곽선 둥근 버튼. 호버 시 옅게 채워지고, 누르면 액센트색.
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(configuration.isPressed ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.22), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
                .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
        }
        private var fill: Color {
            if configuration.isPressed { return .accentColor }
            if hovering { return .primary.opacity(0.08) }
            return .clear
        }
    }
}

private func sectionHeader(_ text: String) -> some View {
    Text(text)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

private func stepperRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
    Stepper(value: value, in: range, step: step) {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

// MARK: - 탭

enum PanelTab: CaseIterable {
    case home, time, alerts, stretch, settings
    var title: String {
        switch self {
        case .home: return "상태"; case .time: return "시간"
        case .alerts: return "알림"; case .stretch: return "동작"; case .settings: return "설정"
        }
    }
    var icon: String {
        switch self {
        case .home: return "timer"; case .time: return "clock"
        case .alerts: return "bell.badge"; case .stretch: return "figure.flexibility"; case .settings: return "gearshape"
        }
    }
}

private struct TabButton: View {
    let tab: PanelTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tab.icon).font(.system(size: 18))
                Text(tab.title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.12)
                          : (hovering ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

// MARK: - 루트 패널

struct PanelView: View {
    @ObservedObject var engine: BreakEngine
    @State private var tab: PanelTab = .home

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    TabButton(tab: t, selected: tab == t) { tab = t }
                }
            }
            .padding(8)

            Divider()

            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 470)
        }
        .frame(width: 380)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home:     HomeTab(engine: engine)
        case .time:     TimeTab(settings: engine.settings)
        case .alerts:   AlertsTab(settings: engine.settings)
        case .stretch:  StretchTab(settings: engine.settings)
        case .settings: SettingsTab(settings: engine.settings)
        }
    }
}

// MARK: - 진행 링

private struct RingView: View {
    @ObservedObject var engine: BreakEngine
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: 12)
            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(engine.phaseColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: engine.progress)
            VStack(spacing: 4) {
                if let cut = MascotCut.image(engine.mascotCut) {
                    cut.resizable().interpolation(.high).scaledToFit()
                        .frame(width: 46, height: 46)
                }
                Text(engine.timeString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(engine.phaseLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 164, height: 164)
    }
}

// MARK: - 상태 탭

private struct HomeTab: View {
    @ObservedObject var engine: BreakEngine

    var body: some View {
        VStack(spacing: 14) {
            RingView(engine: engine)

            Text("완료한 작업 세션 \(engine.completedWork)회")
                .font(.caption).foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button { engine.togglePause() } label: {
                    Label(engine.phase == .paused ? "재개" : "일시정지",
                          systemImage: engine.phase == .paused ? "play.fill" : "pause.fill")
                }
                if engine.phase == .breaking {
                    Button { engine.skipBreak() } label: {
                        Label("휴식 건너뛰기", systemImage: "forward.fill")
                    }
                    Button { engine.snooze() } label: {
                        Label("\(Int(engine.settings.snoozeMinutes))분 연기", systemImage: "zzz")
                    }
                } else if engine.phase == .breakHold {
                    Button { engine.skipBreak() } label: {
                        Label("작업 시작", systemImage: "play.fill")
                    }
                } else {
                    Button { engine.breakNow() } label: {
                        Label("지금 휴식하기", systemImage: "cup.and.saucer.fill")
                    }
                }
            }
            .buttonStyle(PanelButtonStyle())

            if engine.phase == .working {
                VStack(alignment: .leading, spacing: 6) {
                    Text("이번만 — 휴식까지").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach([5, 10, 15, 25], id: \.self) { m in
                            Button("\(m)분") { engine.setTimeUntilBreak(Double(m)) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PanelButtonStyle())
                }
            }
        }
    }
}

// MARK: - 시간 탭

private struct TimeTab: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("작업 / 휴식 (분)")
            stepperRow("작업 시간", $settings.workMinutes, 1...180, 5)
            stepperRow("짧은 휴식", $settings.breakMinutes, 1...60, 1)

            Divider().padding(.vertical, 2)
            Toggle("긴 휴식 사용", isOn: $settings.longBreakEnabled)
            if settings.longBreakEnabled {
                stepperRow("긴 휴식 시간(분)", $settings.longBreakMinutes, 1...90, 5)
                Stepper(value: $settings.cyclesBeforeLongBreak, in: 2...12) {
                    HStack {
                        Text("긴 휴식 주기")
                        Spacer()
                        Text("\(settings.cyclesBeforeLongBreak)번째마다").foregroundStyle(.secondary)
                    }
                }
            }

            Divider().padding(.vertical, 2)
            sectionHeader("예고 / 연기")
            stepperRow("휴식 예고 시간(초)", $settings.warningSeconds, 0...300, 15)
            stepperRow("연기 길이(분)", $settings.snoozeMinutes, 1...30, 1)
        }
    }
}

// MARK: - 알림 탭

private let iconLegend: [(label: String, emoji: String, symbol: String)] = [
    ("작업",       "🌱", "leaf.fill"),
    ("곧 휴식",    "⏳", "hourglass"),
    ("짧은 휴식",  "☕️", "cup.and.saucer.fill"),
    ("긴 휴식",    "🌙", "moon.stars.fill"),
    ("자리 비움",  "💤", "moon.zzz.fill"),
    ("일시정지",   "⏸️", "pause.fill"),
]

private struct AlertsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("메뉴바 아이콘")
            Picker("", selection: $settings.iconTheme) {
                ForEach(IconTheme.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()

            Toggle("메뉴바에 남은 시간 표시", isOn: $settings.showMenuBarTime)
                .font(.callout)

            // 현재 테마의 단계별 아이콘 미리보기
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 6) {
                ForEach(iconLegend, id: \.label) { item in
                    HStack(spacing: 6) {
                        Group {
                            if settings.iconTheme == .emoji {
                                Text(item.emoji)
                            } else {
                                Image(systemName: item.symbol)
                            }
                        }
                        .frame(width: 18)
                        Text(item.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))

            Divider()
            sectionHeader("휴식 알림 방식")
            Picker("", selection: $settings.breakStyle) {
                ForEach(BreakStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
            Text(settings.breakStyle.detail).font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("전환 사운드 재생", isOn: $settings.soundEnabled)
            Button {
                Sound.play(.breakEnd, enabled: true)
            } label: {
                Label("사운드 테스트", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(PanelButtonStyle())
        }
    }
}

// MARK: - 동작 탭

private struct StretchTab: View {
    @ObservedObject var settings: AppSettings

    private var tipsText: Binding<String> {
        Binding(
            get: { settings.stretchTips.joined(separator: "\n") },
            set: { settings.stretchTips = $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("동작 알림")
            Text("작업 중 앉아서 가볍게 할 동작을 주기적으로 알려줘요. 5초간 살짝 떴다 사라집니다.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("작업 중 동작 알림 켜기", isOn: $settings.microBreakEnabled)
            if settings.microBreakEnabled {
                stepperRow("알림 주기(분)", $settings.microBreakMinutes, 5...120, 5)
            }

            Divider()
            sectionHeader("동작 문구 (한 줄에 하나)")
            TextEditor(text: tipsText)
                .font(.callout)
                .frame(height: 170)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
            Button { settings.stretchTips = AppSettings.defaultStretchTips } label: {
                Label("기본 문구로 되돌리기", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PanelButtonStyle())
        }
    }
}

// MARK: - 설정 탭

private struct SettingsTab: View {
    @ObservedObject var settings: AppSettings
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("자리 비움 감지")
            Toggle("자리 비우면 작업 타이머 리셋", isOn: $settings.idleResetEnabled)
            if settings.idleResetEnabled {
                stepperRow("자리 비움 인정 시간(분)", $settings.idleThresholdMinutes, 1...30, 1)
            }
            Toggle("휴식이 끝나도 돌아올 때까지 작업 시작 안 함", isOn: $settings.holdBreakUntilReturn)

            Divider()
            Toggle("로그인 시 자동 실행", isOn: $settings.launchAtLogin)
            Toggle("디버그 로그 기록", isOn: $settings.debugMode)
            Button { NSWorkspace.shared.open(Log.directory) } label: {
                Label("로그 폴더 열기", systemImage: "folder")
            }
            .buttonStyle(PanelButtonStyle())

            Divider()
            VStack(spacing: 8) {
                Button { settings.resetToDefaults() } label: {
                    Label("기본값으로 초기화", systemImage: "arrow.counterclockwise")
                }
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("종료", systemImage: "power")
                }
            }
            .buttonStyle(PanelButtonStyle())

            HStack {
                Text("Fika").font(.callout)
                Spacer()
                Text("v\(appVersion)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
