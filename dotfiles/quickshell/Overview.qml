import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Overview — a Mission-Control-style window switcher, opened by tapping Super alone.
// Windows are grouped into ONE ROW PER WORKSPACE (row 1 = Desktop 1, …). You can:
//   · search (top field) to filter windows by title/app,
//   · click a thumbnail (or Enter) to jump to that window,
//   · DRAG a thumbnail into another row to move it to that workspace,
//   · click the ✕ on a thumbnail to close that window.
// The desktop behind is blurred + dimmed; this layer covers the top bar.
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

            readonly property int cardW: 234
            readonly property int cardH: 158

            // ── search field (top-centre) ──
            Rectangle {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 40
                width: 560; height: 50
                radius: Theme.radiusInner
                color: Theme.elevated
                border.color: Theme.accent; border.width: 2
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 18; anchors.rightMargin: 18
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

            // ── workspace rows ──
            Flickable {
                id: flick
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 28
                anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                contentHeight: rowsCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: rowsCol
                    width: Math.min(flick.width - 80, (stage.cardW + 18) * 5)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Repeater {
                        model: root.wsRows
                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            readonly property int ws: modelData.ws
                            readonly property bool isFocused: ws === root.focusedWs
                            width: rowsCol.width
                            height: Math.max(stage.cardH + 56, rowFlow.height + 44)
                            radius: Theme.radius
                            color: dropZone.containsDrag ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                 : isFocused ? Theme.elevated : Qt.rgba(Theme.elevated.r, Theme.elevated.g, Theme.elevated.b, 0.5)
                            border.color: dropZone.containsDrag ? Theme.accent : (isFocused ? Theme.stroke : "transparent")
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.durFast } }

                            // used only for the drag-over highlight (containsDrag); the actual
                            // move is done in the card's onReleased (see note there)
                            DropArea {
                                id: dropZone
                                anchors.fill: parent
                                keys: ["overview-window"]
                            }

                            // row label
                            Row {
                                anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 12
                                spacing: 8
                                Text { text: "Desktop " + rowItem.ws; color: rowItem.isFocused ? Theme.accent : Theme.fgSecondary; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold }
                                Text { visible: rowItem.isFocused; text: "· current"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                            }

                            // empty-row hint (also a drop target)
                            Text {
                                anchors.centerIn: parent
                                visible: rowItem.modelData.wins.length === 0
                                text: "Drop a window here → Desktop " + rowItem.ws
                                color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                            }

                            // window cards
                            Flow {
                                id: rowFlow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.topMargin: 38
                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                spacing: 16

                                Repeater {
                                    model: rowItem.modelData.wins
                                    delegate: MouseArea {
                                        id: dragArea
                                        required property var modelData
                                        property var winRef: modelData
                                        readonly property int flatIdx: root.flat.indexOf(modelData)
                                        readonly property bool seld: flatIdx === root.sel
                                        width: stage.cardW; height: stage.cardH
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: cardContent
                                        drag.smoothed: false
                                        property bool didDrag: false
                                        onPressed: didDrag = false
                                        onPositionChanged: { if (drag.active) didDrag = true; else root.sel = flatIdx }
                                        onClicked: root.jump(modelData)
                                        // Drop is resolved here, not via DropArea.onDropped: the card's
                                        // ParentChange snaps it back the instant the drag ends, racing the
                                        // drop event — so hit-test the cursor against the workspace rows.
                                        onReleased: function (mouse) {
                                            if (!didDrag) return
                                            var p = dragArea.mapToItem(rowsCol, mouse.x, mouse.y)
                                            var rowAt = rowsCol.childAt(p.x, p.y)
                                            if (rowAt && rowAt.ws !== undefined && rowAt.ws >= 1) root.moveWin(modelData, rowAt.ws)
                                        }

                                        Rectangle {
                                            id: cardContent
                                            // explicit size + no anchors — an anchored item can't be dragged
                                            width: dragArea.width
                                            height: dragArea.height
                                            radius: Theme.radius
                                            color: Theme.panel
                                            border.color: dragArea.seld ? Theme.accent : Theme.stroke
                                            border.width: dragArea.seld ? 2 : 1

                                            Drag.active: dragArea.drag.active
                                            Drag.source: dragArea
                                            Drag.hotSpot.x: width / 2
                                            Drag.hotSpot.y: height / 2
                                            Drag.keys: ["overview-window"]

                                            // while dragging, float above the (clipping) Flickable; ParentChange
                                            // saves & restores x/y, so it snaps back into place on release
                                            states: State {
                                                name: "dragging"; when: dragArea.drag.active
                                                ParentChange { target: cardContent; parent: dragLayer }
                                                PropertyChanges { target: cardContent; opacity: 0.9; z: 3000 }
                                            }

                                            Column {
                                                anchors.fill: parent; anchors.margins: 8; spacing: 6
                                                Item {
                                                    width: parent.width; height: parent.height - 28
                                                    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.bg }
                                                    ScreencopyView {
                                                        id: sc
                                                        visible: hasContent && dragArea.modelData.wayland
                                                        captureSource: dragArea.modelData.wayland || null
                                                        live: Globals.overviewOpen && !cardContent.Drag.active
                                                        anchors.centerIn: parent
                                                        property real ar: (sourceSize.width > 0 && sourceSize.height > 0) ? (sourceSize.width / sourceSize.height) : 1.6
                                                        width: (parent.width / parent.height > ar) ? parent.height * ar : parent.width
                                                        height: width / ar
                                                    }
                                                    Image {
                                                        anchors.centerIn: parent; visible: !sc.visible
                                                        width: 48; height: 48; sourceSize.width: 96; sourceSize.height: 96
                                                        source: root.iconFor(dragArea.modelData)
                                                    }
                                                }
                                                Row {
                                                    width: parent.width; spacing: 7
                                                    Image { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; sourceSize.width: 36; sourceSize.height: 36; source: root.iconFor(dragArea.modelData) }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 26
                                                        text: root.titleOf(dragArea.modelData)
                                                        color: dragArea.seld ? Theme.fg : Theme.fgSecondary
                                                        font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                        font.weight: dragArea.seld ? Font.DemiBold : Font.Normal
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // close (✕) — sibling of the card so it's always on top and
                                        // unaffected by the card reparenting during a drag
                                        Rectangle {
                                            id: closeBtn
                                            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 7
                                            z: 50
                                            width: 22; height: 22; radius: 11
                                            visible: !dragArea.drag.active && (dragArea.containsMouse || closeMa.containsMouse)
                                            color: closeMa.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.6)
                                            Text { anchors.centerIn: parent; text: root.g(0xF0156); font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.accentText }
                                            MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.killWin(dragArea.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // floating layer the dragged card reparents into (so it isn't clipped by the Flickable)
            Item { id: dragLayer; anchors.fill: parent; z: 2000 }
        }
    }
}
