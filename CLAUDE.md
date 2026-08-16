# CLAUDE.md

This file provides guidance to Claude Code when working on this project.

## Project: omarchy-media-pip

**Type**: Omarchy Quickshell plugin + CLI
**Created**: 2026-08-15

## Development Commands

```bash
./install.sh                  # local dev: copy repo root into the live plugin dir + validate + symlink CLI
bin/media-pip status          # inspect current state
hyprctl configerrors          # after any bindings.lua change
```

## Architecture

Hybrid: real content stays in an actual Brave app-mode window (`bin/media-pip`
drives it via `hyprctl`); the Quickshell plugin (repo root `.qml` files)
supplies the bar icon, OSD feedback, and the space-reservation layer-shell
surface. See README.md for the full design and the reasoning behind each
piece.

`~/.config/omarchy/plugins/io.github.haydenmckay.media-pip` must be a real directory, not a
symlink — Omarchy's plugin loader rejects symlinks inside a plugin folder.
`install.sh` copies the repo root's `.qml`/`.json` files there (local dev
only); a real install is `omarchy plugin add <repo-url>`, a plain `git
clone` into that same destination — re-run `install.sh` after editing
anything at the repo root.

`manifest.json` and the `.qml` files live at the **repo root**, not a
`plugin/` subdirectory, specifically because `omarchy plugin add` clones
the whole repo as-is and validates `manifest.json` right at that root —
confirmed this fails validation otherwise by cloning a copy of an earlier,
`plugin/`-nested layout of this repo and running `omarchy plugin validate`
on it directly.

## Key Files

- `bin/media-pip` — CLI that does the actual window management. Not run
  from its own location at runtime -- see Service.qml's `cliPath` note.
- `Service.qml` — mirrors state from `~/.local/state/media-pip/state.json`;
  also self-stages a copy of `bin/media-pip` to that same state directory
  on every shell start, since the CLI can't be launched from inside the
  plugin's own install directory (see the `cliPath` property's comment --
  root cause not found, workaround confirmed working via a real
  install-flow simulation)
- `SpacerWindow.qml` — the reservation layer-shell surface (parked, not deleted — see README)
- `BarWidget.qml` — bar icon, source picker, "Manage sources" popup
- `sources.json` — source list (10 by default: Plex, YouTube, Netflix,
  Jellyfin, Disney+, Hulu, Max, Prime Video, Apple TV+, Paramount+)
- `~/.config/hypr/bindings.lua` — the five hotkeys (not in this repo)

## Notes

- Hyprland 0.56.2's Lua config dropped the classic `hyprctl dispatch <name>
  <args>` CLI syntax entirely. Use `hyprctl dispatch "hl.dsp.window.<fn>({...})"`
  — confirmed against `src/config/lua/bindings/LuaBindingsDispatchers.cpp`
  upstream, not just docs (the wiki was incomplete on this at time of
  writing). `hypr-pip` (the sibling project) needed the same fix.
- `--class=` does nothing for Chromium/Brave windows under Wayland/Ozone —
  window identity is matched by a substring on the URL's host against the
  auto-derived class instead (see `source_host` in bin/media-pip). The host
  match must strip the port, or it silently never matches and every call
  re-launches a duplicate window instead of finding the existing one — this
  was the actual root cause behind a long apparent "slow/flaky launch"
  investigation this session; the real launch latency (Chromium's
  single-instance IPC to an already-running Brave) is under 2s once the
  match works.
- `apply_geometry`'s usable-width calculation must add back the PiP's own
  previous reservation before subtracting the current `hyprctl monitors`
  reserved area, or repeated size/corner cycles shrink the usable area a
  little more each time (the previous reservation is part of what's
  currently reported reserved).
- `omarchy plugin validate` rejects symlinks anywhere under the plugin
  folder, including the folder itself being one.
- Plugins find their own install directory via `manifest.__sourceDir`
  (a plain filesystem path, stamped in by `services/PluginRegistry.qml`).
  Use it for any sibling data file — hardcoding a `~/Work` path silently
  breaks the plugin for every other user.
- Plugins CAN expose arbitrary IPC methods via Quickshell's `IpcHandler`
  (`target:` + named functions), reachable as
  `omarchy-shell <target> <method>`. `omarchy.clock` is the reference
  example. Not to be confused with `omarchy-shell shell toggle <id>`,
  which is only the panel open/close route.
- `Hyprland.toplevels` (Quickshell.Hyprland) is live and drops closed
  windows immediately off the event socket — no polling. But
  `lastIpcObject` on a freshly-mapped window is partially populated
  (`class`/`title` undefined) until a `refreshToplevels()` lands, and that
  call is async — you cannot read the result in the same tick. Quickshell
  addresses also omit the `0x` prefix that `hyprctl` reports.
- Source auto-detection (`auto_detect_source_id` in `bin/media-pip`,
  `openSources` in `Service.qml`) only resolves unambiguously when
  exactly one configured source's window is open. Zero or multiple open is
  ambiguous by design — a bare hotkey falls back to the stored/default
  source either way, and only the bar widget's click path can actually ask
  (via the `PopupCard` picker in `BarWidget.qml`), since a hotkey
  press has no UI to ask with.
- `SUPER + Backspace` (transparency toggle) and `SUPER + left/right-drag`
  (move/resize) are Omarchy defaults (`bindings/utilities.lua`,
  `bindings/tiling.lua`) that apply to the PiP window for free since it's a
  normal floated+pinned window — deliberately not reimplemented here.
- The television bar glyph is U+F0839 in the installed Nerd Fonts
  (CaskaydiaMono/JetBrains Nerd Font); there is no glyph-name table in
  those particular font builds (`post` table has no names) to look it up
  by name, so it was found by rendering codepoint candidates with Pillow
  and checking the output image, not from a cheat sheet.
- `onEnableKey` in sources.json (`send_on_enable_key` in `bin/media-pip`)
  sends a real keypress via `ydotool` every time PiP turns on for that
  source. Verified empirically (screenshots before/after) that Chromium's
  Fullscreen API request from a floated+pinned app-mode window stays
  contained inside the window's own bounds instead of triggering a real
  Hyprland-level fullscreen that would cover the monitor — `hyprctl clients
  -j`'s `.fullscreen` field never flips for it. Don't assume that's true for
  other key/source combos without checking the same way.
- `ydotoold` is a real runtime dependency now, not just a testing tool. It
  ships with Omarchy (`voxtype`/dictation uses it) but `ydotool.service` is
  disabled by default and nothing else keeps it running, so
  `send_on_enable_key` starts it on demand (`systemctl --user start
  ydotool.service`) rather than assuming it's already up. A stale
  `~/.local/state` socket file surviving a dead daemon process is a real
  failure mode here (`Connection refused`, not a missing-socket error) --
  the fix is starting the service, not touching the socket file.
- Every Omarchy web app (Menu > Install > Web App / `omarchy-webapp-install`)
  is a plain `.desktop` file in `~/.local/share/applications/` with
  `Exec=omarchy-launch-webapp <url>` -- no separate manifest exists.
  `maybe_nudge_webapp_setup` / `webapp_desktop_file_for_host` in
  `bin/media-pip` scan for that line to detect whether a source is already
  a "real" web app, purely to decide whether to nudge -- `media-pip`'s own
  launch (`launch_source_window`) never depends on one existing, and
  deliberately doesn't route through `omarchy-launch-webapp` even when one
  does, since that goes through `uwsm-app` scope activation, which measured
  1-15s of added variable latency in earlier testing (see the
  `resolve_browser_exec` comment). Confirmed via `busctl --user list`
  that Quickshell (`quickshell` binary, the omarchy-shell process) owns
  `org.freedesktop.Notifications` on the session bus, so
  `omarchy-notification-send`'s underlying `notify-send` call has
  somewhere real to land -- not verified by an on-screen screenshot,
  since synthesizing input to check turned out to collide with the live
  user's own keyboard/mouse input (see below).
- Do not use `ydotool`/synthetic mouse-click or keypress input to test UI
  interactively on this machine outside of `media-pip`'s own
  `send_on_enable_key` codepath. It shares the same input queue as the
  user's real keyboard/mouse, and testing this way has actually opened the
  Omarchy launcher mid-session and typed into it. Verify via `hyprctl`
  state, `state.json`, journalctl, and screenshots of *stable* UI instead;
  ask the user to confirm anything transient (notifications, popups) that
  needs a human to actually see it appear.
- Right-click on the bar icon used to instantly call `toggleReservation()`,
  then briefly went through a two-item context menu ("Reservation: On/Off",
  "Manage sources…") -- both superseded. Reservation got parked (see
  README's "Space reservation is parked"), which left the context menu
  with exactly one destination, so right-click now opens "Manage sources"
  directly again, same shape as before reservation ever shared the
  gesture. Both remaining popups (source picker, sources-manage) share
  `owner: root` on their `PopupCard`, so `close()` on `BarWidget.qml`'s
  root clears both open flags unconditionally rather than tracking which
  one is actually open -- safe only because this widget's own click
  handlers never open more than one at a time.
- `Service.qml`'s `sourcesStatus` (installed/not-installed per source, for
  the "Manage sources" popup) is populated by shelling out to `media-pip
  sources-status` via `Process` + `StdioCollector` (see `statusProcess`),
  not computed reactively in QML like `openSources` is -- install status
  isn't driven by a Hyprland event to hook a refresh off of, so it's
  refreshed explicitly instead: once on `Component.onCompleted`, and again
  whenever `installWebapp()`'s process exits or the popup is opened.
