# SecureArchSetup
Python script to automate a secure Arch Linux setup for developers, pentesters, and hardware enthusiasts. Installs Docker hardened, pentesting tools, kernel hardening, and audits SUID files. Features an interactive menu and AUR support for easy customization and robust security.


Installation Guide for Your Project on Arch Linux
Follow these simple steps to get your secure Arch Linux environment set up quickly.

1. Install Git (if not already installed)
Open your terminal and run:

sudo pacman -S --noconfirm git

2. Clone the Project Repository

git clone https://github.com/0xBl4ckn3t/SecureArchSetup

This will create a folder named yourrepository in your current directory.

4. Navigate to the Project Directory

cd SecureArchSetup

5. Make the Main Script Executable
If your main script is named seguranca_arch.py, run:

chmod +x seguranca_arch.py

5. (Optional) Make the Installer Script Executable
If you have an installer script like install.sh, give it execute permission as well:

chmod +x install.sh

6. Run the Installer Script (Recommended)
Run the installer with administrative privileges to set up everything automatically:

sudo ./install.sh

