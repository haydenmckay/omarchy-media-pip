import QtQuick
import Quickshell
import Quickshell.Wayland

// Invisible layer-shell surface whose only job is to reserve screen space
// so tiled windows never overlap the PiP browser window. Confirmed
// empirically (this session): a wlr-layer-shell surface only reserves an
// exclusive zone when anchored to a *single* edge -- anchoring to a corner
// (two edges) positions correctly but reserves nothing. So this always
// anchors to one full vertical edge (left or right, matching the PiP's
// current corner) and reserves a full-height strip the width of the PiP
// window, rather than a tight box around just the corner. That's a
// deliberate trade-off: more space held than the box itself uses, but a
// hard guarantee that nothing ever renders under the PiP, in both dwindle
// and master layouts.
PanelWindow {
  id: root

  property string edge: "right"
  property int widthPx: 0
  property bool active: false

  visible: active && widthPx > 0
  color: "transparent"

  anchors.left: edge === "left"
  anchors.right: edge === "right"

  implicitWidth: Math.max(1, widthPx)
  implicitHeight: 1

  WlrLayershell.namespace: "media-pip-spacer"
  WlrLayershell.layer: WlrLayer.Bottom
  exclusionMode: visible ? ExclusionMode.Normal : ExclusionMode.Ignore
  exclusiveZone: visible ? widthPx : 0
}
