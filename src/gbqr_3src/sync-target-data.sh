#!/bin/bash
# Sync target-data files from flu-metrocast repository
# This script downloads the latest target data files needed for model evaluation

set -e

# Base URL for raw GitHub files
BASE_URL="https://raw.githubusercontent.com/reichlab/flu-metrocast/main/target-data"

# Target directory (relative to repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_DIR="$REPO_ROOT/target-data"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

echo "Syncing target-data from flu-metrocast repository..."
echo "Target directory: $TARGET_DIR"
echo ""

# Files to download
FILES=(
    "latest-data.csv"
    "oracle-output.csv"
    "time-series.csv"
    "README.md"
)

# Download each file
for file in "${FILES[@]}"; do
    echo "Downloading $file..."
    curl -sL "$BASE_URL/$file" -o "$TARGET_DIR/$file"
    if [ $? -eq 0 ]; then
        echo "  Downloaded: $file"
    else
        echo "  Error downloading: $file"
        exit 1
    fi
done

echo ""
echo "Sync complete! Files downloaded to $TARGET_DIR:"
ls -la "$TARGET_DIR"
