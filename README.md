<img src="docs/banner.svg" alt="SecureArchSetup" width="100%">

> **Automated secure Arch Linux setup** for developers, pentesters, and hardware enthusiasts.

![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Security](https://img.shields.io/badge/Security-Hardened-orange)
![Status](https://img.shields.io/badge/Status-Active-brightgreen)

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
