# shellcheck shell=bash
# System hardening: kernel parameters, SSH, firewall, hardened kernel.

SYSCTL_FILE=/etc/sysctl.d/90-secure-arch-setup.conf
SSHD_DROPIN=/etc/ssh/sshd_config.d/50-secure-arch-setup.conf
NFT_FILE=/etc/nftables.conf

# key value why — also used by the audit to score the running system
SYSCTL_RULES=(
    "kernel.kptr_restrict 2 hide kernel pointers from unprivileged users"
    "kernel.dmesg_restrict 1 only root reads the kernel log"
    "kernel.unprivileged_bpf_disabled 1 no eBPF for unprivileged users"
    "net.core.bpf_jit_harden 2 harden the BPF JIT against spraying"
    "kernel.kexec_load_disabled 1 no replacing the running kernel"
    "kernel.yama.ptrace_scope 1 processes can only ptrace their children"
    "kernel.sysrq 0 disable magic SysRq"
    "fs.suid_dumpable 0 no core dumps from setuid programs"
    "fs.protected_symlinks 1 block symlink attacks in sticky dirs"
    "fs.protected_hardlinks 1 block hardlink attacks"
    "fs.protected_fifos 2 block FIFO spoofing in sticky dirs"
    "fs.protected_regular 2 block file spoofing in sticky dirs"
    "net.ipv4.tcp_syncookies 1 SYN flood protection"
    "net.ipv4.tcp_rfc1337 1 drop RST for TIME-WAIT sockets"
    "net.ipv4.conf.all.rp_filter 1 reverse path filtering (anti-spoofing)"
    "net.ipv4.conf.default.rp_filter 1 reverse path filtering for new interfaces"
    "net.ipv4.conf.all.accept_redirects 0 ignore ICMP redirects"
    "net.ipv4.conf.default.accept_redirects 0 ignore ICMP redirects on new interfaces"
    "net.ipv4.conf.all.secure_redirects 0 ignore 'secure' redirects too"
    "net.ipv6.conf.all.accept_redirects 0 ignore IPv6 redirects"
    "net.ipv6.conf.default.accept_redirects 0 ignore IPv6 redirects on new interfaces"
    "net.ipv4.conf.all.send_redirects 0 this is not a router"
    "net.ipv4.conf.default.send_redirects 0 this is not a router"
    "net.ipv4.conf.all.accept_source_route 0 refuse source-routed packets"
    "net.ipv6.conf.all.accept_source_route 0 refuse source-routed IPv6 packets"
    "net.ipv4.conf.all.log_martians 1 log impossible source addresses"
    "net.ipv4.icmp_echo_ignore_broadcasts 1 no smurf amplification"
    "net.ipv4.icmp_ignore_bogus_error_responses 1 ignore bogus ICMP errors"
)

harden_sysctl() {
    section "Kernel parameters (sysctl)"
    local rule key val why
    {
        echo "# Managed by secure-arch-setup. Remove this file (or run: secure-arch-setup restore) to undo."
        for rule in "${SYSCTL_RULES[@]}"; do
            read -r key val why <<<"$rule"
            printf '# %s\n%s = %s\n' "$why" "$key" "$val"
        done
    } | write_file "$SYSCTL_FILE" && run sysctl --quiet --system
    info "${#SYSCTL_RULES[@]} parameters in $SYSCTL_FILE"
}

sshd_port() {
    local p
    p=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')
    echo "${p:-22}"
}

harden_ssh() {
    section "OpenSSH server"
    if ! pkg_installed openssh; then
        skip "openssh is not installed"
        return 0
    fi
    # Disabling passwords without a working key would lock the user out of a remote box.
    local keys="" home password=yes
    if [[ -n "$TARGET_USER" ]]; then
        home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        keys=$(path "$home/.ssh/authorized_keys")
    fi
    if [[ -n "$keys" && -s "$keys" ]]; then
        password=no
        ok "$TARGET_USER has authorized keys: password login will be disabled"
    else
        warn "no ~/.ssh/authorized_keys for ${TARGET_USER:-the invoking user}: keeping password login so you are not locked out"
        info "add a key (ssh-copy-id) and run this step again to disable passwords"
    fi
    write_file "$SSHD_DROPIN" 600 <<EOF || return 0
# Managed by secure-arch-setup
PermitRootLogin no
PasswordAuthentication $password
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    (( DRY_RUN )) && return 0
    if [[ -z "$SAS_ROOT" ]] && ! sshd -t 2>/dev/null; then
        err "sshd rejected the new configuration"
        revert_file "$SSHD_DROPIN"
        return 1
    fi
    if systemctl is-active --quiet sshd; then
        run systemctl reload sshd
    fi
}

harden_firewall() {
    section "Firewall (nftables)"
    install_pkgs nftables
    local ssh_rule="" forward=drop port
    if pkg_installed openssh && systemctl is-enabled --quiet sshd 2>/dev/null; then
        port=$(sshd_port)
        ssh_rule="        tcp dport $port ct state new limit rate 15/minute accept comment \"ssh\""
        info "sshd is enabled: allowing tcp/$port (rate limited)"
    fi
    if pkg_installed docker; then
        forward=accept  # containers need forwarding; Docker adds its own rules on top
        info "docker is installed: keeping forwarding open for containers"
    fi
    if [[ -f "$(path "$NFT_FILE")" ]] && ! grep -q "secure-arch-setup" "$(path "$NFT_FILE")"; then
        warn "replacing a custom $NFT_FILE (a backup is kept)"
        confirm "Replace it?" || { skip "firewall unchanged"; return 0; }
    fi
    write_file "$NFT_FILE" <<EOF || return 0
#!/usr/bin/nft -f
# Managed by secure-arch-setup: drop unsolicited inbound traffic, allow everything outbound.
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state invalid drop
        ct state { established, related } accept
        iif lo accept
        meta l4proto ipv6-icmp accept
        icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
$ssh_rule
    }
    chain forward {
        type filter hook forward priority filter; policy $forward;
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
    run nft -c -f "$NFT_FILE" && run systemctl enable --now nftables && run systemctl restart nftables
    if pkg_installed docker && systemctl is-active --quiet docker 2>/dev/null; then
        run systemctl restart docker  # re-create Docker's chains after the flush
    fi
}

harden_kernel() {
    section "linux-hardened kernel"
    install_pkgs linux-hardened linux-hardened-headers
    if command -v grub-mkconfig &>/dev/null && [[ -d "$(path /boot/grub)" ]]; then
        run grub-mkconfig -o /boot/grub/grub.cfg
        info "pick linux-hardened in the GRUB menu on the next boot; the stock kernel stays as a fallback"
    elif command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null; then
        warn "systemd-boot detected: add a loader entry for vmlinuz-linux-hardened (see README)"
    else
        warn "bootloader not detected: add linux-hardened to it manually"
    fi
}
