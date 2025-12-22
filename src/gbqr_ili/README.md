# GBQR Model (MCHub + ILINet)

Gradient Boosting Quantile Regression model using MetroCast Hub target data supplemented with ILINet outpatient surveillance data.

## Data Sources

- **MCHub target data** (primary): Flu ED visits percentage from participating health systems
- **ILINet** (supplementary): CDC's outpatient influenza-like illness surveillance data

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) to generate probabilistic forecasts. It combines MCHub target data with historical ILINet data to provide additional training signal from outpatient surveillance.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- ILINet locations prefixed with "ilinet_" to distinguish from MCHub locations
- Drops Virgin Islands, Puerto Rico, and DC from ILINet data due to data quality issues

## Environment Setup

```bash
pip install -r src/mchub_gbqr/requirements.txt
```

## Running the Model

```bash
# Basic usage - downloads latest MCHub data from GitHub
python -m src.gbqr_ili --today_date 2025-12-17

# Use local MCHub data
python -m src.gbqr_ili --today_date 2025-12-17 --use_local_mchub

# Use versioned MCHub data (as of reference date)
python -m src.gbqr_ili --today_date 2025-12-17 --use_versioned_mchub

# Short run with reduced bagging
python -m src.gbqr_ili --today_date 2025-12-17 --short_run
```

## Output

Predictions are saved to `model-output/UMass-gbqr_ili/` in hubverse format.
