# MCHub GBQR Core Module

This module provides the core infrastructure for Gradient Boosting Quantile Regression (GBQR) models that forecast flu ED visit percentages for the MetroCast Hub.

## Module Structure

| File | Description |
|------|-------------|
| `config.py` | Configuration dataclasses (`ModelConfig`, `RunConfig`) |
| `data_loader.py` | Data loading from all sources (MCHub, ILINet, FluSurvNet, NHSN, NSSP) |
| `model.py` | Core GBQR model implementation with bagging |
| `transforms.py` | Power transforms and scale/center normalization |
| `hsa_populations.py` | Population data for HSA locations |
| `plot-forecasts.R` | R script for generating forecast visualizations |

## Dependencies

### Python Packages

```bash
pip install click python-dateutil pandas numpy lightgbm tqdm pymmwr
```

### Custom Packages (from GitHub)

```bash
# Disease data loader - provides access to ILINet, FluSurvNet, NHSN, NSSP data
pip install git+https://github.com/reichlab/iddata.git

# Preprocessing utilities for disease forecasting
pip install git+https://github.com/reichlab/idmodels.git
```

### R Packages (for plotting only)

```r
install.packages(c("dplyr", "tidyr", "ggplot2", "readr", "lubridate"))
```

## Data Sources

### Primary Source

| Source | Description | Location | Update Frequency |
|--------|-------------|----------|------------------|
| **MCHub** | Flu ED visits percentage from participating health systems | `reichlab/flu-metrocast` GitHub repo | Weekly |

MCHub data is downloaded from:
- **Default**: `https://raw.githubusercontent.com/reichlab/flu-metrocast/main/target-data/latest-data.csv`
- **Versioned**: GitHub API with commit-at-date lookup (for retrospective analysis)
- **Local**: `target-data/latest-data.csv` (if `--use_local_mchub` flag is set)

### Supplementary Sources (via `iddata` package)

| Source | Description | Data Type | Geographic Coverage |
|--------|-------------|-----------|---------------------|
| **ILINet** | CDC outpatient influenza-like illness surveillance | % ILI visits | National, HHS regions, states |
| **FluSurvNet** | CDC influenza hospitalization surveillance | Hospitalization rates | National, surveillance sites |
| **NHSN** | National Healthcare Safety Network | Hospital admissions | National, states |
| **NSSP** | National Syndromic Surveillance Program | ED visit % | National, states, HSAs |

### Required Auxiliary Data

The following file must be present in the repository:

```
auxiliary-data/locations.csv   # Location crosswalk from reichlab/flu-metrocast
```

Download with:
```bash
mkdir -p auxiliary-data
curl -sL "https://raw.githubusercontent.com/reichlab/flu-metrocast/main/auxiliary-data/locations.csv" \
  -o auxiliary-data/locations.csv
```

## Data Loading Behavior

### MCHub Data (Primary)

By default, the model downloads the latest MCHub data from GitHub. Options:

| Flag | Behavior |
|------|----------|
| (none) | Download latest from GitHub |
| `--use_local_mchub` | Use local `target-data/latest-data.csv` |
| `--use_versioned_mchub` | Fetch data as of reference date via GitHub API |

### Supplementary Data

Supplementary sources are loaded via the `iddata` package with `as_of` date versioning where supported (NHSN, NSSP). Data is prefixed to avoid location name collisions:

- ILINet: `ilinet_{location}`
- FluSurvNet: `flusurv_{location}`
- NHSN: `nhsn_{location}`
- NSSP: `nssp_{agg_level}_{location}`

### Season Filtering

Models can drop specific seasons via `drop_seasons` config. Common exclusions:
- Early seasons (1997-2003): Limited data quality
- 2008/09, 2009/10: H1N1 pandemic anomalies
- 2020/21, 2021/22, 2022/23: COVID-19 impacts

## Usage

This module is imported by the individual model packages (e.g., `src.gbqr`, `src.gbqr_ili`):

```python
from src.mchub_gbqr import ModelConfig, RunConfig, GBQRModel

model_config = ModelConfig(
    model_name="my_model",
    use_ilinet=True,
    use_flusurvnet=False,
    # ... other config
)

run_config = RunConfig(
    ref_date=datetime.date(2025, 12, 20),
    hub_root=Path("/path/to/repo"),
    # ... other config
)

model = GBQRModel(model_config)
predictions = model.run(run_config)
```

## Plotting

Generate forecast plots using the R script:

```bash
Rscript src/mchub_gbqr/plot-forecasts.R model-output/UMass-gbqr/2025-12-20-UMass-gbqr.csv
```

Outputs are saved to `src/mchub_gbqr/plots/`.
