# GBQR Model (MCHub + NSSP)

Gradient Boosting Quantile Regression model using MetroCast Hub target data supplemented with NSSP ED visits data.

## Data Sources

- **MCHub target data** (primary): Flu ED visits percentage from participating health systems
- **NSSP** (supplementary): National Syndromic Surveillance Program ED visits data for additional locations

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) to generate probabilistic forecasts. It combines MCHub target data with NSSP ED visit data from additional geographic areas.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- NSSP locations prefixed with "nssp_{agg_level}_" to distinguish aggregation levels
- Uses as_of versioning for NSSP data to respect data availability at forecast time

## Environment Setup

```bash
pip install -r src/mchub_gbqr/requirements.txt
```

## Running the Model

```bash
# Basic usage - downloads latest MCHub data from GitHub
python -m src.gbqr_nssp --today_date 2025-12-17

# Use local MCHub data
python -m src.gbqr_nssp --today_date 2025-12-17 --use_local_mchub

# Use versioned MCHub data (as of reference date)
python -m src.gbqr_nssp --today_date 2025-12-17 --use_versioned_mchub

# Short run with reduced bagging
python -m src.gbqr_nssp --today_date 2025-12-17 --short_run
```

## Output

Predictions are saved to `model-output/UMass-gbqr_nssp/` in hubverse format.
