#!/bin/bash

# Setup GitHub Secrets for WealthPath
# Prerequisites: GitHub CLI (gh) installed and authenticated
#   brew install gh
#   gh auth login

set -e

REPO="harnguyen/WealthPath"

echo "🔐 Setting up GitHub Secrets for $REPO"
echo "================================================"
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed."
    echo "   Install with: brew install gh"
    echo "   Then run: gh auth login"
    exit 1
fi

# Check if authenticated
if ! gh auth status 2>&1 | grep -q "Logged in"; then
    echo "❌ Not authenticated with GitHub CLI."
    echo "   Run: gh auth login"
    exit 1
fi

echo "✓ Authenticated with GitHub CLI"

echo "Enter your secrets (press Enter to skip optional ones):"
echo ""

# Required secrets
read -p "SERVER_IP (required): " SERVER_IP
read -p "DOMAIN (required, e.g., wealthpath.duckdns.org): " DOMAIN
read -p "ADMIN_EMAIL (required): " ADMIN_EMAIL

echo ""
echo "SSH Private Key (paste the entire key, then press Enter twice):"
echo "---"
SSH_PRIVATE_KEY=""
while IFS= read -r line; do
    [[ -z "$line" ]] && break
    SSH_PRIVATE_KEY+="$line"$'\n'
done
echo "---"

# OAuth - Google
echo ""
echo "Google OAuth (optional - press Enter to skip):"
read -p "GOOGLE_CLIENT_ID: " GOOGLE_CLIENT_ID
read -p "GOOGLE_CLIENT_SECRET: " GOOGLE_CLIENT_SECRET

# OAuth - Facebook
echo ""
echo "Facebook OAuth (optional - press Enter to skip):"
read -p "FACEBOOK_APP_ID: " FACEBOOK_APP_ID
read -p "FACEBOOK_APP_SECRET: " FACEBOOK_APP_SECRET

# AI
echo ""
echo "OpenAI (optional - press Enter to skip):"
read -p "OPENAI_API_KEY: " OPENAI_API_KEY

echo ""
echo "🚀 Setting secrets..."

# Set required secrets
[ -n "$SERVER_IP" ] && echo "$SERVER_IP" | gh secret set SERVER_IP -R "$REPO" && echo "✓ SERVER_IP"
[ -n "$DOMAIN" ] && echo "$DOMAIN" | gh secret set DOMAIN -R "$REPO" && echo "✓ DOMAIN"
[ -n "$ADMIN_EMAIL" ] && echo "$ADMIN_EMAIL" | gh secret set ADMIN_EMAIL -R "$REPO" && echo "✓ ADMIN_EMAIL"
[ -n "$SSH_PRIVATE_KEY" ] && echo "$SSH_PRIVATE_KEY" | gh secret set SSH_PRIVATE_KEY -R "$REPO" && echo "✓ SSH_PRIVATE_KEY"

# Set optional secrets
[ -n "$GOOGLE_CLIENT_ID" ] && echo "$GOOGLE_CLIENT_ID" | gh secret set GOOGLE_CLIENT_ID -R "$REPO" && echo "✓ GOOGLE_CLIENT_ID"
[ -n "$GOOGLE_CLIENT_SECRET" ] && echo "$GOOGLE_CLIENT_SECRET" | gh secret set GOOGLE_CLIENT_SECRET -R "$REPO" && echo "✓ GOOGLE_CLIENT_SECRET"
[ -n "$FACEBOOK_APP_ID" ] && echo "$FACEBOOK_APP_ID" | gh secret set FACEBOOK_APP_ID -R "$REPO" && echo "✓ FACEBOOK_APP_ID"
[ -n "$FACEBOOK_APP_SECRET" ] && echo "$FACEBOOK_APP_SECRET" | gh secret set FACEBOOK_APP_SECRET -R "$REPO" && echo "✓ FACEBOOK_APP_SECRET"
[ -n "$OPENAI_API_KEY" ] && echo "$OPENAI_API_KEY" | gh secret set OPENAI_API_KEY -R "$REPO" && echo "✓ OPENAI_API_KEY"

echo ""
echo "✅ Done! Verify with: gh secret list -R $REPO"

