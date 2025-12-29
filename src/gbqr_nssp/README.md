# GBQR Model (MCHub + NSSP)

Gradient Boosting Quantile Regression model using MetroCast Hub target data supplemented with NSSP emergency department surveillance data.

## Data Sources

- **MCHub target data** (primary): Flu ED visits percentage from participating health systems
- **NSSP** (supplementary): National Syndromic Surveillance Program ED visit percentages

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) to generate probabilistic forecasts. It combines MCHub target data with NSSP ED visit data to provide additional training signal from syndromic surveillance.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- NSSP locations prefixed with "nssp_{agg_level}_" to distinguish from MCHub locations
- Uses as_of date versioning for NSSP data to prevent data leakage in retrospective runs
- Includes national, state, and HSA-level NSSP data

## Setup

From the repository root:

```bash
# Option 1: Use the setup script
./src/setup-model.sh gbqr_nssp

# Option 2: Manual setup
cd src/gbqr_nssp
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

See [src/mchub_gbqr/README.md](../mchub_gbqr/README.md) for complete setup instructions.

## Running the Model

**Important:** Run from the repository root with the model's venv activated and `PYTHONPATH` set.

```bash
# From the repository root directory
cd /path/to/metrocast-sandbox-2025-2026

# Activate this model's virtual environment
source src/gbqr_nssp/.venv/bin/activate

# Basic usage - downloads latest MCHub data from GitHub
PYTHONPATH=$(pwd) python src/gbqr_nssp/main.py --today_date 2025-12-26

# Use local MCHub data
PYTHONPATH=$(pwd) python src/gbqr_nssp/main.py --today_date 2025-12-26 --use_local_mchub

# Use versioned MCHub data (as of reference date)
PYTHONPATH=$(pwd) python src/gbqr_nssp/main.py --today_date 2025-12-26 --use_versioned_mchub

# Short run with reduced bagging
PYTHONPATH=$(pwd) python src/gbqr_nssp/main.py --today_date 2025-12-26 --short_run

# Deactivate when done
deactivate
```

### One-Liner (Without Explicit Activation)

```bash
cd /path/to/metrocast-sandbox-2025-2026
PYTHONPATH=$(pwd) src/gbqr_nssp/.venv/bin/python src/gbqr_nssp/main.py --today_date 2025-12-26
```

## Command-Line Options

| Flag | Description |
|------|-------------|
| `--today_date YYYY-MM-DD` | **Required.** The effective run date. Reference date will be the next Saturday. |
| `--short_run` | Use 10 bags instead of 100 for faster testing (~10x speedup) |
| `--use_local_mchub` | Use local `target-data/latest-data.csv` instead of downloading from GitHub |
| `--use_versioned_mchub` | Fetch MCHub data as of reference date via GitHub API (for retrospective runs) |

## Output

Predictions are saved to `model-output/UMass-gbqr_nssp/` in hubverse format.

Example: `model-output/UMass-gbqr_nssp/2025-12-27-UMass-gbqr_nssp.csv`

Quantile levels: 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975

## Runtime

- Full run (100 bags): ~60 minutes
- Short run (10 bags): ~6 minutes
