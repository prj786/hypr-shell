import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// AppMenu — the macOS ⌘-menu equivalent. Clicking the bold app name in the bar
// drops this down: window/app actions driven by Hyprland dispatchers (works for
// every app, since it's compositor-driven — not the app's own File/Edit menus,
// which Wayland/Hyprland can't expose).
Scope {
    id: root

    // all colours come from Theme.qml (single source of truth)
    function g(c) { return String.fromCodePoint(c) }

    readonly property var top: Hyprland.activeToplevel
    function appClass() { return (top && top.lastIpcObject) ? (top.lastIpcObject.class || "") : "" }
    function appName() {
        var c = appClass()
        if (!c) return "Desktop"
        var s = c.split('.').pop().split('-')[0]
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    // Lua config: /dispatch evaluates its arg as Lua, so callers pass a typed
    // hl.dsp.* dispatcher expression (a plain "fullscreen 0" would be invalid Lua).
    function act(expr) { Hyprland.dispatch(expr); Globals.appMenuOpen = false }
    function newWindow() {
        var e = DesktopEntries.heuristicLookup(appClass())
        if (e) e.execute()
        Globals.appMenuOpen = false
    }

    property bool wsExpanded: false
    property int wsCount: {
        var mx = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ? Hyprland.focusedWorkspace.id : 1
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) { var id = ws[i].id; if (id > 0 && id < 100 && id > mx) mx = id }
        return Math.min(10, mx + 1)
    }

    // ── a menu row ──
    component MenuItem: Rectangle {
        id: mi
        property string label: ""
        property string shortcut: ""
        property bool danger: false
        property bool expander: false
        signal triggered()
        width: parent ? parent.width : 220
        height: 30
        radius: 7
        color: miMa.containsMouse ? (danger ? Theme.danger : Theme.accent) : "transparent"
        Text {
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: mi.label
            color: miMa.containsMouse ? Theme.accentText : (mi.danger ? Theme.danger : Theme.fg)
            font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            text: mi.expander ? root.g(0xF078) : mi.shortcut
            visible: text !== ""
            color: miMa.containsMouse ? Theme.accentText : Theme.fgDim
            font.family: mi.expander ? Theme.fontMono : Theme.fontText
            font.pixelSize: mi.expander ? 8 : 10
        }
        MouseArea { id: miMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mi.triggered() }
    }

    PanelWindow {
        id: win
        visible: Globals.appMenuOpen || closeTimer.running
        screen: {
            var s = Quickshell.screens, fm = Hyprland.focusedMonitor
            if (fm) for (var i = 0; i < s.length; i++) if (s[i].name === fm.name) return s[i]
            return s.length > 0 ? s[0] : null
        }
        color: "transparent"
        // Ignore (not exclusiveZone:0): span the FULL output, including under the
        // bar, so clicking the topbar also closes the menu (true toggle).
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:appmenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: 200 }
        Connections {
            target: Globals
            function onAppMenuOpenChanged() {
                if (Globals.appMenuOpen) keyCatcher.forceActiveFocus()
                else { closeTimer.restart(); root.wsExpanded = false }
            }
        }

        MouseArea { anchors.fill: parent; onClicked: Globals.appMenuOpen = false }
        Item { id: keyCatcher; anchors.fill: parent; focus: true; Keys.onEscapePressed: Globals.appMenuOpen = false }

        // clip box pinned to the bar's bottom edge, positioned under the app name;
        // the menu slides down out of it (reads as part of the topbar).
        Item {
            id: clipBox
            x: Math.max(8, Math.min(Globals.appAnchorX, win.width - width - 8))
            anchors.top: parent.top
            anchors.topMargin: 30          // window now spans full output → offset by the bar height
            width: 240
            height: menu.height
            clip: true

            Rectangle {
                id: menu
                width: parent.width
                height: col.implicitHeight + 12
                y: Globals.appMenuOpen ? 0 : -height
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                // square top (flush with the bar), rounded bottom
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 12
                bottomRightRadius: 12
                color: Theme.panel
                border.width: 0
                MouseArea { anchors.fill: parent }   // swallow

            Column {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 6
                spacing: 1

                // app name header
                Text {
                    leftPadding: 10; topPadding: 4; bottomPadding: 4
                    text: root.appName()
                    color: Theme.accent
                    font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold
                }
                Rectangle { width: parent.width; height: 1; color: Theme.stroke }

                MenuItem { label: "New Window"; onTriggered: root.newWindow() }
                MenuItem { label: "Fullscreen"; shortcut: "Super+F"; onTriggered: root.act("hl.dsp.window.fullscreen({mode=0})") }
                MenuItem { label: "Toggle Float"; shortcut: "Super+V"; onTriggered: root.act('hl.dsp.window.float({action="toggle"})') }
                MenuItem { label: "Pin (all spaces)"; onTriggered: root.act("hl.dsp.window.pin()") }
                MenuItem { label: "Center"; onTriggered: root.act("hl.dsp.window.center()") }
                MenuItem { label: "Move to workspace"; expander: true; onTriggered: root.wsExpanded = !root.wsExpanded }

                // workspace chips (inline submenu)
                Flow {
                    width: parent.width
                    spacing: 4
                    visible: root.wsExpanded
                    leftPadding: 10; topPadding: 4; bottomPadding: 4
                    Repeater {
                        model: root.wsCount
                        delegate: Rectangle {
                            required property int index
                            readonly property int wsId: index + 1
                            width: 26; height: 24; radius: 6
                            color: chipMa.containsMouse ? Theme.accent : Theme.elevated
                            Text { anchors.centerIn: parent; text: parent.wsId; color: chipMa.containsMouse ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 12 }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act("hl.dsp.window.move({workspace=" + parent.wsId + ", follow=false})") }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.stroke }
                MenuItem { label: "Quit"; shortcut: "Super+Q"; danger: true; onTriggered: root.act("hl.dsp.window.close()") }
            }
            }
        }
    }
}
