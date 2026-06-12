import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// AppStore — a search box that installs/removes apps from the Arch official repos
// + the AUR (via the paru/yay helper if present, else pacman for repo packages).
// Install/Remove run in a foot terminal so you see the build/download and enter
// your sudo password there — nothing is changed silently. Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }
    property string query: ""
    property var results: []
    property var installed: ({})       // pkg name → true (from `pacman -Qq`)
    property string helper: ""          // "paru" / "yay" / "" (= repo-only via pacman)
    property bool searching: false

    // run a package action in a visible terminal (sudo/build/confirm = user-driven)
    function term(cmd) { Quickshell.execDetached(["foot", "-e", "sh", "-c", cmd + '; echo; echo "── press Enter to close ──"; read x']) }
    function pkgInstall(id) { root.term((root.helper ? root.helper : "sudo pacman") + " -S --needed " + id); refresh.restart() }
    function pkgRemove(id)  { root.term((root.helper ? root.helper : "sudo pacman") + " -Rns " + id); refresh.restart() }

    function doSearch() {
        var q = root.query.trim()
        if (q.length < 2) { root.results = []; root.searching = false; return }
        root.searching = true
        var tool = root.helper ? root.helper : "pacman"   // paru/yay also searches the AUR
        searchProc.command = ["sh", "-c", tool + ' -Ss --color=never -- "$1" 2>/dev/null | head -80', "sh", q]
        searchProc.running = false; searchProc.running = true
    }
    Timer { id: refresh; interval: 1500; onTriggered: qProc.running = true }

    // latch monitor on open (avoid focus-follows-mouse surface-remap blink)
    property var openScreen: null
    function focusedScreen() {
        var fm = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (fm) for (var i = 0; i < ss.length; i++) if (ss[i].name === fm.name) return ss[i]
        return ss.length > 0 ? ss[0] : null
    }
    Component.onCompleted: { root.openScreen = root.focusedScreen(); helperProc.running = true }

    IpcHandler {
        target: "store"
        function toggle(): void { Globals.launcherOpen = false; Globals.storeOpen = !Globals.storeOpen }
        function show(): void { Globals.storeOpen = true }
        function hide(): void { Globals.storeOpen = false }
    }

    // which AUR helper is available?
    Process {
        id: helperProc
        command: ["sh", "-c", "command -v paru || command -v yay || true"]
        stdout: StdioCollector { onStreamFinished: { var p = this.text.trim(); root.helper = p ? p.split("/").pop() : "" } }
    }
    // installed-package set (so badges/buttons reflect reality after actions)
    Process {
        id: qProc
        command: ["sh", "-c", "pacman -Qq 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var m = {}, ls = this.text.split("\n"); for (var i = 0; i < ls.length; i++) if (ls[i].trim()) m[ls[i].trim()] = true; root.installed = m } }
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                // pacman/paru -Ss format: "repo/name version [extra]" then an indented description line.
                var out = [], lines = this.text.split("\n"), cur = null
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i]
                    if (!ln.trim()) continue
                    if (/^\s/.test(ln)) { if (cur) cur.desc = ln.trim(); continue }
                    var m = ln.match(/^([^\/\s]+)\/(\S+)\s+(\S+)(.*)$/)
                    if (m) { if (cur) out.push(cur); cur = { source: m[1], id: m[2], name: m[2], ver: m[3], desc: "", inst: /\[installed/.test(m[4]) } }
                }
                if (cur) out.push(cur)
                root.results = out.slice(0, 40)
                root.searching = false
            }
        }
    }

    PanelWindow {
        id: win
        visible: Globals.storeOpen || closeTimer.running
        screen: root.openScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell:store"
        anchors { top: true; bottom: true; left: true; right: true }

        Timer { id: closeTimer; interval: 220 }
        Connections { target: Globals; function onStoreOpenChanged() {
            if (Globals.storeOpen) { root.openScreen = root.focusedScreen(); root.query = ""; root.results = []; storeIn.text = ""; storeIn.forceActiveFocus(); helperProc.running = true; qProc.running = true }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.storeOpen = false }

        Rectangle {
            id: box
            x: Math.max(12, Math.min(parent.width - width - 12, Globals.storeAnchorX - width / 2))
            y: parent.height - height - 90
            width: 460; height: 460
            radius: Theme.radius; color: Theme.panel
            border.color: Theme.stroke; border.width: 1
            opacity: Globals.storeOpen ? 1 : 0
            scale: Globals.storeOpen ? 1 : 0.96
            transformOrigin: Item.BottomLeft
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.shadow; shadowOpacity: 0.5; shadowBlur: 1.0; shadowVerticalOffset: 8; blurMax: 48 }

            MouseArea { anchors.fill: parent }
            Keys.onEscapePressed: Globals.storeOpen = false

            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 12

                Row {
                    width: parent.width; spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "App Store"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }
                    Item { width: parent.width - 200; height: 1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: root.helper === ""; text: "repo-only (no AUR helper)"; color: Theme.warning; font.family: Theme.fontText; font.pixelSize: 10 }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Theme.radiusInner
                    color: Theme.bg; border.color: storeIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                    Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); font.family: Theme.fontMono; font.pixelSize: 14; color: Theme.fgDim }
                    TextInput {
                        id: storeIn
                        anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: Globals.storeOpen = false
                        onAccepted: root.doSearch()
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: storeIn.text.length === 0; text: "Search apps to install or remove…"; color: Theme.fgDim; font: storeIn.font }
                    }
                }
                Text { width: parent.width; text: "Press Enter to search the official repos + AUR. Actions open a terminal."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }

                Flickable {
                    width: parent.width; height: parent.height - y
                    contentHeight: resCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: resCol
                        width: parent.width; spacing: 6
                        // loading spinner
                        Row {
                            width: parent.width; height: visible ? 30 : 0; visible: root.searching; spacing: 10
                            Item {
                                width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter
                                RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: root.searching }
                                Rectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.color: Theme.stroke; border.width: 2 }
                                Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: -1 }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Searching repos + AUR…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        }
                        Text { width: parent.width; visible: !root.searching && root.results.length === 0 && root.query.trim().length >= 2; text: "No results."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        Repeater {
                            model: root.results
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool aur: modelData.source === "aur"
                                readonly property bool isInstalled: modelData.inst === true || root.installed[modelData.id] === true
                                width: resCol.width; height: 56; radius: Theme.radiusInner; color: Theme.elevated
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: actions.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Image { anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; sourceSize.width: 60; sourceSize.height: 60; source: Quickshell.iconPath(modelData.name, "application-x-executable") }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1; width: 230
                                        Row { spacing: 6
                                            Text { text: modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, 150) }
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: badge.implicitWidth + 10; height: 15; radius: 4; color: parent.parent.parent.parent.aur ? Theme.accent : Theme.hover
                                                Text { id: badge; anchors.centerIn: parent; text: modelData.source; color: parent.parent.parent.parent.parent.aur ? Theme.accentText : Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.DemiBold } }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: parent.parent.parent.parent.isInstalled; text: "installed"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 9 }
                                        }
                                        Text { width: 230; text: modelData.desc; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                                Row {
                                    id: actions
                                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                    // Install (hidden if already installed)
                                    Rectangle { visible: !parent.parent.isInstalled; width: il.implicitWidth + 16; height: 26; radius: 7; color: iMa.containsMouse ? Theme.accent : Theme.hover
                                        Text { id: il; anchors.centerIn: parent; text: "Install"; color: iMa.containsMouse ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pkgInstall(modelData.id) } }
                                    // Remove (only if installed)
                                    Rectangle { visible: parent.parent.isInstalled; width: rl.implicitWidth + 14; height: 26; radius: 7; color: rMa.containsMouse ? Theme.danger : Theme.hover
                                        Text { id: rl; anchors.centerIn: parent; text: "Remove"; color: rMa.containsMouse ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pkgRemove(modelData.id) } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
