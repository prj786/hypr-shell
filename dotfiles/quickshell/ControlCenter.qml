import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// ControlCenter — full-height macOS-style sidebar, slides in from the right.
// Layout: header · quick-toggle grid (Wi-Fi/Bluetooth/VPN/DND, each expands its
// own section) · brightness+volume sliders + audio output · media · calendar ·
// notifications.
Scope {
    id: root

    // all colours come from Theme.qml (single source of truth)
    function g(c) { return String.fromCodePoint(c) }   // handles MDI glyphs > U+FFFF

    // calendar
    property var today: new Date()
    property int calYear:  today.getFullYear()
    property int calMonth: today.getMonth()
    property int calDate:  today.getDate()
    readonly property int firstW: new Date(calYear, calMonth, 1).getDay()
    readonly property int daysIn: new Date(calYear, calMonth + 1, 0).getDate()
    readonly property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]

    // which tile's section is expanded: "" | "wifi" | "bt" | "vpn"
    property string expanded: ""

    // wifi
    property var wifiList: []
    property bool wifiOn: true
    property bool wiredUp: false   // a wired (ethernet) link is the active connection
    property string pwTarget: ""
    property string pwText: ""
    function curSsid() { for (var i = 0; i < wifiList.length; i++) if (wifiList[i].active) return wifiList[i].ssid; return "" }

    // vpn
    property var vpnList: []

    // sliders (0..1), read on open, updated optimistically on drag
    property real brightnessVal: 0.5
    property real volumeVal: 0.5
    property bool audioExpanded: false

    // power menu (floating popover). Power profiles come from the PowerProfiles
    // service, which talks to the net.hadess.PowerProfiles D-Bus iface — provided
    // here by tuned-ppd (Fedora's tuned bridge), so no powerprofilesctl needed.
    property bool powerOpen: false

    function refresh() {
        var d = new Date()
        root.today = d; root.calYear = d.getFullYear(); root.calMonth = d.getMonth(); root.calDate = d.getDate()
        wifiState.running = true; wiredState.running = true; brightnessProc.running = true; volumeProc.running = true
        if (root.expanded === "wifi") wifiScan.running = true
        if (root.expanded === "vpn") vpnScan.running = true
    }
    function clearAll() {
        if (!Globals.server) return
        var v = Globals.server.trackedNotifications.values.slice()
        for (var i = 0; i < v.length; i++) v[i].dismiss()
    }
    function connectWifi(ssid, sec) {
        if (sec && sec !== "" && root.pwText === "") {
            root.pwTarget = (root.pwTarget === ssid) ? "" : ssid   // toggle the password field
            return
        }
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (root.pwText !== "") cmd = cmd.concat(["password", root.pwText])
        Quickshell.execDetached(cmd); root.pwTarget = ""; root.pwText = ""; rescanTimer.restart()
    }
    property string vpnPending: ""
    function toggleVpn(name, up) {
        root.vpnPending = (up ? "Connecting to " : "Disconnecting from ") + name
        vpnUpProc.command = ["nmcli", "connection", up ? "up" : "down", name]
        vpnUpProc.running = true
    }
    function setBrightness(v) { root.brightnessVal = v; Quickshell.execDetached(["brightnessctl", "set", Math.round(v * 100) + "%"]) }
    function setVolume(v) { root.volumeVal = v; Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", Math.round(v * 100) + "%"]) }
    // fire a power action, then collapse the popup + control centre
    function powerAction(cmd) { Quickshell.execDetached(cmd); root.powerOpen = false; Globals.controlOpen = false }

    Connections { target: Globals; function onControlOpenChanged() { if (Globals.controlOpen) root.refresh() } }
    IpcHandler {
        target: "control"
        function toggle(): void { Globals.controlOpen = !Globals.controlOpen }
        function show(): void { Globals.controlOpen = true }
        function hide(): void { Globals.controlOpen = false }
    }

    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), seen = {}, arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split(":")
                    var ssid = p.slice(3).join(":")
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    arr.push({ ssid: ssid, signal: parseInt(p[1]) || 0, sec: p[2] || "", active: p[0] === "*" })
                }
                arr.sort(function (a, b) { return (b.active - a.active) || (b.signal - a.signal) })
                root.wifiList = arr
            }
        }
    }
    Process { id: wifiState; command: ["nmcli", "-t", "-f", "WIFI", "radio"]; stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" } }
    Process { id: wiredState; command: ["sh", "-c", "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print \"yes\"; exit}'"]; stdout: StdioCollector { onStreamFinished: root.wiredUp = this.text.trim() === "yes" } }
    Process {
        id: vpnScan
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), arr = []
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue
                    var p = lines[i].split(":")
                    var type = p[p.length - 2], active = p[p.length - 1] === "yes"
                    var name = p.slice(0, p.length - 2).join(":")
                    if (type && (type.indexOf("vpn") >= 0 || type.indexOf("wireguard") >= 0 || type.indexOf("tun") >= 0))
                        arr.push({ name: name, active: active })
                }
                root.vpnList = arr
            }
        }
    }
    Process { id: brightnessProc; command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]; stdout: StdioCollector { onStreamFinished: { var n = parseInt(this.text.trim()); if (!isNaN(n)) root.brightnessVal = n / 100 } } }
    Process { id: volumeProc; command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+'"]; stdout: StdioCollector { onStreamFinished: { var f = parseFloat(this.text.trim()); if (!isNaN(f)) root.volumeVal = Math.min(1, f) } } }
    Timer { id: rescanTimer; interval: 2500; onTriggered: { wifiState.running = true; wifiScan.running = true } }
    Timer { id: vpnRescan; interval: 2000; onTriggered: vpnScan.running = true }
    // brings a VPN up/down; on failure raises a system notification with the error
    Process {
        id: vpnUpProc
        stderr: StdioCollector { id: vpnErr }
        onExited: function (exitCode, exitStatus) {
            vpnRescan.restart()
            if (exitCode !== 0) {
                var msg = (vpnErr.text || "").trim()
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "VPN", root.vpnPending + " failed", msg !== "" ? msg : ("nmcli exited with code " + exitCode)])
            }
        }
    }
    Timer { interval: 6000; running: true; repeat: true; onTriggered: { if (!Globals.controlOpen) return; wifiState.running = true; wiredState.running = true; if (root.expanded === "wifi") wifiScan.running = true } }

    PanelWindow {
        id: win
        visible: Globals.controlOpen || closeTimer.running
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:control"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: 320 }
        Connections { target: Globals; function onControlOpenChanged() { if (!Globals.controlOpen) { closeTimer.restart(); root.powerOpen = false } } }
        MouseArea { anchors.fill: parent; onClicked: Globals.controlOpen = false }

        Rectangle {
            id: panel
            width: 380
            y: 10                              // equal gap top & bottom (matches the 10px right inset)
            height: parent.height - 20
            radius: Theme.radius
            color: Theme.panel
            border.color: Theme.stroke
            border.width: 1
            clip: true
            property real off: Globals.controlOpen ? 0 : (width + 60)
            x: parent.width - width - 10 + off
            Behavior on off { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            // catches Esc to close (control centre is otherwise mouse-driven)
            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: { if (root.powerOpen) root.powerOpen = false; else Globals.controlOpen = false }
            }
            Connections {
                target: Globals
                function onControlOpenChanged() { if (Globals.controlOpen) keyCatcher.forceActiveFocus() }
            }

            // ── round close button (centered MDI glyph) ──
            component CloseBtn: Rectangle {
                id: cb
                signal pressed()
                width: 22; height: 22; radius: 11
                color: cbMa.containsMouse ? Theme.hover : Theme.elevated
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: root.g(0xF0156); font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.fg }
                MouseArea { id: cbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cb.pressed() }
            }

            // ── a row in the power popover ──
            component PowerItem: Rectangle {
                id: pit
                property int ic: 0
                property string label: ""
                property bool danger: false
                signal go()
                width: parent ? parent.width : 200
                height: 32
                radius: 9
                color: pitMa.containsMouse ? (danger ? Theme.danger : Theme.accent) : "transparent"
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter; spacing: 11
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 16; text: root.g(pit.ic); font.family: Theme.fontMono; font.pixelSize: 14; color: pitMa.containsMouse ? Theme.accentText : (pit.danger ? Theme.danger : Theme.fg) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: pit.label; color: pitMa.containsMouse ? Theme.accentText : (pit.danger ? Theme.danger : Theme.fg); font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.Medium }
                }
                MouseArea { id: pitMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pit.go() }
            }

            // ── quick-toggle tile ──
            component Tile: Rectangle {
                id: tile
                property string ic: ""
                property string label: ""
                property string sub: ""
                property bool active: false
                signal clicked()
                width: (inner.width - 10) / 2
                height: 62
                radius: Theme.radiusInner
                color: active ? Theme.accent : Theme.elevated
                Behavior on color { ColorAnimation { duration: 150 } }
                Column {
                    anchors.fill: parent; anchors.margins: 11; spacing: 5
                    Text { text: tile.ic; font.family: Theme.fontMono; font.pixelSize: 17; color: tile.active ? Theme.accentText : Theme.fg }
                    Text { width: parent.width; text: tile.label; color: tile.active ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 11; text: tile.sub; color: tile.active ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; elide: Text.ElideRight }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
            }

            // ── slider ──
            component Slider: Item {
                id: sld
                property string icon: ""
                property real value: 0
                signal moved(real v)
                height: 26
                Text { id: sIco; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 20; text: sld.icon; font.family: Theme.fontMono; font.pixelSize: 14; color: Theme.fgDim }
                Rectangle {
                    id: trk
                    anchors.left: sIco.right; anchors.leftMargin: 8; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 8; radius: 4; color: Theme.hover
                    Rectangle { height: parent.height; radius: 4; width: parent.width * Math.max(0, Math.min(1, sld.value)); color: Theme.accent }
                    Rectangle { width: 14; height: 14; radius: 7; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: Math.max(0, Math.min(trk.width - width, trk.width * sld.value - width / 2)) }
                    MouseArea {
                        anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                        onPressed: function (m) { sld.moved(Math.max(0, Math.min(1, m.x / trk.width))) }
                        onPositionChanged: function (m) { if (pressed) sld.moved(Math.max(0, Math.min(1, m.x / trk.width))) }
                    }
                }
            }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: inner.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: inner
                    width: flick.width
                    spacing: 13

                    // ── header: date + battery ──
                    Item {
                        width: parent.width; height: hdr.implicitHeight
                        Column {
                            id: hdr
                            spacing: 0
                            Text { text: Qt.formatDateTime(root.today, "dddd"); color: Theme.accent; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold }
                            Text { text: Qt.formatDateTime(root.today, "d MMMM"); color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: hdr.verticalCenter; spacing: 10
                            // battery (only on a laptop)
                            Row {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                                property var dev: UPower.displayDevice
                                property real pct: dev ? (dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                                property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                                Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(parent.pct) + "%"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.charging ? root.g(0xF0E7) : (parent.pct >= 60 ? root.g(0xF240) : parent.pct >= 30 ? root.g(0xF242) : root.g(0xF244)); font.family: Theme.fontMono; font.pixelSize: 13; color: parent.charging ? Theme.success : (parent.pct <= 15 ? Theme.danger : Theme.fgDim) }
                            }
                            // settings gear → opens the Settings window
                            Rectangle {
                                id: gearBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 14
                                color: gbMa.containsMouse ? Theme.hover : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: root.g(0xF0493); font.family: Theme.fontMono; font.pixelSize: 15; color: Theme.fg }
                                MouseArea { id: gbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Globals.controlOpen = false; Globals.settingsOpen = true } }
                            }
                            // power button → opens the floating power menu
                            Rectangle {
                                id: powerBtn
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 14
                                color: (pbMa.containsMouse || root.powerOpen) ? Theme.hover : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: root.g(0xF0425); font.family: Theme.fontMono; font.pixelSize: 15; color: root.powerOpen ? Theme.accent : Theme.fg }
                                MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.powerOpen = !root.powerOpen }
                            }
                        }
                    }

                    // ── quick-toggle grid ──
                    Grid {
                        width: parent.width; columns: 2; spacing: 10
                        Tile {
                            // adapts to the live link: shows the wired/ethernet glyph + "Wired"
                            // when a cable is the active connection and Wi-Fi isn't (e.g. VMs).
                            readonly property bool onWired: root.wiredUp && root.curSsid() === ""
                            ic: onWired ? root.g(0xF0200) : root.g(0xF1EB)   // mdi-ethernet : wifi
                            label: onWired ? "Network" : "Wi-Fi"; active: root.expanded === "wifi"
                            sub: root.curSsid() !== "" ? root.curSsid() : (onWired ? "Wired" : (root.wifiOn ? "On" : "Off"))
                            onClicked: { root.expanded = root.expanded === "wifi" ? "" : "wifi"; if (root.expanded === "wifi") wifiScan.running = true }
                        }
                        Tile {
                            ic: root.g(0xF293); label: "Bluetooth"; active: root.expanded === "bt"
                            sub: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) ? "On" : "Off"
                            onClicked: {
                                root.expanded = root.expanded === "bt" ? "" : "bt"
                                if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = (root.expanded === "bt")
                            }
                        }
                        Tile {
                            ic: root.g(0xF0582); label: "VPN"; active: Globals.vpnActive || root.expanded === "vpn"
                            sub: Globals.vpnActive ? "On" : "Off"
                            onClicked: { root.expanded = root.expanded === "vpn" ? "" : "vpn"; if (root.expanded === "vpn") vpnScan.running = true }
                        }
                        Tile {
                            ic: root.g(0xF186); label: "Do Not Disturb"; active: Globals.dnd
                            sub: Globals.dnd ? "On" : "Off"
                            onClicked: Globals.dnd = !Globals.dnd
                        }
                        Tile {
                            ic: root.g(0xF0176); label: "Caffeine"; active: Globals.caffeine
                            sub: Globals.caffeine ? "Awake" : "Off"
                            onClicked: Globals.caffeine = !Globals.caffeine
                        }
                    }

                    // ── expanded detail (wifi / bt / vpn) ──
                    Rectangle {
                        width: parent.width
                        visible: root.expanded !== ""
                        height: visible ? detailCol.implicitHeight + 20 : 0
                        radius: Theme.radiusInner
                        color: Theme.elevated
                        Column {
                            id: detailCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                            spacing: 4

                            // WIFI
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "wifi"
                                Item {
                                    width: parent.width; height: 26
                                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11; color: root.wifiOn ? Theme.accent : Theme.hover
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Rectangle { width: 18; height: 18; radius: 9; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: root.wifiOn ? parent.width-width-2 : 2; Behavior on x { NumberAnimation { duration: 150 } } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["nmcli","radio","wifi", root.wifiOn ? "off" : "on"]); rescanTimer.restart() } }
                                    }
                                }
                                Repeater {
                                    model: root.wifiOn ? root.wifiList : []
                                    delegate: Column {
                                        required property var modelData
                                        width: detailCol.width
                                        Item {
                                            width: parent.width; height: 30
                                            Rectangle { anchors.fill: parent; radius: 7; color: wMa.containsMouse ? Theme.hover : "transparent" }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: modelData.signal >= 66 ? root.g(0xF0925) : (modelData.signal >= 33 ? root.g(0xF0922) : root.g(0xF091F)); font.family: Theme.fontMono; font.pixelSize: 13; color: modelData.active ? Theme.accent : Theme.fgDim }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 28; anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                            Text { anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; visible: modelData.sec !== ""; text: root.g(0xF023); font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.fgDim }
                                            MouseArea { id: wMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) }
                                        }
                                        Item {
                                            width: parent.width; height: visible ? 34 : 0; visible: root.pwTarget === modelData.ssid
                                            Rectangle {
                                                anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 4; radius: 7; color: Theme.bg; border.color: Theme.accent; border.width: 1
                                                TextInput {
                                                    id: pwInput
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 56; verticalAlignment: TextInput.AlignVCenter
                                                    echoMode: TextInput.Password; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                                    onTextChanged: root.pwText = text
                                                    Component.onCompleted: if (root.pwTarget === modelData.ssid) forceActiveFocus()
                                                    onAccepted: root.connectWifi(modelData.ssid, modelData.sec)
                                                    Keys.onEscapePressed: Globals.controlOpen = false
                                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: pwInput.text.length === 0; text: "Password"; color: Theme.fgDim; font: pwInput.font }
                                                }
                                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Join"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.sec) } }
                                            }
                                        }
                                    }
                                }
                            }

                            // BLUETOOTH
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "bt"
                                Item {
                                    width: parent.width; height: 26
                                    property var adapter: Bluetooth.defaultAdapter
                                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: (parent.adapter && parent.adapter.discovering) ? "Bluetooth · searching…" : "Bluetooth"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11
                                        readonly property bool on: parent.adapter ? parent.adapter.enabled : false
                                        color: on ? Theme.accent : Theme.hover
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Rectangle { width: 18; height: 18; radius: 9; color: "white"; anchors.verticalCenter: parent.verticalCenter; x: parent.on ? parent.width-width-2 : 2; Behavior on x { NumberAnimation { duration: 150 } } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (parent.parent.adapter) parent.parent.adapter.enabled = !parent.parent.adapter.enabled }
                                    }
                                }
                                Repeater {
                                    model: Bluetooth.devices ? Bluetooth.devices.values : []
                                    delegate: Item {
                                        required property var modelData
                                        visible: modelData.paired || modelData.connected || (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)
                                        width: detailCol.width; height: visible ? 30 : 0
                                        Rectangle { anchors.fill: parent; radius: 7; color: bMa.containsMouse ? Theme.hover : "transparent" }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: root.g(modelData.connected ? 0xF294 : 0xF293); font.family: Theme.fontMono; font.pixelSize: 12; color: modelData.connected ? Theme.accent : Theme.fgDim }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 26; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (modelData.name || modelData.deviceName || modelData.address) + (modelData.connected ? "  ·  connected" : (modelData.paired ? "" : "  ·  new")); color: modelData.connected ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.connected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                        MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: modelData.connected ? modelData.disconnect() : (modelData.paired ? modelData.connect() : modelData.pair()) }
                                    }
                                }
                            }

                            // VPN
                            Column {
                                width: parent.width; spacing: 2; visible: root.expanded === "vpn"
                                Text { text: "VPN"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; bottomPadding: 4 }
                                Text { width: parent.width; visible: root.vpnList.length === 0; text: "No VPN connections configured."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap }
                                Repeater {
                                    model: root.vpnList
                                    delegate: Item {
                                        required property var modelData
                                        width: detailCol.width; height: 30
                                        Rectangle { anchors.fill: parent; radius: 7; color: vMa.containsMouse ? Theme.hover : "transparent" }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0582); font.family: Theme.fontMono; font.pixelSize: 12; color: modelData.active ? Theme.accent : Theme.fgDim }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 26; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.name + (modelData.active ? "  ·  connected" : ""); color: modelData.active ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight }
                                        MouseArea { id: vMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleVpn(modelData.name, !modelData.active) }
                                    }
                                }
                            }
                        }
                    }

                    // ── sliders + audio output ──
                    Rectangle {
                        width: parent.width; height: sCol.implicitHeight + 24; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: sCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 12
                            Slider { width: parent.width; icon: root.g(0xF185); value: root.brightnessVal; onMoved: function (v) { root.setBrightness(v) } }
                            Item {
                                width: parent.width; height: 26
                                Slider { id: volSlider; anchors.left: parent.left; anchors.right: outBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; icon: root.g(0xF028); value: root.volumeVal; onMoved: function (v) { root.setVolume(v) } }
                                Text { id: outBtn; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.g(root.audioExpanded ? 0xF077 : 0xF078); font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.fgDim; MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.audioExpanded = !root.audioExpanded } }
                            }
                            Column {
                                width: parent.width; spacing: 2; visible: root.audioExpanded
                                Repeater {
                                    model: {
                                        var out = [], n = Pipewire.nodes.values
                                        for (var i = 0; i < n.length; i++) { var x = n[i]; if (x.isSink && !x.isStream && x.audio) out.push(x) }
                                        return out
                                    }
                                    delegate: Item {
                                        required property var modelData
                                        readonly property bool cur: Pipewire.defaultAudioSink === modelData
                                        width: sCol.width; height: 28
                                        Rectangle { anchors.fill: parent; radius: 7; color: aMa.containsMouse ? Theme.hover : "transparent" }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: root.g(parent.cur ? 0xF058 : 0xF111); font.family: Theme.fontMono; font.pixelSize: 12; color: parent.cur ? Theme.accent : Theme.fgDim }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 26; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.description || modelData.nickname || modelData.name; color: parent.cur ? Theme.accent : Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                                        MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
                                    }
                                }
                            }
                        }
                    }

                    // ── system load (CPU + memory; RunCat reads the same CPU value) ──
                    Rectangle {
                        width: parent.width; height: sysCol.implicitHeight + 24; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: sysCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 10
                            // a labelled meter row
                            component Meter: Column {
                                property string label: ""; property real value: 0; property string glyph: ""
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Row { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: glyph; font.family: Theme.fontMono; font.pixelSize: 13; color: Theme.fgDim }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: label; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                                    }
                                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.round(value * 100) + "%"; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                                }
                                Rectangle { width: parent.width; height: 6; radius: 3; color: Theme.hover
                                    Rectangle { height: parent.height; radius: 3; width: parent.width * Math.max(0, Math.min(1, value)); color: value > 0.85 ? Theme.danger : (value > 0.6 ? Theme.warning : Theme.accent); Behavior on width { NumberAnimation { duration: 400 } } }
                                }
                            }
                            Meter { label: "CPU"; glyph: root.g(0xF0EE0); value: Globals.cpuUsage }
                            Meter { label: "Memory"; glyph: root.g(0xF035B); value: Globals.memUsage }
                        }
                    }

                    // ── media (MPRIS) ──
                    Rectangle {
                        property var player: {
                            var ps = Mpris.players.values
                            for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
                            return ps.length > 0 ? ps[0] : null
                        }
                        visible: player !== null
                        width: parent.width; height: visible ? mediaRow.implicitHeight + 24 : 0; radius: Theme.radiusInner; color: Theme.elevated
                        Row {
                            id: mediaRow
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            Rectangle {
                                width: 48; height: 48; radius: 8; color: Theme.elevated; clip: true
                                Image { id: art; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: parent.parent.parent.player && parent.parent.parent.player.trackArtUrl ? parent.parent.parent.player.trackArtUrl : ""; visible: source != "" }
                                Text { anchors.centerIn: parent; visible: art.source == ""; text: root.g(0xF001); font.family: Theme.fontMono; font.pixelSize: 18; color: Theme.fgDim }
                            }
                            Column {
                                width: parent.width - 48 - 24 - mediaCtl.width; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { width: parent.width; text: parent.parent.parent.player ? (parent.parent.parent.player.trackTitle || "—") : ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Text { width: parent.width; text: parent.parent.parent.player ? (parent.parent.parent.player.trackArtist || "") : ""; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                            }
                            Row {
                                id: mediaCtl
                                anchors.verticalCenter: parent.verticalCenter; spacing: 16
                                property var pl: parent.parent.player
                                Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF048); font.family: Theme.fontMono; font.pixelSize: 15; color: Theme.fg; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl) mediaCtl.pl.previous() } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: mediaCtl.pl && mediaCtl.pl.isPlaying ? root.g(0xF04C) : root.g(0xF04B); font.family: Theme.fontMono; font.pixelSize: 18; color: Theme.fg; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl) mediaCtl.pl.togglePlaying() } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF051); font.family: Theme.fontMono; font.pixelSize: 15; color: Theme.fg; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: if (mediaCtl.pl) mediaCtl.pl.next() } }
                            }
                        }
                    }

                    // ── calendar (compact) ──
                    Rectangle {
                        width: parent.width; height: calCol.implicitHeight + 20; radius: Theme.radiusInner; color: Theme.elevated
                        Column {
                            id: calCol
                            anchors.fill: parent; anchors.margins: 10; spacing: 5
                            Text { text: root.monthNames[root.calMonth] + " " + root.calYear; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                            Grid {
                                width: parent.width; columns: 7
                                Repeater {
                                    model: ["S","M","T","W","T","F","S"]
                                    delegate: Item { required property var modelData; width: calCol.width / 7; height: 22; Text { anchors.centerIn: parent; text: modelData; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11 } }
                                }
                                Repeater {
                                    model: 42
                                    delegate: Item {
                                        required property int index
                                        readonly property int dayNum: index - root.firstW + 1
                                        readonly property bool valid: dayNum >= 1 && dayNum <= root.daysIn
                                        readonly property bool isToday: valid && dayNum === root.calDate
                                        width: calCol.width / 7; height: 32
                                        Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; visible: parent.isToday; color: Theme.accent }
                                        Text { anchors.centerIn: parent; text: parent.valid ? parent.dayNum : ""; color: parent.isToday ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 12; font.weight: parent.isToday ? Font.Bold : Font.Normal }
                                    }
                                }
                            }
                        }
                    }

                    // ── notifications ──
                    Item {
                        width: parent.width; height: 20
                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: Globals.server && Globals.server.trackedNotifications.values.length > 0; text: "Clear All"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearAll() } }
                    }
                    Text { width: parent.width; visible: !Globals.server || Globals.server.trackedNotifications.values.length === 0; text: "No Notifications"; horizontalAlignment: Text.AlignHCenter; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; topPadding: 6; bottomPadding: 6 }
                    Repeater {
                        model: Globals.server ? Globals.server.trackedNotifications.values : []
                        delegate: Rectangle {
                            required property var modelData
                            width: inner.width; height: nCol.implicitHeight + 20; radius: Theme.radiusInner; color: Theme.elevated
                            Row {
                                anchors.fill: parent; anchors.margins: 10; anchors.rightMargin: 30; spacing: 10
                                Image {
                                    width: 32; height: 32; sourceSize.width: 64; sourceSize.height: 64; visible: source != ""
                                    source: { var n = modelData; if (n.image && n.image != "") return n.image; if (n.appIcon && n.appIcon != "") return Quickshell.iconPath(n.appIcon, "dialog-information"); return Quickshell.iconPath("dialog-information") }
                                }
                                Column {
                                    id: nCol
                                    width: parent.width - 50; spacing: 1
                                    Text { width: parent.width; text: modelData.appName || "Notification"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight }
                                    Text { width: parent.width; text: modelData.summary || ""; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text { width: parent.width; visible: text.length > 0; text: modelData.body || ""; color: Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 11; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; textFormat: Text.PlainText }
                                }
                            }
                            CloseBtn { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8; onPressed: modelData.dismiss() }
                        }
                    }
                }
            }

            // ── backdrop: a click anywhere else in the panel dismisses the power menu ──
            MouseArea { anchors.fill: parent; visible: root.powerOpen; onClicked: root.powerOpen = false }

            // ── Power popover: floating, window-like menu (rounded + drop shadow) ──
            Item {
                id: powerPop
                visible: root.powerOpen || ppCloseTimer.running
                width: 232
                height: ppCol.implicitHeight + 16
                anchors.top: parent.top; anchors.topMargin: 56
                anchors.right: parent.right; anchors.rightMargin: 14
                transformOrigin: Item.TopRight
                opacity: root.powerOpen ? 1 : 0
                scale: root.powerOpen ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                Timer { id: ppCloseTimer; interval: 220 }
                Connections { target: root; function onPowerOpenChanged() { if (!root.powerOpen) ppCloseTimer.restart() } }

                // background + real drop shadow (MultiEffect)
                Rectangle {
                    id: ppBg
                    anchors.fill: parent
                    radius: 16
                    color: Theme.elevated
                    border.color: Theme.stroke; border.width: 1
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.shadow
                        shadowOpacity: 0.5
                        shadowBlur: 1.0
                        shadowVerticalOffset: 7
                        blurMax: 40
                    }
                }
                MouseArea { anchors.fill: parent }   // swallow clicks inside the popover

                Column {
                    id: ppCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    Text { leftPadding: 2; text: "Power Profile"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                    // segmented profile selector (PowerProfiles service ← tuned-ppd D-Bus)
                    // uniform 8px gaps: edge→pill = pill→pill = 8 (mathematically even)
                    Row {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: [{ prof: PowerProfile.PowerSaver, ic: 0xF032A, label: "Saver" }, { prof: PowerProfile.Balanced, ic: 0xF05D1, label: "Balanced" }, { prof: PowerProfile.Performance, ic: 0xF04C5, label: "Turbo" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: PowerProfiles.profile === modelData.prof
                                readonly property bool disabled: modelData.prof === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile
                                width: (ppCol.width - 16) / 3
                                height: 46; radius: 9
                                opacity: disabled ? 0.4 : 1
                                color: sel ? Theme.accent : Theme.elevated
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.g(modelData.ic); font.family: Theme.fontMono; font.pixelSize: 15; color: parent.parent.sel ? Theme.accentText : Theme.fg }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: parent.parent.sel ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                                MouseArea { anchors.fill: parent; enabled: !parent.disabled; cursorShape: Qt.PointingHandCursor; onClicked: PowerProfiles.profile = modelData.prof }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.stroke; opacity: 0.6 }

                    PowerItem { ic: 0xF033E; label: "Lock";      onGo: root.powerAction(["sh", "-c", "\"$HOME/.config/hypr/scripts/lock.sh\""]) }
                    PowerItem { ic: 0xF0904; label: "Suspend";   onGo: root.powerAction(["systemctl", "suspend"]) }
                    PowerItem { ic: 0xF0343; label: "Log Out";   onGo: root.powerAction(["hyprctl", "dispatch", "hl.dsp.exit()"]) }
                    PowerItem { ic: 0xF0709; label: "Restart";   onGo: root.powerAction(["systemctl", "reboot"]) }
                    PowerItem { ic: 0xF0425; label: "Shut Down"; danger: true; onGo: root.powerAction(["systemctl", "poweroff"]) }
                }
            }
        }
    }
}
