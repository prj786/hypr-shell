import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Overview — a Mission-Control-style window switcher, opened by tapping Super alone.
// Each workspace is a scaled-down "mini-desktop" CARD; cards sit in a horizontal
// strip you scroll through (mouse wheel or trackpad, either axis). You can:
//   · search (top field) to filter windows by title/app,
//   · click a thumbnail (or Enter) to jump to that window,
//   · DRAG a thumbnail onto another desktop card to move it to that workspace
//     (the trailing empty card moves it to a fresh desktop),
//   · click the ✕ on a thumbnail to close that window.
// Keyboard ←/→ walks the windows and the strip auto-scrolls to keep the
// selection in view. The desktop behind is blurred + dimmed; covers the top bar.
//
// Trigger: `qs ipc call overview toggle` (Super tap, release bind in hyprland.lua).
Scope {
    id: root

    property string query: ""
    property int sel: 0

    function g(c) { return String.fromCodePoint(c) }

    readonly property var allWins: Hyprland.toplevels ? Hyprland.toplevels.values : []
    readonly property int focusedWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

    function classOf(tl) {
        var o = tl && tl.lastIpcObject ? tl.lastIpcObject : null
        return o ? (o.class || o.initialClass || "") : ""
    }
    function titleOf(tl) { return (tl && tl.title) ? tl.title : (root.classOf(tl) || "Window") }
    function wsOf(tl) { return (tl && tl.workspace) ? tl.workspace.id : -1 }

    function iconFor(tl) {
        var cls = root.classOf(tl)
        if (cls === "") return Quickshell.iconPath("application-x-executable")
        var e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e && e.icon ? e.icon : cls, "application-x-executable")
    }

    function matches(tl, q) {
        if (q === "") return true
        return (root.titleOf(tl) + " " + root.classOf(tl)).toLowerCase().indexOf(q) >= 0
    }

    // group windows into rows by workspace id; when not searching, also show a trailing
    // empty workspace as a drop-target for moving a window to a fresh desktop.
    readonly property var wsRows: buildRows()
    readonly property var flat: flatten(wsRows)

    function buildRows() {
        var q = root.query.trim().toLowerCase()
        var byWs = {}, maxWs = 1
        for (var i = 0; i < root.allWins.length; i++) {
            var tl = root.allWins[i], w = root.wsOf(tl)
            if (w < 1) continue
            if (w > maxWs) maxWs = w
            if (!byWs[w]) byWs[w] = []
            byWs[w].push(tl)
        }
        if (root.focusedWs > maxWs) maxWs = root.focusedWs
        var top = Math.min(Math.max(maxWs + (q === "" ? 1 : 0), 1), 10)
        var rows = []
        for (var ws = 1; ws <= top; ws++) {
            var list = (byWs[ws] || []).filter(function (t) { return root.matches(t, q) })
            if (q !== "" && list.length === 0) continue          // hide empty rows while searching
            rows.push({ ws: ws, wins: list })
        }
        return rows
    }
    function flatten(rows) {
        var out = []
        for (var i = 0; i < rows.length; i++)
            for (var j = 0; j < rows[i].wins.length; j++) out.push(rows[i].wins[j])
        return out
    }

    // ── actions ──
    function jump(tl) {
        if (tl && tl.wayland) tl.wayland.activate()
        else if (tl && tl.address) Hyprland.dispatch("focuswindow address:" + tl.address)
        root.close()
    }
    function addrOf(tl) {
        var a = (tl && tl.address) ? String(tl.address) : ""
        if (a !== "" && a.indexOf("0x") !== 0) a = "0x" + a   // Hyprland events sometimes omit the 0x
        return a
    }
    function moveWin(tl, ws) {
        var a = root.addrOf(tl)
        if (a === "" || root.wsOf(tl) === ws) return
        Hyprland.dispatch('hl.dsp.window.move({workspace=' + ws + ', window="address:' + a + '", follow=false})')
    }
    function killWin(tl) {
        var a = root.addrOf(tl)
        if (a !== "") Hyprland.dispatch('hl.dsp.window.close({window="address:' + a + '"})')
    }
    function close() { Globals.overviewOpen = false }

    onQueryChanged: root.sel = 0
    onFlatChanged: if (root.sel >= flat.length) root.sel = Math.max(0, flat.length - 1)

    IpcHandler {
        target: "overview"
        function toggle(): void { Globals.overviewOpen = !Globals.overviewOpen }
        function show(): void { Globals.overviewOpen = true }
        function hide(): void { Globals.overviewOpen = false }
    }

    Timer { id: closeTimer; interval: 240 }
    Connections { target: Globals; function onOverviewOpenChanged() { if (!Globals.overviewOpen) closeTimer.restart() } }

    PanelWindow {
        id: win
        visible: Globals.overviewOpen || closeTimer.running
        // open on whichever monitor is focused (dual-monitor: follow the active screen)
        screen: {
            var fm = Hyprland.focusedMonitor
            if (!fm) return null
            var ss = Quickshell.screens
            for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
            return null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore                 // span the whole screen, OVER the top bar
        WlrLayershell.layer: WlrLayer.Overlay                // above the bar (Top layer)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:overview"       // hyprland.lua blurs this namespace
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: if (visible) Qt.callLater(function () { search.forceActiveFocus() })
        Connections {
            target: Globals
            function onOverviewOpenChanged() { if (Globals.overviewOpen) search.forceActiveFocus() }
        }

        // dim + (compositor-)blurred scrim; click empty space to dismiss
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
            opacity: Globals.overviewOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            id: stage
            anchors.fill: parent
            opacity: Globals.overviewOpen ? 1 : 0
            scale: Globals.overviewOpen ? 1 : 0.98
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }

            // each desktop is a scaled-down monitor: keep the real screen aspect so
            // it reads as a mini-desktop. Sized off the overlay height.
            readonly property real monAR: (win.screen && win.screen.height > 0) ? (win.screen.width / win.screen.height) : 1.6
            readonly property int deskCardH: Math.round(height * 0.46)
            readonly property int deskCardW: Math.round(deskCardH * monAR)
            readonly property int deskGap: 30

            // scroll so the selected window's desktop is on-screen ("intelligent scroll")
            function ensureSelVisible() {
                if (root.flat.length === 0) return
                var ws = root.wsOf(root.flat[root.sel]), idx = -1
                for (var i = 0; i < root.wsRows.length; i++) if (root.wsRows[i].ws === ws) { idx = i; break }
                if (idx < 0) return
                var left = deskRow.x + idx * (deskCardW + deskGap)
                var right = left + deskCardW
                var maxX = Math.max(0, flick.contentWidth - flick.width)
                if (left < flick.contentX + 24) flick.contentX = Math.max(0, left - 24)
                else if (right > flick.contentX + flick.width - 24) flick.contentX = Math.min(maxX, right - flick.width + 24)
            }
            Connections { target: root; function onSelChanged() { stage.ensureSelVisible() } }

            // ── search field (top-centre, pill) ──
            Rectangle {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 36
                width: 540; height: 48
                radius: height / 2
                color: Theme.elevated
                border.color: Theme.accent; border.width: 2
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20; anchors.rightMargin: 20
                    spacing: 12
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF002); font.family: Theme.fontMono; font.pixelSize: 17; color: Theme.fgDim }
                    TextInput {
                        id: search
                        width: parent.width - 40
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge
                        selectionColor: Theme.accent; selectByMouse: true; clip: true
                        onTextChanged: root.query = text
                        Text { visible: search.text.length === 0; anchors.verticalCenter: parent.verticalCenter; text: "Search open windows…"; color: Theme.fgDim; font: search.font }
                        Keys.onPressed: function (ev) {
                            if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                            else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { if (root.flat.length) root.jump(root.flat[root.sel]); ev.accepted = true }
                            else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { root.sel = Math.max(0, root.sel - 1); ev.accepted = true }
                            else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { root.sel = Math.min(root.flat.length - 1, root.sel + 1); ev.accepted = true }
                        }
                    }
                }
            }

            // ── empty state ──
            Text {
                anchors.centerIn: parent
                visible: root.flat.length === 0
                text: root.query.length ? "No matching windows" : "No open windows"
                color: Theme.fgDim; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsTitle
            }

            // ── horizontal strip of desktop cards ──
            Flickable {
                id: flick
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 24
                anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, deskRow.width + 80)
                contentHeight: height
                // smooth, "intelligent" scroll: vertical OR horizontal wheel both pan the
                // strip; programmatic jumps (keyboard nav) glide via the Behavior below.
                Behavior on contentX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function (ev) {
                        var d = Math.abs(ev.angleDelta.y) > Math.abs(ev.angleDelta.x) ? ev.angleDelta.y : ev.angleDelta.x
                        var maxX = Math.max(0, flick.contentWidth - flick.width)
                        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - d))
                    }
                }

                Row {
                    id: deskRow
                    height: flick.height
                    // centre the strip when it fits; otherwise pin a left margin and scroll
                    x: Math.max(40, (flick.contentWidth - width) / 2)
                    spacing: stage.deskGap

                    Repeater {
                        model: root.wsRows
                        delegate: Column {
                            id: deskCol
                            required property var modelData
                            readonly property int ws: modelData.ws
                            readonly property bool isFocused: ws === root.focusedWs
                            // thumbnail grid metrics (2 columns inside the mini-desktop)
                            readonly property int pad: 16
                            readonly property int thumbGap: 14
                            readonly property int thumbW: Math.floor((stage.deskCardW - 2 * pad - thumbGap) / 2)
                            readonly property int thumbH: Math.round(thumbW / stage.monAR)
                            anchors.verticalCenter: parent.verticalCenter   // vertical anchor is safe inside a Row
                            spacing: 12

                            // the mini-desktop card
                            Rectangle {
                                id: card
                                width: stage.deskCardW; height: stage.deskCardH
                                radius: Theme.radius
                                color: dropZone.containsDrag ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                     : deskCol.isFocused ? Theme.elevated : Qt.rgba(Theme.elevated.r, Theme.elevated.g, Theme.elevated.b, 0.5)
                                border.color: dropZone.containsDrag ? Theme.accent : (deskCol.isFocused ? Theme.accent : Theme.stroke)
                                border.width: deskCol.isFocused || dropZone.containsDrag ? 2 : 1
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                clip: true

                                // drag-over highlight only; the move is resolved in the thumb's onReleased
                                DropArea { id: dropZone; anchors.fill: parent; keys: ["overview-window"] }

                                // empty-desktop hint (also a drop target for a fresh desktop)
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 32; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                    visible: deskCol.modelData.wins.length === 0
                                    text: "Drop a window here\n→ Desktop " + deskCol.ws
                                    color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                }

                                // window thumbnails
                                Flow {
                                    id: deskFlow
                                    anchors.fill: parent; anchors.margins: deskCol.pad
                                    spacing: deskCol.thumbGap

                                    Repeater {
                                        model: deskCol.modelData.wins
                                        delegate: MouseArea {
                                            id: dragArea
                                            required property var modelData
                                            readonly property int flatIdx: root.flat.indexOf(modelData)
                                            readonly property bool seld: flatIdx === root.sel
                                            width: deskCol.thumbW; height: deskCol.thumbH
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            drag.target: cardContent
                                            drag.smoothed: false
                                            property bool didDrag: false
                                            onPressed: didDrag = false
                                            onPositionChanged: { if (drag.active) didDrag = true; else root.sel = flatIdx }
                                            onClicked: root.jump(modelData)
                                            // Resolve the drop here (not DropArea.onDropped): the ParentChange
                                            // snaps the clone back the instant the drag ends, racing the drop
                                            // event — so hit-test the cursor against the desktop strip.
                                            onReleased: function (mouse) {
                                                if (!didDrag) return
                                                var p = dragArea.mapToItem(deskRow, mouse.x, mouse.y)
                                                var col = deskRow.childAt(p.x, p.y)
                                                if (col && col.ws !== undefined && col.ws >= 1) root.moveWin(modelData, col.ws)
                                            }

                                            Rectangle {
                                                id: cardContent
                                                width: dragArea.width
                                                height: dragArea.height
                                                radius: Theme.radiusInner
                                                color: Theme.panel
                                                border.color: dragArea.seld ? Theme.accent : Theme.stroke
                                                border.width: dragArea.seld ? 2 : 1
                                                clip: true

                                                Drag.active: dragArea.drag.active
                                                Drag.source: dragArea
                                                Drag.hotSpot.x: width / 2
                                                Drag.hotSpot.y: height / 2
                                                Drag.keys: ["overview-window"]

                                                // float above the clipping card/flickable while dragging;
                                                // ParentChange saves & restores x/y, snapping back on release
                                                states: State {
                                                    name: "dragging"; when: dragArea.drag.active
                                                    ParentChange { target: cardContent; parent: dragLayer }
                                                    PropertyChanges { target: cardContent; opacity: 0.92; z: 3000 }
                                                }

                                                // live window preview, icon fallback
                                                ScreencopyView {
                                                    id: sc
                                                    visible: hasContent && dragArea.modelData.wayland
                                                    captureSource: dragArea.modelData.wayland || null
                                                    live: Globals.overviewOpen && !cardContent.Drag.active
                                                    anchors.fill: parent; anchors.margins: 2
                                                }
                                                Image {
                                                    anchors.centerIn: parent; visible: !sc.visible
                                                    width: 40; height: 40; sourceSize.width: 80; sourceSize.height: 80
                                                    source: root.iconFor(dragArea.modelData)
                                                }

                                                // title chip (bottom), with app icon
                                                Rectangle {
                                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                                    height: 24
                                                    color: Qt.rgba(0, 0, 0, 0.55)
                                                    Row {
                                                        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 6
                                                        Image { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; sourceSize.width: 28; sourceSize.height: 28; source: root.iconFor(dragArea.modelData) }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter; width: parent.width - 22
                                                            text: root.titleOf(dragArea.modelData)
                                                            color: dragArea.seld ? Theme.fg : Theme.fgSecondary
                                                            font.family: Theme.fontText; font.pixelSize: 11
                                                            font.weight: dragArea.seld ? Font.DemiBold : Font.Normal
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }

                                            // close (✕) — sibling of the clone so it stays on top + unaffected by drag
                                            Rectangle {
                                                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6
                                                z: 50
                                                width: 20; height: 20; radius: 10
                                                visible: !dragArea.drag.active && (dragArea.containsMouse || closeMa.containsMouse)
                                                color: closeMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.6)
                                                Text { anchors.centerIn: parent; text: root.g(0xF0156); font.family: Theme.fontMono; font.pixelSize: 12; color: Theme.accentText }
                                                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(dragArea.modelData) }
                                            }
                                        }
                                    }
                                }
                            }

                            // desktop label (below the card)
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 7
                                Text { text: "Desktop " + deskCol.ws; color: deskCol.isFocused ? Theme.accent : Theme.fgSecondary; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                                Text { visible: deskCol.isFocused; anchors.verticalCenter: parent.verticalCenter; text: "· current"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            }
                        }
                    }
                }
            }

            // floating layer the dragged thumbnail reparents into (so it isn't clipped)
            Item { id: dragLayer; anchors.fill: parent; z: 2000 }
        }
    }
}
