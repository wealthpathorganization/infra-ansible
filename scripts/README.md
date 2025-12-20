# Pre-Push Checks

This repository includes automated checks that run before pushing to the `main` branch.

## What Gets Checked

When pushing to `main`, the following checks run automatically:

1. **Backend:**
   - `go mod tidy` - Ensures dependencies are up to date
   - `make lint` - Runs golangci-lint
   - `make build` - Builds the backend binary

2. **Frontend:**
   - `npm run lint` - Runs ESLint
   - `npm run build` - Builds the Next.js application

## Usage

### Automatic (Git Hook)

The checks run automatically when you push to `main`:

```bash
git push origin main
```

If any check fails, the push will be blocked. Fix the errors and try again.

### Manual

You can run the checks manually at any time:

```bash
# Using npm script
npm run check

# Or directly
./scripts/pre-push.sh
```

### Skip Checks (Not Recommended)

If you need to skip checks in an emergency (not recommended):

```bash
git push origin main --no-verify
```

⚠️ **Warning:** Only use `--no-verify` if absolutely necessary. It bypasses all safety checks.

## Individual Commands

You can also run checks individually:

```bash
# Backend only
npm run backend:lint
npm run backend:build

# Frontend only
npm run frontend:lint
npm run frontend:build

# Both
npm run lint
npm run build
```

## Troubleshooting

### Hook Not Running

If the hook doesn't run, make sure it's executable:

```bash
chmod +x .git/hooks/pre-push
chmod +x scripts/pre-push.sh
```

### Linter Not Found

If `golangci-lint` is not installed:

```bash
# Install golangci-lint
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
```

### Build Fails

1. Check that all dependencies are installed:
   ```bash
   cd backend && go mod tidy
   cd ../frontend && npm install
   ```

2. Check for TypeScript errors:
   ```bash
   cd frontend && npm run lint
   ```

3. Check for Go errors:
   ```bash
   cd backend && make lint
   ```

## Configuration

The pre-push hook only runs when pushing to `main`. To change this, edit `scripts/pre-push.sh` and modify the `PROTECTED_BRANCH` variable.



