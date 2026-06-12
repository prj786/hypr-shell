pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Globals — shared, instant shell state (no IPC round-trip for in-shell toggles).
QtObject {
    id: g

    property bool controlOpen: false      // the macOS-style control centre panel
    property bool dnd: false               // Do Not Disturb (suppresses toasts)
    property var server: null              // set by Notifications.qml (the live NotificationServer)
    property bool vpnActive: false         // any VPN connection up (bar shows a VPN glyph)
    property bool caffeine: false          // keep-awake: holds a wayland idle inhibitor (no lock/blank/sleep)
    property bool overviewOpen: false      // GNOME-style window overview (Super tapped alone)
    property bool clipboardOpen: false     // the clipboard-history / emoji popup (scissors icon)
    property bool appMenuOpen: false       // the macOS-style app menu (bold app name in the bar)
    property bool settingsOpen: false      // the Quickshell Settings window (Super+, or the CC gear)
    property real clipAnchorX: 40           // screen-local x of the scissors icon (clipboard opens under it)
    property real appAnchorX: 40            // screen-local x of the app-name (app menu opens under it)

    // ── User-chosen accent colour ─────────────────────────────────────────────
    // Single mutable source the Settings → Theme pane writes; Theme.accent binds to
    // it so the whole shell recolours live. Persisted to ~/.config/quickshell/
    // user-theme.json and re-read here at startup (default = macOS system blue).
    property color accentColor: "#0a84ff"
    property bool tintBorders: false        // mirror window border colour to the accent

    // ── Dock prefs (bottom dock; persisted in user-theme.json) ─────────────────
    property bool dockEnabled: true
    property bool dockAutohide: false       // intelligent hide: slide away, reveal on bottom-edge hover

    // ── Dock popups ────────────────────────────────────────────────────────────
    property bool launcherOpen: false       // pinned-apps / launcher panel
    property bool storeOpen: false           // app-store panel
    property real launcherAnchorX: 200       // screen-local x of the launcher dock button (popup centers on it)
    property real storeAnchorX: 200          // screen-local x of the store dock button

    // ── Pinned apps (desktop ids; persisted in pinned-apps.json) ───────────────
    property var pinnedApps: []
    function isPinned(id) { return (g.pinnedApps || []).indexOf(id) >= 0 }
    function togglePin(id) {
        var a = (g.pinnedApps || []).slice()
        var i = a.indexOf(id)
        if (i >= 0) a.splice(i, 1); else a.push(id)
        g.pinnedApps = a
        g._pinWriter.command = ["sh", "-c", "cat > \"$HOME/.config/quickshell/pinned-apps.json\" <<'QS_EOF'\n" + JSON.stringify(a) + "\nQS_EOF\n"]
        g._pinWriter.running = false; g._pinWriter.running = true
    }
    // ── CPU / memory sampling (shared by the RunCat in the bar + Control Center) ─
    property real cpuUsage: 0      // 0..1
    property real memUsage: 0      // 0..1
    property var _prevCpu: null
    property Process _statProc: Process {
        command: ["sh", "-c", "head -1 /proc/stat; echo SEP; grep -E 'MemTotal|MemAvailable' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parts = this.text.split("SEP")
                    var nums = parts[0].trim().split(/\s+/).slice(1).map(Number)
                    var idle = (nums[3] || 0) + (nums[4] || 0)
                    var total = 0; for (var i = 0; i < nums.length; i++) total += (nums[i] || 0)
                    if (g._prevCpu) { var dt = total - g._prevCpu.total, di = idle - g._prevCpu.idle; if (dt > 0) g.cpuUsage = Math.max(0, Math.min(1, (dt - di) / dt)) }
                    g._prevCpu = { total: total, idle: idle }
                    var mt = 0, ma = 0, ml = (parts[1] || "").split("\n")
                    for (var j = 0; j < ml.length; j++) { if (ml[j].indexOf("MemTotal") >= 0) mt = parseInt(ml[j].replace(/\D/g, "")); else if (ml[j].indexOf("MemAvailable") >= 0) ma = parseInt(ml[j].replace(/\D/g, "")) }
                    if (mt > 0) g.memUsage = Math.max(0, Math.min(1, (mt - ma) / mt))
                } catch (e) {}
            }
        }
    }
    property Timer _statTimer: Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: g._statProc.running = true }

    property Process _pinWriter: Process {}
    property Process _pinLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/pinned-apps.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { var j = JSON.parse(this.text); if (Array.isArray(j)) g.pinnedApps = j } catch (e) {} } }
    }

    property Process _themeLoad: Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/quickshell/user-theme.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j && j.accent) g.accentColor = j.accent
                    if (j && j.tintBorders !== undefined) g.tintBorders = j.tintBorders
                    if (j && j.dockEnabled !== undefined) g.dockEnabled = j.dockEnabled
                    if (j && j.dockAutohide !== undefined) g.dockAutohide = j.dockAutohide
                } catch (e) {}
            }
        }
    }
}
