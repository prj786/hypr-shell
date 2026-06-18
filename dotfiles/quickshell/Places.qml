import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Places — the directories panel that pops up above the dock's folder button.
// Shows the standard XDG locations (Home, Desktop, Documents, …) plus any
// folders you've pinned (persisted via Globals.pinnedPlaces). Works "like apps":
//   • click a place   → opens it in the file manager (xdg-open) and closes
//   • drag a place out → starts a FILE drag (text/uri-list, file://…) so you can
//     drop the folder straight into Slack, an upload field, etc. — same idiom as
//     the screenshot stack (ScreenshotPreview.qml).
//   • pin/unpin        → keep extra folders here.
// The window masks ONLY the box, so the area around it passes input through —
// that's what lets a drag land on the app behind the panel. Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }

    property string home: ""
    property var places: []          // [{ name, path }] — resolved XDG dirs
    property string pinPath: ""      // the "pin a folder" input text

    // freedesktop icon name for a place (falls back to a generic folder)
    function placeIcon(name) {
        switch (name) {
        case "Home":      return "user-home"
        case "Desktop":   return "user-desktop"
        case "Documents": return "folder-documents"
        case "Downloads": return "folder-download"
        case "Music":     return "folder-music"
        case "Pictures":  return "folder-pictures"
        case "Videos":    return "folder-videos"
        default:          return "folder"
        }
    }
    function baseName(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i >= 0 ? s.slice(i + 1) || "/" : s }
    function expand(p) { var s = String(p).trim(); if (s === "~") return root.home; if (s.indexOf("~/") === 0) return root.home + s.slice(1); return s }
    function openPath(p) { Quickshell.execDetached(["xdg-open", p]); Globals.placesOpen = false }

    // resolve the XDG user dirs (Home always; the rest via xdg-user-dir, only if
    // they exist) — one line "name\tpath" each, plus HOME= for ~ expansion.
    Process {
        id: resolver
        command: ["sh", "-c",
            'echo "HOME=$HOME"; printf "Home\\t%s\\n" "$HOME"; ' +
            'for pair in Desktop:DESKTOP Documents:DOCUMENTS Downloads:DOWNLOAD Music:MUSIC Pictures:PICTURES Videos:VIDEOS; do ' +
            '  n=${pair%%:*}; k=${pair##*:}; p=$(xdg-user-dir "$k" 2>/dev/null); ' +
            '  [ -n "$p" ] && [ "$p" != "$HOME" ] && [ -d "$p" ] && printf "%s\\t%s\\n" "$n" "$p"; ' +
            'done']
        stdout: StdioCollector { onStreamFinished: {
            var out = [], ls = this.text.split("\n")
            for (var i = 0; i < ls.length; i++) {
                var ln = ls[i]
                if (ln.indexOf("HOME=") === 0) { root.home = ln.slice(5); continue }
                var t = ln.indexOf("\t"); if (t < 0) continue
                out.push({ name: ln.slice(0, t), path: ln.slice(t + 1) })
            }
            root.places = out
        } }
    }
    Component.onCompleted: { root.openScreen = root.focusedScreen(); resolver.running = true }

    // latch monitor on open (avoid focus-follows-mouse surface-remap blink)
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }

    IpcHandler {
        target: "places"
        function toggle(): void { Globals.launcherOpen = false; Globals.storeOpen = false; Globals.placesOpen = !Globals.placesOpen }
        function show(): void { Globals.placesOpen = true }
        function hide(): void { Globals.placesOpen = false }
    }

    PanelWindow {
        id: win
        visible: Globals.placesOpen || closeTimer.running
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:places"
        anchors { top: true; bottom: true; left: true; right: true }

        // Mask ONLY the box: input outside it passes through to the app below, so
        // a folder drag can land on Slack/etc. (see header). No click-outside close.
        mask: Region { item: box }

        Timer { id: closeTimer; interval: 220 }
        Connections { target: Globals; function onPlacesOpenChanged() {
            if (Globals.placesOpen) { root.openScreen = root.focusedScreen(); resolver.running = true; root.pinPath = ""; box.forceActiveFocus() }
            else closeTimer.restart()
        } }

        Rectangle {
            id: box
            focus: true
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.placesAnchorX - width / 2))
            y: parent.height - height - 90
            width: 380; height: 470
            radius: Theme.radius; color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            opacity: Globals.placesOpen ? 1 : 0
            scale: Globals.placesOpen ? 1 : 0.96
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 8; blurMax: 48 }

            Keys.onEscapePressed: Globals.placesOpen = false

            // ── a single place tile: icon + label, click=open, drag=file URI ──
            component PlaceTile: Item {
                id: tile
                property string pName: ""
                property string pPath: ""
                property bool pinned: false
                width: grid.cellW; height: 84

                Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 12; color: tMa.containsMouse ? Theme.hover : "transparent" }
                Column {
                    anchors.centerIn: parent; spacing: 6
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 42; height: 42; sourceSize.width: 64; sourceSize.height: 64
                        source: Quickshell.iconPath(root.placeIcon(tile.pName), "folder")
                    }
                    Text { width: tile.width - 10; horizontalAlignment: Text.AlignHCenter; text: tile.pName; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1 }
                }

                // invisible drag proxy — dragging this fires the external file drag
                // while the tile stays put (same trick as ScreenshotPreview).
                Item {
                    id: dragProxy; width: 1; height: 1
                    Drag.active: tMa.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.mimeData: ({ "text/uri-list": "file://" + tile.pPath + "\r\n" })
                }
                MouseArea {
                    id: tMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    drag.target: dragProxy
                    onClicked: root.openPath(tile.pPath)
                }

                // unpin badge (pinned tiles only, on hover)
                Rectangle {
                    visible: tile.pinned && (tMa.containsMouse || uMa.containsMouse)
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                    width: 20; height: 20; radius: 10; color: Qt.rgba(0, 0, 0, 0.45)
                    Text { anchors.centerIn: parent; text: root.g(0xF0156); font.family: Theme.fontMono; font.pixelSize: 12; color: Theme.fg }
                    MouseArea { id: uMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.togglePinPlace(tile.pPath) }
                }
            }

            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 10

                // header
                Item {
                    width: parent.width; height: 24
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Places"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11; color: clMa.containsMouse ? Theme.hover : "transparent"
                        Text { anchors.centerIn: parent; text: root.g(0xF0156); font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.fgDim }
                        MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Globals.placesOpen = false }
                    }
                }
                Text { width: parent.width; text: "Click to open · drag a folder into any app"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }

                Flickable {
                    width: parent.width; height: parent.height - y - pinRow.height - 10
                    contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: col
                        width: parent.width; spacing: 8
                        readonly property real cellW: width / 3

                        Grid {
                            id: grid
                            property real cellW: col.cellW
                            width: parent.width; columns: 3; rowSpacing: 2; columnSpacing: 0
                            Repeater { model: root.places; delegate: PlaceTile { required property var modelData; pName: modelData.name; pPath: modelData.path } }
                        }

                        Text {
                            width: parent.width; visible: (Globals.pinnedPlaces || []).length > 0
                            text: "PINNED"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Grid {
                            width: parent.width; columns: 3; rowSpacing: 2; columnSpacing: 0
                            visible: (Globals.pinnedPlaces || []).length > 0
                            Repeater { model: Globals.pinnedPlaces; delegate: PlaceTile { required property var modelData; pName: root.baseName(modelData); pPath: modelData; pinned: true } }
                        }
                    }
                }

                // pin a folder by path (~ allowed)
                Rectangle {
                    id: pinRow
                    width: parent.width; height: 34; radius: Theme.radiusInner
                    color: Theme.bg; border.color: pinIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                    Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0415); font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.fgDim }
                    TextInput {
                        id: pinIn
                        anchors.fill: parent; anchors.leftMargin: 32; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; clip: true
                        onTextChanged: root.pinPath = text
                        Keys.onEscapePressed: Globals.placesOpen = false
                        onAccepted: { var p = root.expand(root.pinPath); if (p && p.indexOf("/") === 0 && !Globals.isPinnedPlace(p)) { Globals.togglePinPlace(p); pinIn.text = "" } }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: pinIn.text.length === 0; text: "Pin a folder by path… (Enter)"; color: Theme.fgDim; font: pinIn.font }
                    }
                }
            }
        }
    }
}
