#!/usr/bin/env bash
# phase 00 — preflight: sanity checks + announce the backup policy.

phase_preflight() {
    step "00 · preflight"

    # tools the installer itself needs
    for t in awk grep sed ln; do
        command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
    done

    # network (best-effort; skip the test under --dry-run)
    if [ "${DRY_RUN:-0}" != "1" ]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsS --max-time 5 -o /dev/null https://github.com 2>/dev/null \
                || warn "no network to github.com — package/repo steps may fail."
        fi
    fi

    # disk space on / (need a couple GB for the package set)
    local freem; freem="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
    if [ -n "$freem" ] && [ "$freem" -lt 3000 ]; then
        warn "only ${freem}MB free on / — the full package set may not fit."
    fi

    info "existing ~/.config/{hypr,quickshell} will be backed up to *.bak.$RUN_STAMP before linking."
    ok "preflight done"
}
