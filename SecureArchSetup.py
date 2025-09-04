#!/usr/bin/env python3
import subprocess
import sys
import os
import shutil
import getpass
from datetime import datetime

LOG_FILE = "/var/log/arch_hardening.log"

# ------------------ Helper Functions ------------------

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {msg}")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")

def run_cmd(cmd):
    log(f"🚀 Executando: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        log(f"❌ Erro ao executar comando: {e}")
        return False
    return True

def check_root():
    if os.geteuid() != 0:
        log("⚠️ Execute este script como root!")
        sys.exit(1)

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
        log("❌ 'yay' não encontrado. Instale-o antes de usar pacotes AUR.")
        return
    log(f"📦 Instalando {pacote} (AUR)...")
    run_cmd(['yay', '-S', '--noconfirm', pacote])

# ------------------ Docker ------------------

def configurar_docker():
    instalar_pacote('docker')
    run_cmd(['systemctl', 'enable', '--now', 'docker.service'])
    user = getpass.getuser()
    run_cmd(['usermod', '-aG', 'docker', user])

    daemon_file = '/etc/docker/daemon.json'
    if os.path.exists(daemon_file):
        shutil.copy(daemon_file, daemon_file + '.bak')
        log(f"Backup de {daemon_file} criado.")

    daemon_json = '''{
  "no-new-privileges": true,
  "userns-remap": "default"
}'''
    os.makedirs('/etc/docker', exist_ok=True)
    with open(daemon_file, 'w') as f:
        f.write(daemon_json)
    run_cmd(['systemctl', 'restart', 'docker'])
    log("✅ Docker configurado com segurança.")

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
    log("✅ Configurações sysctl aplicadas.")

def instalar_kernel_hardened():
    instalar_pacote('linux-hardened')
    log("⚠️ Após reiniciar, selecione o kernel linux-hardened no GRUB.")
    run_cmd(['grub-mkconfig', '-o', '/boot/grub/grub.cfg'])

def checar_suid():
    output_file = '/root/arquivos_suid.txt'
    with open(output_file, 'w') as f:
        subprocess.run(['find', '/', '-perm', '-4000', '-type', 'f'], stdout=f)
    log(f"⚠️ Arquivos SUID listados em {output_file}. Revise manualmente.")

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
    log("✅ SSH hardening aplicado.")

# ------------------ Automatização & Monitoramento ------------------

def atualizar_sistema():
    log("Atualizando sistema...")
    run_cmd(['pacman', '-Syu', '--noconfirm'])

def instalar_aide():
    instalar_pacote('aide')
    run_cmd(['aide', '--init'])
    shutil.move('/var/lib/aide/aide.db.new', '/var/lib/aide/aide.db')
    log("✅ AIDE instalado e inicializado para integridade do sistema.")

def relatorio_sistema():
    log("===== Relatório do Sistema =====")
    run_cmd(['uname', '-a'])
    run_cmd(['pacman', '-Qe'])

# ------------------ Conveniência ------------------

def checar_permissoes_criticas():
    output_file = '/root/world_writable.txt'
    with open(output_file, 'w') as f:
        subprocess.run(['find', '/', '-perm', '-2', '-type', 'f'], stdout=f)
    log(f"⚠️ Arquivos world-writable listados em {output_file}")

def backup_etc():
    dest = f"/root/etc_backup_{datetime.now().strftime('%Y%m%d%H%M%S')}.tar.gz"
    run_cmd(['tar', '-czf', dest, '/etc'])
    log(f"✅ Backup de /etc criado em {dest}")

def checar_pacotes_atualizados():
    log("Verificando pacotes desatualizados...")
    run_cmd(['checkupdates'])

# ------------------ Menu ------------------

def menu():
    while True:
        print("""
===== Menu Segurança Arch Linux =====
1) Instalar e configurar Docker seguro
2) Instalar ferramentas básicas de Pentest
3) Instalar ferramentas AUR de Pentest
4) Instalar ferramentas extras de Pentest
5) Aplicar hardening sysctl
6) Aplicar hardening SSH
7) Instalar kernel linux-hardened
8) Checar arquivos SUID no sistema
9) Atualizar sistema
10) Instalar AIDE (integridade)
11) Gerar relatório do sistema
12) Checar permissões críticas
13) Backup de /etc
14) Checar pacotes desatualizados
15) Sair
""")
        escolha = input("Escolha uma opção: ")
        if escolha == '1':
            configurar_docker()
        elif escolha == '2':
            instalar_pentest_basico()
        elif escolha == '3':
            instalar_pentest_aur()
        elif escolha == '4':
            instalar_pentest_extras()
        elif escolha == '5':
            aplicar_sysctl()
        elif escolha == '6':
            hardening_ssh()
        elif escolha == '7':
            instalar_kernel_hardened()
        elif escolha == '8':
            checar_suid()
        elif escolha == '9':
            atualizar_sistema()
        elif escolha == '10':
            instalar_aide()
        elif escolha == '11':
            relatorio_sistema()
        elif escolha == '12':
            checar_permissoes_criticas()
        elif escolha == '13':
            backup_etc()
