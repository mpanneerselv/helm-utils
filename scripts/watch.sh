#!/bin/bash
set -euo pipefail

# Watch for changes and rebuild chart
# Usage: ./watch.sh

echo "👀 Watching for changes in kustomize/ directory..."
echo "Press Ctrl+C to stop watching"

# Check if fswatch is available
if ! command -v fswatch &> /dev/null; then
    echo "fswatch not found. Installing..."
    if command -v brew &> /dev/null; then
        brew install fswatch
    else
        echo "Please install fswatch manually"
        exit 1
    fi
fi

# Function to rebuild chart
rebuild_chart() {
    echo ""
    echo "🔄 Changes detected, rebuilding chart..."
    if make dev-build; then
        echo "✅ Rebuild completed successfully"
    else
        echo "❌ Rebuild failed"
    fi
    echo "👀 Watching for more changes..."
}

# Watch for changes in kustomize directory
fswatch -o kustomize/ | while read f; do
    rebuild_chart
done