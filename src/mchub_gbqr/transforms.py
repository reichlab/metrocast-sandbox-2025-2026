"""Data transformation utilities for GBQR model.

This module provides power transform and scale/center normalization
for the incidence data, following the approach from idmodels.
"""

from typing import Optional, Tuple

import numpy as np
import pandas as pd


def apply_power_transform(
    inc: pd.Series,
    power_transform: Optional[str] = "4rt"
) -> pd.Series:
    """Apply power transform to incidence values.

    Args:
        inc: Series of incidence values.
        power_transform: Transform type ("4rt" for fourth root, or None).

    Returns:
        Transformed incidence values.
    """
    if power_transform is None:
        return inc + 0.01
    elif power_transform == "4rt":
        return (inc + 0.01) ** 0.25
    else:
        raise ValueError(f"Unknown power transform: {power_transform}")


def inverse_power_transform(
    inc_trans: pd.Series,
    power_transform: Optional[str] = "4rt"
) -> pd.Series:
    """Inverse power transform to get back incidence values.

    Args:
        inc_trans: Series of transformed incidence values.
        power_transform: Transform type that was applied.

    Returns:
        Original-scale incidence values.
    """
    if power_transform is None:
        return inc_trans - 0.01
    elif power_transform == "4rt":
        return inc_trans ** 4 - 0.01
    else:
        raise ValueError(f"Unknown power transform: {power_transform}")


def compute_scale_factors(
    df: pd.DataFrame,
    group_cols: list = ["source", "location"]
) -> pd.DataFrame:
    """Compute scale factors (95th percentile of in-season values).

    Scale factor is the 95th percentile of transformed incidence
    during in-season weeks (season_week 10-45) per source+location.

    Args:
        df: DataFrame with columns inc_trans, season_week, and group_cols.
        group_cols: Columns to group by for computing scale factors.

    Returns:
        DataFrame with original data plus inc_trans_scale_factor column.
    """
    df = df.copy()

    # Mark in-season values (season_week 10-45)
    df["inc_trans_in_season"] = np.where(
        (df["season_week"] >= 10) & (df["season_week"] <= 45),
        df["inc_trans"],
        np.nan
    )

    # Compute 95th percentile per group
    df["inc_trans_scale_factor"] = df.groupby(group_cols)["inc_trans_in_season"] \
        .transform(lambda x: x.quantile(0.95))

    df = df.drop(columns=["inc_trans_in_season"])

    return df


def compute_center_factors(
    df: pd.DataFrame,
    group_cols: list = ["source", "location"]
) -> pd.DataFrame:
    """Compute center factors (mean of scaled in-season values).

    Center factor is the mean of scaled transformed incidence
    during in-season weeks (season_week 10-45) per source+location.

    Args:
        df: DataFrame with columns inc_trans_cs, season_week, and group_cols.
        group_cols: Columns to group by for computing center factors.

    Returns:
        DataFrame with original data plus inc_trans_center_factor column.
    """
    df = df.copy()

    # Mark in-season values (season_week 10-45)
    df["inc_trans_cs_in_season"] = np.where(
        (df["season_week"] >= 10) & (df["season_week"] <= 45),
        df["inc_trans_cs"],
        np.nan
    )

    # Compute mean per group
    df["inc_trans_center_factor"] = df.groupby(group_cols)["inc_trans_cs_in_season"] \
        .transform(lambda x: x.mean())

    df = df.drop(columns=["inc_trans_cs_in_season"])

    return df


def apply_scale_center_transform(
    df: pd.DataFrame,
    power_transform: Optional[str] = "4rt",
    group_cols: list = ["source", "location"]
) -> pd.DataFrame:
    """Apply full power transform and scale/center normalization.

    Pipeline:
    1. Power transform: inc_trans = (inc + 0.01)^0.25
    2. Scale: inc_trans_cs = inc_trans / (scale_factor + 0.01)
    3. Center: inc_trans_cs = inc_trans_cs - center_factor

    Args:
        df: DataFrame with columns inc, season_week, and group_cols.
        power_transform: Transform type ("4rt" or None).
        group_cols: Columns to group by for computing factors.

    Returns:
        DataFrame with additional columns:
        - inc_trans: Power-transformed incidence
        - inc_trans_scale_factor: 95th percentile scale factor
        - inc_trans_cs: Scaled (before centering)
        - inc_trans_center_factor: Mean center factor
        - inc_trans_cs: Final scaled and centered values
    """
    df = df.copy()

    # Step 1: Power transform
    df["inc_trans"] = apply_power_transform(df["inc"], power_transform)

    # Step 2: Compute scale factors and apply scaling
    df = compute_scale_factors(df, group_cols)
    df["inc_trans_cs"] = df["inc_trans"] / (df["inc_trans_scale_factor"] + 0.01)

    # Step 3: Compute center factors and apply centering
    df = compute_center_factors(df, group_cols)
    df["inc_trans_cs"] = df["inc_trans_cs"] - df["inc_trans_center_factor"]

    return df


def inverse_scale_center_transform(
    predictions: pd.DataFrame,
    transform_factors: pd.DataFrame,
    power_transform: Optional[str] = "4rt"
) -> pd.DataFrame:
    """Inverse transform predictions back to original scale.

    Args:
        predictions: DataFrame with inc_trans_cs predictions and location column.
        transform_factors: DataFrame with location, inc_trans_scale_factor,
            inc_trans_center_factor columns.
        power_transform: Transform type that was applied.

    Returns:
        DataFrame with inc column (original scale predictions).
    """
    df = predictions.copy()

    # Merge transform factors
    df = df.merge(
        transform_factors[["location", "inc_trans_scale_factor", "inc_trans_center_factor"]].drop_duplicates(),
        on="location",
        how="left"
    )

    # Inverse center
    df["inc_trans_cs"] = df["inc_trans_cs"] + df["inc_trans_center_factor"]

    # Inverse scale
    df["inc_trans"] = df["inc_trans_cs"] * (df["inc_trans_scale_factor"] + 0.01)

    # Inverse power transform
    df["inc"] = inverse_power_transform(df["inc_trans"], power_transform)

    # Ensure non-negative
    df["inc"] = df["inc"].clip(lower=0)

    return df


def get_transform_factors(df: pd.DataFrame) -> pd.DataFrame:
    """Extract transform factors from a transformed DataFrame.

    Args:
        df: DataFrame with inc_trans_scale_factor and inc_trans_center_factor.

    Returns:
        DataFrame with unique location/factor combinations for inverse transform.
    """
    return df[["location", "inc_trans_scale_factor", "inc_trans_center_factor"]] \
        .drop_duplicates() \
        .reset_index(drop=True)
