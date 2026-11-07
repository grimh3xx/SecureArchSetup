# shellcheck shell=bash
# Core plumbing: command runner, dry run, backed-up file writes, restore, packages.
#
# Every file the tool changes goes through write_file, which first copies the original
# into $BACKUP_ROOT/<run id>/ and records it in that run's manifest. `restore` replays a
# manifest backwards, so any run can be undone.
#
# SAS_ROOT (tests only) prefixes every managed path and turns commands into no-ops, so the
# whole flow can be exercised against a scratch directory.

SAS_ROOT="${SAS_ROOT:-}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
BACKUP_ROOT="$SAS_ROOT/var/backups/secure-arch-setup"
LOG_FILE="${LOG_FILE:-$SAS_ROOT/var/log/secure-arch-setup.log}"
TARGET_USER="${TARGET_USER:-}"
CHANGED=0   # files changed in this run

_log() {
    (( DRY_RUN )) && return 0
    { mkdir -p "$(dirname "$LOG_FILE")" && printf '%s [%s] %s\n' "$(date '+%F %T')" "$RUN_ID" "$*" >>"$LOG_FILE"; } 2>/dev/null || true
}

path() { printf '%s%s' "$SAS_ROOT" "$1"; }

# run CMD... : print, then execute unless this is a dry run (or a SAS_ROOT test run).
run() {
    printf '    %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
    if (( DRY_RUN )) || [[ -n "$SAS_ROOT" ]]; then
        return 0
    fi
    _log "run: $*"
    local rc=0
    "$@" || rc=$?
    (( rc == 0 )) || warn "command failed ($rc): $*"
    return "$rc"
}

_backup() {
    local dest=$1 real dir
    real=$(path "$dest")
    dir="$BACKUP_ROOT/$RUN_ID"
    mkdir -p "$dir"
    if grep -qsE "^(modified|created) ${dest}\$" "$dir/manifest"; then
        return 0  # first state of this file in this run is already saved
    fi
    if [[ -e "$real" ]]; then
        mkdir -p "$dir/files$(dirname "$dest")"
        cp -a "$real" "$dir/files$dest"
        echo "modified $dest" >>"$dir/manifest"
    else
        echo "created $dest" >>"$dir/manifest"
    fi
}

_diff_colors() {
    local line
    while IFS= read -r line; do
        case "$line" in
            +*) printf '      %s%s%s\n' "$C_OK" "$line" "$C_RESET" ;;
            -*) printf '      %s%s%s\n' "$C_ERR" "$line" "$C_RESET" ;;
            *) printf '      %s%s%s\n' "$C_DIM" "$line" "$C_RESET" ;;
        esac
    done
}

# write_file DEST [MODE] < content
# Returns 0 when the file was (or, in a dry run, would be) changed, 1 when already up to date.
write_file() {
    local dest=$1 mode=${2:-644} real tmp
    real=$(path "$dest")
    tmp=$(mktemp)
    cat >"$tmp"
    if [[ -f "$real" ]] && cmp -s "$tmp" "$real"; then
        rm -f "$tmp"
        skip "$dest already up to date"
        return 1
    fi
    if (( DRY_RUN )); then
        if [[ -f "$real" ]]; then info "would update $dest"; else info "would create $dest"; fi
        local before=$real
        [[ -f "$real" ]] || before=/dev/null
        diff -u --label "$dest" --label "$dest (new)" "$before" "$tmp" 2>/dev/null \
            | sed -n '4,40p' | _diff_colors || true
        rm -f "$tmp"
        return 0
    fi
    _backup "$dest"
    mkdir -p "$(dirname "$real")"
    install -m "$mode" "$tmp" "$real"
    rm -f "$tmp"
    CHANGED=$((CHANGED + 1))
    ok "wrote $dest"
    _log "wrote $dest"
}

# Undo the most recent change to DEST made in this run (used when validation fails).
revert_file() {
    local dest=$1 dir="$BACKUP_ROOT/$RUN_ID"
    if [[ -f "$dir/files$dest" ]]; then
        cp -a "$dir/files$dest" "$(path "$dest")"
    elif grep -qsx "created $dest" "$dir/manifest"; then
        rm -f "$(path "$dest")"
    fi
    warn "reverted $dest"
}

list_backups() {
    section "Backups in $BACKUP_ROOT"
    local d n found=0
    for d in "$BACKUP_ROOT"/*/; do
        [[ -f "$d/manifest" ]] || continue
        found=1
        n=$(wc -l <"$d/manifest")
        printf '  %s%s%s  %s file(s)%s\n' "$C_ACCENT2" "$(basename "$d")" "$C_RESET" "$n" \
            "$( [[ -f "$d/restored" ]] && printf '  %s(restored)%s' "$C_DIM" "$C_RESET")"
    done
    (( found )) || skip "no backups yet"
}

# restore [RUN_ID|latest]: put every file of that run back the way it was.
restore_run() {
    local id=${1:-latest} dir kind dest
    if [[ "$id" == latest ]]; then
        id=$(find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -name manifest -printf '%h\n' 2>/dev/null \
            | xargs -r -n1 basename | sort | tail -n1)
        [[ -n "$id" ]] || die "no backups found in $BACKUP_ROOT"
    fi
    dir="$BACKUP_ROOT/$id"
    [[ -f "$dir/manifest" ]] || die "no backup named $id (see: secure-arch-setup restore --list)"
    section "Restoring run $id"
    confirm "Restore $(wc -l <"$dir/manifest") file(s) changed by run $id?" || { skip "cancelled"; return 0; }
    while read -r kind dest; do
        case "$kind" in
            modified)
                if (( DRY_RUN )); then info "would restore $dest"; continue; fi
                cp -a "$dir/files$dest" "$(path "$dest")" && ok "restored $dest" ;;
            created)
                if (( DRY_RUN )); then info "would remove $dest"; continue; fi
                rm -f "$(path "$dest")" && ok "removed $dest (did not exist before)" ;;
        esac
    done < <(tac "$dir/manifest")
    (( DRY_RUN )) || date '+%F %T' >"$dir/restored"
    info "reload what changed: sysctl --system · systemctl restart sshd nftables docker"
}

# ------------------------------------------------------------- packages
pkg_installed() { pacman -Qq "$1" &>/dev/null; }
pkg_in_repos()  { pacman -Si "$1" &>/dev/null; }

aur_helper() {
    local h
    for h in paru yay; do
        command -v "$h" &>/dev/null && { echo "$h"; return 0; }
    done
    return 1
}

# install_pkgs PKG... : repo packages through pacman, the rest through paru/yay as the
# invoking user (makepkg refuses to run as root). Already-installed packages are skipped.
install_pkgs() {
    local p have=() repo=() aur=() helper
    for p in "$@"; do
        if pkg_installed "$p"; then have+=("$p")
        elif pkg_in_repos "$p"; then repo+=("$p")
        else aur+=("$p")
        fi
    done
    (( ${#have[@]} )) && skip "already installed: ${have[*]}"
    (( ${#repo[@]} )) && run pacman -S --needed --noconfirm "${repo[@]}"
    if (( ${#aur[@]} )); then
        if helper=$(aur_helper) && [[ -n "$TARGET_USER" ]]; then
            run sudo -u "$TARGET_USER" "$helper" -S --needed --noconfirm "${aur[@]}"
        else
            warn "not in your repos, and no AUR helper (paru/yay) usable: ${aur[*]}"
        fi
    fi
    return 0
}

detect_target_user() {
    if [[ -z "$TARGET_USER" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
        TARGET_USER=$SUDO_USER
    fi
}
