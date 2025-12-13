# GBQR 3-Source Model for Metrocast Hub

Gradient Boosting Quantile Regression model using NSSP, FluSurv-NET, and ILINet data sources for flu/ILI ED visit percentage forecasts at state and HSA levels.

## Model Configuration

- **Data Sources**: NSSP, FluSurv-NET, ILINet
- **Bagging**: 100 bags, 70% sample fraction
- **Power Transform**: 4th root
- **Fit Strategy**: Locations fit jointly
- **Targets**:
  - "Flu ED visits pct" for all locations
  - "ILI ED visits pct" for NYC only
- **Quantiles**: [0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975]

## Locations

The model forecasts for 72 locations across 13 states:
- **States**: CO, GA, IN, ME, MD, MA, MN, NY, NC, SC, TX, UT, VA
- **HSAs**: Multiple Health Service Areas within each state

Location mappings are defined in `auxiliary-data/locations.csv`.

## To Run Locally

Set up the environment and run a test forecast:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt

python main.py --today_date=2024-12-11 --short_run
```

For a full run (100 bags):

```bash
python main.py --today_date=2024-12-11
```

## To Run on Unity Cluster

Submit the SLURM array job for batch processing:

```bash
mkdir -p logs
sbatch submit-unity-parallel.sh
```

Or run sequentially (for testing):

```bash
./run-all-forecasts.sh
```

## Output

Predictions are saved to `model-output/UMass-gbqr_3src/YYYY-MM-DD-UMass-gbqr_3src.csv` with columns:
- `reference_date`: Saturday reference date
- `target`: "Flu ED visits pct" or "ILI ED visits pct"
- `horizon`: Forecast horizon (weeks ahead)
- `target_end_date`: Target week end date
- `location`: Location slug (e.g., "denver", "colorado")
- `output_type`: "quantile"
- `output_type_id`: Quantile level
- `value`: Predicted percentage (0-100)

## Dependencies

See `requirements.txt`. Requires the `idmodels` and `iddata` packages from the parent research directory.
