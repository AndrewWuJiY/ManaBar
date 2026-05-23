# Handoff: cc-bar (macOS menu bar app for Codex + Claude Code quota)

## Overview

**cc-bar** is a native macOS 26 Tahoe menu bar utility that monitors the user's
quota and spend on **Codex** (OpenAI) and **Claude Code** (Anthropic). It lives
in the system menu bar, opens a popover with the latest usage at a glance,
optionally shows a floating HUD on the desktop, and ships a full Statistics
window with date range presets + custom range.

Core capabilities:

- Auto-detect locally signed-in Codex and Claude Code accounts; let the user
  toggle which to display.
- Show one or both services' 5-hour quota remaining (or weekly quota) in the
  menu bar as an icon + percentage.
- Click the menu bar icon to open a popover showing both services' remaining
  quota, reset time, tokens used, and spend (Codex first, then Claude Code).
- Optional always-on-top floating HUD with one or both services' 5-hour
  percentage on two lines.
- Statistics window with **today / this week / this month / last 7 days /
  last 30 days / all time / custom range** — token usage, spend, and per-service
  breakdown.
- Configurable background auto-refresh interval.

---

## About the Design Files

The files bundled here are **design references** created in HTML/React.
They are prototypes that show the intended look, behavior and component
inventory — they are **not production code to copy directly**.

The task is to **recreate these designs in a native macOS environment**.
Strongly recommended stack:

- **SwiftUI + AppKit hybrid** (Xcode project, macOS 14+ deployment target,
  built against the macOS 26 SDK so Liquid Glass materials and modern
  controls are available).
- `NSStatusItem` for the menu bar icon.
- `NSPopover` (or a custom `NSPanel`) for the dropdown.
- `NSPanel` with `.nonactivatingPanel` + `.canJoinAllSpaces` for the HUD.
- A normal `Window` (SwiftUI) for Statistics and Preferences.
- `SwiftData` or simple `UserDefaults` + a sqlite file for usage history.
- `Swift Charts` for the dashboard charts.

If the developer prefers Electron / Tauri / Rust, the same component layout
and tokens apply — but native is highly recommended for menu bar fidelity
and Liquid Glass.

---

## Fidelity

**High-fidelity.** All mockups are pixel-tuned: exact corner radii, type
scale, spacing, opacities, and the macOS 26 Tahoe "Liquid Glass" surface
treatment (translucent panels with a subtle specular highlight). Recreate
to spec; do not substitute generic Material/Bootstrap chrome.

---

## Design System

### Aesthetic — macOS 26 Tahoe / Liquid Glass

- **Material**: frosted translucent panels (`saturate(180%) blur(40px)`)
  with an inner 1pt specular highlight at the top edge.
  - SwiftUI: `.background(.regularMaterial)` plus
    `.overlay(LinearGradient(...))` for the highlight.
  - AppKit: `NSVisualEffectView` with `material: .menu` / `.popover` /
    `.hudWindow` and `blendingMode: .behindWindow`.
- **Corner radii** (continuous curvature, not circular):
  - Window: **12pt**
  - Popover: **18pt**
  - HUD: **14pt**
  - Cards / panels: **10–12pt**
  - Inset rows / pills: **6–8pt**
- **Shadows**:
  - Window: `0 24 60 rgba(0,0,0,0.22)` + `0 2 8 rgba(0,0,0,0.08)`
  - Popover: `0 14 38 rgba(0,0,0,0.22)`
  - HUD: `0 10 28 rgba(0,0,0,0.28)`

### Type

- **Font**: SF Pro Display (titles ≥ 17pt) and SF Pro Text (body),
  i.e. just `-apple-system` / `.systemFont` everywhere.
- **Numeric values** must use tabular figures
  (`.monospacedDigit()` in SwiftUI; `font-variant-numeric: tabular-nums`).
- Type scale used in the designs:
  | Role | Size | Weight | Use |
  |---|---|---|---|
  | KPI big number | 22–38pt | 600 (-0.5 tracking) | Stats hero, popover big-stat |
  | Section title | 13pt | 600 | Window title, panel title |
  | Body | 12.5pt | 400/500 | Most labels |
  | Caption | 11–11.5pt | 400 | Secondary text |
  | Mono small | 10pt | 400 | Timestamps, paths |

### Bilingual labels

The UI is **EN + 中文**. Pattern: English label primary, Chinese smaller
beneath or after a `·`. Examples:

- Section header: `Menu Bar · 菜单栏`
- Inline label: `Codex` with `OpenAI · GPT-5` as caption
- Body copy: 2 lines — English first, Chinese second

Implementation: use NSLocalizedString with both copies in the strings file,
or compose `Text("Menu Bar") + Text(" · ") + Text("菜单栏").foregroundStyle(.secondary)`.

### Colors

System semantic colors throughout — do **not** hardcode unless noted.

```
Accent:      systemBlue       (#007AFF light / #0A84FF dark)
Green/OK:    systemGreen
Orange/warn: systemOrange
Red/error:   systemRed
Text:        .labelColor / .secondaryLabelColor / .tertiaryLabelColor
Fills:       .quaternarySystemFill, .secondarySystemFill
Separator:   .separator
```

**Product accent colors** (hardcoded — they identify the two services):

| Service | Light | Dark |
|---|---|---|
| Codex | `#6C6C70` (graphite) | `#98989D` |
| Claude Code | `#D97757` (peach) | `#E68A6E` |

Always render the Codex block first, Claude Code second. Per-service swatches
appear as the dot/pill/ring tint everywhere those services are shown.

### State color rules

- Quota ≥ 50% remaining: service color (graphite / peach)
- Quota 20–50% remaining: same color
- Quota < 20% remaining (low warning): `systemOrange` (`#FF9F0A`)
- Quota = 0 / over: `systemRed`

---

## Screens / Views

### 1. Menu bar icon

Appears in the macOS menu bar status area.

**Default variant** (recommended): **Icon + Percentage**

- Layout: SF Symbols-style "gauge with sparkle" glyph 14pt + " 62%" tabular.
  Combined value = `min(codex5h, claude5h)` (i.e. the more critical one), or
  per the preference, an average or the user's pinned service.
- Hover: subtle white-fill background `rgba(255,255,255,0.10)` (dark) /
  `rgba(0,0,0,0.06)` (light), 5pt corner radius, 22pt tall.
- Click: opens popover anchored under the icon.

**Other variants the user can choose** (all are designed and visible in
`Canvas.html` → "Menu bar icon" section):

1. Icon only
2. Icon + % *(default)*
3. Two pills — `C 42%` (graphite) + `CC 78%` (peach), shown side by side
4. Mini ring + %
5. Dual mini bars (two stacked rows, one per service)
6. Text only — `C 42% · L 78%`
7. State color — turns orange when below 20% remaining
8. 5h ↔ Weekly mode chip — adds a small `5H` / `WK` chip after the number

Implementation: `NSStatusItem.button.image` plus
`button.title` for the percentage. For multi-segment variants (pills, dual
bars), draw a custom `NSImage` of size ~22pt × variable width, or use a
SwiftUI `MenuBarExtra(.window)` with a custom view.

### 2. Popover panel

Opens on menu bar click. **Recommended layout: A · Vertical list.**

**Size**: 340pt wide × auto height (~360pt with both services). 18pt corner
radius. Liquid glass material. Subtle 7pt-tall arrow notch at top right
pointing up at the status bar.

**Structure** (top to bottom):

1. **Header row** — 14pt top padding, 16pt horizontal
   - Title `Usage` (13pt, weight 600) + subtitle `用量 · refreshed 32s ago`
     (11pt, secondary)
   - Right side: refresh icon button (14pt circular arrow), kebab/menu icon button
   - Bottom border: `0.5pt separator`

2. **Codex block** — 14pt padding
   - Service header row:
     - 22pt rounded-square (`6pt` radius) tile with the Codex glyph on
       graphite fill
     - "Codex" 13pt 600 + "OpenAI · Plus" 10.5pt secondary
     - Right side: `resets in 2h 18m` 11pt tabular secondary
   - Body row (12pt margin top):
     - 56pt **ring** (5.5pt stroke) showing 5-hour percentage, with the
       percent + `5H` label centered inside
     - Right pane:
       - Weekly bar — "Weekly · 周额度" left, "31%" right, then a 5pt-tall
         bar with `border-radius` 2.5
       - Two stats below (9pt top): tokens used (e.g. `184k / 440k`, label
         `tokens used`), spend (`$12.40`, label `this week`)

3. **Separator** — 0.5pt, inset 16pt

4. **Claude Code block** — identical structure, peach color

5. **Footer** — 10pt 12pt padding, top border 0.5pt
   - Left: `Open Statistics · 查看统计` menu item with hamburger icon
   - Right: refresh + spark icon buttons

**Interactions**:

- Click outside the popover (anywhere on screen) → close.
- Click the refresh icon → force refresh, button rotates 360° during fetch.
- Click "Open Statistics" → open Statistics window, close popover.
- Click a service block → open Statistics window scoped to that service.

### 3. Floating HUD

Always-on-top draggable widget. **Default variant: Two-row pill.**

- 14pt corner radius, Liquid Glass material with HUD-window appearance
  (slightly darker translucency than popover: 0.62 alpha in dark mode).
- 10pt 14pt padding, ~168pt min width.
- Two rows, 7pt gap, each row:
  - 44pt-wide uppercase label (Codex / Claude, 10.5pt, weight 600, secondary)
  - Flex bar (4pt tall, 2pt radius)
  - Percentage right-aligned (13pt, weight 600, tabular, in the service
    color, min-width 34pt)
- Draggable anywhere on screen by mouse drag. Position persists.
- "Always on top" — never hides behind app windows. Visible on all spaces.
- The user can toggle in Preferences:
  - Show / hide HUD
  - Which services (Codex, Claude, both)
  - Variant (8 designed variants in `Canvas.html` → "Floating HUD")
  - Position (top-right default; can drag; remember last position)
  - Idle opacity (slider 0.3–1.0)

Implementation: `NSPanel` with style mask
`[.nonactivatingPanel, .titled, .fullSizeContentView]`, level
`.statusBar - 1`, `collectionBehavior` including
`.canJoinAllSpaces, .stationary, .fullScreenAuxiliary`. Background = clear,
content = `NSHostingView(rootView: HUDView())`.

### 4. Statistics window

Standard macOS window. **Layout: Sidebar + main canvas.**

**Toolbar**:

- Traffic lights (handled by window chrome)
- Title `Statistics · 用量统计`
- Right side: **segmented control** with the 7 range presets
  (`Today / Week / Month / 7d / 30d / All / Custom`). Currently-active
  segment fills with `.quaternarySystemFill` and weight 600.

**Sidebar** (200pt wide, `.sidebar` material):

Three groups, each with a header in uppercase `secondary` text:

- **Range · 时间范围** — list of the same 7 presets as sidebar rows
  (alternative to the toolbar). Active row uses accent background +
  white text.
- **Service · 服务** — All / Codex / Claude Code, each with a colored dot.
- **View · 视图** — Overview (default) / Timeline / Breakdown.

Each sidebar row: 12pt font, 5pt 8pt padding, 6pt radius, with icon left
and bilingual label.

**Main canvas — Overview** (recommended default):

1. **KPI row** — 4 cards, equal width, 12pt gap.
   Each card: 10pt radius, white/.regularMaterial bg, 11pt 14pt padding.
   - Label (11pt secondary) + Chinese caption (10pt tertiary)
   - Value (22pt, weight 600, -0.5 tracking, tabular)
   - Delta chip: `↑ 12.4%` in `systemGreen`, or `↓` in `systemRed`
   - The two service cards have a 6pt color dot prefix
2. **Daily usage panel** — 12pt radius card, 16pt padding.
   - Title `Daily usage · 每日用量` + chart legend right (Codex / Claude)
   - 160pt-tall **stacked bar chart** (one bar per day, Codex bottom
     stacked under Claude top). Bars 2pt radius, 3pt gap between days,
     `min-height: 1pt`.
   - Date axis below: `Jul 16 / Jul 23 / Jul 30 / Aug 06 / Today`.
3. **Two-column row** below:
   - **By service** panel — list rows, one per service, with color dot,
     name, Chinese caption, value (13pt 600 right-aligned), bar, and
     `Xk tokens` + `Y% of spend` row.
   - **Current limits** panel — 4 small rings (5-hour + Weekly per
     service), each with name + `resets in …` caption.

**Main canvas — Timeline** (alternative view):

- **Tokens hourly** panel — area-line chart, 220pt tall. Two stacked
  smooth lines (gradient fill 0.4 → 0 opacity) — Codex graphite,
  Claude peach. Subtle horizontal gridlines at 20/40/60/80%.
- **Hourly pattern** heatmap — 7 days × 24 hours, each cell 14pt tall,
  intensity = Claude usage opacity. Weekends muted.
- **Spend split** donut — 110pt SVG donut, `$1,284` total in center,
  legend with both services and percentages.

**Custom range**: pops a date range picker (two `DatePicker`s and a
"Cancel / Apply" footer) inline below the segmented control.

### 5. Preferences

Single-pane window, 680pt × ~780pt. Grouped insets, macOS-26-style.

Sections (top to bottom), each a 10pt-radius card with rows:

- **Accounts · 账号** — one row per detected account: 28pt icon tile,
  service name + Chinese caption + email + `Connected · 已连接` green
  dot, `NSSwitch` toggle right.
- **Menu Bar · 菜单栏** — Show in menu bar toggle, Display dropdown
  (8 variants), Show service checkboxes (Codex, Claude), Quota period
  radios (5-hour / Weekly / Both cycle).
- **Floating HUD · 桌面悬浮窗** — Show toggle, Service checkboxes, Style
  dropdown, Position dropdown, Opacity slider.
- **Refresh · 刷新** — Auto refresh toggle, Interval dropdown
  (15s / 30s / 1m / 2m / 5m / 10m / 15m), last refresh timestamp.
- **General · 通用** — Launch at login toggle, Show in Dock toggle,
  Language dropdown.

All rows: 10pt 14pt padding, 0.5pt top border, label left + control right,
with optional secondary description line below the label.

### 6. Onboarding

First-run only. Window 620pt × 520pt.

**Step 1 — Welcome**
- Centered 96pt app icon (rounded square, gradient graphite→peach).
- Heading "Welcome to cc-bar" 22pt 700 + "欢迎使用 cc-bar" 14pt secondary.
- Two-line description (EN + 中文).
- `Get started · 开始` primary button, `What's new in 1.0 · 新功能` link.
- 4-dot progress indicator at bottom.

**Step 2 — Detect accounts**
- Heading "We found these accounts" + Chinese subtitle.
- List of detected accounts (see "Account detection" below). Each row:
  checkbox, 34pt service tile, name + Chinese caption, email, source path
  in mono.
- Info card (`systemBlue` tint): "Read-only access" reassurance.
- Footer: `Back` (ghost) · `Add manually` · `Continue` (primary).

**Steps 3–4** (not designed yet — implement similarly):
- Step 3: Menu bar + HUD preference (preview the user's selection live).
- Step 4: Ready to go — open Statistics.

---

## Interactions & Behavior

### Menu bar click

- Single click on `NSStatusItem` button → toggle popover.
- Click outside popover → close.
- Right-click (or option-click) → show native menu with:
  `Open Statistics… ⌘1`, `Preferences… ⌘,`, `Refresh now ⌘R`,
  separator, `About cc-bar`, `Quit cc-bar ⌘Q`.

### Refresh

- Polls in the background at the user's chosen interval (default 2 min).
- Manual: ⌘R from menu, or refresh icon in popover.
- During fetch: refresh icon spins (360° in 700ms).
- On failure: show `systemRed` dot next to "live" indicator, tooltip with
  error message. Keep last-known values visible (do not zero out).

### Window transitions

- Popover: 180ms cubic-bezier(0.2, 0.9, 0.3, 1.15) — slight overshoot;
  `transform: scale(0.96) translateY(-6px)` → identity.
- Window open: 220ms ease-out, scale 0.97 → 1.

### Drag

- HUD: drag from anywhere on its surface (cursor: grab). Snap to nearest
  screen edge if within 20pt.
- Stats and Preferences: standard window drag from title bar.

### Keyboard

- `⌘,` — open Preferences (standard)
- `⌘W` — close active window
- `⌘1` — open Statistics
- `⌘R` — refresh now (in popover or any window)
- `Esc` — close popover

### Status indicators

- Green dot + "live" — refreshed within interval window
- Orange dot + "stale" — last refresh > 2× interval ago
- Red dot + "offline" — last 3 fetches failed

---

## Data Model

### Account

```swift
struct Account: Identifiable, Codable {
    let id: UUID
    var service: Service          // .codex | .claudeCode
    var displayName: String       // "Codex (Work)"
    var email: String?
    var plan: String?             // "Plus", "Max 20×"
    var credentialPath: String    // ~/.codex/auth.json
    var enabled: Bool             // user toggle in Prefs
}
```

### Quota snapshot (per account)

```swift
struct QuotaSnapshot: Codable {
    let accountId: UUID
    let fetchedAt: Date
    var fiveHour: WindowQuota     // tokens or requests used / cap
    var weekly: WindowQuota
    var resetAt5h: Date
    var resetAtWeek: Date
}
struct WindowQuota: Codable {
    var used: Int                 // tokens (or requests, depending on service)
    var cap: Int
    var spendUSD: Double          // optional
    var percentUsed: Double { Double(used) / Double(cap) }
}
```

### Usage event (for the Stats window history)

```swift
struct UsageEvent: Codable {
    let accountId: UUID
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
}
```

Persist `UsageEvent` to SwiftData / SQLite. The Statistics window queries
this store by date range and groups by day / hour / service.

---

## Account Detection

On first launch and on a button in Preferences, scan these locations:

### Codex (OpenAI's `codex` CLI / Plus subscription)

- `~/.codex/auth.json` — local auth tokens
- `~/.codex/config.toml` — user identity hints

### Claude Code (Anthropic's `claude` CLI)

- `~/.claude/credentials.json`
- `~/.claude/.credentials.json` (alternative)
- macOS Keychain: service `claude-code`, account = email

For each found account, read the email/plan if available. Show them in the
onboarding screen with the source path so the user knows which file
matched. **Never** copy or transmit credentials — only display the email
and use the tokens to call the respective official quota endpoints.

### Quota endpoints

Use whichever official endpoint each service exposes for usage / quota
queries. **The developer should look these up themselves and add a
single `QuotaProvider` protocol per service:**

```swift
protocol QuotaProvider {
    func fetchSnapshot(for account: Account) async throws -> QuotaSnapshot
    func recentUsage(for account: Account, in range: DateInterval) async throws -> [UsageEvent]
}
```

If an official endpoint is unavailable, fall back to local CLI log parsing.

---

## Design Tokens

### Radii

```
xs:    6
sm:    8
md:   12
lg:   16
xl:   22
2xl:  28
popover: 18
window:  12
hud:     14
```

### Spacing

Standard 4pt scale: `2 4 6 8 10 12 14 16 20 24 28 32`.

### Type scale

```
Display (KPI):  22–38pt / weight 600 / -0.5 tracking / tabular
Title:          17pt / 700 / -0.4
Headline:       13pt / 600 / -0.1
Body:           12.5pt / 400
Caption:        11pt / 400 / secondary
Mono small:     10pt / 400 / SF Mono
Eyebrow:        10–11pt / 600 / 0.4 tracking / uppercase
```

### Shadows

```
window:  0 24 60 rgba(0,0,0,0.22), 0 2 8 rgba(0,0,0,0.08), inset 0 0 0 0.5 rgba(0,0,0,0.18)
popover: 0 14 38 rgba(0,0,0,0.22), 0 1 4 rgba(0,0,0,0.10)
hud:     0 10 28 rgba(0,0,0,0.28), inset 0 0 0 0.5 rgba(255,255,255,0.10)
```

### Animation

```
Popover open:   180ms cubic-bezier(0.2, 0.9, 0.3, 1.15)
Window open:    220ms cubic-bezier(0.2, 0.9, 0.3, 1.1)
Hover:          100–120ms ease-out
Toggle thumb:   150ms ease-out
Refresh spin:   700ms ease-in-out, 1 turn
```

---

## Assets

- App icon: gradient graphite → peach rounded square with a gauge-sparkle
  glyph. Recreate as a proper macOS `.icns` (need 16/32/64/128/256/512/1024
  @1x and @2x). Reference: see logo in `index.html` and `Onboarding · Welcome`.
- SF Symbols only for icon needs (`gauge.medium`, `arrow.clockwise`,
  `chart.bar.xaxis`, `gear`, `xmark.circle.fill`, etc.).

No third-party imagery is required.

---

## Files in this Handoff

| File | Purpose |
|---|---|
| `index.html` | Entry — links to canvas + prototype |
| `Canvas.html` | All design variations side-by-side (8 menu bar / 4 popovers / 8 HUDs / 2 stats / prefs / onboarding) |
| `Prototype.html` | Interactive prototype of the recommended combination |
| `styles.css` | Design tokens used by all HTML |
| `mac-frames.jsx` | Shared chrome (menu bar, window, popover, HUD wrapper, mini glyphs) |
| `tweaks-panel.jsx` | Variant-switching panel (prototype only) |
| `design-canvas.jsx` | Canvas pan/zoom (canvas only) |
| `artboards/menubar.jsx` | All 8 menu bar variants |
| `artboards/popover.jsx` | All 4 popover variants |
| `artboards/hud.jsx` | All 8 HUD variants |
| `artboards/stats.jsx` | Dashboard + Timeline stats views |
| `artboards/prefs.jsx` | Preferences + Onboarding |
| `prototype-app.jsx` | Interactive prototype shell |

Open the HTML files in any modern browser (Safari recommended for the
truest Liquid Glass preview). They are self-contained — no build step.

---

## Implementation Checklist

- [ ] Xcode project: macOS 14+ target, SwiftUI app lifecycle, Swift 5.10+,
      compiled against macOS 26 SDK.
- [ ] `MenuBarExtra` or `NSStatusItem` + `NSPopover` setup.
- [ ] `NSPanel`-based HUD with always-on-top + space-joining.
- [ ] `QuotaProvider` per service + auto-refresh timer.
- [ ] Account detection on first launch + manual rescan in Preferences.
- [ ] Usage event store (SwiftData) + Swift Charts dashboard.
- [ ] Settings (Preferences) using SwiftUI `Settings` scene.
- [ ] Onboarding sheet on first run.
- [ ] Bilingual strings file (en, zh-Hans).
- [ ] Light + dark appearance verified across all surfaces.
- [ ] Sandbox + Hardened Runtime entitlements; user-selected file access
      for reading the credential files (or use Security-Scoped Bookmarks).
- [ ] LaunchAtLogin (use `SMAppService.mainApp`).
- [ ] App icon `.icns`.

---

## Open Decisions for the Developer

Things deliberately left to implementation:

1. **Which exact quota endpoint to call** for each service — verify against
   current API docs.
2. **Whether spend is shown** for Codex Plus users (the endpoint may not
   return it for subscription plans). If unavailable, hide the spend
   value rather than show $0.00.
3. **Custom range picker UX** — designed as inline date pickers below the
   segmented control; could alternatively be a sheet.
4. **HUD background "stained glass" tint** when the wallpaper is very
   bright/dark — designed as a single material; could add an inner
   contrast-adapting tint layer.
5. **Multi-account UX** — the design assumes 1 account per service;
   if the user has Codex Personal + Codex Work, decide whether to
   stack their bars or let the user pick one as "primary".

When in doubt, open `Canvas.html` for the visual answer.
