#!/usr/bin/env python3
import subprocess
import sys
import os
import shutil
import getpass
from datetime import datetime
from time import sleep
from colorama import init, Fore, Style

init(autoreset=True)

LOG_FILE = "/var/log/arch_hardening.log"
RELATORIO_FINAL = "/root/relatorio_final.txt"

# ------------------ Helper Functions ------------------

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{Fore.CYAN}{timestamp}{Style.RESET_ALL}] {msg}")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")
    with open(RELATORIO_FINAL, "a") as f:
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

def barra_progresso(msg, duracao=1):
    print(f"{Fore.BLUE}{msg}...{Style.RESET_ALL}")
    for _ in range(3):
        print(".", end='', flush=True)
        sleep(duracao/3)
    print(" ✅")

# ------------------ Pacotes ------------------

def instalar_pacote(pacote):
    result = subprocess.run(['pacman', '-Qi', pacote], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        barra_progresso(f"Instalando {pacote}")
        run_cmd(['pacman', '-S', '--noconfirm', pacote])
    else:
        log(f"⚠️ {pacote} já está instalado.")

def instalar_aur(pacote):
    if shutil.which('yay') is None:
        log(f"{Fore.RED}❌ 'yay' não encontrado.{Style.RESET_ALL}")
        return
    barra_progresso(f"Instalando {pacote} (AUR)")
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
    log(f"{Fore.GREEN}✅ Sysctl aplicado.{Style.RESET_ALL}")

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

# ------------------ Docker ------------------

def configurar_docker():
    instalar_pacote('docker')
    run_cmd(['systemctl', 'enable', '--now', 'docker.service'])
    user = getpass.getuser()
    run_cmd(['usermod', '-aG', 'docker', user])
    daemon_file = '/etc/docker/daemon.json'
    if os.path.exists(daemon_file):
        shutil.copy(daemon_file, daemon_file + '.bak')
    daemon_json = '''{
  "no-new-privileges": true,
  "userns-remap": "default"
}'''
    os.makedirs('/etc/docker', exist_ok=True)
    with open(daemon_file, 'w') as f:
        f.write(daemon_json)
    run_cmd(['systemctl', 'restart', 'docker'])
    log(f"{Fore.GREEN}✅ Docker seguro configurado.{Style.RESET_ALL}")

# ------------------ Pentest ------------------

def instalar_pentest_basico():
    pacotes = ['nmap','nikto','netcat','tcpdump','wireshark-qt','hashcat','aircrack-ng','hydra','john','dnsutils']
    for p in pacotes:
        instalar_pacote(p)

def instalar_pentest_aur():
    pacotes = ['metasploit','burpsuite','dirsearch','gobuster','zaproxy','wfuzz','enum4linux','crackmapexec','bettercap','seclists']
    for p in pacotes:
        instalar_aur(p)

def instalar_pentest_extras():
    pacotes = ['sqlmap','wpscan','masscan','ffuf']
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
    run_cmd(['tar','-czf',dest,'/etc'])
    log(f"{Fore.GREEN}✅ Backup de /etc criado em {dest}.{Style.RESET_ALL}")

def relatorio_sistema():
    log(f"{Fore.CYAN}===== Relatório do Sistema ====={Style.RESET_ALL}")
    run_cmd(['uname','-a'])
    run_cmd(['pacman','-Qe'])

def atualizar_sistema():
    log(f"{Fore.CYAN}Atualizando sistema...{Style.RESET_ALL}")
    run_cmd(['pacman','-Syu','--noconfirm'])

def instalar_aide():
    instalar_pacote('aide')
    run_cmd(['aide','--init'])
    shutil.move('/var/lib/aide/aide.db.new','/var/lib/aide/aide.db')
    log(f"{Fore.GREEN}✅ AIDE instalado e inicializado.{Style.RESET_ALL}")

def checar_pacotes_atualizados():
    log(f"{Fore.CYAN}Verificando pacotes desatualizados...{Style.RESET_ALL}")
    run_cmd(['checkupdates'])

# ------------------ Menus ------------------

def menu_hardening():
    while True:
        print(f"""
{Fore.GREEN}===== Hardening ====={Style.RESET_ALL}
1) 💻 Aplicar sysctl hardening
2) 🔒 SSH hardening
3) 🐧 Instalar kernel linux-hardened
0) 🔙 Voltar
""")
        escolha = input(f"{Fore.CYAN}Escolha: {Style.RESET_ALL}")
        if escolha == '1':
            aplicar_sysctl()
        elif escolha == '2':
            hardening_ssh()
        elif escolha == '3':
            instalar_kernel_hardened()
        elif escolha == '0':
            return
        else:
            log(f"{Fore.RED}Opção inválida.{Style.RESET_ALL}")

def menu_pentest():
    while True:
        print(f"""
{Fore.MAGENTA}===== Pentest ====={Style.RESET_ALL}
1) 🛠 Ferramentas básicas
2) 🛠 Ferramentas AUR
3) 🛠 Ferramentas extras
0) 🔙 Voltar
""")
        escolha = input(f"{Fore.CYAN}Escolha: {Style.RESET_ALL}")
        if escolha == '1':
            instalar_pentest_basico()
        elif escolha == '2':
            instalar_pentest_aur()
        elif escolha == '3':
            instalar_pentest_extras()
        elif escolha == '0':
            return
        else:
            log(f"{Fore.RED}Opção inválida.{Style.RESET_ALL}")

def menu_utilitarios():
    while True:
        print(f"""
{Fore.YELLOW}===== Utilitários ====={Style.RESET_ALL}
1) 📄 Checar arquivos SUID
2) 📄 Checar permissões críticas
3) 💾 Backup de /etc
4) 📊 Relatório do sistema
5) 🔄 Atualizar sistema
6) 🛡 Instalar AIDE
7) ⏳ Checar pacotes desatualizados
0) 🔙 Voltar
""")
        escolha = input(f"{Fore.CYAN}Escolha: {Style.RESET_ALL}")
        if escolha == '1':
            checar_suid()
        elif escolha == '2':
            checar_permissoes_criticas()
        elif escolha == '3':
            backup_etc()
        elif escolha == '4':
            relatorio_sistema()
        elif escolha == '5':
            atualizar_sistema()
        elif escolha == '6':
            instalar_aide()
        elif escolha == '7':
            checar_pacotes_atualizados()
        elif escolha == '0':
            return
        else:
            log(f"{Fore.RED}Opção inválida.{Style.RESET_ALL}")

def menu_principal():
    while True:
        print(f"""
{Fore.BLUE}{Style.BRIGHT}===== Painel Ultimate Arch Linux ====={Style.RESET_ALL}
1) 🛡 Hardening
2) 🛠 Pentest
3) ⚙️ Utilitários
4) 🐳 Configurar Docker seguro
0) 🚪 Sair
""")
        escolha = input(f"{Fore.CYAN}Escolha uma opção: {Style.RESET_ALL}")
        if escolha == '1':
            menu_hardening()
        elif escolha == '2':
            menu_pentest()
        elif escolha == '3':
            menu_utilitarios()
        elif escolha ==
