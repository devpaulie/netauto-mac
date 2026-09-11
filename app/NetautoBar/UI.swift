// UI — 메뉴바 패널과 설정 창
//
// 패널은 MenuBarExtra 의 .window 스타일을 쓴다.
// .menu 스타일은 SwiftUI 를 실제 NSMenu 로 변환하는데, 그 과정에서
//   · Text 항목이 전부 비활성(회색)으로 그려진다
//   · 공백으로 맞춘 정렬이 가변폭 글꼴에서 어긋난다
//   · SF Symbol 이 버려진다 (아이콘·체크 표시가 사라짐)
// .window 는 일반 SwiftUI 뷰 계층이라 이 제약이 전부 없다.

import SwiftUI

// MARK: - 디자인 상수

private enum UX {
    static let panelWidth: CGFloat = 330
    static let hPad: CGFloat = 14
    static let rowRadius: CGFloat = 6

    // 타입 스케일 — 메뉴바 패널은 좁으니 촘촘하되 11pt 아래로는 내리지 않는다
    static let titleSize: CGFloat = 15   // 헤더 프로필 이름
    static let rowSize: CGFloat = 13     // 고르는 항목
    static let bodySize: CGFloat = 12    // 현재 상태 값
    static let capSize: CGFloat = 11     // 라벨·섹션 제목·설명

    /// 패널 배경. MenuBarExtra 의 기본 반투명 재질은 뒤 창이 배어 나와
    /// 글자 대비가 무너진다 → 불투명한 창 배경색을 깔아 가독성을 확보한다.
    static let background = Color(nsColor: .windowBackgroundColor)
}

// MARK: - 공통 조각

/// 섹션 제목 (작게, 흐리게)
private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: UX.capSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, UX.hPad)
    }
}

/// 고를 수 있는 항목 한 줄. 선택된 것에 체크가 붙고, 마우스를 올리면 밝아진다.
private struct ChoiceRow: View {
    let symbol: String?
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .frame(width: 17)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                Text(title)
                    .font(.system(size: UX.rowSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: UX.capSize))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: UX.rowRadius, style: .continuous)
                    .fill(hovering && !disabled ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
        .padding(.horizontal, UX.hPad - 8)
    }
}

/// 동작 한 줄 (선택이 아니라 실행)
private struct ActionRow: View {
    let symbol: String
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 17)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: UX.rowSize))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: UX.rowRadius, style: .continuous)
                    .fill(hovering && !disabled ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
        .padding(.horizontal, UX.hPad - 8)
    }
}

// MARK: - 메뉴바 패널

struct PanelView: View {
    @ObservedObject var model: Model
    @Environment(\.openWindow) private var openWindow

    @State private var showPauseOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !Netauto.isInstalled {
                notInstalled
            } else {
                header
                if model.cannotReadSSID {
                    separator
                    ssidWarning
                }
                separator
                infoGrid
                separator
                profileSection
                separator
                ipSection
                separator
                controlSection
            }
            separator
            footer
        }
        .frame(width: UX.panelWidth)
        .background(UX.background)      // 반투명 배경의 대비 문제를 없앤다
        .onAppear { model.refresh() }
    }

    // macOS 15 부터 Wi-Fi 이름 읽기에 위치 서비스 권한이 필요하다.
    // 이름을 못 읽으면 규칙을 적용할 수 없으므로, 무엇을 해야 하는지 알려준다.
    private var ssidWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                Text("Wi-Fi 이름을 읽을 수 없습니다")
                    .font(.system(size: UX.rowSize, weight: .semibold))
            }
            Text("macOS 15 부터 Wi-Fi 이름을 읽으려면 위치 서비스가 켜져 있어야 합니다. 이름을 모르면 규칙을 적용할 수 없습니다.")
                .font(.system(size: UX.capSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("위치 서비스 설정 열기") { model.openLocationSettings() }
                .buttonStyle(.link)
                .font(.system(size: UX.capSize))
        }
        .padding(.horizontal, UX.hPad)
    }

    private var separator: some View {
        Divider().opacity(0.6).padding(.vertical, 7)
    }

    // ── 헤더: 아이콘 + 프로필 이름 + 상태 ──
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(model.tint.opacity(0.20))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(model.tint.opacity(0.35), lineWidth: 0.5)
                Image(systemName: model.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.shortLabel)
                    .font(.system(size: UX.titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(model.stateLabel)
                    .font(.system(size: UX.capSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            if model.busy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, UX.hPad)
        .padding(.top, 12)
    }

    // ── 현재 상태: Grid 로 열을 맞춘다 (공백 정렬은 가변폭에서 어긋난다) ──
    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            infoRow("Wi-Fi", model.status.connected ? model.status.ssid : "연결 없음")
            infoRow("IP", model.ipLabel)
            infoRow("프록시", model.proxyLabel)
            if model.ruleMismatch {
                infoRow("규칙", model.ruleSummary, tint: .orange)
            }
        }
        .padding(.horizontal, UX.hPad)
    }

    private func infoRow(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: UX.capSize))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.system(size: UX.bodySize, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // ── 프로필 ──
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "프로필")
            if model.status.locations.isEmpty {
                hint("네트워크 위치가 없습니다 — 시스템 설정 › 네트워크에서 만드세요")
            } else {
                ForEach(model.status.locations, id: \.self) { loc in
                    ChoiceRow(
                        symbol: model.profileIcon(loc),
                        title: model.profileLabel(loc),
                        isSelected: loc == model.status.location,
                        disabled: model.busy
                    ) { model.send(["pick", loc]) }
                }
                hint("직접 고르면 이 Wi-Fi에 있는 동안 유지됩니다")
            }
        }
    }

    // ── IP ──
    private var ipSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "IP 주소")
            ChoiceRow(symbol: "arrow.triangle.2.circlepath",
                      title: "자동 (DHCP)",
                      isSelected: model.isDHCP,
                      disabled: model.busy) { model.send(["setdhcp"]) }

            ForEach(model.status.saved_ips, id: \.self) { row in
                ChoiceRow(symbol: "pin.fill",
                          title: row.label.isEmpty ? row.ip : row.label,
                          detail: row.label.isEmpty ? nil : row.ip,
                          isSelected: !model.isDHCP && row.ip == model.status.ipv4_address,
                          disabled: model.busy) { model.send(["setip", row.ip]) }
            }

            if model.status.saved_ips.isEmpty {
                hint("자주 쓰는 IP를 설정에 추가하면 여기서 바로 고를 수 있습니다")
            } else if model.currentIPIsUnlisted {
                hint("지금 \(model.status.ipv4_address) — 목록에 없는 주소입니다")
            }
        }
    }

    // ── 제어 ──
    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ActionRow(symbol: "wand.and.stars",
                      title: "규칙대로 지금 맞추기",
                      disabled: model.busy) { model.send(["apply", "--force"]) }

            if model.isPaused {
                ActionRow(symbol: "play.circle",
                          title: "자동 전환 다시 시작",
                          disabled: model.busy) { model.send(["resume"]) }
            } else {
                ActionRow(symbol: "pause.circle",
                          title: showPauseOptions ? "잠시 멈추기 — 시간 고르기" : "잠시 멈추기",
                          disabled: model.busy || model.isDisabled) {
                    withAnimation(.easeOut(duration: 0.12)) { showPauseOptions.toggle() }
                }
                if showPauseOptions {
                    ForEach([30, 60, 120], id: \.self) { m in
                        ChoiceRow(symbol: nil,
                                  title: m < 60 ? "\(m)분" : "\(m / 60)시간",
                                  isSelected: false,
                                  disabled: model.busy) {
                            model.send(["pause", "\(m)"])
                            showPauseOptions = false
                        }
                    }
                }
            }

            // 켜고 끄기는 스위치가 상태를 가장 잘 보여준다
            HStack {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 13)).frame(width: 17).foregroundStyle(.secondary)
                Toggle("자동 전환", isOn: Binding(
                    get: { !model.isDisabled },
                    set: { on in model.send([on ? "on" : "off"]) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: UX.rowSize))
                .disabled(model.busy)
            }
            .padding(.horizontal, UX.hPad)
            .padding(.top, 2)
        }
    }

    // ── 하단 ──
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            ActionRow(symbol: "gearshape", title: "설정…") {
                model.loadDraft()
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            ActionRow(symbol: "doc.text.magnifyingglass", title: "로그 보기") {
                Reveal.log(model.status.log)
            }
            ActionRow(symbol: "network", title: "시스템 네트워크 설정") {
                Reveal.networkSettings()
            }

            HStack(spacing: 8) {
                Text("netauto \(model.status.version)  ·  by devpaulie")
                    .font(.system(size: UX.capSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("제거…") { model.uninstall() }
                    .buttonStyle(.link)
                    .font(.system(size: UX.capSize))
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.system(size: UX.capSize))
            }
            .padding(.horizontal, UX.hPad)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    private var notInstalled: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("백그라운드 서비스가 없습니다")
                    .font(.system(size: UX.rowSize, weight: .semibold))
            }
            Text("설치 프로그램(netauto 설치.pkg)을 다시 실행해 주세요.")
                .font(.system(size: UX.capSize)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, UX.hPad)
        .padding(.top, 12)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: UX.capSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, UX.hPad)
            .padding(.top, 3)
    }
}

// MARK: - 설정 창

struct SettingsView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss

    private let wCol: CGFloat = 180   // Wi-Fi 이름
    private let pCol: CGFloat = 130   // 프로필
    private let mCol: CGFloat = 125   // IP 방식
    private let iCol: CGFloat = 165   // 고정할 주소

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rulesSection
                    Divider()
                    savedIPSection
                    Divider()
                    profileSection
                    Divider()
                    optionSection
                }
                .padding(22)
            }
            Divider()
            footer
        }
        .frame(minWidth: 800, idealWidth: 860, minHeight: 560, idealHeight: 700)
        .onAppear { if model.draft.rules.isEmpty { model.loadDraft() } }
    }

    // ── 규칙 ──
    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            head("Wi-Fi 규칙", "어떤 Wi-Fi에 붙었을 때 어떤 프로필과 IP 설정을 쓸지 정합니다.")
            columns([("Wi-Fi 이름", wCol), ("프로필", pCol), ("IP", mCol), ("고정할 주소", iCol)])

            ForEach($model.draft.rules) { $rule in
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        TextField("Wi-Fi 이름", text: $rule.ssid)
                        Menu {
                            Button("* (그 외 모든 Wi-Fi)") { rule.ssid = "*" }
                            if !model.knownSSIDs.isEmpty {
                                Divider()
                                ForEach(model.knownSSIDs, id: \.self) { s in
                                    Button(s) { rule.ssid = s }
                                }
                            }
                        } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton)
                            .frame(width: 18)
                    }
                    .frame(width: wCol)

                    Picker("", selection: $rule.location) {
                        ForEach(locationChoices(including: rule.location), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: pCol)

                    Picker("", selection: $rule.ip_mode) {
                        ForEach(Config.IPMode.allCases) { m in Text(m.title).tag(m.rawValue) }
                    }
                    .labelsHidden().frame(width: mCol)

                    if rule.mode == .manual {
                        Picker("", selection: $rule.ip) {
                            if model.draft.saved_ips.isEmpty {
                                Text("아래에서 IP를 먼저 추가").tag(rule.ip)
                            } else {
                                if rule.ip.isEmpty { Text("고르세요").tag("") }
                                ForEach(savedIPChoices(including: rule.ip), id: \.self) { ip in
                                    Text(ipTitle(ip)).tag(ip)
                                }
                            }
                        }
                        .labelsHidden().frame(width: iCol)
                    } else {
                        Text(rule.mode == .dhcp ? "자동으로 받음" : "지금 설정 유지")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: iCol, alignment: .leading)
                    }

                    Button {
                        model.draft.rules.removeAll { $0.id == rule.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                }
            }

            Button {
                model.draft.rules.append(.init(ssid: "", location: defaultLocation, ip_mode: .keep, ip: ""))
            } label: { Label("규칙 추가", systemImage: "plus.circle") }
                .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text("`*` 는 “그 외 모든 Wi-Fi”를 뜻합니다. 목록 맨 아래에 두면 기본값이 됩니다.")
                Text("IP — 그대로 두기: 건드리지 않음 · 자동(DHCP): 공유기에서 받음 · 고정 IP: 아래 목록에서 고른 주소")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── 자주 쓰는 IP ──
    private var savedIPSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            head("자주 쓰는 IP", "여기 적어두면 위 규칙의 “고정 IP”와 메뉴바 패널에서 골라 쓸 수 있습니다.")
            columns([("이름", wCol), ("IP 주소", pCol)])

            ForEach($model.draft.saved_ips) { $row in
                HStack(spacing: 8) {
                    TextField("예: 4층 내 자리", text: $row.label).frame(width: wCol)
                    TextField("예: 192.168.10.50", text: $row.ip).frame(width: pCol)
                    Button {
                        model.draft.saved_ips.removeAll { $0.id == row.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                }
            }

            Button {
                model.draft.saved_ips.append(.init(label: "", ip: ""))
            } label: { Label("IP 추가", systemImage: "plus.circle") }
                .buttonStyle(.borderless)
        }
    }

    // ── 프로필 이름표와 아이콘 ──
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            head("프로필 이름표와 아이콘",
                 "메뉴바에 띄울 이름과 아이콘입니다. 왼쪽은 시스템의 네트워크 위치 이름입니다.")
            columns([("네트워크 위치", wCol), ("메뉴바 이름", pCol), ("아이콘", mCol)])

            ForEach($model.draft.profiles) { $p in
                HStack(spacing: 8) {
                    Text(p.location).frame(width: wCol, alignment: .leading)
                    TextField(p.location, text: $p.label).frame(width: pCol)

                    Picker("", selection: $p.icon) {
                        ForEach(ProfileIcon.choices(including: p.icon), id: \.symbol) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.symbol)
                                Text(item.name)
                            }
                            .tag(item.symbol)
                        }
                    }
                    .labelsHidden().frame(width: mCol + 60)

                    // 실제 메뉴바에 어떻게 보일지 미리보기
                    Image(nsImage: MenuBarLabel.image(
                        symbol: p.icon.isEmpty ? "globe" : p.icon,
                        text: model.draft.options.menubar_text
                            ? (p.label.isEmpty ? p.location : p.label) : nil))
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("이 목록은 시스템에서 그대로 읽어옵니다. 위치를 만들거나 지우는 건 시스템 설정 › 네트워크에서 하세요.")
                Text("오른쪽은 실제 메뉴바에 보일 모습입니다. 시스템 Wi-Fi 아이콘과 헷갈리지 않는 것을 고르세요.")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── 옵션 ──
    private var optionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            head("옵션", "")
            Toggle("메뉴바에 프로필 이름 표시 (아이콘만 쓰려면 끄세요)",
                   isOn: $model.draft.options.menubar_text)
            Toggle("프로필이 바뀔 때 알림 표시", isOn: $model.draft.options.notify)
            Toggle("내가 직접 바꾼 프로필은 그 Wi-Fi에서 유지",
                   isOn: $model.draft.options.respect_manual)
        }
    }

    // ── 하단 ──
    private var footer: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if model.saveMessage == nil && model.draftProblems.isEmpty {
                    Text("netauto \(model.status.version)  ·  by devpaulie")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let m = model.saveMessage {
                    Text(m).font(.caption)
                        .foregroundStyle(m == "저장했습니다" ? Color.green : Color.red)
                }
                ForEach(model.draftProblems, id: \.self) { p in
                    Text("· \(p)").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 12)
            Button("취소") {
                if model.confirmDiscard() { model.loadDraft(); dismiss() }
            }
            .keyboardShortcut(.cancelAction)
            Button("되돌리기") { model.loadDraft() }
                .disabled(!model.draftHasChanges)
            Button("저장") { if model.saveDraft() { dismiss() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.draftProblems.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // ── 조각 ──
    private func head(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func columns(_ cols: [(String, CGFloat)]) -> some View {
        HStack(spacing: 8) {
            ForEach(cols, id: \.0) { c in
                Text(c.0).font(.caption).foregroundStyle(.secondary)
                    .frame(width: c.1, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
    private var defaultLocation: String {
        model.status.default_location.isEmpty
            ? (model.status.locations.first ?? "") : model.status.default_location
    }
    private func locationChoices(including current: String) -> [String] {
        var list = model.status.locations
        if !current.isEmpty, !list.contains(current) { list.insert(current, at: 0) }
        return list
    }
    private func savedIPChoices(including current: String) -> [String] {
        var list = model.draft.saved_ips.map(\.ip).filter { !$0.isEmpty }
        if !current.isEmpty, !list.contains(current) { list.insert(current, at: 0) }
        return list
    }
    private func ipTitle(_ ip: String) -> String {
        if let row = model.draft.saved_ips.first(where: { $0.ip == ip }), !row.label.isEmpty {
            return "\(row.label)  (\(ip))"
        }
        return ip
    }
}

// MARK: - 앱

@main
struct NetautoBarApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            // 라벨은 NSStatusItem 버튼이라 SwiftUI 뷰가 아니다.
            // 아이콘과 글자를 하나의 템플릿 NSImage 로 합성해 넘긴다.
            Image(nsImage: model.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        Window("netauto 설정", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
