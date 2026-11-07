#!/usr/bin/env bash
# Tests against a scratch root: SAS_ROOT prefixes every managed path and makes commands no-ops.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$HERE/secure-arch-setup"
PASS=0 FAIL=0

t() {  # t "name" command...
    local name=$1; shift
    if "$@" >/tmp/sas-test.out 2>&1; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$name"
    else FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$name"; sed 's/^/       /' /tmp/sas-test.out | tail -n 15; fi
}

fresh_root() {
    ROOT=$(mktemp -d)
    mkdir -p "$ROOT/etc" "$ROOT/home/alice/.ssh"
    touch "$ROOT/etc/arch-release"
}

cli() { SAS_ROOT="$ROOT" NO_COLOR=1 "$CLI" --yes "$@"; }

# source the libraries with the system-facing helpers stubbed out
lib() {
    SAS_ROOT="$ROOT" NO_COLOR=1 TARGET_USER=alice bash -c '
        SAS_VERSION=test
        for f in ui core harden tools audit; do source "'"$HERE"'/lib/$f.sh"; done
        pkg_installed() { [[ " ${INSTALLED:-} " == *" $1 "* ]]; }
        install_pkgs() { echo "install_pkgs $*"; }
        systemctl() { [[ "$*" == *"is-enabled"*sshd* && -n "${SSHD_ENABLED:-}" ]]; }
        getent() { echo "alice:x:1000:1000::/home/alice:/bin/bash"; }
        sshd() { echo "port 2222"; }
        '"$1"
}

echo "secure-arch-setup tests"

fresh_root
t "version"               bash -c "\"$CLI\" --version | grep -q '^secure-arch-setup '"
t "help lists commands"   bash -c "\"$CLI\" --help | grep -q 'restore \[ID|latest\]'"
t "refuses non-Arch"      bash -c "! SAS_ROOT=\$(mktemp -d) \"$CLI\" audit"

t "sysctl file is created" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; cli harden sysctl >/dev/null
    grep -q '^kernel.kptr_restrict = 2' $ROOT/etc/sysctl.d/90-secure-arch-setup.conf"
t "manifest records creation" bash -c "grep -qx 'created /etc/sysctl.d/90-secure-arch-setup.conf' $ROOT/var/backups/secure-arch-setup/*/manifest"
t "second run is a no-op" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; sleep 1; cli harden sysctl | grep -q 'already up to date'
    [[ \$(ls $ROOT/var/backups/secure-arch-setup | wc -l) == 1 ]]"

fresh_root
mkdir -p "$ROOT/etc/sysctl.d" && echo "custom = 1" >"$ROOT/etc/sysctl.d/90-secure-arch-setup.conf"
t "existing file is backed up" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; cli harden sysctl >/dev/null
    grep -qx 'custom = 1' $ROOT/var/backups/secure-arch-setup/*/files/etc/sysctl.d/90-secure-arch-setup.conf"
t "restore latest brings it back" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; cli restore latest >/dev/null
    grep -qx 'custom = 1' $ROOT/etc/sysctl.d/90-secure-arch-setup.conf"
t "restore --list shows the run" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; cli restore --list | grep -q restored"

fresh_root
t "dry run writes nothing" bash -c "$(declare -f cli); ROOT=$ROOT CLI=$CLI; cli --dry-run harden sysctl | grep -q 'would create'
    [[ ! -e $ROOT/etc/sysctl.d && ! -e $ROOT/var/backups ]]"

fresh_root
t "ssh keeps passwords without a key" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; INSTALLED=openssh lib harden_ssh >/dev/null
    grep -qx 'PasswordAuthentication yes' $ROOT/etc/ssh/sshd_config.d/50-secure-arch-setup.conf
    grep -qx 'PermitRootLogin no' $ROOT/etc/ssh/sshd_config.d/50-secure-arch-setup.conf"
echo "ssh-ed25519 AAAA test" >"$ROOT/home/alice/.ssh/authorized_keys"
t "ssh disables passwords with a key" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; INSTALLED=openssh lib harden_ssh >/dev/null
    grep -qx 'PasswordAuthentication no' $ROOT/etc/ssh/sshd_config.d/50-secure-arch-setup.conf"
t "ssh drop-in is 0600" bash -c "[[ \$(stat -c %a $ROOT/etc/ssh/sshd_config.d/50-secure-arch-setup.conf) == 600 ]]"
t "ssh skipped without openssh" bash -c "$(declare -f lib); ROOT=$(mktemp -d) HERE=$HERE; lib harden_ssh | grep -q 'not installed'"

fresh_root
t "firewall drops inbound, allows ssh port" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; INSTALLED='openssh nftables' SSHD_ENABLED=1 lib harden_firewall >/dev/null
    f=$ROOT/etc/nftables.conf; grep -q 'hook input priority filter; policy drop' \$f && grep -q 'tcp dport 2222' \$f && grep -q 'hook forward priority filter; policy drop' \$f"
fresh_root
t "firewall keeps forwarding for docker" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; INSTALLED='nftables docker' lib harden_firewall >/dev/null
    grep -q 'hook forward priority filter; policy accept' $ROOT/etc/nftables.conf && ! grep -q 'dport' $ROOT/etc/nftables.conf"

t "toolsets resolve" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; lib 'install_tools web' | grep -q 'install_pkgs nikto sqlmap'"
t "unknown toolset fails" bash -c "$(declare -f lib); ROOT=$ROOT HERE=$HERE; ! lib 'install_tools nope'"
t "audit runs read-only" bash -c "NO_COLOR=1 \"$CLI\" audit 2>&1 | grep -q 'passed ·'" 

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
