"""Shared GBQR model code for MetroCast Hub forecasting.

This package provides the core model implementation that can be used
by multiple model variants with different configurations.
"""

from .config import ModelConfig, RunConfig
from .model import GBQRModel

__all__ = ["ModelConfig", "RunConfig", "GBQRModel"]
