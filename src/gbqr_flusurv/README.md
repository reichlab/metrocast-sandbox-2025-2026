# GBQR Model (MCHub + FluSurvNet)

Gradient Boosting Quantile Regression model using MetroCast Hub target data supplemented with FluSurvNet hospitalization data.

## Data Sources

- **MCHub target data** (primary): Flu ED visits percentage from participating health systems
- **FluSurvNet** (supplementary): CDC's influenza hospitalization surveillance network rates

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) to generate probabilistic forecasts. It combines MCHub target data with historical FluSurvNet hospitalization rates to provide additional training signal.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- FluSurvNet locations prefixed with "flusurv_" to distinguish from MCHub locations
- Includes both national and site-level FluSurvNet data

## Environment Setup

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
python -m src.gbqr_flusurv --today_date 2025-12-17

# Use local MCHub data
python -m src.gbqr_flusurv --today_date 2025-12-17 --use_local_mchub

# Use versioned MCHub data (as of reference date)
python -m src.gbqr_flusurv --today_date 2025-12-17 --use_versioned_mchub

# Short run with reduced bagging
python -m src.gbqr_flusurv --today_date 2025-12-17 --short_run
```

## Output

Predictions are saved to `model-output/UMass-gbqr_flusurv/` in hubverse format.
