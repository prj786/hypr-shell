#!/usr/bin/env python3
"""kb-per-window.py — GNOME-style per-window keyboard layout for Hyprland.

Hyprland has no native per-window layout: switchxkblayout changes the layout for
the whole keyboard. This daemon remembers the chosen layout per window address and
restores it on focus, so e.g. a terminal can stay on Georgian while the browser
stays on US.

No external deps: it talks to Hyprland's event socket (.socket2.sock) directly via
the stdlib `socket` module and drives `hyprctl` for queries/switches. Layouts come
from kb_layout = "us,ge" (index 0 = us, 1 = ge); the name→index map below covers
that pair and degrades gracefully to 0 for anything unrecognised.
"""

import json
import os
import socket
import subprocess
import sys

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "")
SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
SOCK = f"{RUNTIME}/hypr/{SIG}/.socket2.sock"

# active_keymap name (as Hyprland reports it) → index in kb_layout "us,ge".
def name_to_index(name: str) -> int:
    n = (name or "").lower()
    if "georg" in n:
        return 1
    return 0  # English (US) and anything else


def keyboards() -> list:
    """Names of all physical keyboards, so every device tracks the same layout."""
    try:
        out = subprocess.run(
            ["hyprctl", "devices", "-j"],
            capture_output=True, text=True, check=True,
        ).stdout
        data = json.loads(out)
        return [k["name"] for k in data.get("keyboards", [])]
    except Exception:
        return []


def apply_layout(kbds: list, index: int) -> None:
    for name in kbds:
        subprocess.run(
            ["hyprctl", "switchxkblayout", name, str(index)],
            capture_output=True,
        )


def main() -> int:
    if not os.path.exists(SOCK):
        print(f"kb-per-window: event socket not found: {SOCK}", file=sys.stderr)
        return 1

    kbds = keyboards()
    mem: dict[str, int] = {}   # window address → layout index
    current = ""               # focused window address

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)

    buf = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                ev = line.decode("utf-8", "replace")
            except Exception:
                continue
            if ">>" not in ev:
                continue
            name, _, payload = ev.partition(">>")

            if name == "activewindowv2":
                # payload = window address (hex, no 0x). Restore its layout.
                current = payload.strip()
                apply_layout(kbds, mem.get(current, 0))

            elif name == "activelayout":
                # payload = "keyboardname,LayoutName". Record what the focused
                # window is now using (covers manual switches: shortcut/bar/click).
                layout = payload.rsplit(",", 1)[-1]
                if current:
                    mem[current] = name_to_index(layout)

            elif name == "closewindow":
                mem.pop(payload.strip(), None)

            elif name in ("configreloaded", "monitoradded", "monitorremoved"):
                # keyboard set can change on reload / device hotplug
                kbds = keyboards()

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
