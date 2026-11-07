# shellcheck shell=bash
# Read-only audit: scores the running system and writes a Markdown report. Changes nothing.

AUDIT_PASS=0 AUDIT_WARN=0 AUDIT_FAIL=0
REPORT=""

_pass() { AUDIT_PASS=$((AUDIT_PASS + 1)); printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; REPORT+="- ✅ $*"$'\n'; }
_warnr() { AUDIT_WARN=$((AUDIT_WARN + 1)); printf '  %s!%s %s\n' "$C_WARN" "$C_RESET" "$*"; REPORT+="- ⚠️ $*"$'\n'; }
_fail() { AUDIT_FAIL=$((AUDIT_FAIL + 1)); printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$*"; REPORT+="- ❌ $*"$'\n'; }
_head() { section "$*"; REPORT+=$'\n'"## $*"$'\n\n'; }

audit_sysctl() {
    _head "Kernel parameters"
    local rule key want why have bad=0
    for rule in "${SYSCTL_RULES[@]}"; do
        read -r key want why <<<"$rule"
        have=$(sysctl -n "$key" 2>/dev/null) || continue  # not present on this kernel
        if [[ "$have" != "$want" ]]; then
            bad=$((bad + 1))
            printf '    %s%-44s%s %s%s%s → %s%s%s  %s%s%s\n' "$C_TEXT" "$key" "$C_RESET" "$C_ERR" "$have" "$C_RESET" \
                "$C_OK" "$want" "$C_RESET" "$C_DIM" "$why" "$C_RESET"
            REPORT+="  - \`$key\` is $have, recommended $want ($why)"$'\n'
        fi
    done
    if (( bad == 0 )); then _pass "all ${#SYSCTL_RULES[@]} recommended kernel parameters are set"
    else _fail "$bad of ${#SYSCTL_RULES[@]} kernel parameters differ from the recommendation"; fi
}

audit_ssh() {
    _head "OpenSSH server"
    if ! command -v sshd &>/dev/null; then _pass "sshd is not installed"; return; fi
    if ! systemctl is-active --quiet sshd 2>/dev/null; then _pass "sshd is installed but not running"; fi
    local conf
    conf=$(sshd -T 2>/dev/null) || { _warnr "could not read the effective sshd config (run as root)"; return; }
    grep -qx "permitrootlogin no" <<<"$conf" && _pass "root login disabled" || _fail "root can log in over SSH"
    grep -qx "passwordauthentication no" <<<"$conf" && _pass "password login disabled (keys only)" \
        || _warnr "password login enabled"
    grep -qx "x11forwarding no" <<<"$conf" && _pass "X11 forwarding disabled" || _warnr "X11 forwarding enabled"
}

audit_firewall() {
    _head "Firewall"
    if systemctl is-active --quiet nftables 2>/dev/null; then
        if nft list ruleset 2>/dev/null | grep -q "hook input.*policy drop"; then _pass "nftables active with a default-drop input policy"
        else _warnr "nftables is active but the input policy is not drop"; fi
    elif systemctl is-active --quiet ufw 2>/dev/null || systemctl is-active --quiet firewalld 2>/dev/null; then
        _pass "a firewall service (ufw/firewalld) is active"
    else
        _fail "no firewall is active"
    fi
    local listening
    if ! command -v ss &>/dev/null; then _warnr "ss (iproute2) missing: listening sockets not checked"; return; fi
    listening=$(ss -Htuln 2>/dev/null | awk '{print $1, $5}' | grep -vE ' (127\.|\[::1\]|::1)' | sort -u)
    if [[ -n "$listening" ]]; then
        _warnr "$(wc -l <<<"$listening") socket(s) listening on non-loopback addresses"
        sed "s/^/      ${C_DIM}/; s/\$/${C_RESET}/" <<<"$listening"
        REPORT+=$(sed 's/^/  - `/; s/$/`/' <<<"$listening")$'\n'
    else
        _pass "nothing listens on external interfaces"
    fi
}

audit_suid() {
    _head "SUID / SGID binaries"
    local f owner unowned=() total=0
    while IFS= read -r f; do
        total=$((total + 1))
        owner=$(pacman -Qoq "$f" 2>/dev/null) || unowned+=("$f")
        : "$owner"
    done < <(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null)
    if (( ${#unowned[@]} )); then
        _fail "${#unowned[@]} of $total SUID/SGID files are not owned by any package"
        printf "      ${C_DIM}%s${C_RESET}\n" "${unowned[@]}"
        REPORT+=$(printf '  - `%s`\n' "${unowned[@]}")$'\n'
    else
        _pass "all $total SUID/SGID files belong to installed packages"
    fi
}

audit_world_writable() {
    _head "World-writable paths"
    local files dirs
    files=$(find / -xdev -type f -perm -0002 \
        -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -not -path '/run/*' \
        -not -path '/tmp/*' -not -path '/var/tmp/*' 2>/dev/null | head -n 50)
    dirs=$(find / -xdev -type d -perm -0002 -not -perm -1000 \
        -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -not -path '/run/*' 2>/dev/null | head -n 50)
    [[ -z "$files" ]] && _pass "no world-writable files" || { _fail "world-writable files found"; sed "s/^/      ${C_DIM}/; s/\$/${C_RESET}/" <<<"$files"; }
    [[ -z "$dirs" ]] && _pass "every world-writable directory has the sticky bit" \
        || { _fail "world-writable directories without the sticky bit"; sed "s/^/      ${C_DIM}/; s/\$/${C_RESET}/" <<<"$dirs"; }
}

audit_system() {
    _head "System"
    local failed upd vulns
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    [[ -z "$failed" ]] && _pass "no failed systemd units" || _warnr "failed units: $(tr '\n' ' ' <<<"$failed")"
    if command -v checkupdates &>/dev/null; then
        upd=$(checkupdates 2>/dev/null | wc -l)
        (( upd == 0 )) && _pass "system is up to date" || _warnr "$upd package update(s) pending"
    else
        _warnr "pacman-contrib not installed: pending updates not checked"
    fi
    if command -v arch-audit &>/dev/null; then
        vulns=$(arch-audit -u 2>/dev/null | wc -l)
        (( vulns == 0 )) && _pass "no packages with known, fixed vulnerabilities" \
            || _fail "$vulns package(s) have security fixes waiting (arch-audit -u)"
    else
        _warnr "arch-audit not installed: known CVEs not checked"
    fi
    case "$(uname -r)" in
        *hardened*) _pass "running linux-hardened ($(uname -r))" ;;
        *) _warnr "not running linux-hardened ($(uname -r))" ;;
    esac
}

run_audit() {
    REPORT="# secure-arch-setup audit · $(hostname 2>/dev/null || cat /etc/hostname) · $(date '+%F %T')"$'\n'
    (( EUID == 0 )) || warn "not running as root: some checks will be incomplete"
    audit_sysctl
    audit_ssh
    audit_firewall
    audit_suid
    audit_world_writable
    audit_system
    local total=$((AUDIT_PASS + AUDIT_WARN + AUDIT_FAIL)) score
    score=$(( total ? (AUDIT_PASS * 100 + AUDIT_WARN * 50) / total : 0 ))
    section "Score"
    local color=$C_ERR
    (( score >= 60 )) && color=$C_WARN
    (( score >= 85 )) && color=$C_OK
    local bar="" i
    for ((i = 0; i < 40; i++)); do
        if (( i < score * 40 / 100 )); then bar+="${color}━"; else bar+="${C_DIM}━"; fi
    done
    printf '  %s%s%%%s  %s%s\n' "$color$C_BOLD" "$score" "$C_RESET" "$bar" "$C_RESET"
    printf '  %s%d passed · %d warnings · %d failed%s\n' "$C_MUTED" "$AUDIT_PASS" "$AUDIT_WARN" "$AUDIT_FAIL" "$C_RESET"
    REPORT+=$'\n'"**Score: $score%** · $AUDIT_PASS passed · $AUDIT_WARN warnings · $AUDIT_FAIL failed"$'\n'
    if (( EUID == 0 )) && ! (( DRY_RUN )); then
        local out
        out="$(path /var/log/secure-arch-setup)/audit-$RUN_ID.md"
        mkdir -p "$(dirname "$out")" && printf '%s' "$REPORT" >"$out" && info "report saved to $out"
    fi
}
