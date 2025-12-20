#!/bin/bash
# Run this on your fresh VPS
# Usage: curl -sSL https://raw.githubusercontent.com/harnguyen/WealthPath/main/scripts/server-setup.sh | bash

set -e

echo "🚀 WealthPath Server Setup"
echo "=========================="

# Update system
echo "📦 Updating system..."
apt update && apt upgrade -y

# Install Docker
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com | sh

# Install Docker Compose
echo "📦 Installing Docker Compose..."
apt install -y docker-compose-plugin

# Add current user to docker group
usermod -aG docker $USER

# Install Caddy (for SSL/reverse proxy)
echo "🔒 Installing Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Create app directory
mkdir -p /opt/wealthpath
cd /opt/wealthpath

# Clone repo
echo "📥 Cloning WealthPath..."
git clone https://github.com/harnguyen/WealthPath.git .

# Generate secrets
echo "🔐 Generating secrets..."
JWT_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)

# Create .env file
cat > .env << EOF
POSTGRES_USER=wealthpath
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=wealthpath
JWT_SECRET=${JWT_SECRET}
ALLOWED_ORIGINS=https://your-domain.com
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Edit /opt/wealthpath/.env and set your domain in ALLOWED_ORIGINS"
echo "2. Edit /etc/caddy/Caddyfile with your domain"
echo "3. Run: cd /opt/wealthpath && docker compose -f docker-compose.prod.yaml up -d"
echo ""
echo "🔑 Your generated secrets (save these!):"
echo "   JWT_SECRET=${JWT_SECRET}"
echo "   POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"





