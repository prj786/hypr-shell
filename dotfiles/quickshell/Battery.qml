import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery — low/critical battery safety. While discharging it warns at 20% and
// 10% (once each), and at ≤5% suspends to protect unsaved work (hypridle locks
// before sleep). Devices without a laptop battery (desktops) are ignored.
// notify-send routes the toast through our own Quickshell notification server.
Scope {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool isBattery: dev && dev.isLaptopBattery
    readonly property bool discharging: dev && dev.state === UPowerDeviceState.Discharging
    readonly property int pct: dev ? Math.round(dev.percentage) : 100

    // highest threshold already fired this discharge cycle; re-armed when charging
    property int armed: 101

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "hypr-shell", "-u", urgency,
                                 "-h", "string:x-canonical-private-synchronous:hypr-battery",
                                 title, body])
    }

    function evaluate() {
        if (!isBattery) return
        if (!discharging) { armed = 101; return }          // charging/full → re-arm
        if (pct <= 5 && armed > 5) {
            armed = 5
            notify("critical", "Battery critically low", pct + "% — suspending to protect your work.")
            Quickshell.execDetached(["systemctl", "suspend"])
        } else if (pct <= 10 && armed > 10) {
            armed = 10
            notify("critical", "Battery low", pct + "% left — plug in soon.")
        } else if (pct <= 20 && armed > 20) {
            armed = 20
            notify("normal", "Battery at " + pct + "%", "Consider plugging in.")
        }
    }

    onPctChanged: evaluate()
    onDischargingChanged: evaluate()
    Component.onCompleted: evaluate()
}
