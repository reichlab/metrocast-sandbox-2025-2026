# MCHub GBQR Core Module

This module provides the core infrastructure for Gradient Boosting Quantile Regression (GBQR) models that forecast flu ED visit percentages for the MetroCast Hub.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/reichlab/metrocast-sandbox-2025-2026.git
cd metrocast-sandbox-2025-2026

# Set up a model (creates venv and installs dependencies)
./src/setup-model.sh gbqr

# Run the model
source src/gbqr/.venv/bin/activate
PYTHONPATH=$(pwd) python src/gbqr/main.py --today_date 2025-12-26
```

## Complete Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/reichlab/metrocast-sandbox-2025-2026.git
cd metrocast-sandbox-2025-2026
```

### 2. Set Up Model Environment(s)

Each model has its own virtual environment in `src/<model>/.venv/`. This allows different models to have different dependencies if needed.

**Option A: Set up all models at once**

```bash
./src/setup-model.sh
```

**Option B: Set up specific model(s)**

```bash
# Set up a single model
./src/setup-model.sh gbqr

# Set up multiple models
./src/setup-model.sh gbqr gbqr_5src
```

The setup script will:
- Create a Python 3.11+ virtual environment in `src/<model>/.venv/`
- Install dependencies from the model's `requirements.txt`
- Download required auxiliary data if not present

### 3. Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Create venv for a specific model
cd src/gbqr
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Download auxiliary data (from repo root)
cd ../..
mkdir -p auxiliary-data
curl -sL "https://raw.githubusercontent.com/reichlab/flu-metrocast/main/auxiliary-data/locations.csv" \
  -o auxiliary-data/locations.csv
```

### 4. (Optional) Install R Packages for Plotting

To generate forecast visualization plots:

```r
install.packages(c("dplyr", "tidyr", "ggplot2", "readr", "lubridate"))
```

## Running Models

**Important:** All models must be run from the repository root directory with:
1. The model's virtual environment activated
2. `PYTHONPATH` set to the repo root

### Basic Usage Pattern

```bash
# From the repository root directory
cd /path/to/metrocast-sandbox-2025-2026

# Activate the model's virtual environment
source src/<model>/.venv/bin/activate

# Run the model with PYTHONPATH set
PYTHONPATH=$(pwd) python src/<model>/main.py --today_date YYYY-MM-DD

# Deactivate when done
deactivate
```

### Available Models

| Model | Data Sources | Approx. Runtime |
|-------|--------------|-----------------|
| `gbqr` | MCHub only | ~30 min |
| `gbqr_ili` | MCHub + ILINet | ~40 min |
| `gbqr_flusurv` | MCHub + FluSurvNet | ~40 min |
| `gbqr_nhsn` | MCHub + NHSN | ~50 min |
| `gbqr_nssp` | MCHub + NSSP | ~60 min |
| `gbqr_5src` | All 5 sources | ~90 min |

### Command-Line Options

All models support these flags:

| Flag | Description |
|------|-------------|
| `--today_date YYYY-MM-DD` | **Required.** The effective run date. Reference date will be the next Saturday. |
| `--short_run` | Use 10 bags instead of 100 for faster testing (~10x speedup) |
| `--use_local_mchub` | Use local `target-data/latest-data.csv` instead of downloading from GitHub |
| `--use_versioned_mchub` | Fetch MCHub data as of reference date via GitHub API (for retrospective runs) |

### Example: Running Multiple Models

```bash
cd /path/to/metrocast-sandbox-2025-2026

# Run gbqr model
source src/gbqr/.venv/bin/activate
PYTHONPATH=$(pwd) python src/gbqr/main.py --today_date 2025-12-26
deactivate

# Run gbqr_5src model
source src/gbqr_5src/.venv/bin/activate
PYTHONPATH=$(pwd) python src/gbqr_5src/main.py --today_date 2025-12-26
deactivate
```

### One-Liner (Without Explicit Activation)

You can also run without explicitly activating the venv:

```bash
cd /path/to/metrocast-sandbox-2025-2026
PYTHONPATH=$(pwd) src/gbqr/.venv/bin/python src/gbqr/main.py --today_date 2025-12-26
```

## Output

Model outputs are saved to `model-output/UMass-<model_name>/` in the standard hubverse format:

```
model-output/
├── UMass-gbqr/
│   └── 2025-12-27-UMass-gbqr.csv
├── UMass-gbqr_5src/
│   └── 2025-12-27-UMass-gbqr_5src.csv
└── ...
```

Output files contain quantile predictions at levels: 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975.

## Generating Plots

After running models, generate forecast visualizations:

```bash
# From repo root
Rscript src/mchub_gbqr/plot-forecasts.R model-output/UMass-gbqr/2025-12-27-UMass-gbqr.csv
```

Plots are saved to `src/mchub_gbqr/plots/`:
- `YYYY-MM-DD-<model>-forecasts.pdf` - Full PDF with one page per state
- `YYYY-MM-DD-<model>-summary.png` - Summary plot of selected locations

## Submitting Forecasts

To submit a forecast to the flu-metrocast hub:

```bash
python src/submit-forecast.py
```

This interactive script will:
1. Show available models for the most recent reference date
2. Let you select which model to submit as `UMass-alloy`
3. Copy the file to the flu-metrocast repo
4. Create a branch, commit, and submit a PR

**Prerequisite:** The `flu-metrocast` repo must be cloned as a sibling directory and you must have push access.

## Project Structure

```
metrocast-sandbox-2025-2026/
├── src/
│   ├── mchub_gbqr/           # Shared core module
│   │   ├── config.py         # Configuration dataclasses
│   │   ├── data_loader.py    # Data loading utilities
│   │   ├── model.py          # Core GBQR model
│   │   ├── transforms.py     # Power transforms
│   │   ├── requirements.txt  # Shared dependencies
│   │   └── plot-forecasts.R  # Plotting script
│   │
│   ├── gbqr/                 # MCHub-only model
│   │   ├── .venv/            # Model-specific virtual environment
│   │   ├── main.py           # Entry point
│   │   └── requirements.txt  # References shared requirements
│   │
│   ├── gbqr_5src/            # All 5 sources model
│   │   ├── .venv/
│   │   ├── main.py
│   │   └── requirements.txt
│   │
│   ├── ... (other models)
│   │
│   ├── setup-model.sh        # Setup script for venvs
│   └── submit-forecast.py    # Forecast submission script
│
├── model-output/             # Generated forecasts
├── auxiliary-data/           # Location crosswalk
└── target-data/              # Local target data cache
```

## Dependencies

### Shared Dependencies (src/mchub_gbqr/requirements.txt)

- `click` - Command-line interface
- `python-dateutil` - Date parsing
- `pandas`, `numpy` - Data manipulation
- `lightgbm` - Gradient boosting framework
- `tqdm` - Progress bars
- `pymmwr` - Epiweek calculations
- `iddata` - Reich Lab data loading utilities (from GitHub)
- `idmodels` - Reich Lab modeling utilities (from GitHub)

### Model-Specific Dependencies

Each model has a `requirements.txt` that references the shared requirements:

```
# src/gbqr/requirements.txt
-r ../mchub_gbqr/requirements.txt

# Add model-specific dependencies below if needed
```

To add model-specific dependencies, edit the model's `requirements.txt` and add packages below the `-r` line.

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

### Data Loading Behavior

Supplementary sources are loaded via the `iddata` package with `as_of` date versioning where supported (NHSN, NSSP). Data is prefixed to avoid location name collisions:

- ILINet: `ilinet_{location}`
- FluSurvNet: `flusurv_{location}`
- NHSN: `nhsn_{location}`
- NSSP: `nssp_{agg_level}_{location}`

### Season Filtering

Models drop specific seasons via `drop_seasons` config. Common exclusions:
- Early seasons (1997-2003): Limited data quality
- 2008/09, 2009/10: H1N1 pandemic anomalies
- 2020/21, 2021/22, 2022/23: COVID-19 impacts

## Troubleshooting

### "No module named 'src'"

Make sure you're running from the repo root with `PYTHONPATH` set:

```bash
cd /path/to/metrocast-sandbox-2025-2026
source src/gbqr/.venv/bin/activate
PYTHONPATH=$(pwd) python src/gbqr/main.py --today_date 2025-12-26
```

### "No module named 'idmodels'" or "No module named 'iddata'"

These packages are installed from GitHub. Reinstall dependencies:

```bash
source src/gbqr/.venv/bin/activate
pip install --force-reinstall git+https://github.com/reichlab/iddata.git
pip install --force-reinstall git+https://github.com/reichlab/idmodels.git
```

Or re-run the setup script:

```bash
./src/setup-model.sh gbqr
```

### Missing locations.csv

Download the auxiliary data file:

```bash
mkdir -p auxiliary-data
curl -sL "https://raw.githubusercontent.com/reichlab/flu-metrocast/main/auxiliary-data/locations.csv" \
  -o auxiliary-data/locations.csv
```

Or run the setup script (it downloads automatically):

```bash
./src/setup-model.sh
```

### Wrong Python version

Ensure you're using Python 3.11+:

```bash
python3 --version
```

If needed, specify the Python version when creating venvs:

```bash
python3.11 -m venv src/gbqr/.venv
```

## Usage as a Library

This module can be imported by custom model scripts:

```python
from src.mchub_gbqr import ModelConfig, RunConfig, GBQRModel

model_config = ModelConfig(
    model_name="my_model",
    use_ilinet=True,
    use_flusurvnet=False,
    num_bags=100,
    # ... other config
)

run_config = RunConfig(
    ref_date=datetime.date(2025, 12, 27),
    hub_root=Path("/path/to/repo"),
    output_root=Path("/path/to/repo/model-output"),
    max_horizon=4,
    q_levels=[0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975],
    q_labels=['0.025', '0.05', '0.1', '0.25', '0.5', '0.75', '0.9', '0.95', '0.975']
)

model = GBQRModel(model_config)
predictions = model.run(run_config)
```
