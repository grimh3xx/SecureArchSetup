#!/usr/bin/env python3
import subprocess
import sys
import os
import shutil
import getpass
from datetime import datetime
from colorama import init, Fore, Style

init(autoreset=True)  # Inicializa colorama

LOG_FILE = "/var/log/arch_hardening.log"

# ------------------ Helper Functions ------------------

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{Fore.CYAN}{timestamp}{Style.RESET_ALL}] {msg}")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")

def run_cmd(cmd):
    log(f"{Fore.YELLOW}🚀 Executando: {' '.join(cmd)}{Style.RESET_ALL}")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        log(f"{Fore.RED}❌ Erro ao executar comando: {e}{Style.RESET_ALL}")
        return False
    return True

def check_root():
    if os.geteuid() != 0:
        log(f"{Fore.RED}⚠️ Execute este script como root!{Style.RESET_ALL}")
        sys.exit(1)

def confirmar_acao(mensagem):
    resp = input(f"{Fore.MAGENTA}{mensagem} [y/N]: {Style.RESET_ALL}")
    return resp.lower() == 'y'

# ------------------ Instalação de Pacotes ------------------

def instalar_pacote(pacote):
    log(f"📦 Instalando {pacote}...")
    result = subprocess.run(['pacman', '-Qi', pacote], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        run_cmd(['pacman', '-S', '--noconfirm', pacote])
        log(f"✅ {pacote} instalado com sucesso!")
    else:
        log(f"⚠️ {pacote} já está instalado.")

def instalar_aur(pacote):
    if shutil.which('yay') is None:
        log(f"{Fore.RED}❌ 'yay' não encontrado. Instale-o antes de usar pacotes AUR.{Style.RESET_ALL}")
        return
    log(f"📦 Instalando {pacote} (AUR)...")
    run_cmd(['yay', '-S', '--noconfirm', pacote])

# ------------------ Hardening ------------------

def aplicar_sysctl():
    config_file = '/etc/sysctl.d/99-hardening.conf'
    if os.path.exists(config_file):
        shutil.copy(config_file, config_file + '.bak')
        log(f"Backup de {config_file} criado.")

    config = '''fs.suid_dumpable = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
'''
    with open(config_file, 'w') as f:
        f.write(config)
    run_cmd(['sysctl', '--system'])
    log(f"{Fore.GREEN}✅ Configurações sysctl aplicadas.{Style.RESET_ALL}")

def hardening_ssh():
    sshd_config = '/etc/ssh/sshd_config'
    if os.path.exists(sshd_config):
        shutil.copy(sshd_config, sshd_config + '.bak')
        log(f"Backup de {sshd_config} criado.")
    lines = []
    with open(sshd_config, 'r') as f:
        for line in f:
            if line.startswith('PermitRootLogin'):
                lines.append('PermitRootLogin no\n')
            elif line.startswith('PasswordAuthentication'):
                lines.append('PasswordAuthentication yes\n')
            else:
                lines.append(line)
    with open(sshd_config, 'w') as f:
        f.writelines(lines)
    run_cmd(['systemctl', 'restart', 'sshd'])
    log(f"{Fore.GREEN}✅ SSH hardening aplicado.{Style.RESET_ALL}")

def instalar_kernel_hardened():
    instalar_pacote('linux-hardened')
    log(f"{Fore.YELLOW}⚠️ Após reiniciar, selecione o kernel linux-hardened no GRUB.{Style.RESET_ALL}")
    run_cmd(['grub-mkconfig', '-o', '/boot/grub/grub.cfg'])

# ------------------ Pentest ------------------

def instalar_pentest_basico():
    pacotes = ['nmap', 'nikto', 'netcat', 'tcpdump', 'wireshark-qt',
               'hashcat', 'aircrack-ng', 'hydra', 'john', 'dnsutils']
    for p in pacotes:
        instalar_pacote(p)

def instalar_pentest_aur():
    pacotes = ['metasploit', 'burpsuite', 'dirsearch', 'gobuster',
               'zaproxy', 'wfuzz', 'enum4linux', 'crackmapexec',
               'bettercap', 'seclists']
    for p in pacotes:
        instalar_aur(p)

def instalar_pentest_extras():
    pacotes = ['sqlmap', 'wpscan', 'masscan', 'ffuf']
    for p in pacotes:
        instalar_pacote(p)

# ------------------ Utilitários ------------------

def checar_suid():
    output_file = '/root/arquivos_suid.txt'
    with open(output_file, 'w') as f:
        subprocess.run(['find', '/', '-perm', '-4000', '-type', 'f'], stdout=f)
    log(f"{Fore.YELLOW}⚠️ Arquivos SUID listados em {output_file}.{Style.RESET_ALL}")

def checar_permissoes_criticas():
    output_file = '/root/world_writable.txt'
    with open(output_file, 'w') as f:
        subprocess.run(['find', '/', '-perm', '-2', '-type', 'f'], stdout=f)
    log(f"{Fore.YELLOW}⚠️ Arquivos world-writable listados em {output_file}.{Style.RESET_ALL}")

def backup_etc():
    dest = f"/root/etc_backup_{datetime.now().strftime('%Y%m%d%H%M%S')}.tar.gz"
    run_cmd(['tar', '-czf', dest, '/etc'])
    log(f"{Fore.GREEN}✅ Backup de /etc criado em {dest}.{Style.RESET_ALL}")

def relatorio_sistema():
    log(f"{Fore.CYAN}===== Relatório do Sistema ====={Style.RESET_ALL}")
    run_cmd(['uname', '-a'])
    run_cmd(['pacman', '-Qe'])

def atualizar_sistema():
    log(f"{Fore.CYAN}Atualizando sistema...{Style.RESET_ALL}")
    run_cmd(['pacman', '-Syu', '--noconfirm'])

def instalar_aide():
    instalar_pacote('aide')
    run_cmd(['aide', '--init'])
    shutil.move('/var/lib/aide/aide.db.new', '/var/lib/aide/aide.db')
    log(f"{Fore.GREEN}✅ AIDE instalado e inicializado.{Style.RESET_ALL}")

def checar_pacotes_atualizados():
    log(f"{Fore.CYAN}Verificando pacotes desatualizados...{Style.RESET_ALL}")
    run_cmd(['checkupdates'])

# ------------------ Menu Interativo ------------------

def menu():
    while True:
        print(f"""
{Fore.BLUE}{Style.BRIGHT}===== Painel de Segurança & Pentest Arch Linux ====={Style.RESET_ALL}
{Fore.GREEN}🔹 Hardening:{Style.RESET_ALL}
  1) 💻 Aplicar sysctl hardening
  2) 🔒 SSH hardening
  3) 🐧 Instalar kernel linux-hardened

{Fore.MAGENTA}🔹 Pentest:{Style.RESET_ALL}
  4) 🛠 Ferramentas básicas
  5) 🛠 Ferramentas AUR
  6) 🛠 Ferramentas extras (sqlmap, wpscan, masscan, ffuf)

{Fore.YELLOW}🔹 Utilitários:{Style.RESET_ALL}
  7) 📄 Checar arquivos SUID
  8) 📄 Checar permissões críticas
  9) 💾 Backup de /etc
  10) 📊 Relatório do sistema
  11) 🔄 Atualizar sistema
  12) 🛡 Instalar AIDE
  13) ⏳ Checar pacotes desatualizados

  0) 🚪 Sair
""")
        escolha = input(f"{Fore.CYAN}Escolha uma opção: {Style.RESET_ALL}")
        if escolha == '1':
            aplicar_sysctl()
        elif escolha == '2':
            hardening_ssh()
        elif escolha == '3':
            instalar_kernel_hardened()
        elif escolha == '4':
            instalar_pentest_basico()
        elif escolha == '5':
            instalar_pentest_aur()
        elif escolha == '6':
            instalar_pentest_extras()
        elif escolha == '7':
            checar_suid()
        elif escolha == '8':
            checar_permissoes_criticas()
        elif escolha == '9':
            backup_etc()
        elif escolha == '10':
            relatorio_sistema()
        elif escolha == '11':
            atualizar_sistema()
        elif escolha == '12':
            instalar_aide()
        elif escolha == '13':
            checar_pacotes_atualizados()
        elif escolha == '0':
            log(f"{Fore.GREEN}Saindo... 🔚{Style.RESET_ALL}")
            sys.exit(0)
        else:
            log(f"{Fore.RED}Opção inválida, tente novamente.{Style.RESET_ALL}")

# ------------------ Main ------------------

if __name__ == "__main__":
    check_root()
    try:
        menu()
    except KeyboardInterrupt:
        log(f"{Fore.RED}Interrompido pelo usuário. Saindo...{Style.RESET_ALL}")
