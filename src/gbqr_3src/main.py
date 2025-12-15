import click
import datetime
import numpy as np
import pandas as pd
import pymmwr
from dateutil import relativedelta
from pathlib import Path
from types import SimpleNamespace

from iddata.loader import DiseaseDataLoader
from idmodels.gbqr import GBQRModel
from idmodels.preprocess import create_directional_wave_features, create_features_and_targets
from idmodels.utils import build_save_path

# URL for NYC ILI data
NYC_DATA_URL = "https://raw.githubusercontent.com/reichlab/flu-metrocast/main/target-data/latest-data.csv"

# State abbreviation to FIPS code mapping
STATE_ABB_TO_FIPS = {
    "CO": "08",
    "GA": "13",
    "IN": "18",
    "ME": "23",
    "MD": "24",
    "MA": "25",
    "MN": "27",
    "NY": "36",
    "NC": "37",
    "SC": "45",
    "TX": "48",
    "UT": "49",
    "VA": "51",
}


def load_location_crosswalk():
    """Load location crosswalk from auxiliary-data/locations.csv."""
    locations_path = Path(__file__).parent.parent.parent / "auxiliary-data" / "locations.csv"
    return pd.read_csv(locations_path, dtype=str)


def parse_locations(locations_df):
    """Parse locations into states and HSAs with mappings.

    Returns:
        states: List of state FIPS codes
        hsas: List of HSA NCI IDs
        code_to_slug: Dict mapping FIPS/HSA codes to location slugs
        slug_to_code: Dict mapping location slugs to FIPS/HSA codes
    """
    states = []
    hsas = []
    code_to_slug = {}
    slug_to_code = {}

    for _, row in locations_df.iterrows():
        slug = row["location"]
        original_code = row["original_location_code"]
        state_abb = row["state_abb"]
        location_type = row["location_type"]

        if original_code == "All":
            # State-level location
            fips = STATE_ABB_TO_FIPS.get(state_abb)
            if fips:
                states.append(fips)
                code_to_slug[fips] = slug
                slug_to_code[slug] = fips
        elif location_type == "hsa_nci_id":
            # HSA-level location
            hsas.append(original_code)
            code_to_slug[original_code] = slug
            slug_to_code[slug] = original_code
        # Skip nc_flu_region_id locations for now (not supported by NSSP)

    return states, hsas, code_to_slug, slug_to_code


def transform_predictions(preds_df, code_to_slug, target_name="Flu ED visits pct"):
    """Transform idmodels output to metrocast hub format.

    Args:
        preds_df: DataFrame with idmodels predictions
        code_to_slug: Dict mapping location codes to slugs
        target_name: Target name to use in output

    Returns:
        Transformed DataFrame in hub format
    """
    df = preds_df.copy()

    # Map location codes to slugs
    df["location"] = df["location"].map(code_to_slug)

    # Drop rows where location mapping failed (shouldn't happen)
    df = df.dropna(subset=["location"])

    # Convert proportion to percentage
    df["value"] = df["value"] * 100

    # Rename target
    df["target"] = target_name

    return df


def fetch_nyc_data_for_model(reference_date):
    """Fetch NYC ILI data and transform to iddata format for model integration.

    Args:
        reference_date: The reference date for filtering

    Returns:
        DataFrame with NYC data in iddata format, ready for model integration
    """
    print("  Fetching NYC data from flu-metrocast repository...")
    df = pd.read_csv(NYC_DATA_URL)

    # Filter to NYC ILI data only
    df = df[(df["location"] == "nyc") & (df["target"] == "ILI ED visits pct")].copy()

    if df.empty:
        print("  Warning: No NYC data available")
        return pd.DataFrame()

    # Convert date column to datetime
    df["wk_end_date"] = pd.to_datetime(df["target_end_date"])

    # Filter to data before reference_date
    df = df[df["wk_end_date"].dt.date < reference_date]

    # Convert observation from percentage to proportion (NSSP format is percentage)
    # The observation is already in percentage (0-100), keep it as-is since NSSP uses percentage
    df["inc"] = df["observation"]

    # Add epiweek info using pymmwr
    def get_epiweek_info(row):
        date = row["wk_end_date"].date()
        ew = pymmwr.date_to_epiweek(date)
        return pd.Series({
            "year": ew.year,
            "week": ew.week
        })

    epiweek_info = df.apply(get_epiweek_info, axis=1)
    df["year"] = epiweek_info["year"]
    df["week"] = epiweek_info["week"]

    # Calculate season and season_week
    def calc_season(row):
        year = int(row["year"])
        week = int(row["week"])
        if week >= 40:
            return f"{year}/{str(year + 1)[2:]}"
        else:
            return f"{year - 1}/{str(year)[2:]}"

    def calc_season_week(row):
        week = int(row["week"])
        if week >= 40:
            return week - 39
        else:
            return week + 13

    df["season"] = df.apply(calc_season, axis=1)
    df["season_week"] = df.apply(calc_season_week, axis=1)

    # Set iddata-compatible columns
    df["location"] = "94"  # NYC HSA NCI ID
    df["agg_level"] = "hsa"
    df["source"] = "nssp"  # Treat as NSSP-like data for model compatibility
    df["pop"] = np.nan  # HSAs don't have population in iddata
    df["log_pop"] = np.nan

    # Keep only required columns
    df = df[["agg_level", "location", "season", "season_week", "wk_end_date", "inc", "source", "pop", "log_pop"]]
    df = df.sort_values("wk_end_date")

    latest_date = df["wk_end_date"].iloc[-1]
    latest_value = df["inc"].iloc[-1]
    print(f"  NYC data loaded: {len(df)} weeks, latest: {latest_date.date()} = {latest_value:.2f}%")

    return df


class GBQRModelWithNYC(GBQRModel):
    """Extended GBQR model that can integrate NYC data from external source."""

    def __init__(self, model_config, nyc_data=None):
        super().__init__(model_config)
        self.nyc_data = nyc_data

    def run(self, run_config):
        """
        Load data, integrate NYC data if provided, generate predictions, and save.
        This overrides the parent run() to inject NYC data into the pipeline.
        """
        # Load flu data (same as parent)
        if self.model_config.reporting_adj:
            ilinet_kwargs = None
            flusurvnet_kwargs = None
        else:
            ilinet_kwargs = {"scale_to_positive": False}
            flusurvnet_kwargs = {"burden_adj": False}

        valid_sources = ["flusurvnet", "nhsn", "ilinet", "nssp"]
        if not np.isin(np.array(self.model_config.sources), valid_sources).all():
            raise ValueError("For GBQR, the only supported data sources are 'nhsn', 'flusurvnet', 'ilinet', or 'nssp'.")

        if all(src in self.model_config.sources for src in ["nhsn", "nssp"]):
            raise ValueError("Only one of 'nhsn' or 'nssp' may be selected as a data source.")

        fdl = DiseaseDataLoader()
        if "nhsn" in self.model_config.sources:
            df = fdl.load_data(nhsn_kwargs={"as_of": run_config.ref_date, "disease": run_config.disease},
                               ilinet_kwargs=ilinet_kwargs,
                               flusurvnet_kwargs=flusurvnet_kwargs,
                               sources=self.model_config.sources,
                               power_transform=self.model_config.power_transform)
        elif "nssp" in self.model_config.sources:
            df = fdl.load_data(nssp_kwargs={"as_of": run_config.ref_date, "disease": run_config.disease},
                               ilinet_kwargs=ilinet_kwargs,
                               flusurvnet_kwargs=flusurvnet_kwargs,
                               sources=self.model_config.sources,
                               power_transform=self.model_config.power_transform)

        # INJECT NYC DATA HERE if provided
        if self.nyc_data is not None and not self.nyc_data.empty:
            print("  Integrating NYC data into model dataset...")

            # First, remove any existing data for NYC (location="94") to avoid duplicates
            # This ensures our injected data is the only source for NYC predictions
            original_count = len(df)
            df = df[df["location"] != "94"]
            removed_count = original_count - len(df)
            if removed_count > 0:
                print(f"  Removed {removed_count} existing NYC rows from data")

            # Get the max date from non-NYC HSA data to ensure NYC doesn't extend beyond
            # This prevents NYC having a later date than other HSAs, which would filter them out
            hsa_max_date = df[df["agg_level"] == "hsa"]["wk_end_date"].max()
            print(f"  Max HSA data date (non-NYC): {hsa_max_date.date() if pd.notna(hsa_max_date) else 'N/A'}")

            nyc_df = self.nyc_data.copy()

            # Filter NYC data to not extend beyond HSA data
            if pd.notna(hsa_max_date):
                pre_filter_count = len(nyc_df)
                nyc_df = nyc_df[nyc_df["wk_end_date"] <= hsa_max_date]
                date_filtered = pre_filter_count - len(nyc_df)
                if date_filtered > 0:
                    print(f"  Filtered {date_filtered} NYC rows to align with HSA max date")

            # Filter out pandemic-affected seasons (2020/21 and 2021/22)
            # Keep 2019/20 as it was largely typical before March
            pandemic_seasons = ["2020/21", "2021/22"]
            pre_filter_count = len(nyc_df)
            nyc_df = nyc_df[~nyc_df["season"].isin(pandemic_seasons)]
            filtered_count = pre_filter_count - len(nyc_df)
            if filtered_count > 0:
                print(f"  Filtered out {filtered_count} NYC rows from pandemic seasons {pandemic_seasons}")

            # Apply the same transformations as iddata does for NSSP data
            # Power transform: inc_trans = (inc + 0.01)^0.25
            if self.model_config.power_transform == "4rt":
                nyc_df["inc_trans"] = (nyc_df["inc"] + 0.01) ** 0.25
            else:
                nyc_df["inc_trans"] = nyc_df["inc"] + 0.01

            # Extract scale and center factors from pooled HSA data (for consistency)
            # Use factors from other HSAs so NYC is on the same scale
            hsa_data = df[df["agg_level"] == "hsa"]
            if len(hsa_data) > 0 and "inc_trans_scale_factor" in hsa_data.columns:
                # Get the pooled scale/center factors (should be same across all HSAs)
                scale_factor = hsa_data["inc_trans_scale_factor"].iloc[0]
                center_factor = hsa_data["inc_trans_center_factor"].iloc[0]
                print(f"  Using pooled HSA scale_factor={scale_factor:.4f}, center_factor={center_factor:.4f}")
            else:
                # Fallback: compute from NYC data if HSA factors not available
                print("  Warning: Could not extract HSA factors, computing from NYC data")
                nyc_in_season = nyc_df[(nyc_df["season_week"] >= 10) & (nyc_df["season_week"] <= 45)]
                if len(nyc_in_season) > 0:
                    scale_factor = nyc_in_season["inc_trans"].quantile(0.95)
                else:
                    scale_factor = nyc_df["inc_trans"].quantile(0.95)
                nyc_df["inc_trans_cs_temp"] = nyc_df["inc_trans"] / (scale_factor + 0.01)
                nyc_in_season_cs = nyc_df[(nyc_df["season_week"] >= 10) & (nyc_df["season_week"] <= 45)]
                if len(nyc_in_season_cs) > 0:
                    center_factor = nyc_in_season_cs["inc_trans_cs_temp"].mean()
                else:
                    center_factor = nyc_df["inc_trans_cs_temp"].mean()
                nyc_df = nyc_df.drop(columns=["inc_trans_cs_temp"])

            # Apply the pooled scale and center factors to NYC data
            nyc_df["inc_trans_scale_factor"] = scale_factor
            nyc_df["inc_trans_cs"] = nyc_df["inc_trans"] / (scale_factor + 0.01)
            nyc_df["inc_trans_center_factor"] = center_factor
            nyc_df["inc_trans_cs"] = nyc_df["inc_trans_cs"] - center_factor

            # Append NYC data to main dataframe
            df = pd.concat([df, nyc_df], axis=0, ignore_index=True)
            df = df.sort_values(["source", "location", "wk_end_date"])
            print(f"  NYC data integrated: {len(nyc_df)} rows added")

        # Continue with standard GBQRModel processing
        if (run_config.states == []) & (run_config.hsas == []):
            raise ValueError("User must request a non-empty set of locations to forecast for.")

        if (run_config.states != []) & (run_config.hsas != []):
            raise NotImplementedError("Functionality for simultaneously forecasting state- and hsa-level locations is not yet implemented.")

        df_states = df.loc[(df["location"].isin(run_config.states)) & (df["agg_level"] != "hsa")]
        df_hsas = df.loc[(df["location"].isin(run_config.hsas)) & (df["agg_level"] == "hsa")]
        df = pd.concat([df_states, df_hsas], join="inner", axis=0)

        # Augment data with features and target values
        if run_config.disease == "flu":
            init_feats = ["inc_trans_cs", "season_week", "log_pop"]
        elif run_config.disease == "covid":
            init_feats = ["inc_trans_cs", "log_pop"]

        # Create directional wave features if enabled
        if hasattr(self.model_config, "use_directional_waves") and self.model_config.use_directional_waves:
            wave_config = {
                "enabled": True,
                "directions": getattr(self.model_config, "wave_directions", ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]),
                "temporal_lags": getattr(self.model_config, "wave_temporal_lags", [1, 2]),
                "max_distance_km": getattr(self.model_config, "wave_max_distance_km", 1000),
                "include_velocity": getattr(self.model_config, "wave_include_velocity", False),
                "include_aggregate": getattr(self.model_config, "wave_include_aggregate", True)
            }
            df, wave_feat_names = create_directional_wave_features(df, wave_config)
            init_feats = init_feats + wave_feat_names

        df, feat_names = create_features_and_targets(
            df=df,
            incl_level_feats=self.model_config.incl_level_feats,
            max_horizon=run_config.max_horizon,
            curr_feat_names=init_feats)

        # Keep only rows that are in-season
        if run_config.disease == "flu":
            df = df.query("season_week >= 5 and season_week <= 45")

        # "test set" df used to generate look-ahead predictions
        df_test = df.loc[df.wk_end_date == df.wk_end_date.max()].copy()

        # "train set" df for model fitting; target value non-missing
        df_train = df.loc[~df["delta_target"].isna().values]

        # Train model and obtain test set predictions
        if self.model_config.fit_locations_separately:
            locations = df_test["location"].unique()
            preds_df = [
                self._train_gbq_and_predict(
                    run_config,
                    df_train, df_test, feat_names, location
                ) for location in locations
            ]
            preds_df = pd.concat(preds_df, axis=0)
        else:
            preds_df = self._train_gbq_and_predict(
                run_config,
                df_train, df_test, feat_names
            )

        # Save
        save_path = build_save_path(
            root=run_config.output_root,
            run_config=run_config,
            model_config=self.model_config
        )
        preds_df.to_csv(save_path, index=False)


@click.command()
@click.option(
    "--today_date",
    type=str,
    required=True,
    help="Date to use as effective model run date (YYYY-MM-DD)",
)
@click.option(
    "--short_run",
    is_flag=True,
    help="Perform a short run with fewer bags.",
)
def main(today_date: str, short_run: bool):
    """Generate flu predictions from gbqr model for metrocast hub."""
    try:
        today_date = datetime.date.fromisoformat(today_date)
    except (TypeError, ValueError):
        today_date = datetime.date.today()
    reference_date = today_date + relativedelta.relativedelta(weekday=5)

    # Load and parse location crosswalk
    locations_df = load_location_crosswalk()
    states, hsas, code_to_slug, slug_to_code = parse_locations(locations_df)

    print(f"Running forecasts for reference date: {reference_date}")
    print(f"States: {states}")
    print(f"HSAs (including NYC): {hsas}")

    # Common run configuration
    q_levels = [0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975]
    q_labels = ['0.025', '0.05', '0.1', '0.25', '0.5', '0.75', '0.9', '0.95', '0.975']

    num_bags = 10 if short_run else 100

    all_predictions = []

    # Output directory for intermediate files
    output_root = Path(__file__).parent.parent.parent / "model-output"

    # Fetch NYC data for integration into the HSA model
    print("\nFetching NYC data for model integration...")
    nyc_data = fetch_nyc_data_for_model(reference_date)

    # Run model for states
    if states:
        print(f"\nRunning model for {len(states)} states...")

        # Use temporary model name for states
        model_config_states = SimpleNamespace(
            model_class="gbqr",
            model_name="gbqr_3src_states_temp",
            incl_level_feats=True,
            num_bags=num_bags,
            bag_frac_samples=0.7,
            reporting_adj=False,
            sources=["nssp", "flusurvnet", "ilinet"],
            fit_locations_separately=False,
            power_transform="4rt"
        )

        run_config_states = SimpleNamespace(
            disease="flu",
            ref_date=reference_date,
            output_root=output_root,
            artifact_store_root=None,
            save_feat_importance=False,
            max_horizon=4,
            states=states,
            hsas=[],
            q_levels=q_levels,
            q_labels=q_labels
        )

        model = GBQRModel(model_config_states)
        model.run(run_config_states)

        # Read the saved predictions
        states_output_file = output_root / "UMass-gbqr_3src_states_temp" / f"{reference_date}-UMass-gbqr_3src_states_temp.csv"
        if states_output_file.exists():
            preds_states = pd.read_csv(states_output_file, dtype={"location": str})
            preds_states_transformed = transform_predictions(
                preds_states, code_to_slug, "Flu ED visits pct"
            )
            all_predictions.append(preds_states_transformed)
            print(f"  Generated {len(preds_states_transformed)} state predictions")
            # Clean up temp file
            states_output_file.unlink()
            states_output_file.parent.rmdir()

    # Run model for HSAs (including NYC with integrated data)
    if hsas:
        print(f"\nRunning model for {len(hsas)} HSAs (including NYC with integrated data)...")

        # Use temporary model name for HSAs
        model_config_hsas = SimpleNamespace(
            model_class="gbqr",
            model_name="gbqr_3src_hsas_temp",
            incl_level_feats=True,
            num_bags=num_bags,
            bag_frac_samples=0.7,
            reporting_adj=False,
            sources=["nssp", "flusurvnet", "ilinet"],
            fit_locations_separately=False,
            power_transform="4rt"
        )

        run_config_hsas = SimpleNamespace(
            disease="flu",
            ref_date=reference_date,
            output_root=output_root,
            artifact_store_root=None,
            save_feat_importance=False,
            max_horizon=4,
            states=[],
            hsas=hsas,  # Include all HSAs including NYC (94)
            q_levels=q_levels,
            q_labels=q_labels
        )

        # Use custom model class with NYC data integration
        model = GBQRModelWithNYC(model_config_hsas, nyc_data=nyc_data)
        model.run(run_config_hsas)

        # Read the saved predictions
        hsas_output_file = output_root / "UMass-gbqr_3src_hsas_temp" / f"{reference_date}-UMass-gbqr_3src_hsas_temp.csv"
        if hsas_output_file.exists():
            preds_hsas = pd.read_csv(hsas_output_file, dtype={"location": str})

            # Transform predictions - NYC gets "ILI ED visits pct", others get "Flu ED visits pct"
            preds_hsas_non_nyc = preds_hsas[preds_hsas["location"] != "94"]
            preds_hsas_nyc = preds_hsas[preds_hsas["location"] == "94"]

            if not preds_hsas_non_nyc.empty:
                preds_non_nyc_transformed = transform_predictions(
                    preds_hsas_non_nyc, code_to_slug, "Flu ED visits pct"
                )
                all_predictions.append(preds_non_nyc_transformed)
                print(f"  Generated {len(preds_non_nyc_transformed)} HSA predictions (Flu)")

            if not preds_hsas_nyc.empty:
                preds_nyc_transformed = transform_predictions(
                    preds_hsas_nyc, code_to_slug, "ILI ED visits pct"
                )
                # Deduplicate NYC predictions by taking the mean of non-null values
                # This can happen when the model processes NYC from multiple internal data rows
                dedup_cols = ["location", "reference_date", "horizon", "target_end_date", "target", "output_type", "output_type_id"]
                # Drop rows with NaN values before grouping, then average
                preds_nyc_transformed = preds_nyc_transformed.dropna(subset=["value"])
                preds_nyc_transformed = preds_nyc_transformed.groupby(dedup_cols, as_index=False)["value"].mean()
                all_predictions.append(preds_nyc_transformed)
                print(f"  Generated {len(preds_nyc_transformed)} NYC predictions (ILI)")

            # Clean up temp file
            hsas_output_file.unlink()
            hsas_output_file.parent.rmdir()

    # Combine all predictions
    if all_predictions:
        combined_df = pd.concat(all_predictions, ignore_index=True)

        # Ensure output directory exists
        output_dir = output_root / "UMass-gbqr_3src"
        output_dir.mkdir(parents=True, exist_ok=True)

        # Save predictions
        output_file = output_dir / f"{reference_date}-UMass-gbqr_3src.csv"
        combined_df.to_csv(output_file, index=False)
        print(f"\nSaved {len(combined_df)} predictions to {output_file}")
    else:
        print("\nNo predictions generated!")


if __name__ == "__main__":
    main()
