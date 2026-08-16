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
  readonly property string stateDir: home + "/.local/state/media-pip"
  readonly property string statePath: stateDir + "/state.json"
  // The plugin registry stamps each manifest with its own install directory,
  // so sources.json is found wherever the plugin actually lives -- hardcoding
  // a ~/Work path left the source list empty for anyone else installing this.
  readonly property string sourceDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : ""
  readonly property string sourcesPath: sourceDir + "/sources.json"

  // `omarchy plugin add` clones this repo straight into the live plugins
  // directory and never runs install.sh (there's no post-install hook in
  // the manifest schema), so nothing symlinks bin/media-pip onto $PATH for
  // a real install -- a bare "media-pip" command would fail to launch.
  //
  // Resolving it via sourceDir (the same way sourcesPath does above) is
  // the obvious next attempt, but doesn't work: empirically, ANY
  // executable placed inside the live, PluginRegistry-loaded plugin
  // directory fails to launch via Quickshell's Process ("likely because
  // the binary could not be found"), even at its exact correct absolute
  // path with the right permissions -- confirmed with multiple unrelated
  // scripts, ruling out this specific file, dots in the path, stale
  // bindings, and script-vs-binary as the cause. A standalone Quickshell
  // scene launching a companion script from its own shellDir works fine,
  // so the restriction is specific to being loaded through
  // PluginRegistry.qml inside the shared shell process, not Process or
  // plugin-relative paths in general -- root cause not found; see
  // gotchas.md for what was ruled out.
  //
  // Workaround: self-stage a copy of the CLI to a location outside the
  // plugin directory the moment sourceDir is known (see
  // onSourceDirChanged), using `cp`/`chmod` -- themselves outside the
  // plugin dir, so they launch fine -- then always invoke *that* copy.
  // Re-staged on every shell start, so it can't go stale across an
  // `omarchy plugin update`.
  readonly property string cliPath: stateDir + "/media-pip"

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
  readonly property bool welcomeShown: pipState.welcomeShown === true
  // FileView's onLoaded fires once state.json has actually been read, vs.
  // pipState's initial `{}` -- without this, welcomeShown reads false (its
  // default) for the brief window before the real value loads, same as any
  // returning user, which would auto-open the welcome popup for everyone
  // for one frame on every shell start.
  property bool stateLoaded: false

  // Host of a source's URL, matched against Chromium's auto-derived window
  // class (it ignores --class under Wayland). Port must be stripped: it
  // survives in the URL but never appears in the class string.
  function hostFor(url) {
    return String(url || "").replace(/^[a-z]+:\/\//, "").replace(/[:\/].*$/, "")
  }

  readonly property string activeSourceHost: {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id === activeSourceId) return hostFor(sources[i].url)
    }
    return ""
  }

  // Sources whose window is live right now, regardless of which one (if
  // any) is the active PiP source -- used by the bar widget to auto-pick
  // when exactly one is open and to prompt when more than one is, rather
  // than guessing. Same live toplevel match as pipWindowLive below.
  readonly property var openSources: {
    var result = []
    var v = Hyprland.toplevels.values
    for (var i = 0; i < sources.length; i++) {
      var host = hostFor(sources[i].url)
      if (host === "") continue
      for (var j = 0; j < v.length; j++) {
        var ipc = v[j].lastIpcObject
        if (ipc && ipc.class && String(ipc.class).indexOf(host) >= 0) {
          result.push({ id: sources[i].id, name: sources[i].name })
          break
        }
      }
    }
    return result
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
    onLoaded: { root.pipState = root.parseObject(text()); root.stateLoaded = true }
    onLoadFailed: { root.pipState = ({}); root.stateLoaded = true }
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
  //
  // Every caller here is normally a user click, well after `manifest` has
  // loaded -- except markWelcomeShown(), which fires programmatically the
  // instant welcomeNeeded flips true, and could in principle race manifest
  // injection the same way reconcile/sources-status used to (see
  // onSourceDirChanged below). Guard here too rather than trust every call
  // site to be timing-safe.
  function run(args) {
    if (!cliReady || runner.running) return
    runner.command = [root.cliPath].concat(args)
    runner.running = true
  }

  // MEDIA_PIP_SOURCES_DIR tells the staged CLI copy where sources.json
  // really lives, since its own on-disk location (cliPath, outside the
  // plugin dir) no longer sits next to it the way a plugin-dir install
  // would -- see bin/media-pip's own comment on SOURCES_FILE. Every
  // Process below that invokes cliPath sets the same variable.
  Process { id: runner; environment: ({ "MEDIA_PIP_SOURCES_DIR": root.sourceDir }) }

  // True once the CLI has actually been copied to cliPath and made
  // executable -- see the staging chain below. Every Process that invokes
  // cliPath gates on this instead of sourceDir directly, since sourceDir
  // being known only means staging *can* start, not that it's finished.
  property bool cliReady: false

  // Stages a copy of the CLI outside the plugin directory (see cliPath's
  // comment for why) the moment sourceDir is known: mkdir the state dir,
  // copy the CLI in, mark it executable, then run reconcile/sources-status
  // for the first time -- chained through onExited rather than fired
  // together, since each step depends on the previous one having
  // succeeded (a `cp` into a directory that doesn't exist yet fails, a
  // freshly-copied file isn't +x until chmod runs).
  onSourceDirChanged: {
    if (sourceDir === "") return
    cliMkdir.running = true
  }
  Process {
    id: cliMkdir
    command: ["/usr/bin/mkdir", "-p", root.stateDir]
    onExited: (code) => { if (code === 0) cliStage.running = true }
  }
  Process {
    id: cliStage
    command: ["/usr/bin/cp", "-f", root.sourceDir + "/bin/media-pip", root.cliPath]
    onExited: (code) => { if (code === 0) cliChmod.running = true }
  }
  Process {
    id: cliChmod
    command: ["/usr/bin/chmod", "+x", root.cliPath]
    onExited: (code) => {
      if (code !== 0) return
      root.cliReady = true
      reconciler.running = true
      refreshSourcesStatus()
    }
  }

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
    command: [root.cliPath, "reconcile"]
    environment: ({ "MEDIA_PIP_SOURCES_DIR": root.sourceDir })
  }
  Component.onCompleted: Hyprland.refreshToplevels()

  // sourceId is passed by the bar widget's picker when more than one
  // source is open at once, to skip the CLI's own auto-detection (which is
  // only unambiguous with zero or one source open) and go straight to the
  // one the user picked.
  function toggle(sourceId) { run(sourceId ? ["toggle", sourceId] : ["toggle"]) }
  function cycleSize() { run(["size"]) }
  function cycleCorner() { run(["corner"]) }
  function cycleSource() { run(["source"]) }
  function toggleReservation() { run(["reservation", "toggle"]) }
  function markWelcomeShown() { run(["welcome-seen"]) }

  // Per-source install status for the "Manage sources" popup -- separate
  // from `runner` above since a status refresh shouldn't be dropped just
  // because a toggle happens to be in flight, or vice versa.
  property var sourcesStatus: []

  // Guards against the same too-early-to-launch race as onSourceDirChanged
  // above -- BarWidget.qml's welcome-popup trigger calls this independently
  // of that handler (gated on stateLoaded, not cliReady), so it needs its
  // own check rather than relying on callers to order things correctly.
  function refreshSourcesStatus() {
    if (!cliReady || statusProcess.running) return
    statusProcess.running = true
  }

  Process {
    id: statusProcess
    command: [root.cliPath, "sources-status"]
    environment: ({ "MEDIA_PIP_SOURCES_DIR": root.sourceDir })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sourcesStatus = root.parseArray(text)
    }
  }

  // Which source (if any) installWebapp() is currently mid-flight for --
  // the popup row uses this to show "Installing…" instead of sitting
  // there looking unresponsive for the several seconds a favicon fetch
  // can take. Empty string means none in flight.
  property string installingSourceId: ""

  // Favicon fetch inside `omarchy-webapp-install` can take a few seconds
  // over the network, so this runs in the background rather than blocking
  // the popup -- refreshes sourcesStatus once it's actually done rather
  // than optimistically flipping the row to installed immediately.
  function installWebapp(sourceId) {
    if (installProcess.running) return
    installingSourceId = sourceId
    installProcess.command = [root.cliPath, "webapp-install", sourceId]
    installProcess.running = true
  }

  Process {
    id: installProcess
    environment: ({ "MEDIA_PIP_SOURCES_DIR": root.sourceDir })
    onExited: {
      root.installingSourceId = ""
      root.refreshSourcesStatus()
    }
  }

  SpacerWindow {
    edge: root.reservationEdge
    widthPx: root.reservationWidthPx
    active: root.pipActive && root.reservationEnabled && root.pipWindowLive
  }
}
