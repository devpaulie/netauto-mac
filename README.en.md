# netauto

[한국어](README.md) · **English**

**Switch macOS network settings automatically, based on which Wi-Fi you're on.**

Join the office Wi-Fi and your Mac applies the office profile — static IP, proxy, DNS.
Walk into a cafe and it goes back to plain DHCP. A menu bar item always shows
which profile is live, and lets you override it.

```
Menu bar:   🌐 Auto      ← plain DHCP right now
            🏢 Office    ← office profile right now
```

*by devpaulie*

---

## Why network Locations?

macOS **Network Locations** already bundle everything that changes between sites:

- IPv4 method (DHCP / static / DHCP-with-manual-address)
- DNS servers and search domains
- **Proxies**, including PAC
- Per-interface settings for Wi-Fi *and* every Ethernet adapter

netauto doesn't reinvent that. It picks the right Location for the Wi-Fi you're on.
One switch, and wired and wireless are both correct — something you'd miss if you
only scripted the Wi-Fi service.

On top of that, each rule can pin the IPv4 method: leave it alone, force DHCP, or
set a static address you've saved.

---

## Install

Grab the latest `.dmg` from [Releases](../../releases), open it, and double-click
**“netauto 설치.pkg”**. Click through, enter your admin password once. Done.

No Terminal required. Uninstall from the menu bar item › **netauto 제거…**

> **“unidentified developer” warning?**
> The package isn't signed with an Apple Developer ID (that costs $99/year).
> - macOS 14 and earlier — right-click the `.pkg` → **Open**
> - macOS 15 and later — double-click once, then **System Settings › Privacy & Security › Open Anyway**

**Requirements:** macOS 13 (Ventura) or later. Universal — Apple Silicon and Intel.

### First run

netauto switches between Locations, so you need at least one to switch *to*:

1. **System Settings › Network** › `⋯` › **Location** › **Edit Locations…** — add one (e.g. *Office*)
2. Switch to it, configure the office IP and proxy, then switch back to `Automatic`
3. Menu bar › **설정…** — add a rule: *Wi-Fi name = OfficeWiFi, profile = Office, IP = static*

Out of the box the only rule is `* → Automatic → leave IP alone`, so netauto
changes nothing until you tell it to.

---

## The menu bar panel

```
┌──────────────────────────────────────┐
│  ┌──┐                                │
│  │🏢│  Office                        │  icon + profile name
│  └──┘  auto · matches rule           │  + current state
├──────────────────────────────────────┤
│  Wi-Fi    OfficeWiFi                 │  aligned status grid
│  IP       192.168.10.50 · manual     │
│  Proxy    PAC proxy.pac              │
├──────────────────────────────────────┤
│  Profile                             │
│  🏢 Office                        ✓  │  click to switch
│  🌐 Auto                             │
├──────────────────────────────────────┤
│  IP address                          │
│  ↻ Automatic (DHCP)                  │
│  📌 Desk, 4F     192.168.10.50    ✓  │
│  📌 Meeting room 192.168.10.51       │
├──────────────────────────────────────┤
│  ✦ Apply rules now                   │
│  ⏸ Pause                             │
│  ⚡ Auto-switching           (●━ )    │
├──────────────────────────────────────┤
│  ⚙ Settings…   🔍 Log   🌐 Network    │
└──────────────────────────────────────┘
```

### Manual overrides win

Pick a profile yourself and netauto **backs off for as long as you stay on that
Wi-Fi**. Move to a different network and automatic behavior resumes. To hand
control back immediately, hit **Apply rules now**.

### Icon states

| | |
|---|---|
| 🏢 / 🌐 | the profile currently applied (icon is yours to choose) |
| ✋ | you picked this one — automation is standing down |
| ⏸ | paused |
| 🚫 | auto-switching off |
| ⚠️ | no Wi-Fi, or the config file is broken |

---

## Settings

Everything is edited in the app — no config file spelunking.

### Wi-Fi rules

| Wi-Fi name | Profile | IP | Static address |
|---|---|---|---|
| `OfficeWiFi` | Office | Static IP | Desk, 4F (192.168.10.50) |
| `HomeNet` | Automatic | Automatic (DHCP) | — |
| `*` | Automatic | Leave alone | — |

- `*` means “every other Wi-Fi”. Put it last and it becomes the default.
- The `▾` next to the name lists Wi-Fi networks your Mac already knows.
- **IP** has three modes — *leave alone*, *automatic (DHCP)*, *static*.
  A static address is **chosen from your saved list**, not typed each time.
- The **Profile** list is read live from `networksetup -listlocations`.
  Add a Location in System Settings and it shows up here.

### Saved IPs

Name a few addresses once (`Desk, 4F`, `Meeting room`) and pick them from the
panel whenever you move desks or hit an address conflict — no digging through
System Settings.

---

## How it works

```
Wi-Fi changes  →  /var/run/resolv.conf is rewritten  →  launchd WatchPaths fires
               →  netauto apply  →  read SSID  →  match rule  →  switch Location
```

- **Trigger** — watches `resolv.conf` (effectively instant) plus a 30 s safety net
- **Idempotent** — if the state is already right, *nothing is written*. Switching a
  Location rewrites `resolv.conf`, which is our own trigger, so this early return
  is what stops the loop. Same for the IP.
- **Privileges** — a `LaunchDaemon` runs as root, so you enter your password once
  at install and never again.
- **SSID detection** — `networksetup -getairportnetwork`, falling back to
  `ipconfig getsummary`. (`airport -I` was deprecated in macOS 14.4.)

### The app never touches the network directly

The menu bar app runs as you; changing network settings needs root. So the app
writes a request file and the root daemon does the work:

```
app (user)  ──▶  /usr/local/var/netauto/queue/   ──▶  daemon (root)  ──▶  networksetup
```

launchd's `QueueDirectories` starts the job whenever that directory isn't empty
and restarts it until it's drained — so the daemon **must** delete each request it
handles, and a test pins that down.

| Path | Mode | Why |
|---|---|---|
| `/usr/local/libexec/netauto` | `root:wheel 755` | code that runs as root must only be writable by root |
| `/usr/local/etc/netauto/` | `root:admin 775` | so the app can save settings atomically |
| `/usr/local/var/netauto/queue/` | `root:admin 775` | so the app can drop requests |

Admins can already change network settings in System Settings, so this isn't a
privilege escalation. The config only holds Location *names* and IP strings, both
validated before use — there's no path to arbitrary execution.

---

## CLI

The daemon ships with a CLI, useful for scripting and debugging.

```bash
netauto status              # current Wi-Fi, profile, IP, rules, saved IPs
netauto status --json       # machine-readable (what the app reads)
netauto test <ssid>         # what would happen on that Wi-Fi (changes nothing)
netauto log [lines]
netauto doctor              # diagnose why switching isn't happening

netauto pick <profile>      # switch profile, mark as a manual override
netauto setip <address>     # pin a static address
netauto setdhcp             # back to automatic

sudo netauto apply [--force]
sudo netauto pause [minutes] | resume
sudo netauto off | on
```

Admin users can run `pick`, `setip` and `setdhcp` without `sudo` — the request
goes through the daemon queue.

---

## Troubleshooting

Run **`netauto doctor`** first. It prints the macOS version, the Wi-Fi device,
**each SSID detection method and whether it worked**, network Locations, config
validity, the rule verdict, service registration and the recent log — everything
needed to tell what's wrong. Paste that output into an [issue](../../issues).

### Nothing switches on macOS 15 (Sequoia) or later

Since macOS 15, **reading the Wi-Fi name requires Location Services**. Without the
name there's no rule to match, so the icon appears but nothing ever changes.

If every entry under `[SSID 감지]` in `netauto doctor` is `✗`, that's this. netauto
tries five paths in order:

| Method | Note |
|---|---|
| `networksetup -getairportnetwork` | fastest; may be gated on macOS 15+ |
| `ipconfig getsummary` | SSID field |
| `scutil` `SSID_STR` | already redacted on some 14.x systems |
| `scutil` `ProfileID` hex decode | the name survives here as hex |
| `wdutil info` | real value only as root (the daemon is root) |

The panel also shows a warning with an **Open Location Services settings** button.

---

## Building

No Xcode needed — Command Line Tools are enough.

```bash
./build-app.sh          # dist/NetautoBar.app (universal)
./build-installer.sh    # dist/netauto-<version>.pkg + .dmg
./setup.sh              # install straight from source, skipping packaging
```

`swiftc` compiles the SwiftUI app for arm64 and x86_64, `lipo` fuses them, and the
`.app` bundle is assembled by hand. `pkgbuild` + `productbuild` make the installer,
`hdiutil` wraps it in a disk image. The app is ad-hoc signed (`codesign -s -`); the
package is unsigned.

`bin/netauto` is the single source of truth for the version number — the build
scripts read it from there.

### Two macOS gotchas baked into the build

- **`pkgbuild` marks `.app` payloads relocatable by default.** The installer then
  hunts for an existing bundle with the same identifier and overwrites *that*
  instead of `/Applications` — so nothing appears where you expect.
  Fixed with `--component-plist` and `BundleIsRelocatable=false`.
- **`MenuBarExtra`'s `.menu` style converts SwiftUI into a real `NSMenu`**, which
  renders every `Text` item disabled-gray, breaks space-based alignment in a
  proportional font, and drops SF Symbols entirely. The panel uses `.window`
  instead. The menu bar label itself is an `NSStatusItem` button, not a SwiftUI
  view, so the icon and text are composed into a single template `NSImage`.

---

## Tests

```bash
./tests/test_netauto.sh            # 83 assertions — daemon logic
./tests/test_config_roundtrip.sh   # 17 assertions — Swift ↔ bash config round-trip
```

`networksetup`, `ipconfig` and `id` are all replaced with mocks, so the suite
**never touches real network settings** — safe on your machine and on CI.

Covered: rule lookup, idempotence, profile switching, all three IP modes, legacy
config inference, manual-override handling, pause/expiry/disable, the request
queue (priority, guaranteed deletion, partial-write skipping, unknown requests),
non-root delegation, every `status --json` field, malformed config files, and
SSIDs containing quotes, spaces and non-ASCII characters.

---

## Layout

```
bin/netauto                          daemon + CLI (bash, no dependencies)
bin/netauto-uninstall                uninstaller the app runs with admin rights
etc/netauto.json                     default config
launchd/dev.devpaulie.netauto.plist  daemon registration
app/NetautoBar/Core.swift            config I/O, CLI bridge, state model
app/NetautoBar/UI.swift              menu bar panel + settings window
installer/                           pkg scripts, wizard screens
tools/render-symbol.swift            SF Symbol → PNG (for the installer screens)
tools/build-html.py                  installer HTML from templates
```

The config lives at `/usr/local/etc/netauto/config.json` and is **shared by the
Swift app and the bash daemon**. bash reads JSON with `plutil`, so there are no
third-party dependencies anywhere in the project.

---

## Contributing

Issues and pull requests are welcome. Please run both test scripts before opening
a PR — CI runs them on every push. When adding behavior to the daemon, add an
assertion for it; the mocks make that cheap.

---

## License

[MIT](LICENSE) — © 2026 devpaulie
