# shellcheck shell=bash
# Pentest toolkits, Docker, maintenance (updates, /etc snapshot, AIDE).

declare -A TOOLSETS=(
    [recon]="nmap masscan bind whois amass subfinder theharvester recon-ng httpx nuclei"
    [web]="nikto sqlmap wpscan gobuster ffuf feroxbuster dirsearch whatweb wfuzz zaproxy burpsuite"
    [network]="tcpdump wireshark-qt openbsd-netcat bettercap responder impacket netexec enum4linux proxychains-ng"
    [wireless]="aircrack-ng"
    [cracking]="hashcat john hydra seclists"
    [exploit]="metasploit exploitdb radare2 gdb ghidra binwalk"
)
TOOLSET_ORDER=(recon web network wireless cracking exploit)

install_toolset() {
    local name=$1
    [[ -n "${TOOLSETS[$name]:-}" ]] || die "unknown toolset '$name' (have: ${TOOLSET_ORDER[*]})"
    section "Tools · $name"
    # shellcheck disable=SC2086  # word splitting of the package list is intended
    install_pkgs ${TOOLSETS[$name]}
    if [[ "$name" == network && -n "$TARGET_USER" ]] && pkg_installed wireshark-qt; then
        run usermod -aG wireshark "$TARGET_USER"
        info "$TARGET_USER can capture with Wireshark after logging in again"
    fi
}

install_tools() {
    local sets=("$@") s
    (( ${#sets[@]} )) || sets=("${TOOLSET_ORDER[@]}")
    [[ "${sets[0]}" == all ]] && sets=("${TOOLSET_ORDER[@]}")
    for s in "${sets[@]}"; do install_toolset "$s"; done
}

# ------------------------------------------------------------- docker
DOCKER_DAEMON=/etc/docker/daemon.json

setup_docker() {
    section "Docker (hardened daemon)"
    install_pkgs docker docker-compose
    write_file "$DOCKER_DAEMON" <<'EOF' && (systemctl is-active --quiet docker 2>/dev/null && run systemctl restart docker || true)
{
  "no-new-privileges": true,
  "icc": false,
  "live-restore": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
    run systemctl enable --now docker.service
    if [[ -n "$TARGET_USER" ]]; then
        warn "the docker group is root-equivalent: anyone in it can mount / into a container"
        if confirm "Add $TARGET_USER to the docker group anyway?"; then
            run usermod -aG docker "$TARGET_USER"
        else
            info "skipped; use sudo docker, or rootless Docker (see README)"
        fi
    fi
}

# ------------------------------------------------------------- maintenance
update_system() {
    section "System update"
    run pacman -Syu --noconfirm
    if helper=$(aur_helper) && [[ -n "$TARGET_USER" ]]; then
        run sudo -u "$TARGET_USER" "$helper" -Sua --noconfirm
    fi
}

snapshot_etc() {
    section "Snapshot of /etc"
    local dest="/var/backups/secure-arch-setup/etc-$RUN_ID.tar.gz"
    run mkdir -p /var/backups/secure-arch-setup
    run tar --one-file-system -czf "$dest" -C / etc && info "saved to $dest"
}

setup_aide() {
    section "AIDE file integrity database"
    install_pkgs aide
    if ! command -v aide &>/dev/null && ! (( DRY_RUN )); then
        warn "aide is not available (it comes from the AUR or BlackArch)"
        return 0
    fi
    info "building the baseline (takes a few minutes)"
    run aide --init || return 0
    local new
    for new in /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.new; do
        if [[ -f "$new" ]]; then
            run mv "$new" "${new/.new/}"
        fi
    done
    info "later, check for changes with: sudo aide --check"
}
