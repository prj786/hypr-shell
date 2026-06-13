import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// AppStore — search + install/remove apps from the Arch official repos + the AUR.
// Installs run in the BACKGROUND (no terminal): clicking an action opens a themed
// sudo-password prompt, the password is piped to `sudo -S` over stdin (never put
// on the command line), and a spinner shows on the button until it finishes.
// If no AUR helper is present, an "Enable AUR" button builds paru from source the
// same way. Themed from Theme.qml.
Scope {
    id: root
    function g(c) { return String.fromCodePoint(c) }
    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }   // shell single-quote

    property string query: ""
    property var results: []
    property var installed: ({})       // pkg name → true (from `pacman -Qq`)
    property string helper: ""          // "paru" / "yay" / "" (= repo-only via pacman)
    property bool searching: false
    property bool searched: false       // a search has actually completed

    // ── one background operation at a time (gated by the single password prompt) ──
    property string busyId: ""          // pkg id currently being installed/removed ("" = idle)
    property string busyKind: ""        // "install" | "remove" | "paru"
    property string opError: ""         // last failure message (shown as a banner)
    // pending op awaiting the password
    property string pendId: ""
    property string pendKind: ""
    property bool pwOpen: false
    property string pwText: ""

    function ask(kind, id) {
        if (root.busyId !== "") return            // an op is already running
        root.pendKind = kind; root.pendId = id
        root.opError = ""; root.pwText = ""; root.pwOpen = true
    }
    function cancelAsk() { root.pwOpen = false; root.pwText = ""; root.pendId = ""; root.pendKind = "" }

    // The privileged part of each op. paru/makepkg are run as the normal user
    // (they refuse root) and call `sudo` themselves; our own steps use sudo too.
    // None of these read stdin — see wrap(): we hand sudo an ASKPASS helper, which
    // it uses automatically because the process has no controlling terminal. That
    // avoids the deadlock where a second sudo blocks forever on an empty stdin.
    function opBody(kind, id) {
        if (kind === "install")
            return root.helper
                ? root.helper + " -S --noconfirm --skipreview --needed -- " + root.sq(id)
                : "sudo -A pacman -S --noconfirm --needed -- " + root.sq(id)
        if (kind === "remove")
            return "sudo -A pacman -Rns --noconfirm -- " + root.sq(id)
        // kind === "paru": build the AUR helper from source (links current libalpm)
        return "sudo -A pacman -S --needed --noconfirm base-devel git rust && "
             + "bd=$(mktemp -d) && git clone --depth 1 https://aur.archlinux.org/paru.git \"$bd\" && "
             + "( cd \"$bd\" && makepkg -si --noconfirm ); st=$?; rm -rf \"$bd\"; exit $st"
    }
    // wrap a body: read the password (one line on stdin), drop it into a 0700
    // ASKPASS helper under XDG_RUNTIME_DIR (tmpfs, user-only), export SUDO_ASKPASS
    // so every sudo in the body authenticates non-interactively, run it, then wipe
    // the helper. Status is the body's status; it never hangs on stdin.
    function opCommand(kind, id) {
        return [
            "IFS= read -r __PW",
            'D=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/hs.XXXXXX") || exit 9',
            'chmod 700 "$D"',
            'printf "%s\\n" "$__PW" > "$D/pw"',
            'cat > "$D/askpass" <<EOF',
            '#!/bin/sh',
            'cat "$D/pw"',
            'EOF',
            'chmod 700 "$D/askpass" "$D/pw"',
            'export SUDO_ASKPASS="$D/askpass"',
            '( ' + root.opBody(kind, id) + ' ); __st=$?',
            'rm -rf "$D"',
            'exit $__st'
        ].join("\n")
    }
    function confirmAsk() {
        if (root.pwText.length === 0 || root.busyId !== "") return
        root.busyKind = root.pendKind
        root.busyId = (root.pendKind === "paru") ? "paru" : root.pendId
        root.opError = ""
        opProc.command = ["sh", "-c", root.opCommand(root.pendKind, root.pendId)]
        opProc.running = false; opProc.running = true
        root.pwOpen = false; root.pendId = ""; root.pendKind = ""
    }

    function doSearch() {
        var q = root.query.trim()
        if (q.length < 2) { root.results = []; root.searching = false; root.searched = false; return }
        root.searching = true
        var tool = root.helper ? root.helper : "pacman"   // paru/yay also searches the AUR
        searchProc.command = ["sh", "-c", tool + ' -Ss --color=never -- "$1" 2>/dev/null | head -80', "sh", q]
        searchProc.running = false; searchProc.running = true
    }
    // live search: fire shortly after the user stops typing (no need to press Enter)
    Timer { id: searchDebounce; interval: 350; onTriggered: root.doSearch() }
    Timer { id: refresh; interval: 1500; onTriggered: { qProc.running = true; helperProc.running = true } }

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
                root.searching = false; root.searched = true
            }
        }
    }

    // ── the background install/remove/build process ──
    Process {
        id: opProc
        stdinEnabled: true
        onStarted: { if (root.pwText.length) opProc.write(root.pwText + "\n"); root.pwText = "" }   // one stdin line → ASKPASS file, then drop the in-memory copy
        stderr: StdioCollector { id: opErr }
        onExited: function (code, status) {
            if (code === 0) { root.opError = "" }
            else {
                var e = (opErr.text || "").trim().split("\n").filter(function (l) { return l.trim().length }).pop()
                root.opError = (root.busyKind === "paru" ? "Couldn't build paru. " : "Operation failed. ")
                             + (e && e.length ? e : ("exit code " + code + " — wrong password?"))
            }
            root.busyId = ""; root.busyKind = ""
            qProc.running = true; helperProc.running = true     // refresh installed set + helper presence
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
            if (Globals.storeOpen) { root.openScreen = root.focusedScreen(); root.query = ""; root.results = []; root.searched = false; root.cancelAsk(); storeIn.text = ""; storeIn.forceActiveFocus(); helperProc.running = true; qProc.running = true }
            else closeTimer.restart()
        } }

        MouseArea { anchors.fill: parent; onClicked: Globals.storeOpen = false }

        // small reusable spinner
        component Spinner: Item {
            property color ring: Theme.stroke
            property color dot: Theme.accent
            RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: true }
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: parent.ring; border.width: 2 }
            Rectangle { width: parent.width * 0.3; height: width; radius: width / 2; color: parent.dot; anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: -1 }
        }

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
            Keys.onEscapePressed: { if (root.pwOpen) root.cancelAsk(); else Globals.storeOpen = false }

            Column {
                anchors.fill: parent; anchors.margins: 14; spacing: 12

                // ── header: title (left) + AUR status / Enable-AUR (right) ──
                Item {
                    width: parent.width; height: 26
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "App Store"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsLarge; font.weight: Font.Bold }

                    // AUR present → quiet "AUR ✓" tag
                    Text {
                        visible: root.helper !== "" && root.busyKind !== "paru"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: "AUR · " + root.helper; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10
                    }
                    // building paru → progress tag
                    Row {
                        visible: root.busyKind === "paru"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Spinner { width: 13; height: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Building paru…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }
                    }
                    // no AUR helper → one-click Enable AUR (builds paru in the background)
                    Rectangle {
                        visible: root.helper === "" && root.busyKind !== "paru"
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: eaRow.implicitWidth + 18; height: 24; radius: 7
                        color: eaMa.containsMouse ? Theme.accent : Theme.elevated
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row { id: eaRow; anchors.centerIn: parent; spacing: 6
                            Text { anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF01DA); font.family: Theme.fontMono; font.pixelSize: 12; color: eaMa.containsMouse ? Theme.accentText : Theme.accent }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Enable AUR"; color: eaMa.containsMouse ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                        }
                        MouseArea { id: eaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ask("paru", "paru") }
                    }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Theme.radiusInner
                    color: Theme.bg; border.color: storeIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                    Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: root.g(0xF0349); font.family: Theme.fontMono; font.pixelSize: 14; color: Theme.fgDim }
                    TextInput {
                        id: storeIn
                        anchors.fill: parent; anchors.leftMargin: 34; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                        enabled: !root.pwOpen
                        onTextChanged: {
                            root.query = text
                            root.searched = false
                            if (text.trim().length < 2) { root.results = []; root.searching = false; searchDebounce.stop() }
                            else searchDebounce.restart()
                        }
                        Keys.onEscapePressed: Globals.storeOpen = false
                        onAccepted: { searchDebounce.stop(); root.doSearch() }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: storeIn.text.length === 0; text: "Search apps to install or remove…"; color: Theme.fgDim; font: storeIn.font }
                    }
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: (root.helper ? "Searches the official repos + AUR as you type." : "Searches the official repos as you type — enable AUR for the rest.") + " Installs run in the background."; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 10 }

                // ── error banner ──
                Rectangle {
                    width: parent.width; visible: root.opError !== ""; radius: Theme.radiusInner
                    height: visible ? errT.implicitHeight + 16 : 0; color: Qt.rgba(1, 0.27, 0.23, 0.12); border.color: Theme.danger; border.width: 1
                    Text { id: errT; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8; text: root.opError; wrapMode: Text.WordWrap; color: Theme.danger; font.family: Theme.fontText; font.pixelSize: 10 }
                }

                Flickable {
                    width: parent.width; height: parent.height - y
                    contentHeight: resCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: resCol
                        width: parent.width; spacing: 6
                        // search spinner
                        Row {
                            width: parent.width; height: visible ? 30 : 0; visible: root.searching; spacing: 10
                            Spinner { width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Searching repos + AUR…"; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall }
                        }
                        Text {
                            width: parent.width
                            visible: !root.searching && root.searched && root.results.length === 0 && root.query.trim().length >= 2
                            text: root.helper === "" ? "No results in the official repos. Many apps (e.g. Chrome) are AUR-only — click “Enable AUR”."
                                                      : "No results."
                            wrapMode: Text.WordWrap
                            color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                        }
                        Repeater {
                            model: root.results
                            delegate: Rectangle {
                                id: rowItem
                                required property var modelData
                                readonly property bool aur: modelData.source === "aur"
                                readonly property bool isInstalled: modelData.inst === true || root.installed[modelData.id] === true
                                readonly property bool isBusy: root.busyId === modelData.id
                                width: resCol.width; height: 56; radius: Theme.radiusInner; color: Theme.elevated
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: actions.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Image { anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; sourceSize.width: 60; sourceSize.height: 60; source: Quickshell.iconPath(modelData.name, "application-x-executable") }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1; width: 230
                                        Row { spacing: 6
                                            Text { text: modelData.name; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsSmall; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, 150) }
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: badge.implicitWidth + 10; height: 15; radius: 4; color: rowItem.aur ? Theme.accent : Theme.hover
                                                Text { id: badge; anchors.centerIn: parent; text: modelData.source; color: rowItem.aur ? Theme.accentText : Theme.fgSecondary; font.family: Theme.fontText; font.pixelSize: 9; font.weight: Font.DemiBold } }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: rowItem.isInstalled; text: "installed"; color: Theme.accent; font.family: Theme.fontText; font.pixelSize: 9 }
                                        }
                                        Text { width: 230; text: modelData.desc; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                                Row {
                                    id: actions
                                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                    // busy → spinner on this row's button
                                    Rectangle {
                                        visible: rowItem.isBusy; width: 26; height: 26; radius: 7; color: Theme.hover
                                        Spinner { anchors.centerIn: parent; width: 15; height: 15 }
                                    }
                                    // Install (hidden if already installed or busy)
                                    Rectangle { visible: !rowItem.isInstalled && !rowItem.isBusy; width: il.implicitWidth + 16; height: 26; radius: 7
                                        opacity: root.busyId === "" ? 1 : 0.4
                                        color: iMa.containsMouse && root.busyId === "" ? Theme.accent : Theme.hover
                                        Text { id: il; anchors.centerIn: parent; text: "Install"; color: (iMa.containsMouse && root.busyId === "") ? Theme.accentText : Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ask("install", modelData.id) } }
                                    // Remove (only if installed, hidden while busy)
                                    Rectangle { visible: rowItem.isInstalled && !rowItem.isBusy; width: rl.implicitWidth + 14; height: 26; radius: 7
                                        opacity: root.busyId === "" ? 1 : 0.4
                                        color: rMa.containsMouse && root.busyId === "" ? Theme.danger : Theme.hover
                                        Text { id: rl; anchors.centerIn: parent; text: "Remove"; color: (rMa.containsMouse && root.busyId === "") ? Theme.accentText : Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ask("remove", modelData.id) } }
                                }
                            }
                        }
                    }
                }
            }

            // ════════ in-app sudo password prompt (background auth — no terminal) ════════
            Rectangle {
                anchors.fill: parent; radius: Theme.radius; visible: root.pwOpen
                color: Qt.rgba(0, 0, 0, 0.55)
                MouseArea { anchors.fill: parent; onClicked: root.cancelAsk() }   // click-outside cancels
                Rectangle {
                    anchors.centerIn: parent; width: 320; height: pwCol.implicitHeight + 36
                    radius: Theme.radius; color: Theme.panel; border.color: Theme.stroke; border.width: 1
                    MouseArea { anchors.fill: parent }   // swallow clicks inside the card
                    Column {
                        id: pwCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 18; spacing: 12
                        Text { text: "Administrator password"; color: Theme.fg; font.family: Theme.fontDisplay; font.pixelSize: Theme.fsBody; font.weight: Font.Bold }
                        Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.fgDim; font.family: Theme.fontText; font.pixelSize: 11
                            text: root.pendKind === "paru" ? "Build the paru AUR helper from source."
                                : (root.pendKind === "remove" ? "Remove " : "Install ") + (root.pendId || "") + (root.pendKind === "install" && root.helper ? "  (repos + AUR)" : "") }
                        Rectangle {
                            width: parent.width; height: 38; radius: Theme.radiusInner
                            color: Theme.bg; border.color: pwIn.activeFocus ? Theme.accent : Theme.stroke; border.width: 1
                            TextInput {
                                id: pwIn
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password; passwordCharacter: "•"
                                color: Theme.fg; font.family: Theme.fontText; font.pixelSize: Theme.fsBody; clip: true
                                onTextChanged: root.pwText = text
                                Keys.onEscapePressed: root.cancelAsk()
                                onAccepted: { if (root.pwText.length) root.confirmAsk() }
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: pwIn.text.length === 0; text: "sudo password"; color: Theme.fgDim; font: pwIn.font }
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Rectangle { width: cl.implicitWidth + 22; height: 30; radius: 8; color: clMa.containsMouse ? Theme.hover : Theme.elevated
                                Text { id: cl; anchors.centerIn: parent; text: "Cancel"; color: Theme.fg; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { id: clMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelAsk() } }
                            Rectangle { width: ol.implicitWidth + 22; height: 30; radius: 8; opacity: root.pwText.length ? 1 : 0.4
                                color: Theme.accent
                                Text { id: ol; anchors.centerIn: parent; text: root.pendKind === "remove" ? "Remove" : (root.pendKind === "paru" ? "Build" : "Install"); color: Theme.accentText; font.family: Theme.fontText; font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.pwText.length) root.confirmAsk() } } }
                        }
                    }
                    // clear + focus the field whenever the prompt opens
                    Connections { target: root; function onPwOpenChanged() { if (root.pwOpen) { pwIn.text = ""; pwIn.forceActiveFocus() } } }
                }
            }
        }
    }
}
