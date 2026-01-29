#!/bin/bash
# Setup script for GBQR model virtual environments
#
# Usage:
#   ./src/setup-model.sh              # Set up all models
#   ./src/setup-model.sh gbqr         # Set up a specific model
#   ./src/setup-model.sh gbqr gbqr_5src  # Set up multiple models

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Available models
ALL_MODELS="gbqr gbqr_5src gbqr_ili gbqr_flusurv gbqr_nhsn gbqr_nssp"

# Determine which models to set up
if [ $# -eq 0 ]; then
    MODELS="$ALL_MODELS"
    echo "Setting up all models..."
else
    MODELS="$@"
    echo "Setting up specified models: $MODELS"
fi

# Download auxiliary data if needed
if [ ! -f "$REPO_ROOT/auxiliary-data/locations.csv" ]; then
    echo ""
    echo "Downloading auxiliary data..."
    mkdir -p "$REPO_ROOT/auxiliary-data"
    curl -sL "https://raw.githubusercontent.com/reichlab/flu-metrocast/main/auxiliary-data/locations.csv" \
        -o "$REPO_ROOT/auxiliary-data/locations.csv"
    echo "  Downloaded: auxiliary-data/locations.csv"
fi

# Set up each model
for model in $MODELS; do
    MODEL_DIR="$SCRIPT_DIR/$model"

    if [ ! -d "$MODEL_DIR" ]; then
        echo "Warning: Model directory not found: $MODEL_DIR"
        continue
    fi

    echo ""
    echo "=== Setting up $model ==="

    VENV_DIR="$MODEL_DIR/.venv"

    # Create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
        echo "  Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    else
        echo "  Virtual environment exists"
    fi

    # Activate and install requirements
    echo "  Installing dependencies..."
    source "$VENV_DIR/bin/activate"

    # Upgrade pip
    pip install --quiet --upgrade pip

    # Install requirements (from model directory so relative paths work)
    cd "$MODEL_DIR"
    if [ -f "requirements.txt" ]; then
        pip install --quiet -r requirements.txt
    else
        # Fall back to shared requirements
        pip install --quiet -r ../mchub_gbqr/requirements.txt
    fi
    cd "$REPO_ROOT"

    deactivate

    echo "  Done: $model"
done

echo ""
echo "=== Setup complete ==="
echo ""
echo "To run a model:"
echo "  cd $REPO_ROOT"
echo "  source src/<model>/.venv/bin/activate"
echo "  PYTHONPATH=\$(pwd) python src/<model>/main.py --today_date YYYY-MM-DD"
