"""GBQR model using MCHub + NSSP extra data.

This model uses:
- MCHub target data (primary source)
- NSSP ED visits for additional locations (supplementary)
"""

import datetime
from pathlib import Path

import click
from dateutil import relativedelta

from src.mchub_gbqr import ModelConfig, RunConfig, GBQRModel


@click.command()
@click.option(
    "--today_date",
    type=str,
    required=True,
    help="Date to use as effective model run date (YYYY-MM-DD)"
)
@click.option(
    "--short_run",
    is_flag=True,
    help="Perform a short run with reduced bagging (10 bags)"
)
@click.option(
    "--use_local_mchub",
    is_flag=True,
    help="Use local MCHub target data instead of downloading from GitHub"
)
@click.option(
    "--use_versioned_mchub",
    is_flag=True,
    help="Fetch MCHub data as of reference date using GitHub API versioning"
)
def main(today_date: str, short_run: bool, use_local_mchub: bool, use_versioned_mchub: bool):
    """Generate GBQR forecasts using MCHub + NSSP extra data."""
    # Parse date and compute reference date (next Saturday from today_date)
    try:
        today_date = datetime.date.fromisoformat(today_date)
    except (TypeError, ValueError):
        today_date = datetime.date.today()
    reference_date = today_date + relativedelta.relativedelta(weekday=5)

    # Model configuration - MCHub + NSSP extra only
    model_config = ModelConfig(
        model_name="gbqr_nssp",

        # Only NSSP extra supplementary source
        use_ilinet=False,
        use_flusurvnet=False,
        use_nhsn=False,
        use_nssp_extra=True,

        # Bagging parameters
        num_bags=100,
        bag_frac_samples=0.7,

        # Feature configuration
        incl_level_feats=True,
        power_transform="4rt",
        fit_locations_separately=False,

        # Drop seasons with data quality issues or anomalous patterns
        drop_seasons=["1997/98", "1998/99", "1999/00", "2000/01", "2001/02", "2002/03",
                      "2008/09", "2009/10", "2020/21", "2021/22", "2022/23"]
    )

    # Run configuration
    hub_root = Path(__file__).parent.parent.parent
    run_config = RunConfig(
        ref_date=reference_date,
        hub_root=hub_root,
        output_root=hub_root / "model-output",
        max_horizon=4,
        q_levels=[0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975],
        q_labels=['0.025', '0.05', '0.1', '0.25', '0.5', '0.75', '0.9', '0.95', '0.975']
    )

    if short_run:
        model_config.num_bags = 10

    # Print configuration
    click.echo("Running GBQR model: gbqr_nssp")
    click.echo(f"  Reference date: {reference_date}")
    click.echo(f"  Num bags: {model_config.num_bags}")
    click.echo(f"  Data sources: MCHub + NSSP extra")
    click.echo()

    # Run model
    model = GBQRModel(model_config)
    preds_df = model.run(run_config, use_local_mchub=use_local_mchub, use_versioned_mchub=use_versioned_mchub)

    click.echo(f"\nGenerated {len(preds_df)} predictions for {preds_df['location'].nunique()} locations")


if __name__ == "__main__":
    main()
