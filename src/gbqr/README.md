# GBQR Model (MCHub Only)

Gradient Boosting Quantile Regression model using only MetroCast Hub (MCHub) target data.

## Data Sources

- **MCHub target data** (primary and only source): Flu ED visits percentage from participating health systems

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) to generate probabilistic forecasts of flu ED visit percentages. It uses only the MCHub target data without any supplementary training data sources.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- Scale/center normalization by location
- Season-based train/test splitting

## Environment Setup

This model requires Python 3.11+ and the following dependencies:

```bash
# Install required packages
pip install click python-dateutil pandas numpy lightgbm tqdm pymmwr

# Install custom packages from GitHub
pip install git+https://github.com/reichlab/iddata.git
pip install git+https://github.com/reichlab/idmodels.git
```

## Running the Model

```bash
# Basic usage - downloads latest MCHub data from GitHub
python -m src.gbqr --today_date 2025-12-17

# Use local MCHub data instead of downloading
python -m src.gbqr --today_date 2025-12-17 --use_local_mchub

# Use versioned MCHub data (as of reference date)
python -m src.gbqr --today_date 2025-12-17 --use_versioned_mchub

# Short run with reduced bagging (10 bags instead of 100)
python -m src.gbqr --today_date 2025-12-17 --short_run
```

## Output

Predictions are saved to `model-output/UMass-gbqr/` in the standard hubverse format with quantile predictions at levels: 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975.
