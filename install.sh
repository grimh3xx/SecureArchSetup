#!/bin/bash

REPO_URL="https://github.com/0xBl4ckn3t/SecureArchSetup.git"
PROJETO_DIR="meu-projeto"

echo "🚀 Iniciando instalador..."

# Verifica se git está instalado
if ! command -v git &> /dev/null; then
    echo "❌ Git não encontrado. Instalando git..."
    sudo pacman -S --noconfirm git
fi

# Clona o repositório se não existir
if [ ! -d "$PROJETO_DIR" ]; then
    echo "Clonando repositório..."
    git clone "$REPO_URL"
else
    echo "Pasta $PROJETO_DIR já existe, pulando clone."
fi

cd "$PROJETO_DIR" || { echo "Não foi possível acessar a pasta $PROJETO_DIR"; exit 1; }

# Dá permissão de execução ao script principal
chmod +x seguranca_arch.py

echo "Executando o script principal..."
sudo ./seguranca_arch.py

echo "✔️ Instalação concluída!"
