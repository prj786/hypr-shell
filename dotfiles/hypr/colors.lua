-- colors.lua — Gruvbox (dark, medium contrast) palette for the Hyprland side
-- (window borders), ported from the old Qtile `desktop_env/theme/colors.py`.
-- NOTE: the shell (bar + launcher) is now Quickshell under ~/.config/quickshell/
-- — the bar replica carries its own gruvbox hex; the macOS redesign uses
-- Theme.qml (graphite + SF Pro). This file only feeds hyprland.lua now.
--
-- Hyprland wants colours as `rgba(RRGGBBAA)` / `rgb(RRGGBB)` strings, or as
-- 0xAARRGGBB integers (shadows). We store the raw 6-digit hex and build the
-- string forms with the helpers below, so a colour is written exactly once.

local M = {}

-- Backgrounds, darkest -> lightest -------------------------------------------
M.bg0_h   = "1d2021"  -- bar / deepest background
M.bg0     = "282828"  -- main background
M.bg1     = "3c3836"  -- raised surface (pills, cards)
M.bg2     = "504945"  -- second surface / inactive border
M.bg3     = "665c54"  -- dividers
M.bg4     = "7c6f64"  -- stronger divider / inactive icon

-- Foregrounds ---------------------------------------------------------------
M.fg1     = "ebdbb2"  -- primary text
M.fg2     = "d5c4a1"  -- secondary text
M.fg3     = "bdae93"  -- tertiary / dimmed
M.gray    = "928374"  -- disabled / placeholder

-- Accents + named hues ------------------------------------------------------
M.yellow  = "fabd2f"  -- accent
M.yellow2 = "d79921"  -- accent (dim)
M.red     = "fb4934"
M.green   = "b8bb26"
M.blue    = "83a598"
M.purple  = "d3869b"
M.aqua    = "8ec07c"
M.orange  = "fe8019"

-- macOS graphite theme — MIRRORS ~/.config/quickshell/Theme.qml (the shell's single
-- source of truth). Kept here so Hyprland-drawn chrome (group bar / borders) matches the
-- shell. If a token changes in Theme.qml, change it here too.
M.t_bg          = "1c1c1e"  -- desktop / app base
M.t_panel       = "1d1d1f"  -- popup / panel surface
M.t_elevated    = "2c2c2e"  -- cards / inactive tab
M.t_hover       = "3a3a3c"  -- hover fill
M.t_stroke      = "38383a"  -- hairline border
M.t_fg          = "f2f2f7"  -- primary text
M.t_fg_dim      = "8e8e93"  -- dim text
M.t_accent      = "0a84ff"  -- macOS system blue (active tab)
M.t_accent_text = "ffffff"

-- Helpers -------------------------------------------------------------------
-- rgba("fabd2f", 0xee) -> "rgba(fabd2fee)"
function M.rgba(hex, alpha)
    return string.format("rgba(%s%02x)", hex, alpha)
end

-- rgb("fabd2f") -> "rgb(fabd2f)"
function M.rgb(hex)
    return string.format("rgb(%s)", hex)
end

return M
