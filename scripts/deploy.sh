#!/bin/bash
set -e

echo "🚀 Deploying WealthPath..."

cd /opt/wealthpath

# Pull latest code (for compose file and Caddyfile updates)
git pull origin main

# Pull latest images
echo "📦 Pulling latest images..."
docker compose -f docker-compose.deploy.yaml pull

# Restart services
echo "🔄 Restarting services..."
docker compose -f docker-compose.deploy.yaml up -d

# Show status
echo "✅ Deployment complete!"
docker compose -f docker-compose.deploy.yaml ps
