<img src="docs/banner.svg" alt="SecureArchSetup" width="100%">

> **Automated secure Arch Linux setup** for developers, pentesters, and hardware enthusiasts.

[![build](https://img.shields.io/github/actions/workflow/status/grimh3xx/SecureArchSetup/build.yml?branch=main&style=flat-square&labelColor=111826&label=build)](https://github.com/grimh3xx/SecureArchSetup/actions)
[![license](https://img.shields.io/github/license/grimh3xx/SecureArchSetup?style=flat-square&labelColor=111826&color=22D3EE)](LICENSE)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-hardened-3B82F6?style=flat-square&labelColor=111826)
![python](https://img.shields.io/badge/python-3-22D3EE?style=flat-square&labelColor=111826)

## 📖 About
**SecureArchSetup** is a Python-powered automation tool that transforms a fresh Arch Linux install into a hardened, developer- and pentester-friendly environment.  
It focuses on **security**, **automation**, and **customization**, providing:

- 🔒 **Kernel Hardening** & security tweaks
- 🐳 **Hardened Docker** installation
- 🛠 **Pentesting toolkit** ready to use
- 🔍 **SUID audit** with removal suggestions
- 🖥 **Interactive menu** with AUR support

---

## 📦 Requirements
- Arch Linux (fresh or existing install)
- Internet connection
- `sudo` privileges

---

## 🚀 Installation

```bash
# 1️⃣ Install Git
sudo pacman -S --noconfirm git

# 2️⃣ Clone the repository
git clone https://github.com/0xBl4ckn3t/SecureArchSetup
cd SecureArchSetup

# 3️⃣ Make scripts executable
chmod +x SecureArchSetup.py

# 4️⃣ Run the installer (recommended)
sudo python3 SecureArchSetup.py
