# CLAUDE.md

This file provides guidance to Claude Code when working on this project.

## Project: omarchy-media-pip

**Type**: Omarchy Quickshell plugin + CLI
**Created**: 2026-08-15

## Development Commands

```bash
./install.sh                  # sync plugin/ into the live plugin dir + validate + symlink CLI
bin/media-pip status          # inspect current state
hyprctl configerrors          # after any bindings.lua change
```

## Architecture

Hybrid: real content stays in an actual Brave app-mode window (`bin/media-pip`
drives it via `hyprctl`); the Quickshell plugin (`plugin/`) supplies the bar
icon, OSD feedback, and the space-reservation layer-shell surface. See
README.md for the full design and the reasoning behind each piece.

`~/.config/omarchy/plugins/trigz.media-pip` must be a real directory, not a
symlink — Omarchy's plugin loader rejects symlinks inside a plugin folder.
`install.sh` copies `plugin/*` there; re-run it after editing anything under
`plugin/`.

## Key Files

- `bin/media-pip` — CLI that does the actual window management
- `plugin/Service.qml` — mirrors state from `~/.local/state/media-pip/state.json`
- `plugin/SpacerWindow.qml` — the reservation layer-shell surface
- `plugin/BarWidget.qml` — bar icon
- `plugin/sources.json` — source list (Plex/YouTube by default)
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
