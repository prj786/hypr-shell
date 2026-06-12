import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notifications — Quickshell IS the notification server now (replaces swaync).
// Live notifications appear as solid toasts top-right (unless DND); the full
// list lives in the control centre. The server is shared via Globals.server.
Scope {
    id: root

    property var popups: []

    function pushPopup(n) {
        var a = root.popups.slice(); a.push(n); root.popups = a
    }
    function removePopup(n) {
        root.popups = root.popups.filter(function (x) { return x !== n })
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        Component.onCompleted: Globals.server = server
        onNotification: function (n) {
            n.tracked = true                 // keep in trackedNotifications (history)
            if (!Globals.dnd) root.pushPopup(n)
        }
    }

    // ── toast stack, top-right, below the bar ─────────────────────────────
    PanelWindow {
        visible: root.popups.length > 0 && !Globals.dnd
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { top: true; right: true; left: true; bottom: true }

        // Only the toast column grabs pointer input; the rest of this full-screen
        // overlay is click-through (otherwise it would block everything below it,
        // e.g. the screenshot preview, for the toasts' whole lifetime).
        mask: Region { item: toastColumn }

        Column {
            id: toastColumn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 38
            anchors.rightMargin: 10
            spacing: 8

            Repeater {
                model: root.popups
                delegate: Rectangle {
                    id: toast
                    required property var modelData
                    width: 360
                    height: col.implicitHeight + 24
                    radius: Theme.radiusInner
                    color: Theme.panel   // solid, from Theme (single source of truth)
                    border.color: Theme.stroke
                    border.width: 1

                    Timer {
                        running: true
                        interval: toast.modelData.expireTimeout > 0 ? toast.modelData.expireTimeout : 5000
                        onTriggered: root.removePopup(toast.modelData)
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Image {
                            width: 38; height: 38
                            sourceSize.width: 76; sourceSize.height: 76
                            visible: source != ""
                            source: {
                                var n = toast.modelData
                                if (n.image && n.image != "") return n.image
                                if (n.appIcon && n.appIcon != "") return Quickshell.iconPath(n.appIcon, "dialog-information")
                                return Quickshell.iconPath("dialog-information")
                            }
                        }
                        Column {
                            id: col
                            width: parent.width - 60
                            spacing: 2
                            Text {
                                width: parent.width
                                text: toast.modelData.appName || "Notification"
                                color: Theme.fgDim
                                font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: toast.modelData.summary || ""
                                color: Theme.fg
                                font.family: Theme.fontText; font.pixelSize: Theme.fsBody; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: text.length > 0
                                text: toast.modelData.body || ""
                                color: Theme.fgSecondary
                                font.family: Theme.fontText; font.pixelSize: Theme.fsSmall
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.removePopup(toast.modelData)
                    }
                }
            }
        }
    }
}
