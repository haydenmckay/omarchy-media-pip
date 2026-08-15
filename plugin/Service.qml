import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
// SpacerWindow.qml is a sibling file in this same plugin directory, so QML
// makes it available as the `SpacerWindow` type automatically.

// Headless service: owns shared PiP state for the bar widget, mirrored from
// ~/.local/state/media-pip/state.json (written by the `media-pip` CLI, which
// does all the actual hyprctl/browser work -- see bin/media-pip). Hotkeys
// and the bar widget both just shell out to that same CLI, so there is one
// source of truth regardless of which triggered a change.
Item {
  id: root

  // Injected by omarchy-shell (the plugin loader).
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/media-pip/state.json"
  // The plugin registry stamps each manifest with its own install directory,
  // so sources.json is found wherever the plugin actually lives -- hardcoding
  // a ~/Work path left the source list empty for anyone else installing this.
  readonly property string sourcesPath:
    (manifest && manifest.__sourceDir ? manifest.__sourceDir : "") + "/sources.json"

  property var pipState: ({})
  property var sources: []

  readonly property bool pipActive: pipState.pipActive === true
  // Opt-in: reservation claims a coarse full-edge strip (a wlr-layer-shell
  // constraint -- see SpacerWindow.qml), so it stays off unless asked for.
  readonly property bool reservationEnabled: pipState.reservationEnabled === true
  readonly property string activeSourceId: pipState.activeSourceId || (sources.length ? sources[0].id : "")
  readonly property string activeSourceName: {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id === activeSourceId) return sources[i].name
    }
    return activeSourceId
  }
  readonly property int sizeIdx: pipState.sizeIdx || 0
  readonly property int cornerIdx: pipState.cornerIdx || 0
  readonly property string reservationEdge: (pipState.reservation && pipState.reservation.edge) || "right"
  readonly property int reservationWidthPx: (pipState.reservation && pipState.reservation.widthPx) || 0

  // Host of the active source's URL, matched against Chromium's auto-derived
  // window class (it ignores --class under Wayland). Port must be stripped:
  // it survives in the URL but never appears in the class string.
  readonly property string activeSourceHost: {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id === activeSourceId)
        return String(sources[i].url || "").replace(/^[a-z]+:\/\//, "").replace(/[:\/].*$/, "")
    }
    return ""
  }

  // Live existence check against Hyprland's toplevel model. Verified: the
  // model drops a closed window immediately off Hyprland's event socket,
  // with no polling or explicit refresh needed.
  //
  // This is the safety interlock. Reserving screen space is the one action
  // here that degrades the desktop for windows that aren't ours -- a stale
  // persisted "PiP is on" once left a 480px strip reserved for a window
  // that no longer existed, squeezing the bar on every shell start. Gating
  // on live existence makes that unrepresentable rather than merely
  // corrected after the fact, and it fails toward not-reserving.
  readonly property bool pipWindowLive: {
    if (activeSourceHost === "") return false
    var v = Hyprland.toplevels.values
    for (var i = 0; i < v.length; i++) {
      var ipc = v[i].lastIpcObject
      if (ipc && ipc.class && String(ipc.class).indexOf(activeSourceHost) >= 0) return true
    }
    return false
  }

  // A freshly-mapped toplevel arrives with lastIpcObject only partially
  // populated (class/title undefined until a full query lands), so the
  // class match above needs a refresh once the window list changes.
  // refreshToplevels() is async -- its result shows up on a later tick, not
  // this one. Driven off window events rather than the model's own change
  // signal, which a refresh would itself re-trigger.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event ? String(event.name) : ""
      if (n === "openwindow" || n === "closewindow" || n === "changefloatingmode")
        Hyprland.refreshToplevels()
    }
  }


  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.pipState = root.parseObject(text())
    onLoadFailed: root.pipState = ({})
  }

  FileView {
    path: root.sourcesPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.sources = root.parseArray(text())
    onLoadFailed: root.sources = []
  }

  function parseObject(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      return parsed && typeof parsed === "object" ? parsed : {}
    } catch (e) {
      return {}
    }
  }

  function parseArray(content) {
    try {
      var parsed = JSON.parse(String(content || "[]"))
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }

  // The first source-opening launch can take a while (Chromium's
  // single-instance IPC handoff to an already-running browser is slow and
  // variable -- see bin/media-pip). Dropping repeat clicks while one is in
  // flight avoids stacking up redundant launches.
  function run(args) {
    if (runner.running) return
    runner.command = ["media-pip"].concat(args)
    runner.running = true
  }

  Process { id: runner }

  // Quickshell reloads this service on every shell start (login, crash
  // recovery, `omarchy restart shell`), and it mirrors state.json exactly
  // as persisted -- including reservation. A source that's genuinely still
  // floating/pinned from before is worth restoring, but stale
  // `pipActive:true` left over from a source that's since been closed (or
  // a reboot that dropped Hyprland's floating/pinned state) would
  // otherwise make the spacer reserve real screen space with nothing
  // actually floating there, the instant the shell loads -- no user
  // action involved at all. `media-pip reconcile` only ever turns a stale
  // "on" into an honest "off" by checking live window state; it never
  // launches anything, so this can't itself cause a PiP to open.
  Process {
    id: reconciler
    command: ["media-pip", "reconcile"]
  }
  Component.onCompleted: {
    Hyprland.refreshToplevels()
    reconciler.running = true
  }

  function toggle() { run(["toggle"]) }
  function cycleSize() { run(["size"]) }
  function cycleCorner() { run(["corner"]) }
  function cycleSource() { run(["source"]) }
  function toggleReservation() { run(["reservation", "toggle"]) }

  SpacerWindow {
    edge: root.reservationEdge
    widthPx: root.reservationWidthPx
    active: root.pipActive && root.reservationEnabled && root.pipWindowLive
  }
}
