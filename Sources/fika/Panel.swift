import SwiftUI
import AppKit
import Charts

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

/// enum 설정용 컴팩트 메뉴 픽커 행.
private func enumPickerRow<T: CaseIterable & Identifiable & Hashable>(
    _ title: String, _ selection: Binding<T>, _ label: @escaping (T) -> String
) -> some View where T.AllCases: RandomAccessCollection {
    HStack {
        Text(title)
        Spacer()
        Picker("", selection: selection) {
            ForEach(T.allCases) { Text(label($0)).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }
}

// MARK: - 탭

enum PanelTab: CaseIterable {
    case home, time, alerts, stretch, stats, settings
    var title: String {
        switch self {
        case .home: return "상태"; case .time: return "시간"
        case .alerts: return "알림"; case .stretch: return "동작"
        case .stats: return "분석"; case .settings: return "설정"
        }
    }
    var icon: String {
        switch self {
        case .home: return "timer"; case .time: return "clock"
        case .alerts: return "bell.badge"; case .stretch: return "figure.flexibility"
        case .stats: return "chart.bar.fill"; case .settings: return "gearshape"
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
        case .alerts:   AlertsTab(engine: engine, settings: engine.settings)
        case .stretch:  StretchTab(settings: engine.settings)
        case .stats:    StatsTab()
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
    @ObservedObject private var stats = SessionStore.shared

    var body: some View {
        VStack(spacing: 14) {
            RingView(engine: engine)

            VStack(spacing: 2) {
                Text("오늘 \(stats.today.sessions)회 · \(SessionStore.hm(stats.today.minutes)) 집중")
                    .font(.caption).foregroundStyle(.secondary)
                Text("이번 주 \(stats.thisWeek.sessions)회 · \(SessionStore.hm(stats.thisWeek.minutes))")
                    .font(.caption2).foregroundStyle(.secondary)
                if let up = engine.scheduledRestUpcoming {
                    Text(up).font(.caption2).foregroundStyle(.secondary)
                }
            }

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
                } else if engine.phase == .scheduledRest {
                    Text("고정 휴식 중 — 끝나면 자동으로 작업을 시작해요")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { engine.cancelScheduledRest() } label: {
                        Label("지금 작업 시작", systemImage: "play.fill")
                    }
                } else {
                    Button { engine.breakNow() } label: {
                        Label("지금 휴식하기", systemImage: "cup.and.saucer.fill")
                    }
                    if engine.phase == .working {
                        Button { engine.restartWork() } label: {
                            Label("작업 다시 시작", systemImage: "arrow.clockwise")
                        }
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

            Divider().padding(.vertical, 2)
            sectionHeader("고정 휴식 시간대")
            Text("매일 정해진 시간엔 작업 사이클을 멈추고 쉬어요 (예: 점심). 화면은 덮지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("고정 휴식 사용", isOn: $settings.scheduledRestEnabled)
            if settings.scheduledRestEnabled {
                HStack {
                    Text("시간").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: timeBinding(\.scheduledRestStart), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("~").foregroundStyle(.secondary)
                    DatePicker("", selection: timeBinding(\.scheduledRestEnd), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                HStack {
                    Text("이름").foregroundStyle(.secondary)
                    Spacer()
                    TextField("점심 휴식", text: $settings.scheduledRestLabel)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                }
            }
        }
    }

    /// Int(자정 기준 분) ↔ DatePicker(Date) 브리지.
    private func timeBinding(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let mins = settings[keyPath: key]
                return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
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
    @ObservedObject var engine: BreakEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject private var notifLog = NotificationLog.shared

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
            sectionHeader("남은 시간 알림")
            Text("메뉴바 시간 표시와 별개로, 작업 중 \"휴식까지 N분\"을 주기적으로 잠깐 띄워요.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("남은 시간 알림 켜기", isOn: $settings.timeNoticeEnabled)
            if settings.timeNoticeEnabled {
                stepperRow("알림 주기(분)", $settings.timeNoticeMinutes, 5...120, 5)

                Text("겉모습 · 동작 (아래 알림 테스트 → \"남은시간\" 버튼으로 바로 확인)")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                enumPickerRow("위치", $settings.timeNoticePosition) { $0.label }
                enumPickerRow("등장 모션", $settings.timeNoticeMotion) { $0.label }
                enumPickerRow("소리", $settings.timeNoticeSound) { $0.label }
                stepperRow("표시 시간(초)", $settings.timeNoticeDuration, 3...10, 1)
                Toggle("숫자 크게 (히어로)", isOn: $settings.timeNoticeHero).font(.callout)
                Toggle("임박 강조 색", isOn: $settings.timeNoticeWarm).font(.callout)
                Toggle("카드 크게", isOn: $settings.timeNoticeBig).font(.callout)
                Toggle("유지 중 살짝 펄스", isOn: $settings.timeNoticePulse).font(.callout)
            }

            Divider()
            sectionHeader("하루 마무리 알림")
            Text("마칠 시각 30분·15분 전과 도래 시 알려줘요. 강제로 끄진 않아요.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("하루 마무리 알림 켜기", isOn: $settings.shutdownEnabled)
            if settings.shutdownEnabled {
                HStack {
                    Text("마칠 시각").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: shutdownBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }

            Divider()
            sectionHeader("휴식 알림 방식")
            Picker("", selection: $settings.breakStyle) {
                ForEach(BreakStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
            Text(settings.breakStyle.detail).font(.caption).foregroundStyle(.secondary)

            Divider()
            sectionHeader("알림 테스트")
            Text("지금(마우스가 있는 화면)에 각 알림을 띄워봐요. 멀티 모니터에서 어느 화면에 뜨는지 확인할 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { engine.testStretchAlert() } label: { Text("동작") }
                Button { engine.testTimeNoticeAlert() } label: { Text("남은시간") }
                Button { engine.testShutdownAlert() } label: { Text("마무리") }
            }
            .buttonStyle(PanelButtonStyle())

            Divider()
            Toggle("전환 사운드 재생", isOn: $settings.soundEnabled)
            Button {
                Sound.play(.breakEnd, enabled: true)
            } label: {
                Label("사운드 테스트", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(PanelButtonStyle())

            Divider()
            sectionHeader("알림 이력")
            Text("최근 뜬 알림 20건. \"안 온 건지 놓친 건지\" 여기서 확인해요.")
                .font(.caption).foregroundStyle(.secondary)
            if notifLog.entries.isEmpty {
                Text("아직 없어요. 위 테스트 버튼으로 띄워보세요.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notifLog.entries) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.hm(e.date))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Text(e.kind)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)))
                            Text(e.text)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
            }
        }
    }

    /// 이력 표시용 HH:mm.
    private static func hm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Int(자정 기준 분) ↔ DatePicker(Date) 브리지.
    private var shutdownBinding: Binding<Date> {
        Binding(
            get: {
                let m = settings.shutdownTime
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.shutdownTime = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
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

// MARK: - 분석 탭

private struct StatsTab: View {
    @ObservedObject private var stats = SessionStore.shared
    @State private var period: Period = .daily
    @State private var selected: Date?
    private let amber = Color(red: 0.83, green: 0.59, blue: 0.22)

    enum Period: String, CaseIterable, Identifiable {
        case daily = "일별", weekly = "주별", monthly = "월별"
        var id: String { rawValue }
    }

    private var series: [(date: Date, minutes: Double)] {
        switch period {
        case .daily:   return stats.dailySeries(days: 7)
        case .weekly:  return stats.weeklySeries(weeks: 8)
        case .monthly: return stats.monthlySeries(months: 6)
        }
    }
    private var barUnit: Calendar.Component {
        switch period { case .daily: return .day; case .weekly: return .weekOfYear; case .monthly: return .month }
    }
    private var total: Double { series.reduce(0) { $0 + $1.minutes } }

    /// 선택된 x 위치에 가장 가까운 막대.
    private var selectedItem: (date: Date, minutes: Double)? {
        guard let selected else { return nil }
        return series.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    private func label(_ d: Date) -> String {
        let f = DateFormatter()
        switch period {
        case .daily:   f.dateFormat = "EEEEE"   // 요일 1글자
        case .weekly:  f.dateFormat = "M/d"
        case .monthly: f.dateFormat = "M월"
        }
        return f.string(from: d)
    }

    private func detailLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        switch period {
        case .daily:   f.dateFormat = "M월 d일 (E)"
        case .weekly:  f.dateFormat = "M/d 주"
        case .monthly: f.dateFormat = "yyyy년 M월"
        }
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: period) { selected = nil }

            // 막대를 탭하면 그 날(기간) 상세, 아니면 전체 합계
            if let item = selectedItem {
                Text("\(detailLabel(item.date)) · \(SessionStore.hm(item.minutes))")
                    .font(.callout.weight(.semibold)).foregroundStyle(amber)
            } else {
                Text("\(period.rawValue) 합계 · \(SessionStore.hm(total))")
                    .font(.callout.weight(.semibold)).foregroundStyle(amber)
            }

            Chart(series, id: \.date) { item in
                BarMark(
                    x: .value("기간", item.date, unit: barUnit),
                    y: .value("집중(분)", item.minutes)
                )
                .foregroundStyle(selectedItem == nil || selectedItem!.date == item.date
                                 ? amber : amber.opacity(0.35))
                .cornerRadius(4)
            }
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: series.map { $0.date }) { value in
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(label(d)) }
                    }
                }
            }
            .frame(height: 190)

            Text(stats.records.isEmpty
                 ? "작업을 한 세션 마치면 여기에 기록이 쌓여요."
                 : "막대를 탭하면 그 날의 집중 시간을 볼 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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
