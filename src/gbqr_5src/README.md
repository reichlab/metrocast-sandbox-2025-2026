# GBQR Model (5 Sources)

Gradient Boosting Quantile Regression model using all available data sources for maximum training data.

## Data Sources

- **MCHub target data** (primary): Flu ED visits percentage from participating health systems
- **ILINet** (supplementary): CDC's outpatient influenza-like illness surveillance
- **FluSurvNet** (supplementary): CDC's influenza hospitalization surveillance network
- **NHSN** (supplementary): National Healthcare Safety Network hospital admissions
- **NSSP** (supplementary): National Syndromic Surveillance Program ED visits

## Model Description

This model uses Gradient Boosting Quantile Regression (GBQR) with the maximum available training data by combining all five data sources. This provides the richest training signal but may also introduce more complexity.

Key features:
- Bagged ensemble of 100 LightGBM quantile regression models
- Power transform (4th root) for variance stabilization
- Each supplementary source prefixed to distinguish from MCHub locations
- Uses as_of versioning for NHSN and NSSP data

## Environment Setup

```bash
pip install -r src/mchub_gbqr/requirements.txt
```

## Running the Model

```bash
# Basic usage - downloads latest MCHub data from GitHub
python -m src.gbqr_5src --today_date 2025-12-17

# Use local MCHub data
python -m src.gbqr_5src --today_date 2025-12-17 --use_local_mchub

# Use versioned MCHub data (as of reference date)
python -m src.gbqr_5src --today_date 2025-12-17 --use_versioned_mchub

# Short run with reduced bagging
python -m src.gbqr_5src --today_date 2025-12-17 --short_run
```

## Output

Predictions are saved to `model-output/UMass-gbqr_5src/` in hubverse format.

## Notes

This model takes the longest to run (~85 minutes with 100 bags) due to the large combined training dataset.
