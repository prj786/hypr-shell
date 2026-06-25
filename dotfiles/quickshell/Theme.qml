pragma Singleton
import QtQuick

// Theme — single source of truth for the "graphite dark + blue" look.
// Tuned for SF Pro and compact, polished metrics. Imported as `Theme.*`.
QtObject {
    // ── Palette: graphite dark — SINGLE SOURCE OF TRUTH for colour ─────────
    // Solid, no glass/transparency (we revisit theming later). Keep every colour
    // here and reference it as Theme.* — components should not define their own.
    readonly property color bg:          "#1c1c1e"   // desktop / app base
    readonly property color panel:       "#1d1d1f"   // popup / panel surface (solid)
    readonly property color elevated:    "#2c2c2e"   // cards / rows on a panel
    readonly property color hover:       "#3a3a3c"   // hover fill
    readonly property color stroke:      "#38383a"   // hairline border
    readonly property color shadow:      Qt.rgba(0, 0, 0, 0.45)

    readonly property color fg:          "#f2f2f7"   // primary text
    readonly property color fgSecondary: "#aeaeb2"
    readonly property color fgDim:       "#8e8e93"   // tertiary / placeholder

    // Accent is user-settable: it binds to Globals.accentColor (written by the
    // Settings → Theme pane, persisted in user-theme.json). Changing it recolours
    // every surface live. Default stays system blue.
    readonly property color accent:      Globals.accentColor
    // accentText auto-contrasts with the accent (white on dark accents, ink on
    // light ones) so foreground text on accent fills stays legible at any hue.
    readonly property color accentText:  (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#1c1c1e" : "#ffffff"

    // status cues (battery / vpn / connectivity / profile)
    readonly property color success:     "#30d158"   // charging · connected · power-saver
    readonly property color warning:     "#ff9f0a"   // low-ish · performance
    readonly property color danger:      "#ff453a"   // critical / low battery

    // ── Type (SF Pro) ─────────────────────────────────────────────────────
    // SF Pro Text for body/small, SF Pro Display for large/titles (the
    // optical-size split).
    readonly property string fontText:    "SF Pro Text"
    readonly property string fontDisplay: "SF Pro Display"
    readonly property string fontMono:    "Hurmit Nerd Font"            // glyphs + mono fallback

    readonly property int fsSmall:  12
    readonly property int fsBody:   14
    readonly property int fsLarge:  17
    readonly property int fsTitle:  22

    // ── Metrics ───────────────────────────────────────────────────────────
    readonly property int radius:       14    // panels / launcher
    readonly property int radiusInner:  10    // rows, input field
    readonly property int radiusPill:   8
    readonly property int pad:          12
    readonly property int gap:          8
    readonly property int barHeight:    28

    // ── Motion (ms) — quick, ease-out. Scaled by the global
    //    animation-speed setting (>1 faster, 0 = instant) so the whole shell
    //    tracks the Settings → Theme → Animations control. ──────────────────
    readonly property real _animMul: Globals.animationSpeed
    readonly property int durFast:   _animMul <= 0 ? 0 : Math.round(120 / _animMul)
    readonly property int durBase:   _animMul <= 0 ? 0 : Math.round(180 / _animMul)
    readonly property int durSlow:   _animMul <= 0 ? 0 : Math.round(260 / _animMul)
}
