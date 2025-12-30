# Running GBQR Models on Unity Cluster

This directory contains scripts for running GBQR models on the UMass Unity HPC cluster.

## Quick Start

**Important**: Always submit jobs from the repository root directory. The scripts use `SLURM_SUBMIT_DIR` to locate virtual environments and model code.

```bash
# On Unity, from repo root
cd /path/to/metrocast-sandbox-2025-2026

# 1. Set up environments (one-time)
./src/unity/setup-unity.sh

# 2. Submit all models for a specific date
./src/unity/submit-all.sh 2025-12-26

# 3. Or submit a single model
sbatch src/unity/run-model.sbatch gbqr 2025-12-26
```

## Files

| File | Description |
|------|-------------|
| `setup-unity.sh` | One-time setup script to create venvs on Unity |
| `run-model.sbatch` | SLURM batch script for running a single model |
| `submit-all.sh` | Submit all 6 models as separate jobs |
| `submit-array.sbatch` | Alternative: submit all models as a SLURM array job |

## Setup (One-Time)

Before running models on Unity, set up the Python environments:

```bash
# Clone repo to Unity (if not already done)
cd /work/pi_username_umass_edu/  # Your work directory
git clone https://github.com/reichlab/metrocast-sandbox-2025-2026.git
cd metrocast-sandbox-2025-2026

# Run setup script
./src/unity/setup-unity.sh
```

This creates virtual environments for each model in `src/<model>/.venv/`.

## Running Models

**Note**: Always run these commands from the repository root directory.

### Option 1: Submit All Models

```bash
./src/unity/submit-all.sh 2025-12-26
```

This submits 6 separate jobs, one for each model.

### Option 2: Submit Single Model

```bash
sbatch src/unity/run-model.sbatch <model_name> <today_date> [--short_run]

# Examples:
sbatch src/unity/run-model.sbatch gbqr 2025-12-26
sbatch src/unity/run-model.sbatch gbqr_5src 2025-12-26
sbatch src/unity/run-model.sbatch gbqr 2025-12-26 --short_run
```

### Option 3: Array Job (All Models at Once)

```bash
sbatch --export=TODAY_DATE=2025-12-26 src/unity/submit-array.sbatch
```

## Monitoring Jobs

```bash
# View your queued/running jobs
squeue --me

# View job details
sacct -j <job_id>

# Check resource usage for your lab
unity-slurm-account-usage
```

## Output

- Job logs: `logs/slurm-<job_id>-<model>.out`
- Forecasts: `model-output/UMass-<model>/<date>-UMass-<model>.csv`

## Resource Configuration

Default resources per model (includes 2h buffer for Unity variability):

| Model | Memory | Time | CPUs |
|-------|--------|------|------|
| gbqr | 16GB | 3.5h | 4 |
| gbqr_ili | 16GB | 4h | 4 |
| gbqr_flusurv | 16GB | 4h | 4 |
| gbqr_nhsn | 20GB | 4.5h | 4 |
| gbqr_nssp | 24GB | 4.5h | 4 |
| gbqr_5src | 32GB | 5.5h | 4 |

Adjust in `submit-all.sh` or `run-model.sbatch` if needed.

## Scheduling Weekly Runs with scrontab

Unity supports `scrontab`, SLURM's cron-like interface for recurring jobs.

### Setup

1. Open your scrontab:
   ```bash
   scrontab -e
   ```

2. Add the following entry (adjust path to your repo location):
   ```bash
   #SCRON -p cpu
   #SCRON -c 1
   #SCRON --mem=1G
   #SCRON -t 00:10:00
   #SCRON -o /work/pi_username_umass_edu/metrocast-sandbox-2025-2026/logs/scron-%j.out

   # Run every Wednesday at 1pm ET (6pm UTC)
   0 18 * * 3 /work/pi_username_umass_edu/metrocast-sandbox-2025-2026/src/unity/submit-all.sh $(date +\%Y-\%m-\%d)
   ```

3. Save and exit the editor.

### Notes

- **Timezone**: Unity uses UTC. 1pm ET = 6pm UTC (during EST/winter) or 5pm UTC (during EDT/summer).
- **Paths**: Use absolute paths in scrontab entries.
- **Resources**: The scrontab job just runs the submit script (low resources), which then submits the actual model jobs.

### scrontab Commands

```bash
scrontab -e      # Edit your scrontab
scrontab -l      # List/view current scrontab
scrontab -r      # Remove scrontab entirely
```

## Troubleshooting

### Job pending with "MaxCpuPerAccount"
Your lab has hit the 1000 CPU core limit. Wait for other jobs to complete.

### Module not found errors
Ensure setup script completed successfully:
```bash
./src/unity/setup-unity.sh gbqr  # Re-run for specific model
```

### Out of memory
Increase `--mem` in the sbatch script or use `--mem=64G`.

### Time limit exceeded
Increase `-t` time limit or use `--short_run` flag for testing.
