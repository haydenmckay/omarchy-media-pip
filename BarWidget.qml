import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar icon for Media PiP. Left click toggles PiP for the active source, or
// opens a picker when more than one source's window is currently open
// (see openSources on the Service -- unambiguous cases are auto-detected
// by the CLI itself and don't need a picker at all). Right click opens the
// "Manage sources" popup. Scroll cycles size. Everything just calls into
// the paired Service (haydenmckay.media-pip), which shells out to the
// `media-pip` CLI -- see plugin/Service.qml and bin/media-pip.
//
// Space-reservation (the layer-shell spacer, SUPER ALT+R) is parked, not
// removed: SpacerWindow/reservationEnabled/toggleReservation still exist
// and work in Service.qml and bin/media-pip, just not surfaced here --
// nobody was actually using it day to day. See README's "reservation
// interlock" section for why it's more involved than it looks if it ever
// needs to come back.
BarWidget {
  id: root
  moduleName: "io.github.haydenmckay.media-pip"

  readonly property var svc: bar?.shell?.serviceFor("io.github.haydenmckay.media-pip")
  readonly property bool pipActive: svc ? svc.pipActive : false
  readonly property string sourceName: svc ? svc.activeSourceName : ""
  readonly property var openSources: svc ? svc.openSources : []
  readonly property var sourcesStatus: svc ? svc.sourcesStatus : []

  // A literal television glyph reads unambiguously as "this is the media
  // PiP" at a glance -- swapped in for an earlier frame-corners placeholder
  // that read more like a generic floating-window icon than a media one.
  readonly property string glyph: "󰠹"

  // Exactly one popup is ever open at a time, and the welcome popup *is*
  // the "Manage sources" popup (just auto-triggered once with an extra
  // greeting line rather than a separate UI) -- one string naming which
  // popup is open, rather than a "which popup" flag plus a second
  // "is this the welcome variant" flag layered on top of it, makes both
  // facts (open vs. closed, and which one) a single value with one write
  // site per opener instead of two independently-mutated booleans.
  property string openPopup: "none" // "none" | "picker" | "manage" | "welcome"
  // All popups share `owner: root`, so outside-click dismissal (via
  // PopupCard's HyprlandFocusGrab) always lands here regardless of which
  // one is open.
  function close() { openPopup = "none" }

  // First-run welcome: auto-open "Manage sources" (with a greeting) once
  // ever, the moment state.json has actually loaded and says it hasn't
  // been shown yet. Gated on stateLoaded so this doesn't fire for a single
  // frame on every shell start before the real persisted value arrives --
  // see stateLoaded's comment in Service.qml. Reactive rather than
  // Component.onCompleted since `svc` itself isn't available until the
  // shell finishes wiring up serviceFor().
  //
  // Also gated on cliReady, not just stateLoaded -- markWelcomeShown()
  // shells out through Service.qml's run(), which itself silently no-ops
  // until cliReady is true (the CLI's mkdir/cp/chmod self-staging chain
  // hasn't finished yet). stateLoaded reliably flips true well before
  // cliReady does (one fast local file read vs. three chained external
  // process launches), so without this the popup was opening every time
  // but "mark as seen" was silently dropped every time -- welcomeShown
  // never actually persisted, so it reopened on every single shell
  // restart. Confirmed live: state.json's welcomeShown sat at false
  // through many restarts despite the popup visibly appearing each time.
  readonly property bool welcomeNeeded: svc && svc.stateLoaded && svc.cliReady && !svc.welcomeShown
  onWelcomeNeededChanged: {
    if (!welcomeNeeded) return
    svc.refreshSourcesStatus()
    openPopup = "welcome"
    svc.markWelcomeShown()
  }

  visible: svc !== null
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.pipActive ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 120 }
      }
    }

    Text {
      visible: root.pipActive && !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      text: root.sourceName
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (!root.svc) return
      if (mouse.button === Qt.RightButton) {
        root.svc.refreshSourcesStatus()
        root.openPopup = "manage"
        return
      }
      if (!root.pipActive && root.openSources.length > 1) {
        // More than one source open at once (e.g. Plex and YouTube both
        // running) -- ask which one instead of guessing.
        root.openPopup = "picker"
        return
      }
      root.svc.toggle()
    }
    onWheel: function(wheel) {
      if (!root.svc) return
      if (wheel.angleDelta.y !== 0) root.svc.cycleSize()
      else if (wheel.angleDelta.x !== 0) root.svc.cycleCorner()
    }
  }

  PopupCard {
    id: sourcePopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.openPopup === "picker"
    contentWidth: sourcePopup.fittedContentWidth(Style.space(180))
    contentHeight: sourcePopup.fittedContentHeight(list.implicitHeight)

    Column {
      id: list
      anchors.fill: parent
      spacing: Style.space(2)

      Repeater {
        model: root.openSources

        Rectangle {
          id: sourceRow
          required property var modelData

          width: list.width
          height: label.implicitHeight + Style.space(10)
          radius: Style.spacing.labelGap
          color: hover.hovered ? Style.hoverFillFor(root.bar.foreground, root.bar.foreground) : "transparent"

          Text {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            text: sourceRow.modelData.name
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.svc.toggle(sourceRow.modelData.id)
              root.openPopup = "none"
            }
          }
        }
      }
    }
  }

  PopupCard {
    id: sourcesManagePopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.openPopup === "manage" || root.openPopup === "welcome"
    // Only the first-run trigger centers on the bar -- the everyday
    // right-click path stays anchored near the icon like every other
    // popup here, so it doesn't jump to a different spot depending on how
    // it was opened.
    centerOnBar: root.openPopup === "welcome"
    contentWidth: sourcesManagePopup.fittedContentWidth(Style.space(280))
    contentHeight: sourcesManagePopup.fittedContentHeight(manageList.implicitHeight)

    Column {
      id: manageList
      anchors.fill: parent
      spacing: Style.space(4)

      Text {
        visible: root.openPopup === "welcome"
        width: manageList.width
        text: "Welcome! Set up the media services you use as Omarchy web apps:"
        wrapMode: Text.WordWrap
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        bottomPadding: Style.space(4)
      }

      Repeater {
        model: root.sourcesStatus

        Rectangle {
          id: manageSourceRow
          required property var modelData

          width: manageList.width
          height: Math.max(sourceLabel.implicitHeight, statusLabel.implicitHeight) + Style.space(10)
          radius: Style.spacing.labelGap
          color: "transparent"

          Text {
            id: sourceLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            text: manageSourceRow.modelData.name
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          // Installed: a plain status glyph, nothing to click. Not
          // installed: the same slot doubles as an "Install" action --
          // installWebapp() is idempotent-ish (it just (re)writes the
          // .desktop file) so there's no harm if this is clicked more than
          // once before the status refresh lands.
          Text {
            id: statusLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(8)
            text: manageSourceRow.modelData.installed ? "✓ Installed" : "Install"
            color: manageSourceRow.modelData.installed
              ? Qt.darker(root.bar.foreground, 1.5)
              : (installHover.hovered ? root.bar.foreground : Color.accent)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: installHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !manageSourceRow.modelData.installed
            cursorShape: Qt.PointingHandCursor
            onClicked: root.svc.installWebapp(manageSourceRow.modelData.id)
          }
        }
      }
    }
  }
}
