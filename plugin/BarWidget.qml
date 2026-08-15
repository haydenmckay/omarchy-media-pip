import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar icon for Media PiP. Left click toggles PiP for the active source,
// right click toggles space reservation, scroll cycles size. Everything
// just calls into the paired Service (trigz.media-pip), which shells out
// to the `media-pip` CLI -- see plugin/Service.qml and bin/media-pip.
BarWidget {
  id: root
  moduleName: "trigz.media-pip"

  readonly property var svc: bar?.shell?.serviceFor("trigz.media-pip")
  readonly property bool pipActive: svc ? svc.pipActive : false
  readonly property bool reservationEnabled: svc ? svc.reservationEnabled : true
  readonly property string sourceName: svc ? svc.activeSourceName : ""

  // Frame-corners glyph reads as "floating framed window" without
  // depending on a specific Nerd Font codepoint being correct.
  readonly property string glyph: "⛶"

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
      opacity: root.pipActive && !root.reservationEnabled ? 0.6 : 1.0
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 120 }
      }
      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
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
      if (mouse.button === Qt.RightButton) root.svc.toggleReservation()
      else root.svc.toggle()
    }
    onWheel: function(wheel) {
      if (!root.svc) return
      if (wheel.angleDelta.y !== 0) root.svc.cycleSize()
      else if (wheel.angleDelta.x !== 0) root.svc.cycleCorner()
    }
  }
}
