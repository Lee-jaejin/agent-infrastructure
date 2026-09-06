#!/bin/bash
# Backup script for Private AI System
# - Headscale database
# - Configuration files
# - Ollama models list

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/.agent-infrastructure/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

echo "=== Private AI System Backup ==="
echo "Backup location: $BACKUP_PATH"
echo ""

mkdir -p "$BACKUP_PATH"

# 1. Headscale backup
echo ">>> Backing up Headscale..."
if podman ps --format '{{.Names}}' | grep -q "^headscale$"; then
    podman cp headscale:/var/lib/headscale/db.sqlite "$BACKUP_PATH/headscale.db"
    podman cp headscale:/etc/headscale "$BACKUP_PATH/headscale-config"
    echo "    Headscale backup: OK"
else
    echo "    Headscale container not running, skipping..."
fi

if podman volume ls --format '{{.Name}}' | grep -q '^headscale-data$'; then
    podman volume export headscale-data > "$BACKUP_PATH/headscale-data.tar"
    echo "    Headscale volume backup: OK"
    echo "    Restore: podman volume import headscale-data < $BACKUP_PATH/headscale-data.tar"
fi

# 2. Configuration backup
echo ">>> Backing up configurations..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cp -r "$PROJECT_DIR/config" "$BACKUP_PATH/config"
echo "    Config backup: OK"

# 3. Ollama models list
echo ">>> Backing up Ollama models list..."
if command -v ollama &> /dev/null; then
    ollama list > "$BACKUP_PATH/ollama-models.txt" 2>/dev/null || echo "No models found"
    echo "    Models list: OK"
else
    echo "    Ollama not installed, skipping..."
fi

# 4. Compress backup
echo ">>> Compressing backup..."
cd "$BACKUP_DIR"
tar -czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
rm -rf "$TIMESTAMP"

echo ""
echo "=== Backup Complete ==="
echo "File: $BACKUP_DIR/$TIMESTAMP.tar.gz"
echo "Size: $(du -h "$BACKUP_DIR/$TIMESTAMP.tar.gz" | cut -f1)"

# Cleanup old backups (keep last 7)
echo ""
echo ">>> Cleaning old backups (keeping last 7)..."
OLD_BACKUPS=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +8)
if [[ -n "$OLD_BACKUPS" ]]; then
    echo "$OLD_BACKUPS" | xargs rm -f
fi
echo "Done!"
