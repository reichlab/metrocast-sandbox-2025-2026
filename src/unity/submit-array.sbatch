#!/bin/bash
#SBATCH --array=0-5                   # 6 models (0-indexed)
#SBATCH -c 4                          # CPUs per task
#SBATCH --mem=32G                     # Memory (use max needed across models)
#SBATCH -p cpu                        # Partition
#SBATCH -t 06:00:00                   # Time limit (use max needed + buffer)
#SBATCH -o logs/slurm-%A_%a.out       # Output: %A=array_job_id, %a=task_id
#SBATCH --mail-type=END,FAIL          # Email on completion or failure
#SBATCH --job-name=gbqr-array

# GBQR Array Job for Unity Cluster
# Runs all 6 models as a SLURM array job
#
# Usage:
#   sbatch --export=TODAY_DATE=2025-12-26 src/unity/submit-array.sbatch
#   sbatch --export=TODAY_DATE=2025-12-26,EXTRA_ARGS=--short_run src/unity/submit-array.sbatch

set -e

# Model list (indexed by SLURM_ARRAY_TASK_ID)
MODELS=(
    "gbqr"
    "gbqr_ili"
    "gbqr_flusurv"
    "gbqr_nhsn"
    "gbqr_nssp"
    "gbqr_5src"
)

# Get model for this array task
MODEL_NAME="${MODELS[$SLURM_ARRAY_TASK_ID]}"

# Check required environment variable
if [ -z "$TODAY_DATE" ]; then
    echo "Error: TODAY_DATE environment variable not set"
    echo "Usage: sbatch --export=TODAY_DATE=2025-12-26 submit-array.sbatch"
    exit 1
fi

# Optional extra arguments (e.g., --short_run)
EXTRA_ARGS="${EXTRA_ARGS:-}"

# Determine repo root from submission directory
# SLURM_SUBMIT_DIR is the directory where sbatch was called
REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

echo "=============================================="
echo "GBQR Array Job"
echo "Array Job ID:  $SLURM_ARRAY_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Model:         $MODEL_NAME"
echo "Today Date:    $TODAY_DATE"
echo "Extra Args:    $EXTRA_ARGS"
echo "Node:          $(hostname)"
echo "Start Time:    $(date)"
echo "=============================================="

# Change to repo root
cd "$REPO_ROOT"

# Load Python module
module load python/3.11.0 2>/dev/null || module load python/3.10.0 2>/dev/null || true

# Activate model's virtual environment
VENV_PATH="$REPO_ROOT/src/$MODEL_NAME/.venv"
if [ ! -d "$VENV_PATH" ]; then
    echo "Error: Virtual environment not found at $VENV_PATH"
    echo "Run setup script first: ./src/unity/setup-unity.sh $MODEL_NAME"
    exit 1
fi

echo "Activating virtual environment: $VENV_PATH"
source "$VENV_PATH/bin/activate"

# Verify Python
echo "Python: $(which python)"
echo "Python version: $(python --version)"

# Set PYTHONPATH for imports
export PYTHONPATH="$REPO_ROOT"

# Run the model
echo ""
echo "Running model..."
echo "Command: python src/$MODEL_NAME/main.py --today_date $TODAY_DATE $EXTRA_ARGS"
echo ""

python "src/$MODEL_NAME/main.py" --today_date "$TODAY_DATE" $EXTRA_ARGS

# Deactivate
deactivate

echo ""
echo "=============================================="
echo "End Time: $(date)"
echo "=============================================="
