# Tuck

A small dot in the macOS menu bar that holds the menu bar items you don't want to see, and every item the notch is hiding.

Phase 0 of [spec.md](spec.md). macOS 26, Apple Silicon, no Dock icon, no network.

## How it works

- **Click the dot**: a bar drops down under it with every item that is hidden in Tuck or stuck behind the notch. Click one to open it: Tuck brings the item out next to the dot, opens it, and puts it back once its menu closes. The gear at the right end opens Settings.
- **Hover the notch**: rest the pointer behind the notch for a moment and the same items drop down in a black drawer that grows out of the notch. It closes when the pointer leaves. Can be switched off in Settings.
- **Settings** (gear, or right-click the dot): a switch per menu bar item to hide it in Tuck, Open at Login, and permissions.

Items right of the dot (Clock, Control Center) are never touched.

Under the hood Tuck has two status items of its own: the dot, and an invisible separator. Items left of the separator are hidden by stretching the separator until they are pushed off-screen. Items are moved with the same ⌘-drag you would do by hand, sent as synthetic events addressed to the item's window, so it also works for items that are off-screen. macOS remembers item positions itself, so the layout survives restarts.

On macOS 26 every menu bar item window belongs to Control Center, so Tuck finds out which app owns an item by matching window frames against each app's Accessibility menu bar extras.

## Permissions

Accessibility is required (System Settings › Privacy & Security › Accessibility). Screen Recording is optional: with it, the bar shows pictures of the real menu bar items instead of app icons.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test      # unit tests
make run       # build and launch the Debug app
make install   # Release build into /Applications (needed for Open at Login)
```

## Debugging

Tuck logs to `~/Library/Logs/Tuck.log`. It also takes `tuck://` URLs:

| URL | Does |
|---|---|
| `tuck://bar`, `tuck://notch`, `tuck://settings` | Open the bar / the notch drawer / the Settings window |
| `tuck://dump` | Logs every item: window ID, position, placement, owner |
| `tuck://axdump` | Logs every app's raw Accessibility menu bar items |
| `tuck://hide/<window>` / `tuck://show/<window>` | Same as the switch in Settings |
| `tuck://move/<window>?leftOf=<window>` | Move an item next to another (`rightOf=` too) |
| `tuck://open/<window>` | Same as clicking it in the bar |
| `tuck://click/<window>`, `tuck://press/<window>` | Raw synthetic click / Accessibility press |
| `tuck://route/<session\|pid\|hid>` | Where synthetic events are posted |
| `tuck://separator/<idle\|collapsed\|expanded>` | Force the separator state |
