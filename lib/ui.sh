# shellcheck shell=bash
# Terminal output: grimh3xx palette, status lines, prompts.
# shellcheck disable=SC2034  # colours are used by the other modules

if [[ ( -t 1 || -n "${FORCE_COLOR:-}" ) && -z "${NO_COLOR:-}" ]]; then
    C_ACCENT=$'\e[38;2;59;130;246m'  C_ACCENT2=$'\e[38;2;34;211;238m'
    C_TITLE=$'\e[1;38;2;241;245;251m' C_TEXT=$'\e[38;2;197;207;221m'
    C_MUTED=$'\e[38;2;139;152;173m'  C_DIM=$'\e[38;2;91;102;120m'
    C_OK=$'\e[38;2;52;211;153m'      C_WARN=$'\e[38;2;251;191;36m'
    C_ERR=$'\e[38;2;248;113;113m'    C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_ACCENT='' C_ACCENT2='' C_TITLE='' C_TEXT='' C_MUTED='' C_DIM=''
    C_OK='' C_WARN='' C_ERR='' C_BOLD='' C_RESET=''
fi

banner() {
    local l1="╔═╗╔═╗╔═╗╦ ╦╦═╗╔═╗  ╔═╗╦═╗╔═╗╦ ╦"
    local l2="╚═╗║╣ ║  ║ ║╠╦╝║╣   ╠═╣╠╦╝║  ╠═╣"
    local l3="╚═╝╚═╝╚═╝╚═╝╩╚═╚═╝  ╩ ╩╩╚═╚═╝╩ ╩"
    printf '\n'
    printf '  %s%s%s\n' "$C_ACCENT" "$l1" "$C_RESET"
    printf '  %s%s%s   %sSETUP%s %sv%s%s\n' "$C_ACCENT" "$l2" "$C_RESET" "$C_ACCENT2$C_BOLD" "$C_RESET" "$C_DIM" "$SAS_VERSION" "$C_RESET"
    printf '  %s%s%s   %sHardening & pentest setup for Arch Linux%s\n' "$C_ACCENT2" "$l3" "$C_RESET" "$C_MUTED" "$C_RESET"
    printf '  %sgithub.com/grimh3xx/SecureArchSetup%s\n' "$C_DIM" "$C_RESET"
    if (( DRY_RUN )); then
        printf '\n  %s● DRY RUN%s %s— nothing will be changed%s\n' "$C_WARN$C_BOLD" "$C_RESET" "$C_MUTED" "$C_RESET"
    fi
}

section() { printf '\n%s▍%s %s%s%s\n' "$C_ACCENT2" "$C_RESET" "$C_TITLE" "$*" "$C_RESET"; _log "== $*"; }
info()    { printf '  %s•%s %s\n' "$C_ACCENT" "$C_RESET" "$*"; _log "info: $*"; }
ok()      { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; _log "ok: $*"; }
skip()    { printf '  %s−%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_MUTED" "$*" "$C_RESET"; _log "skip: $*"; }
warn()    { printf '  %s!%s %s\n' "$C_WARN" "$C_RESET" "$*"; _log "warn: $*"; }
err()     { printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; _log "error: $*"; }
die()     { err "$*"; exit 1; }

# confirm "question" -> 0 for yes. --yes answers yes; dry runs never need to ask.
confirm() {
    (( ASSUME_YES || DRY_RUN )) && return 0
    local reply
    read -r -p "  ${C_ACCENT2}?${C_RESET} $1 ${C_DIM}[y/N]${C_RESET} " reply
    [[ "$reply" =~ ^[YysS]$ ]]
}
