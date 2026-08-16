# omarchy-media-pip

Streamlines your media streaming setup on Omarchy with one-click
Omarchy web apps for Plex, YouTube, Netflix, and the rest of your
streaming services — then lets you float any of them into a corner as
picture-in-picture whenever you want them out of the way.

The setup half is what makes the rest painless: set up all your streaming
web apps from one place, then every source you've added is available as
PiP with a click. Right-click the bar icon any time for the same checklist
across every configured source. The PiP half does what it says: float,
pin, and corner-snap any configured source's window to a few fixed sizes,
with a real Quickshell bar icon and hotkeys (see `sources.json` for the
ten sources it ships with).

## Screenshots

**First run.** A one-time welcome popup offers to set up the media
services you use as proper Omarchy web apps — never shown again once
dismissed.

![Welcome popup on first launch](assets/welcome-popup.png)

**Manage sources, any time.** Right-click the bar icon for the same
checklist — installed services show a checkmark, everything else is a
one-click install.

![Manage sources checklist popup](assets/manage-sources-popup.png)

**Multiple sources at once.** With more than one source's window open,
clicking the bar icon asks which to PiP instead of guessing — shown here
with YouTube tiled, the Plex/YouTube/Netflix picker open top-right, and
Netflix already floating as PiP bottom-right.

![Source picker with three sources open](assets/source-picker-live.png)

**Out of your way.** PiP sits in the corner while you work — here running
alongside a terminal session, well clear of anything else on screen.

![PiP floating in the corner during a coding session](assets/pip-in-action-corner.png)

## Install

```bash
omarchy plugin add https://github.com/haydenmckay/omarchy-media-pip.git --enable
```

(For local development against a checkout of this repo instead: `./install.sh`,
then `omarchy plugin enable io.github.haydenmckay.media-pip --section right`
if it doesn't enable itself.)

## Keybindings

Add these to `~/.config/hypr/bindings.lua` (already done on this machine —
see that file for the exact lines). This is the whole list — deliberately
short, because the bar icon covers the rest and Omarchy's own window
hotkeys apply for free (see below).

| Keys | Action |
|---|---|
| `SUPER ALT + P` | Toggle PiP (show/hide current source) |
| `SUPER ALT SHIFT + P` | Cycle size (small → medium → large) |
| `SUPER CTRL ALT + P` | Cycle corner (bottom-right → bottom-left → top-left → top-right) |
| `SUPER ALT + O` | Cycle source (Plex → YouTube → …) |
| `SUPER ALT + R` | Toggle space reservation (works if bound, but has no bar-icon path — see "Known limitations") |

**Mouse:**

| Action | Result |
|---|---|
| Left-click bar icon | Toggle PiP for the active source — or open the source picker if more than one is open (see screenshots above) |
| Right-click bar icon | Open "Manage sources…" |
| Scroll bar icon up/down | Cycle size |
| `SUPER` + left-drag on the PiP window | Move it freely |
| `SUPER` + right-drag on the PiP window | Resize it freely |

The last two are Omarchy defaults, not plugin-specific — the PiP window is
a normal floated+pinned Hyprland window underneath, so dragging it around
already just works, same as `SUPER + Backspace` for toggling its
transparency. A manual move/resize just repositions the window; it doesn't
update the stored corner/size preset, so the next `size`/`corner` cycle
snaps back to whatever the preset says.

### Picking a source when more than one is open

Toggling PiP on doesn't always need `SUPER ALT + O` first. `media-pip`
checks which configured sources' windows are actually open
(`open_source_ids` / `auto_detect_source_id` in `bin/media-pip`):

- Exactly one open → that one, automatically, even if a different source
  was last active.
- None open → falls back to the last-active (or default) source, and
  launches it.
- More than one open at once → ambiguous. The hotkey path falls back the
  same as "none open," but the bar icon instead shows a small picker on
  click, listing whichever of the open ones apply — see `openSources` in
  `Service.qml` and the `PopupCard` in `BarWidget.qml`.

## Architecture

**Hybrid.** Real video content stays in an actual Brave app-mode window —
DRM, auth, each source's own player all just work for free. A Quickshell
plugin supplies everything else: a bar icon and OSD feedback.

- `bin/media-pip` — CLI that does the actual work: launches/finds the
  source's browser window and drives it with `hyprctl dispatch
  "hl.dsp.window.*"` calls (float, pin, resize, move). Writes all state to
  `~/.local/state/media-pip/state.json`.
- `Service.qml` — headless Quickshell service. Mirrors that state
  file live via `FileView`.
- `SpacerWindow.qml` — an invisible `PanelWindow` anchored to a
  single edge with an `exclusiveZone`, so Hyprland's tiling layout reserves
  real space for it, active whenever reservation is turned on (`SUPER ALT
  + R` if bound, or `media-pip reservation on`) — off by default, and with
  no bar-icon path to it, since day to day nobody actually needed tiled
  windows kept clear of the PiP corner.
- `BarWidget.qml` — the bar icon (a television glyph), the
  source-picker popup shown when more than one source is open at once, and
  the "Manage sources" popup (right-click).
- `sources.json` — the source list (Plex, YouTube, Netflix, and a
  handful of other streaming services out of the box — edit this to add
  more, e.g. a self-hosted Jellyfin). A source can set `onEnableKey` to
  have `media-pip` type that key into its window every time PiP turns on
  for it — YouTube uses `"f"` to drop into its own in-page fullscreen
  player, which fits a small PiP box far better than the normal
  header/sidebar/comments layout (verified empirically to stay contained
  inside the small window rather than hijacking the whole monitor — see
  "Known limitations"). Not yet verified for the other bundled sources.
  Sent via `ydotool`
  (ships with Omarchy for voxtype/dictation; `media-pip` starts its
  `ydotool.service` on demand since it isn't kept running by default).

## Known limitations

- Space reservation (`SUPER ALT + R` / `media-pip reservation on`) has no
  bar-icon path — nobody was actually using it day to day, so it's parked
  rather than surfaced, though the code and hotkey both still work.
- Two `toggle`/`size`/`corner` calls for a source with no window open yet,
  issued within about a second of each other, can each fail to see the
  other's in-flight launch and open a duplicate window (a `flock` guard
  narrows but doesn't fully close this — see `ensure_window` in
  `bin/media-pip`). Not an issue once a source's window already exists;
  only the very first cold-open per source per session is slow enough to
  matter.
- `onEnableKey` (YouTube's `f`) sends a real keypress, which *toggles*
  in-page fullscreen rather than forcing it on. It fires every time PiP
  turns on, which is right in the common case (you were already on a video
  in a normal tab, then toggled PiP on), but re-toggling PiP on and off
  again without navigating away in between can flip it back to YouTube's
  normal chrome instead of re-entering fullscreen — there's no reliable way
  to read the page's actual fullscreen state from outside it. Press `f`
  manually if that happens.
- `plex`'s `url` in `sources.json` defaults to
  `http://localhost:32400/web/index.html` — right if Plex Media Server
  runs on the same machine as Omarchy, wrong otherwise. Edit it to your
  server's actual LAN IP or hostname if Plex runs elsewhere.
- `jellyfin`'s `url` in `sources.json` (`http://jellyfin.local:8096/`) is a
  placeholder for the same reason — Jellyfin is self-hosted too, so there's
  no fixed public URL to ship. Edit it to your actual server before using
  that source.
