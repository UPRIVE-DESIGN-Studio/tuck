# Menu Bar Manager — Product & Technical Spec

> Working title: **TBD** (see Open Questions). In-house macOS app, built for the adventure and for our own daily use.
> Target: macOS 26 Tahoe first, macOS 27 when it ships. Apple Silicon MacBooks with a notch are the primary hardware.
> Status: draft v0.1 — 2026-10-08

---

## 1. Why

macOS gives the menu bar a fixed strip of space. On a notched MacBook that strip is split in two, and when the right side runs out of room **macOS silently drops status items** — no overflow menu, no warning. The same Mac with an external display shows everything, because that menu bar is wider and has no notch.

Existing tools:

| App | Model | Notes |
|---|---|---|
| Bartender 6 / 7 / Pro | Paid, one-time or yearly | Most complete. Reference for feature scope. |
| Ice | Free, open source (GPL) | Good feature set, had breakage on Tahoe. |
| Thaw | Free, open source fork of Ice | Tahoe-focused fork. |
| Hidden Bar | Free, open source | Divider only; unaware of the notch; unmaintained. |
| Dozer, Vanilla | Free / freemium | Divider only. |

**Clean-room rule:** we build from public macOS APIs and our own observation of behavior. We do not copy code, assets, names or UI text from Bartender. If we read Ice/Thaw source for reference, remember it is GPL — anything copied makes our app GPL too. Prefer reading for understanding, then writing our own.

## 2. Goals / Non-goals

**Goals**
- Never lose a menu bar item to the notch again.
- Different layouts for "laptop only" vs "external display connected", switched automatically.
- Fast: zero visible lag when revealing items; idle CPU ≈ 0 %.
- Small, native, Swift + AppKit/SwiftUI. No Electron.
- Learn how macOS window server, accessibility and event APIs actually work.

**Non-goals (for now)**
- Mac App Store distribution (sandbox forbids what we need — see §6).
- Replacing the system menu bar wholesale (SketchyBar territory).
- Dynamic Island / "Top Shelf" style widgets — parked in §5 Later.
- Intel Macs, macOS < 26.

## 3. Glossary

- **Item** — one status item (NSStatusItem) in the right side of the menu bar, owned by some app or by the system (Control Center, Clock, Wi-Fi…).
- **Section** — a group of items with a visibility rule: `Visible`, `Hidden`, `Always Hidden`.
- **Separator** — our own invisible status item that marks a section boundary.
- **Overflow** — items macOS has dropped because they don't fit (usually behind the notch).
- **Second Bar** — our floating panel under the menu bar that shows hidden/overflow items.
- **Profile** — a saved layout (which item lives in which section, order), bound to conditions.

## 4. Features

Priority: **P0** = MVP, **P1** = v1.0, **P2** = after v1.

### 4.1 Core: sections & hiding — P0
- Three sections: **Visible**, **Hidden** (revealed on demand), **Always Hidden** (only in Second Bar / search).
- Implemented with our own separator status items. Collapsing a section = expanding the separator's length so the items left of it are pushed off-screen; expanding = shrink it back.
- A single **toggle icon** in the menu bar: click to reveal/hide the Hidden section.
- Auto-rehide after N seconds (configurable, default 10 s) or when focus leaves the menu bar.
- Option: show hidden items **inline** (menu bar expands) or **in the Second Bar** (default on notched displays, because inline expansion is what pushes items behind the notch in the first place).

### 4.2 Notch & overflow awareness — P0 (the reason this project exists)
- Detect notch per screen: `NSScreen.safeAreaInsets.top > 0`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` give the usable rects.
- Compute available width on the right side: `auxiliaryTopRightArea.width` minus the system items (Clock, Control Center).
- Detect items that are **present but not on screen** (window exists, frame off-screen or overlapping the notch rect) → treat them as Overflow.
- Overflow items appear in the Second Bar automatically, so nothing is ever unreachable.
- Optional badge on the toggle icon: "3 items overflowed".

### 4.3 Second Bar — P0
- Borderless, non-activating `NSPanel` anchored under the menu bar, right-aligned under the toggle icon (or centered — setting).
- Shows an image of each hidden/overflow item (captured from the real item, see §6.3), in the user's order.
- **Click-through:** clicking an image opens the real item's menu. Mechanism: temporarily bring the real item on screen (shrink the separator), post a synthetic click at its real frame, re-hide once its menu closes.
- Right-click / ⌥-click forwarded as such.
- Respects light/dark and the menu bar's translucency; matches system menu bar height on each display.
- Fallback when Screen Recording is denied: show the owning app's icon + name instead of the captured image.

### 4.4 Arranging items — P0 (basic), P1 (polished)
- **P0:** Settings window lists every item (icon, owning app, current section). Drag between sections; we move the real item by simulating a ⌘-drag in the menu bar.
- **P1:** Live preview of the layout, undo, "reset to macOS order".
- Remember layout per item identity (bundle ID + item title/index), survive app relaunches and reboots.
- Detect new items (an app installed or launched) → put in a configurable default section and notify once.

### 4.5 Display-aware profiles — P1
- A profile = full layout. Built-in conditions: **built-in display only**, **external display connected**, **specific display** (by name/serial).
- Auto-switch on `NSApplication.didChangeScreenParametersNotification`.
- Typical setup: on the laptop, keep 6 important items visible and everything else in the Second Bar; on an external display, show everything.

### 4.6 Triggers (show item when…) — P1 / P2
Temporarily move an item into the Visible section while a condition holds:
- **P1** Battery below X % / on battery power (IOKit power sources).
- **P1** Item changed appearance (e.g. Dropbox syncing, VPN disconnected). Detect by diffing periodic captures of that one item; diff interval adaptive (2–10 s), only for items with this trigger.
- **P1** Specific app is frontmost / running.
- **P2** Wi-Fi network name (CoreWLAN — needs Location permission on modern macOS).
- **P2** Time of day / day of week.
- **P2** Focus mode active (public API only says "focused yes/no"; per-mode detection would need hacks — decide later).
- **P2** Shell-script trigger: run a script every N seconds, show item while exit code = 0. Power-user escape hatch.

### 4.7 Search & keyboard — P1
- Global hotkey opens a Spotlight-style search over all items (by app name, item title).
- Enter = click the item, ⌥Enter = alternate click.
- Hotkeys: toggle Hidden, toggle Second Bar, per-item "open this item's menu".
- Keyboard navigation inside the Second Bar (arrows + Enter).

### 4.8 Appearance — P1 / P2
- **P1** Item spacing control (system `NSStatusItemSpacing` / `NSStatusItemSelectionPadding`), with a one-click "apply + relaunch affected apps".
- **P1** Custom toggle icon (SF Symbols picker), hide toggle icon entirely (hotkey-only mode).
- **P2** Menu bar tint / border / rounded "pill" background behind item groups.
- **P2** Hover to reveal: move pointer over empty menu bar space → show Hidden section.
- **P2** Scroll on menu bar to show/hide.

### 4.9 Housekeeping — P0 / P1
- **P0** Launch at login (`SMAppService.mainApp`).
- **P0** Onboarding that explains each permission *before* asking for it, and keeps working (degraded) if one is denied.
- **P1** Auto-update via Sparkle 2 (EdDSA-signed appcast).
- **P1** Export / import settings as JSON.
- **P1** Local-only diagnostics log, "copy debug info" button. **No telemetry, no network calls** besides the update check.

### 4.10 Later / ideas — P2+
- Notch "shelf": use the dead pixels around the notch for now-playing, timers, AirDrop drop-target (Bartender Pro's "Top Shelf" / NotchNook territory).
- Per-Space or per-Focus profiles.
- Widgets in the Second Bar (clock in another timezone, CPU, server status from our own infra).
- Stream Deck plugin: buttons to toggle sections / switch profiles (we already have Stream Deck tooling).
- CLI / URL scheme: `menubar://toggle`, `menubar://profile/laptop` for Raycast and Shortcuts.

## 5. User stories (acceptance tests)

1. On the MacBook alone, with 25 status items running, **every item is reachable within 2 clicks or 1 hotkey + typing**.
2. Plugging in an external display switches to the "Desk" profile within 1 s, without flicker; unplugging switches back.
3. Clicking an item in the Second Bar opens its real menu at a sensible position within 150 ms.
4. Quitting and relaunching an app keeps its item in the section I put it in.
5. Rebooting keeps the whole layout.
6. Denying Screen Recording still leaves a usable app (icons instead of captures).
7. Idle CPU < 0.5 % averaged over 10 minutes with no triggers; memory < 60 MB.

## 6. Technical design

### 6.1 Stack
- Swift 6, AppKit for the menu bar / panels / event plumbing, SwiftUI for Settings.
- Xcode 26, minimum deployment macOS 26.
- Agent app (`LSUIElement = YES`) — no Dock icon.
- Dependencies (keep it small): Sparkle 2 (updates), KeyboardShortcuts (sindresorhus, MIT) for hotkeys. Everything else first-party.

### 6.2 Discovering items
- Enumerate menu bar item windows with `CGWindowListCopyWindowInfo(.optionOnScreenOnly / .optionAll)`, filter by window layer = status item level (`kCGStatusWindowLevel`) and y-position on each screen's menu bar.
- Each entry gives: window ID, owner PID, owner name, bounds. Window **titles require Screen Recording** permission.
- Map PID → app bundle ID via `NSRunningApplication`.
- **Tahoe risk:** on macOS 26 some or all status item windows may be owned/hosted by a system process instead of the source app, which breaks PID-based identification. First spike (M0) must confirm what we see on 26.x and find a stable identity key (window title, AX attributes, or private CGS window properties).
- Accessibility tree (`AXUIElementCreateApplication(pid)` → `AXExtrasMenuBar`) as a second source of truth: gives item titles/descriptions and lets us `AXPress` an item directly — possibly a cleaner click-through than synthetic mouse events. Evaluate in M0.
- Refresh on: app launch/quit notifications (`NSWorkspace`), screen changes, and a slow timer (5 s) as safety net. Never poll fast.

### 6.3 Capturing item images
- `CGWindowListCreateImage` is deprecated → use **ScreenCaptureKit** (`SCScreenshotManager.captureImage` with an `SCContentFilter` for the single window).
- Requires Screen Recording permission. Note: macOS periodically re-prompts users to confirm Screen Recording for apps — design onboarding around that.
- Cache captures; re-capture only when the Second Bar is about to open, or for items with a "changed appearance" trigger.

### 6.4 Hiding & moving
- Hiding: our separator `NSStatusItem` with `length` toggled between ~0 and a very large value (e.g. 10 000 pt) pushes everything to its left off-screen. Order: `[Always Hidden items] [sep2] [Hidden items] [sep1] [Visible items] [toggle]`.
- Separator positions persist via `autosaveName` (macOS stores `NSStatusItem Preferred Position <name>`).
- Moving another app's item: synthesize a ⌘-drag with `CGEvent` (mouseDown with `.maskCommand` at source → mouseDragged → mouseUp at target), posted at `.cghidEventTap`. Requires **Accessibility** permission. Must hide the cursor / restore its position so the user doesn't see it jump (Bartender 7 advertises "never moves the pointer" — worth matching).
- Moves must be serialized, verified (re-enumerate after each move), and retried; menu bar animations make this timing-sensitive.

### 6.5 Permissions
| Permission | Why | If denied |
|---|---|---|
| Accessibility | Post synthetic events (move items, click-through), AX tree | Can hide/show sections, can't rearrange or click-through from Second Bar |
| Screen Recording | Item titles + captured images | Second Bar shows app icons; no "changed appearance" trigger |
| Location (optional) | Wi-Fi SSID trigger | That trigger disabled |

### 6.6 Distribution
- **Not sandboxed**, so no Mac App Store. Developer ID signing + notarization (`notarytool`), hardened runtime.
- Ship as a DMG + Sparkle appcast on our own domain. Possibly a Homebrew cask later.

### 6.7 Module layout (proposal)
```
App/            entry point, LSUIElement agent, launch at login
MenuBarModel/   item discovery, identity, layout state, profiles
Mover/          CGEvent-based item moving, verification, retries
Capture/        ScreenCaptureKit wrapper, image cache, diffing
SecondBar/      NSPanel, item views, click-through
Triggers/       battery, app, appearance-change, wifi, time, script
Search/         search panel, hotkeys
Settings/       SwiftUI settings, onboarding, permissions
Persistence/    Codable JSON in Application Support, import/export
```

## 7. Milestones

| # | Name | Outcome |
|---|---|---|
| M0 | **Spike** (1–2 weekends) | CLI/debug window that lists every menu bar item on Tahoe with owner, bounds, on-screen/overflow flag; capture one item's image; move one item via ⌘-drag; click one item via AX. Answers all §6.2 risks. |
| M1 | **MVP** | Sections + toggle + Second Bar + overflow detection + basic arranging + launch at login. Daily-drivable on our own MacBook. |
| M2 | **v1.0** | Display profiles, search & hotkeys, battery/app/appearance triggers, spacing control, Sparkle, onboarding polish. |
| M3 | **Later** | Remaining P2 triggers, appearance customisation, URL scheme, Stream Deck, notch shelf. |

## 8. Risks

- **Private / undocumented behavior.** The menu bar has no public API for managing other apps' items; every macOS major release can break us (it broke Ice and older Bartenders on Tahoe). Keep all OS-specific code behind one `MenuBarBackend` protocol so a macOS 27 backend can be swapped in.
- **Synthetic-event fragility.** Timing, animations, Stage Manager, full-screen apps, multiple displays with different menu bars.
- **Permission friction.** Two scary permissions; macOS re-prompts for Screen Recording. Onboarding has to be honest and clear.
- **Performance.** Screen capture and window enumeration can get expensive; strict "no polling unless needed" rule.

## 9. Open questions

1. Name. Avoid anything bar/bartending-themed that collides with Bartender's trademark. Candidates to check: _Notchly_, _Overflow_, _Tuck_, _Stash_.
2. Purely internal tool, or eventually public (free / open source / paid)? Affects licensing choices (MIT vs GPL reference code) and polish level.
3. Swift Concurrency strictness: go full Swift 6 strict mode from day one?
4. Do we want a Second Bar that floats under the notch (centered), or always under the toggle icon?
5. Ship macOS 27 support from start (beta SDK) or after release?
