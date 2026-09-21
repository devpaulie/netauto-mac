// Core — netauto CLI 브리지, 설정 파일 읽기/쓰기, 상태 모델
//
// 이 앱은 네트워크를 직접 바꾸지 않는다. 위치 전환과 IP 설정은 root 권한이
// 필요하므로 요청 파일만 큐에 떨어뜨리고 root 데몬이 수행한다.
// → GUI에서 비밀번호를 한 번도 묻지 않는다.

import Foundation
import SwiftUI
import AppKit
import CoreWLAN
import CoreLocation
import Combine

// MARK: - 설정 파일 (netauto 데몬과 공유하는 JSON)

struct Config: Codable, Equatable {
    var version = 2
    var options = Options()
    var profiles: [Profile] = []
    var rules: [Rule] = []
    var saved_ips: [SavedIP] = []

    enum CodingKeys: String, CodingKey { case version, options, profiles, rules, saved_ips }

    init() {}

    // Swift 가 자동 생성하는 디코더는 프로퍼티에 기본값이 있어도
    // 키가 없으면 실패한다. 설정 일부가 빠진 파일에서도 나머지를 살리려면
    // 이렇게 직접 써야 한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version   = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        options   = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
        profiles  = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        rules     = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        saved_ips = try c.decodeIfPresent([SavedIP].self, forKey: .saved_ips) ?? []
    }

    struct Options: Codable, Equatable {
        var notify = true
        var respect_manual = true
        var menubar_text = true
        var no_wifi = "skip"

        enum CodingKeys: String, CodingKey { case notify, respect_manual, menubar_text, no_wifi }

        init() {}
        init(notify: Bool, respect_manual: Bool, menubar_text: Bool, no_wifi: String) {
            self.notify = notify; self.respect_manual = respect_manual
            self.menubar_text = menubar_text; self.no_wifi = no_wifi
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            notify         = try c.decodeIfPresent(Bool.self,   forKey: .notify) ?? true
            respect_manual = try c.decodeIfPresent(Bool.self,   forKey: .respect_manual) ?? true
            menubar_text   = try c.decodeIfPresent(Bool.self,   forKey: .menubar_text) ?? true
            no_wifi        = try c.decodeIfPresent(String.self, forKey: .no_wifi) ?? "skip"
        }
    }

    /// 네트워크 위치에 붙이는 짧은 이름표와 아이콘 (메뉴바 표시용)
    struct Profile: Codable, Identifiable, Equatable {
        var id = UUID()
        var location = ""
        var label = ""
        var icon = ""
        enum CodingKeys: String, CodingKey { case location, label, icon }

        init(location: String = "", label: String = "", icon: String = "") {
            self.location = location; self.label = label; self.icon = icon
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
            label    = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
            icon     = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        }
    }

    /// Wi-Fi 이름 → 프로필 + IP 처리 방식
    struct Rule: Codable, Identifiable, Equatable {
        var id = UUID()
        var ssid = ""
        var location = ""
        /// keep(그대로) · dhcp(자동) · manual(고정)
        var ip_mode = IPMode.keep.rawValue
        var ip = ""
        enum CodingKeys: String, CodingKey { case ssid, location, ip_mode, ip }

        init(ssid: String = "", location: String = "",
             ip_mode: IPMode = .keep, ip: String = "") {
            self.ssid = ssid; self.location = location
            self.ip_mode = ip_mode.rawValue; self.ip = ip
        }

        /// 예전 설정에는 ip_mode 가 없다 — ip 값이 있으면 고정, 없으면 그대로.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? ""
            location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
            ip = try c.decodeIfPresent(String.self, forKey: .ip) ?? ""
            if let m = try c.decodeIfPresent(String.self, forKey: .ip_mode),
               IPMode(rawValue: m) != nil {
                ip_mode = m
            } else {
                ip_mode = ip.isEmpty ? IPMode.keep.rawValue : IPMode.manual.rawValue
            }
        }

        var mode: IPMode {
            get { IPMode(rawValue: ip_mode) ?? .keep }
            set { ip_mode = newValue.rawValue }
        }
    }

    enum IPMode: String, CaseIterable, Identifiable {
        case keep, dhcp, manual
        var id: String { rawValue }
        var title: String {
            switch self {
            case .keep:   return "그대로 두기"
            case .dhcp:   return "자동 (DHCP)"
            case .manual: return "고정 IP"
            }
        }
    }

    /// 메뉴에서 바로 골라 적용할 수 있게 적어두는 IP
    struct SavedIP: Codable, Identifiable, Equatable {
        var id = UUID()
        var label = ""
        var ip = ""
        enum CodingKeys: String, CodingKey { case label, ip }

        init(label: String = "", ip: String = "") { self.label = label; self.ip = ip }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
            ip    = try c.decodeIfPresent(String.self, forKey: .ip) ?? ""
        }
    }
}

// id(UUID)는 JSON에 저장되지 않고 디코딩할 때 새로 생성된다.
// 자동 생성 == 는 id까지 비교해 "같은 내용인데 다르다"고 판정하므로,
// 내용만 비교하도록 직접 구현한다.
extension Config.Rule {
    static func == (a: Self, b: Self) -> Bool {
        a.ssid == b.ssid && a.location == b.location && a.ip == b.ip
    }
}
extension Config.SavedIP {
    static func == (a: Self, b: Self) -> Bool { a.label == b.label && a.ip == b.ip }
}
extension Config.Profile {
    static func == (a: Self, b: Self) -> Bool {
        a.location == b.location && a.label == b.label && a.icon == b.icon
    }
}

enum ConfigStore {
    static let defaultPath = "/usr/local/etc/netauto/config.json"

    static func load(_ path: String) -> Config? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    /// 설정 디렉터리가 admin 쓰기 가능(root:admin 775)이라 원자적 저장이 가능하다.
    static func save(_ config: Config, to path: String) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(config) else { return "설정을 JSON으로 만들 수 없습니다" }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return nil
        } catch {
            return "저장 실패: \(error.localizedDescription)"
        }
    }
}


// MARK: - netauto CLI

/// `netauto status --json` 의 출력. 키 이름이 그대로 대응된다.
struct Status: Codable {
    var version           = ""
    var wifi_device       = ""
    var ssid              = ""
    var connected         = false
    var location          = ""
    var expected_location = ""
    var expected_ip       = ""
    var expected_ip_mode  = "keep"
    var ipv4_is_dhcp      = false
    var label             = ""
    var icon              = ""
    var menubar_text      = true
    var default_location  = ""
    var state             = "unknown"
    var pause_remaining   = 0
    var applied_at        = 0
    var ipv4_config       = ""
    var ipv4_address      = ""
    var router            = ""
    var pac_url           = ""
    var conf              = ConfigStore.defaultPath
    var conf_valid        = true
    var log               = ""
    var queue_ready       = false
    var locations: [String] = []
    var saved_ips: [SavedIPRow] = []
    var profiles: [ProfileRow] = []

    struct SavedIPRow: Codable, Hashable { var label = ""; var ip = "" }
    struct ProfileRow: Codable, Hashable { var location = ""; var label = ""; var icon = "" }

    // 설치된 CLI 가 구버전이라 일부 필드를 안 내보낼 수 있다 → 기본값으로 채운다
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys, _ d: String = "") -> String {
            (try? c.decodeIfPresent(String.self, forKey: k)) ?? d
        }
        func b(_ k: CodingKeys, _ d: Bool) -> Bool {
            (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? d
        }
        func i(_ k: CodingKeys, _ d: Int = 0) -> Int {
            (try? c.decodeIfPresent(Int.self, forKey: k)) ?? d
        }
        version = s(.version); wifi_device = s(.wifi_device); ssid = s(.ssid)
        connected = b(.connected, false)
        location = s(.location); expected_location = s(.expected_location)
        expected_ip = s(.expected_ip); expected_ip_mode = s(.expected_ip_mode, "keep")
        label = s(.label); icon = s(.icon)
        menubar_text = b(.menubar_text, true)
        default_location = s(.default_location)
        state = s(.state, "unknown")
        pause_remaining = i(.pause_remaining); applied_at = i(.applied_at)
        ipv4_config = s(.ipv4_config); ipv4_address = s(.ipv4_address)
        ipv4_is_dhcp = b(.ipv4_is_dhcp, false)
        router = s(.router); pac_url = s(.pac_url)
        conf = s(.conf, ConfigStore.defaultPath)
        conf_valid = b(.conf_valid, true)
        log = s(.log); queue_ready = b(.queue_ready, false)
        locations = (try? c.decodeIfPresent([String].self, forKey: .locations)) ?? []
        saved_ips = (try? c.decodeIfPresent([SavedIPRow].self, forKey: .saved_ips)) ?? []
        profiles = (try? c.decodeIfPresent([ProfileRow].self, forKey: .profiles)) ?? []
    }
}

enum Netauto {
    /// root 소유 경로. /usr/local/bin 은 사용자 쓰기가 가능해 일부러 쓰지 않는다.
    static let binary = "/usr/local/libexec/netauto"
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary) }

    struct Result { let out: String; let err: String; let code: Int32 }

    static func run(_ args: [String]) -> Result {
        guard isInstalled else {
            return Result(out: "", err: "netauto 가 설치되지 않았습니다", code: -1)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let o = Pipe(), e = Pipe()
        proc.standardOutput = o
        proc.standardError = e
        do { try proc.run() } catch {
            return Result(out: "", err: "실행 실패: \(error.localizedDescription)", code: -1)
        }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Result(out: String(data: od, encoding: .utf8) ?? "",
                      err: String(data: ed, encoding: .utf8) ?? "",
                      code: proc.terminationStatus)
    }

    static func status() -> (Status?, String?) {
        let r = run(["status", "--json"])
        guard r.code == 0, let d = r.out.data(using: .utf8) else {
            return (nil, r.err.isEmpty ? "상태를 읽을 수 없습니다" : r.err.trimmed)
        }
        do { return (try JSONDecoder().decode(Status.self, from: d), nil) }
        catch { return (nil, "상태 해석 실패") }
    }

    /// 저장된 Wi-Fi 이름 목록 (설정 창에서 고를 수 있게)
    static func knownSSIDs() -> [String] {
        run(["ssids"]).out
            .split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 빈 문자열이거나 올바른 IPv4 형식인지
    var isBlankOrIPv4: Bool {
        if trimmed.isEmpty { return true }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard !p.isEmpty, p.count <= 3, p.allSatisfy(\.isNumber), let v = Int(p) else { return false }
            return v <= 255
        }
    }
}

// MARK: - 모델

@MainActor
final class Model: ObservableObject {
    @Published var status = Status()
    @Published var error: String?
    @Published var busy = false

    /// 설정 창이 편집하는 사본. 저장을 눌러야 파일에 쓴다.
    @Published var draft = Config()
    @Published var knownSSIDs: [String] = []
    @Published var saveMessage: String?

    /// Wi-Fi 이름을 대신 읽어 데몬에 넘긴다 (macOS 15+ 위치 권한 필요)
    let wifi = WiFiMonitor()

    private var timer: Timer?
    private var wifiObserver: AnyCancellable?

    init() {
        // 앱이 읽은 이름이 바뀌면 곧바로 상태를 다시 읽는다
        wifiObserver = wifi.objectWillChange.sink { [weak self] _ in
            guard let me = self else { return }
            Task { @MainActor in me.refresh() }
        }
        refresh()
        schedulePolling()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let me = self else { return }
            Task { @MainActor in me.refresh() }
        }
    }

    /// 패널이 열려 있으면 자주, 닫혀 있으면 드물게 갱신한다.
    /// 상태 조회는 netauto 프로세스를 띄우므로 닫힌 동안의 빈도를 줄인다.
    @Published var panelOpen = false {
        didSet { if panelOpen != oldValue { schedulePolling(); if panelOpen { refresh() } } }
    }

    private func schedulePolling() {
        timer?.invalidate()
        let interval: TimeInterval = panelOpen ? 3 : 30
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let me = self else { return }
            Task { @MainActor in me.refresh() }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let (s, e) = Netauto.status()
            await MainActor.run {
                if let s { self.status = s; self.error = nil } else { self.error = e }
            }
        }
    }

    /// 데몬에 작업을 요청하고 잠시 뒤 상태를 다시 읽는다.
    func send(_ args: [String]) {
        busy = true
        Task.detached(priority: .userInitiated) {
            let r = Netauto.run(args)
            try? await Task.sleep(nanoseconds: 1_600_000_000)   // 데몬이 큐를 처리할 시간
            let (s, e) = Netauto.status()
            await MainActor.run {
                self.busy = false
                if let s { self.status = s }
                if r.code != 0, !r.err.isEmpty { self.error = r.err.trimmed }
                else if s != nil { self.error = e }
            }
        }
    }

    // ── 설정 창 ──────────────────────────────────────────────────────

    func loadDraft() {
        draft = ConfigStore.load(status.conf) ?? Config()
        // 시스템에 있는 네트워크 위치가 프로필 목록에 빠져 있으면 채워준다
        for loc in status.locations where !draft.profiles.contains(where: { $0.location == loc }) {
            draft.profiles.append(.init(location: loc, label: loc, icon: "wifi"))
        }
        saveMessage = nil
        Task.detached(priority: .utility) {
            let list = Netauto.knownSSIDs()
            await MainActor.run { self.knownSSIDs = list }
        }
    }

    /// 설정 창에서 편집한 내용이 파일과 다른가 (취소·되돌리기 활성화 판단)
    var draftHasChanges: Bool {
        draft != (ConfigStore.load(status.conf) ?? Config())
    }

    /// 취소: 변경이 있으면 한 번 확인하고 버린다. 닫아도 되면 true.
    func confirmDiscard() -> Bool {
        guard draftHasChanges else { return true }
        let a = NSAlert()
        a.messageText = "저장하지 않은 변경이 있습니다"
        a.informativeText = "지금 닫으면 변경한 내용이 사라집니다."
        a.alertStyle = .warning
        a.addButton(withTitle: "변경 버리고 닫기")
        a.addButton(withTitle: "계속 편집")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    var draftProblems: [String] {
        var out: [String] = []
        if draft.rules.isEmpty { out.append("규칙이 하나도 없습니다") }
        for r in draft.rules {
            if r.ssid.trimmed.isEmpty { out.append("Wi-Fi 이름이 빈 규칙이 있습니다") }
            if r.location.trimmed.isEmpty { out.append("'\(r.ssid)' 규칙에 프로필이 없습니다") }
            if !r.ip.isBlankOrIPv4 { out.append("'\(r.ssid)' 규칙의 IP 형식이 잘못됐습니다: \(r.ip)") }
            if r.mode == .manual, r.ip.trimmed.isEmpty {
                out.append("'\(r.ssid)' 규칙이 고정 IP인데 주소를 고르지 않았습니다")
            }
        }
        for s in draft.saved_ips where !s.ip.isBlankOrIPv4 {
            out.append("저장된 IP '\(s.label)' 의 형식이 잘못됐습니다: \(s.ip)")
        }
        var seen = Set<String>()
        for r in draft.rules where !seen.insert(r.ssid.trimmed).inserted {
            out.append("Wi-Fi 이름이 중복됩니다: \(r.ssid)")
        }
        return Array(Set(out)).sorted()
    }

    @discardableResult
    func saveDraft() -> Bool {
        guard draftProblems.isEmpty else { return false }
        var c = draft
        c.rules = c.rules.map { r0 in
            var r = r0
            r.ssid = r.ssid.trimmed
            r.ip = r.mode == .manual ? r.ip.trimmed : ""   // 고정이 아니면 주소는 무의미
            return r
        }
        c.saved_ips = c.saved_ips.map { var s = $0; s.label = s.label.trimmed; s.ip = s.ip.trimmed; return s }
        if let err = ConfigStore.save(c, to: status.conf) {
            saveMessage = err
            return false
        }
        draft = c
        saveMessage = "저장했습니다"
        // 바뀐 규칙을 바로 반영시킨다 (데몬의 다음 주기를 기다리지 않도록)
        send(["apply"])
        return true
    }

    /// 메뉴의 "netauto 제거…". 확인 후 관리자 인증을 거쳐 제거한다.
    func uninstall() {
        let alert = NSAlert()
        alert.messageText = "netauto 를 제거할까요?"
        alert.informativeText = """
        메뉴바 앱과 백그라운드 서비스, 설정이 모두 지워집니다.
        네트워크 프로필(Office / Automatic)은 그대로 남습니다.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "제거")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let err = Admin.run("/usr/local/libexec/netauto-uninstall",
                               prompt: "netauto 를 제거하려면 관리자 암호가 필요합니다.") {
            if err == "취소" { return }
            let fail = NSAlert()
            fail.messageText = "제거하지 못했습니다"
            fail.informativeText = err
            fail.runModal()
            return
        }
        NSApplication.shared.terminate(nil)
    }

    // ── 표시용 파생 값 ───────────────────────────────────────────────

    var symbol: String {
        if !Netauto.isInstalled { return "exclamationmark.triangle" }
        if error != nil || !status.conf_valid { return "wifi.exclamationmark" }
        switch status.state {
        case "disabled": return "nosign"
        case "paused":   return "pause.circle"
        case "nowifi":   return "wifi.slash"
        case "nossid":   return "wifi.exclamationmark"
        case "manual":   return "hand.raised.fill"
        default:
            return status.icon.isEmpty
                ? (status.location == status.default_location ? "globe" : "building.2.fill")
                : status.icon
        }
    }

    /// 메뉴바에 띄우는 짧은 이름 (Office / Auto …)
    var shortLabel: String {
        if !Netauto.isInstalled { return "미설치" }
        if !status.conf_valid { return "설정 오류" }
        switch status.state {
        case "disabled": return "꺼짐"
        case "paused":   return "일시중지"
        case "nowifi":   return "연결 없음"
        case "nossid":   return "이름 확인 불가"
        default:         return status.label.isEmpty ? status.location : status.label
        }
    }

    var showText: Bool { status.menubar_text }

    /// 메뉴바에 실제로 그려지는 이미지 (아이콘 + 선택적 이름)
    var menuBarImage: NSImage {
        MenuBarLabel.image(symbol: symbol, text: showText ? shortLabel : nil)
    }

    /// 현재 IPv4 가 자동(DHCP)인지
    var isDHCP: Bool { status.ipv4_is_dhcp }

    // ── 메뉴에서 "지금 값"을 표시하기 위한 것들 ──────────────────────
    // 체크 표시는 Toggle 이 네이티브로 그린다 (Button + Label(systemImage:) 은
    // 이 환경에서 아이콘이 렌더링되지 않는다).

    /// 네트워크 위치 이름 → 설정한 짧은 이름표
    func profileLabel(_ location: String) -> String {
        let l = status.profiles.first { $0.location == location }?.label ?? ""
        return l.isEmpty ? location : l
    }

    /// "프로필 바꾸기 (Office)" — 상위 메뉴에서 바로 현재값이 보이게
    var profileMenuTitle: String {
        status.location.isEmpty ? "프로필 바꾸기" : "프로필 바꾸기 (\(profileLabel(status.location)))"
    }

    /// "IP 바꾸기 (자동)" 또는 "IP 바꾸기 (192.168.10.50)"
    var ipMenuTitle: String {
        if isDHCP { return "IP 바꾸기 (자동)" }
        return status.ipv4_address.isEmpty ? "IP 바꾸기" : "IP 바꾸기 (\(status.ipv4_address))"
    }

    /// 상태별 강조색 — 헤더 아이콘과 경고 표시에 쓴다
    var tint: Color {
        if !Netauto.isInstalled || !status.conf_valid || error != nil { return .orange }
        switch status.state {
        case "disabled": return .secondary
        case "paused":   return .secondary
        case "nowifi":   return .secondary
        case "nossid":   return .orange
        case "manual":   return .orange
        default:         return .accentColor
        }
    }

    /// 네트워크 위치 이름 → 설정한 아이콘 (없으면 기본값 추론)
    func profileIcon(_ location: String) -> String {
        let i = status.profiles.first { $0.location == location }?.icon ?? ""
        if !i.isEmpty { return i }
        return location == status.default_location ? "globe" : "building.2.fill"
    }

    /// 규칙이 기대하는 상태와 지금이 다른가 (자동 상태에서만 의미 있다)
    var ruleMismatch: Bool {
        guard status.state == "auto" else { return false }
        if status.location != status.expected_location { return true }
        switch status.expected_ip_mode {
        case "dhcp":   return !status.ipv4_is_dhcp
        case "manual": return status.ipv4_address != status.expected_ip
        default:       return false
        }
    }

    /// "Office + 고정 192.168.10.50" 처럼 규칙이 바라는 상태를 한 줄로
    var ruleSummary: String {
        let loc = profileLabel(status.expected_location)
        switch status.expected_ip_mode {
        case "dhcp":   return "\(loc) · 자동"
        case "manual": return "\(loc) · 고정 \(status.expected_ip)"
        default:       return loc
        }
    }

    /// SSID 를 읽지 못하는 상태인가 (macOS 15+ 위치 서비스 권한 문제)
    var cannotReadSSID: Bool { status.state == "nossid" }

    /// 앱이 위치 권한을 못 받아 Wi-Fi 이름을 읽지 못하는 상태
    var needsLocationPermission: Bool { wifi.needsAuthorization }

    /// 위치 권한 상태를 사람이 읽는 문장으로
    var locationStatusLabel: String {
        if wifi.isAuthorized {
            return wifi.ssid.map { "허용됨 · \($0)" } ?? "허용됨 · 이름 없음"
        }
        switch wifi.authStatus {
        case .notDetermined: return "아직 요청하지 않음"
        case .denied:        return "거부됨 — 설정에서 켜야 합니다"
        case .restricted:    return "제한됨"
        default:             return "확인 중"
        }
    }

    /// 위치 서비스 설정 창을 연다
    func openLocationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
        ]
        for u in urls where NSWorkspace.shared.open(URL(string: u)!) { return }
    }

    /// 현재 IP 가 저장 목록에 없는 주소인지 (있으면 목록에서 체크로 표시된다)
    var currentIPIsUnlisted: Bool {
        !isDHCP && !status.ipv4_address.isEmpty
            && !status.saved_ips.contains { $0.ip == status.ipv4_address }
    }

    var stateLabel: String {
        if !Netauto.isInstalled { return "netauto 미설치 — setup.sh 를 실행하세요" }
        if !status.conf_valid { return "설정 파일이 깨졌습니다" }
        if let error { return error }
        switch status.state {
        case "disabled": return "자동 전환 꺼짐"
        case "paused":   return "일시중지 · \(status.pause_remaining / 60 + 1)분 남음"
        case "nowifi":   return "Wi-Fi 미연결"
        case "nossid":   return "Wi-Fi 이름을 읽을 수 없음 — 위치 서비스 권한 필요"
        case "manual":   return "내가 고른 프로필 유지 중"
        default:
            return status.location == status.expected_location ? "자동 · 규칙과 일치" : "자동 · 적용 대기"
        }
    }

    /// 패널에 보여줄 Wi-Fi 이름. 데몬이 못 읽어도 앱이 읽은 값을 쓴다.
    var displaySSID: String {
        if let s = wifi.ssid, !s.isEmpty { return s }
        if status.connected, !status.ssid.isEmpty { return status.ssid }
        return status.state == "nowifi" ? "연결 없음" : "이름 확인 불가"
    }

    var ipLabel: String {
        let addr = status.ipv4_address.isEmpty ? "—" : status.ipv4_address
        let cfg = status.ipv4_config
            .replacingOccurrences(of: "DHCP Configuration", with: "DHCP")
            .replacingOccurrences(of: "Manual Configuration", with: "수동")
            .replacingOccurrences(of: "Configuration", with: "").trimmed
        return cfg.isEmpty ? addr : "\(addr) · \(cfg)"
    }

    var proxyLabel: String {
        status.pac_url.isEmpty
            ? "없음"
            : "PAC \(URL(string: status.pac_url)?.lastPathComponent ?? status.pac_url)"
    }

    var isPaused: Bool { status.state == "paused" }
    var isDisabled: Bool { status.state == "disabled" }
}

// MARK: - Wi-Fi 이름 감시자

/// macOS 15 부터 Wi-Fi 이름을 읽으려면 위치 서비스 권한이 필요하다.
/// root 데몬은 그 권한을 받을 수 없어서 — macOS 26 에서는 wdutil 조차
/// `<redacted>` 를 돌려준다 — 사용자 권한으로 도는 이 앱이 대신 읽어
/// 데몬이 보는 파일에 적어 둔다.
///
/// 파일 형식 (2줄):
///   1행: 기록 시각 (epoch 초)
///   2행: Wi-Fi 이름 (읽지 못했으면 빈 줄)
/// 데몬은 너무 오래된 값을 무시하므로, 앱이 꺼져 있으면 자동으로 폐기된다.
@MainActor
final class WiFiMonitor: NSObject, ObservableObject {
    static let publishPath = "/usr/local/var/netauto/ssid"

    @Published private(set) var ssid: String?
    @Published private(set) var authStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var canPublish = true

    private let location = CLLocationManager()
    private let wifi = CWWiFiClient.shared()
    private var timer: Timer?

    override init() {
        super.init()
        location.delegate = self
        // 위치 자체는 쓰지 않는다. 권한만 있으면 CoreWLAN 이 Wi-Fi 이름을 돌려준다.
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        authStatus = location.authorizationStatus
        refresh()
        // 앱 구동이 끝난 뒤에 요청해야 대화상자가 유실되지 않는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.requestAuthorizationIfNeeded()
        }
        // 15초마다 확인한다. 데몬은 90초까지 유효하게 보므로 충분히 여유 있고,
        // CoreWLAN 조회는 프로세스를 띄우지 않아 비용이 거의 없다.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let me = self else { return }
            Task { @MainActor in me.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let me = self else { return }
            Task { @MainActor in me.refresh() }
        }
    }

    var isAuthorized: Bool {
        authStatus == .authorizedAlways
    }

    var needsAuthorization: Bool {
        !isAuthorized && ssid == nil
    }

    /// 아직 묻지 않았다면 한 번 요청한다.
    /// LSUIElement 앱은 활성 상태가 아니면 대화상자가 뜨지 않을 수 있고,
    /// macOS 에 따라 실제로 위치 사용을 시작해야 프롬프트가 나오므로 둘 다 한다.
    func requestAuthorizationIfNeeded() {
        guard authStatus == .notDetermined else { return }
        NSApp.activate(ignoringOtherApps: true)
        location.requestAlwaysAuthorization()
        location.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.location.stopUpdatingLocation()
        }
    }

    /// 권한 요청. 이미 거부된 상태면 설정 창을 여는 수밖에 없다.
    func requestAuthorization() {
        switch authStatus {
        case .notDetermined:
            requestAuthorizationIfNeeded()
        case .denied, .restricted:
            openLocationSettings()
        default:
            refresh()
        }
    }

    func openLocationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
        ]
        for c in candidates {
            if let u = URL(string: c), NSWorkspace.shared.open(u) { return }
        }
    }

    func refresh() {
        let name = wifi.interface()?.ssid()
        ssid = (name?.isEmpty == false) ? name : nil
        publish()
    }

    /// 진단용 권한 상태 문자열
    var authText: String {
        switch authStatus {
        case .notDetermined:    return "notDetermined"
        case .restricted:       return "restricted"
        case .denied:           return "denied"
        case .authorizedAlways: return "authorizedAlways"
        @unknown default:       return "unknown(\(authStatus.rawValue))"
        }
    }

    private func publish() {
        // 3행에 권한 상태를 함께 적는다 (데몬은 1~2행만 읽으므로 호환된다)
        let payload = "\(Int(Date().timeIntervalSince1970))\n\(ssid ?? "")\n\(authText)\n"
        do {
            try payload.write(toFile: Self.publishPath, atomically: true, encoding: .utf8)
            canPublish = true
        } catch {
            // 데몬이 설치되지 않았거나 디렉터리 권한이 없으면 쓸 수 없다
            canPublish = false
        }
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authStatus = status
            self.refresh()
        }
    }
}

// MARK: - 프로필 아이콘 선택 목록

/// 설정 창에서 고를 수 있는 아이콘.
/// 시스템 메뉴바 아이콘(Wi-Fi·배터리·제어센터 등)과 헷갈리지 않는 것만 골랐다.
enum ProfileIcon {
    static let all: [(symbol: String, name: String)] = [
        ("globe",              "일반 · 인터넷"),
        ("building.2.fill",    "사무실"),
        ("house.fill",         "집"),
        ("briefcase.fill",     "업무"),
        ("cup.and.saucer.fill","카페"),
        ("airplane",           "이동 중"),
        ("lock.fill",          "보안망"),
        ("shield.fill",        "VPN"),
        ("server.rack",        "서버실"),
        ("desktopcomputer",    "데스크탑"),
        ("bolt.fill",          "빠른 회선"),
        ("star.fill",          "즐겨찾기"),
    ]
    static func name(_ symbol: String) -> String {
        all.first { $0.symbol == symbol }?.name ?? symbol
    }
    /// 목록에 없는 아이콘을 쓰고 있어도 Picker 에서 사라지지 않게
    static func choices(including current: String) -> [(symbol: String, name: String)] {
        if current.isEmpty || all.contains(where: { $0.symbol == current }) { return all }
        return [(current, current)] + all
    }
}

// MARK: - 메뉴바 라벨 이미지

/// SwiftUI 의 MenuBarExtra 라벨에서는 Text 안에 끼운 SF Symbol 이 렌더링되지 않고
/// 텍스트만 표시된다. 그래서 아이콘과 글자를 하나의 NSImage 로 직접 합성한다.
/// isTemplate = true 로 두면 메뉴바 색(라이트/다크·강조색)에 맞춰 알아서 그려진다.
enum MenuBarLabel {
    static func image(symbol: String, text: String?) -> NSImage {
        let height: CGFloat = 18
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(cfg)
        let iconSize = icon?.size ?? .zero

        var attributed: NSAttributedString?
        var textSize = CGSize.zero
        if let text, !text.isEmpty {
            let a = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.black,   // 템플릿 이미지라 실제 색은 시스템이 결정
            ])
            attributed = a
            textSize = a.size()
        }

        let gap: CGFloat = attributed == nil ? 0 : 4
        let width = max(iconSize.width + gap + ceil(textSize.width), 1)
        let img = NSImage(size: CGSize(width: width, height: height))
        img.lockFocus()
        icon?.draw(in: CGRect(x: 0, y: (height - iconSize.height) / 2,
                              width: iconSize.width, height: iconSize.height))
        attributed?.draw(at: CGPoint(x: iconSize.width + gap,
                                     y: (height - textSize.height) / 2))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}

// MARK: - 파일/설정 열기

/// 관리자 권한이 필요한 작업을 macOS 표준 인증 대화상자로 실행한다.
/// (터미널을 열지 않고도 제거할 수 있게)
enum Admin {
    /// 성공하면 nil, 사용자가 취소하거나 실패하면 사유
    static func run(_ command: String, prompt: String) -> String? {
        let script = "do shell script \"\(command)\" with prompt \"\(prompt)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        guard let err else { return nil }
        // -128 = 사용자가 취소
        if (err[NSAppleScript.errorNumber] as? Int) == -128 { return "취소" }
        return (err[NSAppleScript.errorMessage] as? String) ?? "실패"
    }
}

enum Reveal {
    static func file(_ path: String, app: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { NSSound.beep(); return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: app),
                                configuration: NSWorkspace.OpenConfiguration())
    }
    static func log(_ p: String) { file(p, app: "/System/Applications/Utilities/Console.app") }
    static func networkSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }
}
