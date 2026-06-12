#!/usr/bin/env bash
# lib/pkg.sh — generic→native package name mapping and batched install.
#
# Map files (packages/<family>.map) are OVERRIDES ONLY: list a generic name only
# when the native name differs, or to mark it SKIP (not available) / BUILD (must
# be built from source on this family). Anything not in the map installs under
# its generic name verbatim — keeps the maps small and the common.list canonical.

# map_pkg <generic> -> prints native name(s), or "SKIP"/"BUILD" sentinel.
map_pkg() {
    local generic="$1" mapfile="$DOTREPO/packages/$FAMILY.map" line
    if [ -r "$mapfile" ]; then
        # first field == generic ; rest is the native package list / sentinel
        line="$(awk -v g="$generic" '!/^[[:space:]]*#/ && $1==g {$1=""; sub(/^ /,""); print; exit}' "$mapfile")"
        if [ -n "$line" ]; then printf '%s' "$line"; return; fi
    fi
    printf '%s' "$generic"
}

# read_list — echo the generic package names from common.list (strips comments).
read_list() {
    awk '!/^[[:space:]]*#/ && NF {print $1}' "$DOTREPO/packages/common.list"
}

# resolve_packages — splits common.list into TO_INSTALL[], TO_BUILD[], SKIPPED[].
resolve_packages() {
    TO_INSTALL=(); TO_BUILD=(); SKIPPED=()
    local g native
    while read -r g; do
        native="$(map_pkg "$g")"
        case "$native" in
            SKIP)  SKIPPED+=("$g") ;;
            BUILD) TO_BUILD+=("$g") ;;
            *)     # native may expand to several space-separated packages
                   # shellcheck disable=SC2206
                   TO_INSTALL+=($native) ;;
        esac
    done < <(read_list)
}

# install_packages — one batched install command for the family.
install_packages() {
    [ "${#TO_INSTALL[@]}" -gt 0 ] || { warn "nothing to install?"; return 0; }
    case "$FAMILY" in
        arch)   sudo_run pacman -S --needed --noconfirm "${TO_INSTALL[@]}" ;;
        fedora) sudo_run dnf install -y --skip-unavailable "${TO_INSTALL[@]}" ;;
        debian) sudo_run apt-get install -y --no-install-recommends "${TO_INSTALL[@]}" ;;
        suse)   sudo_run zypper --non-interactive install --no-recommends "${TO_INSTALL[@]}" ;;
    esac
}

# pkg_present <generic> — is the (mapped) package installed? best-effort.
pkg_present() {
    local n; n="$(map_pkg "$1")"; n="${n%% *}"   # first token
    case "$FAMILY" in
        arch)   pacman -Qi "$n" >/dev/null 2>&1 ;;
        fedora) rpm -q "$n" >/dev/null 2>&1 ;;
        debian) dpkg -s "$n" >/dev/null 2>&1 ;;
        suse)   rpm -q "$n" >/dev/null 2>&1 ;;
    esac
}
