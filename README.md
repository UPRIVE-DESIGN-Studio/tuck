# Tuck

A small dot in the macOS menu bar for the items you don't want to see and every item the notch is hiding, with a drawer that grows out of the notch.

Built from [spec.md](spec.md). macOS 26, Apple Silicon, no Dock icon, no network.

## What it does

- **The drawer.** Rest the pointer behind the notch, click the dot, or press **⌃⌥M**: the tucked items drop down (out of the notch on a notched display, as a glass bar under the dot elsewhere). Click an item to open it in place, right-click or ⌥-click for its other menus, drag icons to rearrange the real menu bar. With the hotkey, ← → and Return work, and typing searches every menu bar item.
- **Automatic tucking.** Every item has a mode, **Show**, **Auto** or **Hide**, and a rank (drag to sort in Settings). When the notch would cover something, the least important Auto item is tucked; when there is room again, the most important one comes back. New items start as Auto. The dot shows how many items are out of sight.
- **Displays without a notch.** Hidden items show in the menu bar there (can be switched off).
- **Shelf.** Under the items: what Spotify or Music is playing with play and skip, a 5/15/25 minute timer, and file drop targets (AirDrop, or Keep to park files until you drag them out). Dragging files onto the notch opens the drawer.
- **Triggers.** An item can come into the menu bar while an app is in front, on battery, below a battery level, on a Wi‑Fi network or in a Focus, or make the drawer peek when its icon changes.
- **Self-check.** After a macOS update Tuck checks that finding, hiding and moving items still work, and shows "!" on the dot if not. Settings › General › Health runs it on demand.
- **Settings file.** Export and import modes, ranks, triggers, preferences and the hotkey as JSON.

## How it works

Tuck has two status items of its own: the dot, and an invisible separator. Items left of the separator are hidden by stretching the separator until they are pushed off-screen. Items are moved with the same ⌘-drag you would do by hand, sent as synthetic events addressed to the item's window, with the pointer hidden. macOS remembers item positions itself, so the layout survives restarts.

Things learned on macOS 26 that the code depends on:

- Every menu bar item window belongs to Control Center, so owners are found by matching window frames against each app's Accessibility menu bar extras. Items are keyed across relaunches by bundle ID plus Accessibility identifier.
- A menu opens wherever its item is, so hidden items are moved out before they are opened, and back afterwards.
- Where a drop lands depends on the direction of travel; items leaving the hidden section step onto the section boundary first. Drops are never made against the dot, since events reaching it make Tuck drag its own dot.
- The collapsed separator's frame is reported late, so moves into and out of the hidden section are confirmed by the item's new position instead.

## Permissions

| Permission | Needed for |
|---|---|
| Accessibility | Required: finding, moving and opening items |
| Screen Recording | Optional: real item icons in the drawer, "icon changes" triggers |
| Automation (Spotify, Music) | Optional: now playing on the shelf; asked on first use |
| Location | Optional: Wi‑Fi triggers (macOS only reveals the network name to apps with Location access) |

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test      # unit tests
make run       # build and launch the Debug app
make install   # Release build into /Applications (needed for Open at Login)
swift scripts/make-icon.swift   # re-render the app icon
```

`project.yml` is the source of truth; the `.xcodeproj` is generated. Signing uses an Apple Development certificate so permissions survive rebuilds.

## Debugging

Tuck logs to `~/Library/Logs/Tuck.log`. It also takes `tuck://` URLs; window IDs are the ones `dump` logs:

| URL | Does |
|---|---|
| `tuck://dump`, `tuck://axdump`, `tuck://ax/<window>` | Log every item / every app's raw Accessibility items / one item's attributes |
| `tuck://bar`, `tuck://notch`, `tuck://peek`, `tuck://settings` | Open the bar / the notch drawer / a short peek / Settings |
| `tuck://snapshot` | Render the open bar to `~/Library/Logs/Tuck-bar.png` |
| `tuck://hide/<window>`, `tuck://show/<window>` | Move an item into or out of Tuck |
| `tuck://mode/<window>/<show\|auto\|hide>` | Set an item's mode |
| `tuck://trigger/<window>/<none\|battery\|below-N\|focus\|appearance\|app-BUNDLEID>` | Set an item's trigger |
| `tuck://open/<window>?at=notch&click=secondary` | Open an item as from the drawer (`click=alternate` for ⌥) |
| `tuck://move/<window>?leftOf=<window>` | Move an item next to another (`rightOf=` too) |
| `tuck://health`, `tuck://state`, `tuck://resetdot` | Self-check / queue state / put the dot back |
| `tuck://route/<session\|pid\|hid>`, `tuck://separator/<idle\|collapsed\|expanded>` | Low-level event route / separator state |
