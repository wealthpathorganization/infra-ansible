#!/bin/bash
# Pre-push hook script
# Runs build and lint checks before allowing push to main

set -e

echo "🔍 Running pre-push checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Check if pushing to main
PROTECTED_BRANCH="main"
if [ "$CURRENT_BRANCH" = "$PROTECTED_BRANCH" ]; then
    echo -e "${YELLOW}⚠️  Pushing to main branch - running checks...${NC}"
else
    echo -e "${GREEN}✓ Not pushing to main, skipping checks${NC}"
    exit 0
fi

ERRORS=0

# Backend checks
echo ""
echo "📦 Checking backend..."
cd backend

echo "  → Running go mod tidy..."
if ! go mod tidy; then
    echo -e "${RED}✗ Backend: go mod tidy failed${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo "  → Running linter..."
if ! make lint; then
    echo -e "${RED}✗ Backend: Lint failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Backend: Lint passed${NC}"
fi

echo "  → Building backend..."
if ! make build; then
    echo -e "${RED}✗ Backend: Build failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Backend: Build successful${NC}"
fi

echo "  → Running tests..."
if ! go test ./internal/... -short; then
    echo -e "${RED}✗ Backend: Tests failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Backend: Tests passed${NC}"
fi

cd ..

# Frontend checks
echo ""
echo "📦 Checking frontend..."
cd frontend

echo "  → Running linter..."
if ! npm run lint; then
    echo -e "${RED}✗ Frontend: Lint failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Frontend: Lint passed${NC}"
fi

echo "  → Building frontend..."
if ! npm run build; then
    echo -e "${RED}✗ Frontend: Build failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Frontend: Build successful${NC}"
fi

echo "  → Running tests..."
if ! npm test -- --passWithNoTests; then
    echo -e "${RED}✗ Frontend: Tests failed${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Frontend: Tests passed${NC}"
fi

cd ..

# Summary
echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready to push.${NC}"
    exit 0
else
    echo -e "${RED}❌ $ERRORS check(s) failed. Please fix errors before pushing.${NC}"
    exit 1
fi


