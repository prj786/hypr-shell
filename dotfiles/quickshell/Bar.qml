import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// Bar — the macOS-style topbar. One bar per monitor. All colours and fonts are
// pulled from Theme.qml (the single source of truth), solid (no glass).
Scope {
    id: bar

    property bool barVisible: true

    // Colours & fonts come entirely from Theme.qml (single source of truth).
    function g(code) { return String.fromCodePoint(code) }   // Nerd Font glyph (handles MDI > U+FFFF)
    // This Hyprland uses a Lua config: the /dispatch IPC evaluates its argument as Lua
    // (`return hl.dispatch(<arg>)`), so a plain "workspace 3" is invalid. Use the typed
    // hl.dsp.* dispatchers. (exec_raw("workspace N") parses but silently no-ops; and
    // move's silent toggle is follow=false, not silent=true.)
    function goWorkspace(n) { Hyprland.dispatch("hl.dsp.focus({workspace=" + n + "})") }
    function sendToWorkspace(n) { Hyprland.dispatch("hl.dsp.window.move({workspace=" + n + ", follow=false})") }
    function appName() {
        var t = Hyprland.activeToplevel
        // lastIpcObject.class is the richest source but can lag a focus change /
        // be momentarily empty — fall back to the Wayland appId so the label
        // doesn't blank out. Empty only on the true bare desktop.
        var c = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class : ""
        if (!c && t && t.wayland && t.wayland.appId) c = t.wayland.appId
        if (!c) return ""
        var s = c.split('.').pop().split('-')[0]
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    // ── IPC: Super+Shift+B → qs ipc call bar toggle ───────────────────────
    IpcHandler {
        target: "bar"
        function toggle(): void { bar.barVisible = !bar.barVisible }
        function show(): void { bar.barVisible = true }
        function hide(): void { bar.barVisible = false }
    }

    // ── clock (shared, 12-hour like the old waybar) ───────────────────────
    property string clockText: ""
    function updateClock() { bar.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM   hh:mm AP") }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: bar.updateClock() }

    // ── nmcli polls: VPN active → Globals.vpnActive, Wi-Fi connected → wifiUp ──
    property bool wifiUp: false
    Process {
        id: vpnProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE connection show --active 2>/dev/null | awk -F: '($1 ~ /vpn|wireguard|tun/) && $2==\"activated\"{print \"yes\"; exit}'"]
        stdout: StdioCollector { onStreamFinished: Globals.vpnActive = (this.text.trim() === "yes") }
    }
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1==\"wifi\" && $2==\"connected\"{print \"yes\"; exit}'"]
        stdout: StdioCollector { onStreamFinished: bar.wifiUp = (this.text.trim() === "yes") }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { vpnProc.running = true; wifiProc.running = true; kbProc.running = true } }

    // ── keyboard layout indicator (US ↔ GE) ───────────────────────────────
    property string kbLayout: "US"
    property string kbDevice: ""
    function shortLayout(name) {
        var n = (name || "").toLowerCase()
        if (n.indexOf("georg") >= 0) return "GE"
        if (n.indexOf("english") >= 0 || n.indexOf("us") >= 0) return "US"
        return (name || "??").slice(0, 2).toUpperCase()
    }
    Process {
        id: kbProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text), kbs = d.keyboards || []
                    for (var i = 0; i < kbs.length; i++) {
                        if (kbs[i].main) { bar.kbDevice = kbs[i].name; bar.kbLayout = bar.shortLayout(kbs[i].active_keymap); break }
                    }
                } catch (e) {}
            }
        }
    }
    // live update: Hyprland emits `activelayout>>keyboard,LayoutName` on every switch
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                var p = event.data.split(",")
                bar.kbLayout = bar.shortLayout(p[p.length - 1])
            }
        }
    }

    function wsOccupied(id) {
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) if (ws[i].id === id) return true
        return false
    }

    // Dynamic workspace count: 1 … (highest used or focused) + 1, capped at 10.
    property int wsCount: {
        var mx = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ? Hyprland.focusedWorkspace.id : 1
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) { var id = ws[i].id; if (id > 0 && id < 100 && id > mx) mx = id }
        return Math.min(10, mx + 1)
    }

    // ── a status glyph button: no hover box, just a pointer cursor and a
    //    full-bar-height click target (only the control-centre group highlights). ──
    component StatusItem: Item {
        id: si
        property string glyph: ""
        property color fg: Theme.fgSecondary
        property int fontPx: 15
        signal activated()
        signal secondary()
        signal tertiary()
        signal scrolled(real dy)
        implicitWidth: lbl.implicitWidth + 18
        height: parent ? parent.height : 30
        Text {
            id: lbl
            anchors.centerIn: parent
            text: si.glyph
            color: si.fg
            font.family: Theme.fontMono
            font.pixelSize: si.fontPx
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: function (m) {
                if (m.button === Qt.RightButton) si.secondary()
                else if (m.button === Qt.LeftButton) si.activated()
            }
            // middle-click fires on press — onClicked is unreliable for the
            // middle button (wheel-press / trackpad taps often aren't "clicks").
            onPressed: function (m) {
                if (m.button === Qt.MiddleButton) si.tertiary()
            }
            onWheel: function (w) { si.scrolled(w.angleDelta.y) }
        }
    }

    // ── one bar per monitor ───────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: bar.barVisible
            color: "transparent"
            implicitHeight: 30
            exclusiveZone: bar.barVisible ? 30 : 0
            WlrLayershell.namespace: "quickshell:bar"
            anchors { top: true; left: true; right: true }

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.stroke
                }

                // ── LEFT: "Search…" affordance + focused window title ──
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: parent.height
                        Text {
                            id: searchLbl
                            anchors.centerIn: parent
                            text: bar.g(0xF002)        //
                            color: Theme.fgSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: searchMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "spotlight", "toggle"])
                        }
                    }
                    // bold app name → app menu (macOS ⌘-menu equivalent)
                    Item {
                        id: appNameItem
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bar.appName() !== ""
                        width: appRow.implicitWidth + 14
                        height: parent.height
                        Rectangle { anchors.centerIn: parent; width: parent.width; height: 22; radius: 7; color: Globals.appMenuOpen ? Theme.hover : "transparent" }
                        Row {
                            id: appRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { anchors.verticalCenter: parent.verticalCenter; text: bar.appName(); color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 13; font.weight: Font.Bold }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: bar.g(0xF078); font.family: Theme.fontMono; font.pixelSize: 8; color: Theme.fgSecondary }
                        }
                        MouseArea {
                            id: appMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Globals.appAnchorX = appNameItem.mapToItem(null, 0, 0).x; Globals.appMenuOpen = !Globals.appMenuOpen }
                        }
                    }
                    // window title (dim, secondary)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Hyprland.activeToplevel && Hyprland.activeToplevel.title ? Hyprland.activeToplevel.title : ""
                        color: Theme.fgDim
                        font.family: Theme.fontText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 420)
                    }
                }

                // (Workspace switching moved to the bottom dock — no centre module here.)

                // ── RIGHT: status cluster ──
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    // system tray
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 11
                        Repeater {
                            model: SystemTray.items
                            delegate: Item {
                                required property var modelData
                                width: 18; height: win.height
                                Image {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: modelData.icon
                                    sourceSize.width: 32; sourceSize.height: 32
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function (m) {
                                        if (m.button === Qt.RightButton) modelData.secondaryActivate()
                                        else modelData.activate()
                                    }
                                }
                            }
                        }
                    }

                    // clipboard history + emoji picker (scissors) — opens its popup
                    StatusItem {
                        id: scissorsItem
                        glyph: bar.g(0xF0C4)        // scissors
                        fg: Globals.clipboardOpen ? Theme.fg : Theme.fgSecondary
                        fontPx: 14
                        onActivated: { Globals.clipAnchorX = scissorsItem.mapToItem(null, scissorsItem.width / 2, 0).x; Globals.clipboardOpen = !Globals.clipboardOpen }
                    }

                    // screenshot (camera) — Left: region · Right: whole screen · Middle: a window
                    StatusItem {
                        glyph: bar.g(0xF030)        // camera
                        fontPx: 14
                        onActivated: Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" region"])
                        onSecondary: Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" full"])
                        onTertiary:  Quickshell.execDetached(["sh", "-c", "\"$HOME/.config/hypr/scripts/screenshot.sh\" activewindow"])
                    }

                    // keyboard layout — plain text (US / GE); click cycles the layout
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: kbLbl.implicitWidth + 16
                        height: parent.height
                        Text {
                            id: kbLbl
                            anchors.centerIn: parent
                            text: bar.kbLayout
                            color: Theme.fgSecondary
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", bar.kbDevice || "current", "next"])
                        }
                    }

                    // ── ONE wide Control-Centre button: active services + battery.
                    // Hovering highlights the whole group; click opens the sidebar.
                    Rectangle {
                        id: ctlGroup
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        radius: 8
                        width: ctlRow.implicitWidth + 18
                        color: (ctlMa.containsMouse || Globals.controlOpen) ? Theme.hover : "transparent"

                        Row {
                            id: ctlRow
                            anchors.centerIn: parent
                            spacing: 9

                            // RunCat — runs faster under CPU load, sleeps when idle
                            RunCat { anchors.verticalCenter: parent.verticalCenter }

                            // Wi-Fi (only when connected)
                            Text {
                                visible: bar.wifiUp
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.g(0xF1EB)
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.fgSecondary
                            }
                            // Bluetooth (only when adapter on); blue when a device is connected
                            Text {
                                property var adapter: Bluetooth.defaultAdapter
                                property int conn: {
                                    if (!Bluetooth.devices) return 0
                                    var d = Bluetooth.devices.values, n = 0
                                    for (var i = 0; i < d.length; i++) if (d[i].connected) n++
                                    return n
                                }
                                visible: adapter && adapter.enabled
                                anchors.verticalCenter: parent.verticalCenter
                                text: conn > 0 ? bar.g(0xF294) : bar.g(0xF293)
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: conn > 0 ? Theme.accent : Theme.fgSecondary
                            }
                            // VPN (only when active)
                            Text {
                                visible: Globals.vpnActive
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.g(0xF0582)
                                font.family: Theme.fontMono; font.pixelSize: 14
                                color: Theme.success
                            }
                            // Caffeine (only when keep-awake is on)
                            Text {
                                visible: Globals.caffeine
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.g(0xF0176)
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: Theme.warning
                            }
                            // Power profile (leaf · balance · speedometer) — reflects tuned profile
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: PowerProfiles.profile === PowerProfile.PowerSaver ? bar.g(0xF032A)
                                    : PowerProfiles.profile === PowerProfile.Performance ? bar.g(0xF04C5)
                                    : bar.g(0xF05D1)
                                font.family: Theme.fontMono; font.pixelSize: 13
                                color: PowerProfiles.profile === PowerProfile.Performance ? Theme.warning
                                     : PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.success
                                     : Theme.fgSecondary
                            }
                            // Battery — icon + always-on percentage
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                property var dev: UPower.displayDevice
                                property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                                property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                                visible: dev && dev.isLaptopBattery
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.charging ? bar.g(0xF0E7)
                                        : parent.pct >= 80 ? bar.g(0xF240)
                                        : parent.pct >= 60 ? bar.g(0xF241)
                                        : parent.pct >= 40 ? bar.g(0xF242)
                                        : parent.pct >= 20 ? bar.g(0xF243)
                                        : bar.g(0xF244)
                                    font.family: Theme.fontMono; font.pixelSize: 13
                                    color: parent.charging ? Theme.success : (parent.pct <= 10 ? Theme.danger : (parent.pct <= 20 ? Theme.warning : Theme.fgSecondary))
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(parent.pct) + "%"
                                    font.family: Theme.fontText; font.pixelSize: 12
                                    color: Theme.fgSecondary
                                }
                            }
                            // thin separator, then the clock — all one button
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 13; color: Theme.fgSecondary; opacity: 0.25 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar.clockText
                                color: Theme.fg
                                font.family: Theme.fontText
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: ctlMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Globals.controlOpen = !Globals.controlOpen
                        }
                    }
                }
            }
        }
    }
}
