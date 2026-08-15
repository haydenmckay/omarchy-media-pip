# omarchy-media-pip

Picture-in-picture mode for media (Plex, YouTube, extensible to others like
Jellyfin) on Omarchy/Hyprland: float, pin, and corner-snap a source's window
to a few fixed sizes, with a real Quickshell bar icon, hotkeys, and
toggleable screen-space reservation so tiled windows never render under it.

## Install

```bash
./install.sh
omarchy plugin enable trigz.media-pip --section right   # if not already enabled
```

Add the hotkeys below to `~/.config/hypr/bindings.lua` (already done on this
machine — see that file for the exact lines):

| Keys | Action |
|---|---|
| `SUPER ALT + P` | Toggle PiP (show/hide current source) |
| `SUPER ALT SHIFT + P` | Cycle size (small/medium/large) |
| `SUPER CTRL ALT + P` | Cycle corner |
| `SUPER ALT + O` | Cycle source (Plex → YouTube → …) |
| `SUPER ALT + R` | Toggle space reservation on/off |

Click the bar icon to toggle PiP; right-click toggles reservation; scroll
cycles size.

## Architecture

**Hybrid.** Real video content stays in an actual Brave app-mode window —
DRM, auth, YouTube's own player all just work for free. A Quickshell plugin
supplies everything else: a bar icon, OSD feedback, and a layer-shell
"spacer" surface that reserves real screen space.

- `bin/media-pip` — CLI that does the actual work: launches/finds the
  source's browser window and drives it with `hyprctl dispatch
  "hl.dsp.window.*"` calls (float, pin, resize, move). Writes all state to
  `~/.local/state/media-pip/state.json`.
- `plugin/Service.qml` — headless Quickshell service. Mirrors that state
  file live via `FileView`, and hosts the reservation spacer.
- `plugin/SpacerWindow.qml` — an invisible `PanelWindow` anchored to a
  single edge with an `exclusiveZone`, so Hyprland's tiling layout reserves
  real space for it.
- `plugin/BarWidget.qml` — the bar icon.
- `plugin/sources.json` — the source list (edit this to add e.g. Jellyfin).

Hotkeys and the bar widget both just shell out to `media-pip`, so there's
one source of truth regardless of what triggered a change.

### Why hotkeys call the CLI rather than Quickshell IPC

Plugins *can* expose arbitrary IPC methods — Quickshell's `IpcHandler`
lets a plugin declare named functions and `omarchy-shell <target> <method>`
routes to them (`omarchy.clock` does exactly this with `cycleFormat`,
`toggleWeekStart`). An earlier version of this file claimed otherwise; that
was wrong, and it's why this project reached for a CLI first.

The CLI is still the right home for the *window-management* logic, for a
reason that survives that correction: `hyprctl clients -j` is a complete,
synchronous snapshot, whereas Quickshell's `Hyprland.toplevels` populates
`lastIpcObject` asynchronously and partially — a freshly-mapped window
arrives with `class`/`title` still undefined until a refresh lands. Matching
a browser window *by class at the moment it appears* is markedly simpler
against the synchronous snapshot.

Quickshell's live model is used for what it's genuinely better at: knowing,
reactively and with no polling, whether the window still exists. See the
reservation interlock below.

### The reservation interlock

Reserving screen space is the one thing here that degrades the desktop for
windows that aren't ours, so it is gated on three things: the user turned
PiP on, the user opted into reservation, **and** the source's window is
live in `Hyprland.toplevels` right now.

That third condition is the important one. Persisted "PiP is on" state was
once trusted on its own, and a stale flag left a 480px strip reserved for a
window that no longer existed — squeezing the bar on every shell start. The
live gate makes that unrepresentable rather than corrected after the fact,
and it fails toward not-reserving. Verified: the toplevel model drops a
closed window immediately off Hyprland's event socket, so killing the
browser window by any means (not just through this tool) releases the
space at once.

`media-pip reconcile` still runs at service start to tidy the persisted
flag, but nothing load-bearing depends on it being correct any more.

### Window targeting

Not "whatever's focused" (that's `~/Work/hypr-pip`, which stays as a
separate, general-purpose tool) — a specific source needs to be found
reliably regardless of what's currently focused. `--class=` does nothing
for Chromium/Brave under Wayland; window class is auto-derived from the
URL's host, so that's what gets matched (`source_host` in `bin/media-pip`,
stripping the port — a URL's port never survives into the class string).

### Reservation is a full-edge strip, not a corner box

wlr-layer-shell only reserves an exclusive zone for a surface anchored to a
**single** edge — a corner-anchored surface (two edges) positions correctly
but reserves nothing (verified empirically this session: `hyprctl monitors`
reserved area only changed for single-edge anchoring). So the spacer always
reserves a full-height (or full-width) strip on whichever edge the PiP's
corner is nearest, sized to the PiP's current width. It guarantees nothing
ever renders under the PiP, in both dwindle and master layouts, at the
monitor level (upstream of Hyprland's layout engine).

The trade-off is real and is why reservation is **off by default**: a
480×270 corner box reserves a full-height 480px column, roughly 4× the area
the window actually occupies. Turn it on per-session with `SUPER ALT + R`
(or right-click the bar icon) when you actually want tiles to keep clear.

## Deploying plugin changes

`~/.config/omarchy/plugins/trigz.media-pip` must be a **real directory**,
not a symlink — `omarchy plugin validate` rejects symlinks anywhere under a
plugin folder, including the folder itself being one. Run `./install.sh`
after editing anything under `plugin/` to sync the copy.

## Future: native embedded panel

QtWebEngine is installed on this system, which raised the idea of rendering
Plex/YouTube directly inside a Quickshell panel instead of puppeting a
separate browser window. Tried it: `WebEngineView` inside a Quickshell
`PanelWindow` crashes Quickshell outright (`FATAL: Argument list is empty,
the program name is not passed to QCoreApplication`) — a known, open,
unfixed upstream bug:
[quickshell-mirror/quickshell#298](https://github.com/quickshell-mirror/quickshell/issues/298).

If that gets fixed upstream, the natural migration is: replace the Brave
app-window + `hyprctl` positioning with a native `WebEngineView` rendered
directly inside the plugin, dropping the external browser process and
window-class targeting entirely. The reservation mechanism stays valid
either way — it's a wlr-layer-shell protocol constraint, not a
WebEngineView one — so `SpacerWindow.qml` shouldn't need to change.

## Known limitations

- Two `toggle`/`size`/`corner` calls for a source with no window open yet,
  issued within about a second of each other, can each fail to see the
  other's in-flight launch and open a duplicate window (a `flock` guard
  narrows but doesn't fully close this — see `ensure_window` in
  `bin/media-pip`). Not an issue once a source's window already exists;
  only the very first cold-open per source per session is slow enough to
  matter.
