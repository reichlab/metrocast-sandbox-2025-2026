"""HSA population utilities for GBQR model.

This module provides population data for HSA (Health Service Area) locations.
MCHub locations have population in the locations.csv crosswalk. For supplementary
NSSP HSAs beyond MCHub, populations would need to be computed from county-level
census data with HSA-to-county mappings.
"""

from pathlib import Path
from typing import Dict, Optional

import pandas as pd


def load_mchub_populations(hub_root: Path) -> Dict[str, int]:
    """Load population data for MCHub locations.

    Args:
        hub_root: Path to MCHub repository root.

    Returns:
        Dictionary mapping location slug to population.
    """
    locations_path = hub_root / "auxiliary-data" / "locations.csv"
    df = pd.read_csv(locations_path, dtype={"population": int})

    # Create mapping from location slug to population
    return dict(zip(df["location"], df["population"]))


def get_population(
    location: str,
    mchub_populations: Dict[str, int],
    nssp_populations: Optional[Dict[str, int]] = None
) -> Optional[int]:
    """Get population for a location.

    Args:
        location: Location identifier (slug or prefixed ID).
        mchub_populations: Dictionary of MCHub location populations.
        nssp_populations: Optional dictionary of NSSP HSA populations.

    Returns:
        Population as integer, or None if not available.
    """
    # MCHub locations (no prefix)
    if location in mchub_populations:
        return mchub_populations[location]

    # NSSP extra locations (nssp_ prefix)
    if location.startswith("nssp_") and nssp_populations:
        nssp_id = location[5:]  # Remove "nssp_" prefix
        return nssp_populations.get(nssp_id)

    return None


def load_supplementary_populations(
    hub_root: Path
) -> Dict[str, Dict[str, int]]:
    """Load population data for all sources.

    Returns dictionaries for different data sources that can be used
    to look up populations by location ID.

    Args:
        hub_root: Path to MCHub repository root.

    Returns:
        Dictionary with keys for each source type:
        - "mchub": MCHub location populations
        - "state": State FIPS -> population (for nhsn, ilinet state data)
        - "nssp_hsa": NSSP HSA NCI ID -> population (computed from counties)

    Note:
        Currently only MCHub populations are implemented. State populations
        can be obtained from iddata's census data. NSSP HSA populations
        beyond MCHub locations require county-level aggregation.
    """
    populations = {
        "mchub": load_mchub_populations(hub_root),
        "state": {},  # Can be populated from iddata census data
        "nssp_hsa": {},  # Requires county-level aggregation
    }

    return populations


def compute_nssp_hsa_populations() -> Dict[str, int]:
    """Compute populations for all NSSP HSAs from county data.

    This would require:
    1. Loading county-level population from Census API or iddata
    2. Loading HSA-to-county mapping from NSSP/CDC
    3. Aggregating county populations to HSA level

    Returns:
        Dictionary mapping HSA NCI ID to population.

    Note:
        Not yet implemented. For now, NSSP HSA populations beyond
        MCHub locations will be NaN, matching current iddata behavior.
    """
    # TODO: Implement HSA population computation from county data
    # For now, MCHub locations have population in locations.csv
    # and that covers the 72 prediction target locations
    return {}
