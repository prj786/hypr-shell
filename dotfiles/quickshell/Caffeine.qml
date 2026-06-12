import QtQuick
import Quickshell
import Quickshell.Wayland

// Caffeine — "keep awake". When Globals.caffeine is on, a wayland idle-inhibitor
// is held on a tiny always-mapped surface. Hyprland then stops reporting idle, so
// hypridle never fires (no auto-lock, no screen-blank, no auto-suspend). Turning it
// off releases the inhibitor and normal idle behaviour resumes immediately.
//
// This only affects *idle* timers — the lid script and a manual lock still work.
Scope {
    PanelWindow {
        id: w
        // a 1px transparent surface parked in a corner, behind everything, click-through
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        visible: true
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}                                   // no input region → fully click-through
        WlrLayershell.namespace: "quickshell:caffeine"
        WlrLayershell.layer: WlrLayer.Background
        anchors { top: true; left: true }

        IdleInhibitor {
            window: w
            enabled: Globals.caffeine
        }
    }
}
