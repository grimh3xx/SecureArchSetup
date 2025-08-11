#!/usr/bin/env python3
import subprocess
import sys

def run_cmd(cmd, sudo=True):
    if sudo:
        cmd = ['sudo'] + cmd
    print(f"\n🚀 Executando: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        print("Erro ao executar comando!!! ")
        sys.exit(1)

def instalar_pacote(pacote):
    print(f"📦 Instalando {pacote}...")
    run_cmd(['pacman', '-S', '--noconfirm', pacote])

def instalar_aur(pacote):
    print(f"📦 Instalando {pacote} (AUR)...")
    run_cmd(['yay', '-S', '--noconfirm', pacote])

def configurar_docker():
    instalar_pacote('docker')
    run_cmd(['systemctl', 'enable', '--now', 'docker.service'])
    run_cmd(['usermod', '-aG', 'docker', subprocess.getoutput('whoami')])
    print("Configurando Docker daemon para segurança extra...")
    daemon_json = '''{
  "no-new-privileges": true,
  "userns-remap": "default"
}'''
    run_cmd(['mkdir', '-p', '/etc/docker'])
    with open('/etc/docker/daemon.json', 'w') as f:
        f.write(daemon_json)
    run_cmd(['systemctl', 'restart', 'docker'])

def instalar_pentest_basico():
    pacotes = ['nmap', 'nikto', 'netcat', 'tcpdump', 'wireshark-qt', 'hashcat', 'aircrack-ng', 'hydra', 'john', 'dnsutils']
    for p in pacotes:
        instalar_pacote(p)

def instalar_pentest_aur():
    pacotes = ['metasploit', 'burpsuite', 'dirsearch', 'gobuster', 'zaproxy', 'wfuzz', 'enum4linux', 'crackmapexec', 'bettercap', 'seclists']
    for p in pacotes:
        instalar_aur(p)

def aplicar_sysctl():
    config = '''fs.suid_dumpable = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
'''
    print("Aplicando configurações de sysctl...")
    with open('/etc/sysctl.d/99-hardening.conf', 'w') as f:
        f.write(config)
    run_cmd(['sysctl', '--system'])

def instalar_kernel_hardened():
    instalar_pacote('linux-hardened')
    print("⚠️ Após reiniciar, selecione o kernel linux-hardened no GRUB.")
    run_cmd(['grub-mkconfig', '-o', '/boot/grub/grub.cfg'])

def checar_suid():
    print("Buscando arquivos SUID...")
    with open('/root/arquivos_suid.txt', 'w') as f:
        subprocess.run(['find', '/', '-perm', '-4000', '-type', 'f'], stdout=f)
    print("⚠️ Arquivos SUID listados em /root/arquivos_suid.txt - revise manualmente.")

def menu():
    while True:
        print("""
===== Menu Segurança Arch Linux =====
1) Instalar e configurar Docker seguro
2) Instalar ferramentas básicas de Pentest
3) Instalar ferramentas AUR de Pentest
4) Aplicar hardening sysctl
5) Instalar kernel linux-hardened
6) Checar arquivos SUID no sistema
7) Sair
""")
        escolha = input("Escolha uma opção: ")
        if escolha == '1':
            configurar_docker()
        elif escolha == '2':
            instalar_pentest_basico()
        elif escolha == '3':
            instalar_pentest_aur()
        elif escolha == '4':
            aplicar_sysctl()
        elif escolha == '5':
            instalar_kernel_hardened()
        elif escolha == '6':
            checar_suid()
        elif escolha == '7':
            print("Saindo... 🔚")
            sys.exit(0)
        else:
            print("Opção inválida, tente novamente.")

if __name__ == "__main__":
    try:
        menu()
    except KeyboardInterrupt:
        print("\nInterrompido pelo usuário. Saindo...")
