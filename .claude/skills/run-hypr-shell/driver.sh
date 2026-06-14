#!/usr/bin/env bash
# hypr-shell driver — launch & drive the Quickshell shell WITHOUT installing to
# the live session. It nests a throwaway Hyprland compositor on its own Wayland
# socket (aquamarine's Wayland backend), runs `qs -p dotfiles/quickshell` inside
# it, and screenshots that virtual output with grim. Nothing touches the host's
# real screen, and the host's running shell (if any) is left untouched.
#
# REQUIRES: an existing host Wayland session (WAYLAND_DISPLAY set) — aquamarine's
# headless backend can't grab a seat when logind already owns it, so we nest via
# the Wayland backend instead. On a truly headless box, start a parent compositor
# first (e.g. `cage`/`sway --headless`) and point WAYLAND_DISPLAY at it.
#
# Binaries: Hyprland, qs (quickshell), grim, hyprctl, luac.
#
# Usage:
#   driver.sh up                 # start nested compositor + shell, wait for load
#   driver.sh ipc <tgt> <fn> ..  # call a shell IpcHandler (settings|store|control|...)
#   driver.sh open <tgt> [png]   # toggle a surface, screenshot it (default: <tgt>.png)
#   driver.sh shot [png]         # screenshot current nested output (default: shell.png)
#   driver.sh targets            # list all IpcHandler targets/functions
#   driver.sh log                # tail the shell's qs log
#   driver.sh check              # luac -p the Hyprland Lua config (static syntax check)
#   driver.sh down               # tear everything down
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
QSDIR="$REPO/dotfiles/quickshell"
WORK="${HS_WORK:-/tmp/hs-driver}"
STATE="$WORK/state"
OUTDIR="${HS_OUT:-$WORK}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export AQ_DRM_DEVICES="${AQ_DRM_DEVICES:-/dev/dri/renderD128}"
mkdir -p "$WORK"

die()  { echo "driver: $*" >&2; exit 1; }
load() { [ -f "$STATE" ] && . "$STATE" || die "not up — run 'driver.sh up' first"; }

cmd_up() {
  [ -n "${WAYLAND_DISPLAY:-}" ] || die "no host WAYLAND_DISPLAY — need a parent Wayland session to nest into"
  command -v Hyprland >/dev/null || die "Hyprland not found"
  command -v qs >/dev/null       || die "qs (quickshell) not found"

  cat > "$WORK/hypr-min.conf" <<'EOF'
# minimal compositor just to host the shell — no autostart, no keybinds
monitor = WL-1, 1280x800@60, 0x0, 1
monitor = , preferred, auto, 1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    disable_watchdog_warning = true
    force_default_wallpaper = 0
}
EOF

  local before after sock
  before="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null)"
  Hyprland --config "$WORK/hypr-min.conf" > "$WORK/hypr.log" 2>&1 &
  local hpid=$!
  # wait for the new wayland socket the nested compositor opens
  for _ in $(seq 1 30); do
    sleep 0.3
    after="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null)"
    sock="$(comm -13 <(echo "$before") <(echo "$after") | grep -v '\.lock$' | head -1)"
    [ -n "$sock" ] && break
    kill -0 $hpid 2>/dev/null || die "nested Hyprland died — see $WORK/hypr.log"
  done
  [ -n "$sock" ] || die "nested compositor never opened a socket — see $WORK/hypr.log"
  local nestwd; nestwd="$(basename "$sock")"

  WAYLAND_DISPLAY="$nestwd" QT_QPA_PLATFORM=wayland \
    qs -p "$QSDIR" > "$WORK/qs.log" 2>&1 &
  local qpid=$!
  for _ in $(seq 1 30); do
    sleep 0.3
    grep -q "Configuration Loaded" "$WORK/qs.log" 2>/dev/null && break
    kill -0 $qpid 2>/dev/null || die "qs died — see $WORK/qs.log"
  done

  { echo "HYPR_PID=$hpid"; echo "QS_PID=$qpid"; echo "NEST_WD=$nestwd"; } > "$STATE"
  echo "up: nested compositor on $nestwd (hypr pid $hpid), shell qs pid $qpid"
  echo "    config loaded — try: driver.sh open settings"
}

cmd_ipc()     { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$@"; }
cmd_targets() { load; WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" show; }
cmd_shot()    { load; WAYLAND_DISPLAY="$NEST_WD" grim "$OUTDIR/${1:-shell.png}" && echo "wrote $OUTDIR/${1:-shell.png}"; }
cmd_log()     { tail -n "${1:-25}" "$WORK/qs.log"; }
cmd_check()   { command -v luac >/dev/null || die "luac not found"; ( cd "$REPO/dotfiles/hypr" && luac -p hyprland.lua colors.lua && echo "lua config: syntax OK" ); }

cmd_open() {
  load
  local tgt="$1" out="${2:-$1.png}"
  # NOTE: use `toggle`, not `show` — quickshell's `qs ipc call <tgt> show` collides
  # with the `ipc show` listing subcommand and just prints the target list. After
  # `up` every surface starts hidden, so toggle == open.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" toggle
  sleep 2
  WAYLAND_DISPLAY="$NEST_WD" grim "$OUTDIR/$out" && echo "wrote $OUTDIR/$out"
  # close with `hide` (not a 2nd toggle — toggle can race) so the next open()/shot
  # starts from a hidden surface. The settle lets the close render before any
  # following screenshot.
  WAYLAND_DISPLAY="$NEST_WD" qs ipc --pid "$QS_PID" call "$tgt" hide >/dev/null 2>&1
  sleep 1
}

cmd_down() {
  [ -f "$STATE" ] && . "$STATE"
  [ -n "${QS_PID:-}" ]   && kill "$QS_PID"   2>/dev/null
  [ -n "${HYPR_PID:-}" ] && kill "$HYPR_PID" 2>/dev/null
  rm -f "$STATE"
  echo "down"
}

case "${1:-}" in
  up)      cmd_up ;;
  ipc)     shift; cmd_ipc "$@" ;;
  open)    shift; cmd_open "$@" ;;
  shot)    shift; cmd_shot "$@" ;;
  targets) cmd_targets ;;
  log)     shift; cmd_log "$@" ;;
  check)   cmd_check ;;
  down)    cmd_down ;;
  *) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
