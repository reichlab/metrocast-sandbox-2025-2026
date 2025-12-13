#!/bin/bash
#SBATCH -J gbqr_3src_metrocast           # Job name
#SBATCH -N 1                              # Number of nodes
#SBATCH -c 8                              # Number of cores per task
#SBATCH --mem=32G                         # Memory per node
#SBATCH -p cpu                            # Partition name
#SBATCH -t 08:00:00                       # Time limit (8 hours)
#SBATCH --array=0-3                       # Array indices (4 dates total)
#SBATCH -o logs/slurm-%A_%a.out           # Output file (%A=job ID, %a=array index)
#SBATCH -e logs/slurm-%A_%a.err           # Error file
#SBATCH --mail-type=FAIL,TIME_LIMIT_80    # Email on failure or 80% time reached
#SBATCH --mail-user=nick@umass.edu

# Array of dates to process (2025-2026 season)
# Note: iddata NSSP loading requires as_of dates >= 2025-09-17
dates=(
  "2025-11-19"
  "2025-11-26"
  "2025-12-03"
  "2025-12-10"
)

# Get the date for this array task
date="${dates[$SLURM_ARRAY_TASK_ID]}"

echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Running forecast for date: $date"
echo "Node: $SLURM_NODELIST"
echo "Start time: $(date)"
echo "=========================================="

# Create logs directory if it doesn't exist
mkdir -p logs

# Set up Python virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "Error: Virtual environment not found at .venv"
    exit 1
fi

# Verify Python environment
echo "Python: $(which python)"
echo "Python version: $(python --version)"

# Run the forecast
python main.py --today_date="$date"

# Check exit status
if [ $? -eq 0 ]; then
    echo "Successfully completed forecast for $date"
else
    echo "Error: Forecast failed for $date"
    exit 1
fi

echo "End time: $(date)"
echo "=========================================="
