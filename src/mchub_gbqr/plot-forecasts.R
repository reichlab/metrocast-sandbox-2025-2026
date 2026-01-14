#!/usr/bin/env Rscript
# Plot forecasts from a single gbqr_v2 model output file
# Groups all locations by state on each page
# Usage: Rscript plot-forecasts.R <forecast_file>
# Example: Rscript plot-forecasts.R ../../model-output/UMass-gbqr_v2/2025-12-10-UMass-gbqr_v2.csv

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(lubridate)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  # Default to most recent forecast file
  script_dir <- dirname(normalizePath(sub(
    "--file=",
    "",
    grep("--file=", commandArgs(FALSE), value = TRUE)
  )))
  if (length(script_dir) == 0) {
    script_dir <- getwd()
  }
  repo_root <- normalizePath(file.path(script_dir, "../.."))
  model_output_dir <- file.path(repo_root, "model-output", "UMass-gbqr_v2")
  forecast_files <- list.files(
    model_output_dir,
    pattern = "*.csv",
    full.names = TRUE
  )
  if (length(forecast_files) == 0) {
    stop(
      "No forecast files found and no file specified. Usage: Rscript plot-forecasts.R <forecast_file>"
    )
  }
  forecast_file <- forecast_files[length(forecast_files)] # Most recent
  cat(sprintf("No file specified, using most recent: %s\n", forecast_file))
} else {
  forecast_file <- args[1]
}

# Determine repo root from forecast file path
if (grepl("model-output", forecast_file)) {
  repo_root <- normalizePath(file.path(dirname(forecast_file), "../.."))
} else {
  # Try to find repo root from script location
  script_dir <- dirname(normalizePath(sub(
    "--file=",
    "",
    grep("--file=", commandArgs(FALSE), value = TRUE)
  )))
  if (length(script_dir) == 0) {
    script_dir <- getwd()
  }
  repo_root <- normalizePath(file.path(script_dir, "../.."))
}

target_data_file <- "https://raw.githubusercontent.com/reichlab/flu-metrocast/refs/heads/main/target-data/latest-data.csv"
locations_file <- file.path(repo_root, "auxiliary-data", "locations.csv")

cat(sprintf("Forecast file: %s\n", forecast_file))
cat(sprintf("Target data: %s\n", target_data_file))
cat(sprintf("Locations: %s\n", locations_file))

# Load data
cat("\nLoading data...\n")

locations <- read_csv(locations_file, show_col_types = FALSE)

target_data <- read_csv(target_data_file, show_col_types = FALSE) |>
  mutate(target_end_date = as.Date(target_end_date))

forecasts <- read_csv(forecast_file, show_col_types = FALSE) |>
  mutate(
    reference_date = as.Date(reference_date),
    target_end_date = as.Date(target_end_date),
    output_type_id = as.numeric(output_type_id)
  )

# Get reference date from forecast
ref_date <- unique(forecasts$reference_date)[1]
cat(sprintf("Reference date: %s\n", ref_date))
cat(sprintf(
  "Loaded %d forecast rows for %d locations\n",
  nrow(forecasts),
  n_distinct(forecasts$location)
))

# Extract model name from forecast file path
model_name <- tryCatch(
  {
    basename(dirname(forecast_file)) |>
      gsub("UMass-", "", x = _)
  },
  error = function(e) "gbqr"
)
cat(sprintf("Model: %s\n", model_name))

# Determine current season year (season runs roughly Aug-Jul, use ref_date to determine)
current_season_year <- if (month(ref_date) >= 8) {
  year(ref_date)
} else {
  year(ref_date) - 1
}
cat(sprintf(
  "Current season: %d/%d\n",
  current_season_year,
  current_season_year + 1
))

# Create historical season data aligned to current year
# For each location, shift past seasons to align with current season dates
create_historical_seasons <- function(target_df, ref_date) {
  current_season_year <- if (month(ref_date) >= 8) {
    year(ref_date)
  } else {
    year(ref_date) - 1
  }

  # Add season info to target data
  target_with_season <- target_df |>
    mutate(
      season_year = if_else(
        month(target_end_date) >= 8,
        year(target_end_date),
        year(target_end_date) - 1
      ),
      # Calculate days since Aug 1 of season year for alignment
      season_start = as.Date(paste0(season_year, "-08-01")),
      day_of_season = as.numeric(target_end_date - season_start)
    )

  # Get past seasons (exclude current season)
  past_seasons <- target_with_season |>
    filter(season_year < current_season_year) |>
    mutate(
      # Shift dates to align with current season
      current_season_start = as.Date(paste0(current_season_year, "-08-01")),
      aligned_date = current_season_start + day_of_season,
      season_label = paste0(season_year, "/", (season_year + 1) %% 100)
    )

  return(past_seasons)
}

historical_data <- create_historical_seasons(target_data, ref_date)
n_historical_seasons <- n_distinct(historical_data$season_year)
cat(sprintf("Historical seasons available: %d\n", n_historical_seasons))

# Pivot forecasts to wide format
forecasts_wide <- forecasts |>
  select(
    location,
    reference_date,
    target_end_date,
    target,
    output_type_id,
    value
  ) |>
  pivot_wider(
    names_from = output_type_id,
    values_from = value,
    names_prefix = "q"
  )

# Output directory - save in src/gbqr_v2/plots/
script_dir <- tryCatch(
  {
    dirname(normalizePath(sub(
      "--file=",
      "",
      grep("--file=", commandArgs(FALSE), value = TRUE)
    )))
  },
  error = function(e) getwd()
)

output_dir <- file.path(script_dir, "plots")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Function to plot all locations for a state on one page
plot_state <- function(
  state_name,
  forecasts_df,
  target_df,
  historical_df,
  locations_df,
  ref_date,
  model_name = "gbqr",
  season_year = NULL
) {
  # Get locations for this state
  state_locs <- locations_df |>
    filter(state == state_name, location %in% unique(forecasts_df$location)) |>
    select(location, state, state_abb, location_name, original_location_code) |>
    # Put state-level first (original_location_code == "All"), then alphabetically
    arrange(desc(original_location_code == "All"), location_name)

  if (nrow(state_locs) == 0) {
    return(NULL)
  }

  loc_list <- state_locs$location
  n_locs <- length(loc_list)
  state_abb <- state_locs$state_abb[1]

  # Prepare forecast data
  state_forecasts <- forecasts_df |>
    filter(location %in% loc_list) |>
    left_join(state_locs |> select(location, location_name), by = "location") |>
    mutate(
      location_name = factor(location_name, levels = state_locs$location_name)
    )

  # Get target type
  target_type <- unique(state_forecasts$target)[1]

  # Prepare target data
  state_targets <- target_df |>
    filter(location %in% loc_list, target == target_type) |>
    left_join(state_locs |> select(location, location_name), by = "location") |>
    mutate(
      location_name = factor(location_name, levels = state_locs$location_name)
    )

  # Date range - extend to April 1 for full historical season context
  # season_year is the year the flu season started (e.g., 2025 for 2025/2026 season)
  if (is.null(season_year)) {
    season_year <- if (month(ref_date) >= 8) {
      year(ref_date)
    } else {
      year(ref_date) - 1
    }
  }
  min_date <- min(state_forecasts$target_end_date) - 56
  max_date <- as.Date(paste0(season_year + 1, "-04-01")) # April 1 of season end year

  state_targets_filtered <- state_targets |>
    filter(target_end_date >= min_date, target_end_date <= max_date)

  # Prepare historical data (aligned to current season dates) - show through April 1
  state_historical <- historical_df |>
    filter(location %in% loc_list, target == target_type) |>
    filter(aligned_date >= min_date, aligned_date <= max_date) |>
    left_join(state_locs |> select(location, location_name), by = "location") |>
    mutate(
      location_name = factor(location_name, levels = state_locs$location_name)
    )

  # Determine grid layout
  ncol <- if (n_locs <= 2) {
    1
  } else if (n_locs <= 6) {
    2
  } else {
    3
  }

  # Build plot - start with historical seasons in background
  p <- ggplot()

  # Add historical season curves (grey, in background)
  if (nrow(state_historical) > 0) {
    p <- p +
      geom_line(
        data = state_historical,
        aes(x = aligned_date, y = observation, group = season_label),
        color = "grey70",
        linewidth = 0.4,
        alpha = 0.6
      )
  }

  # Current season observations (black)
  p <- p +
    geom_line(
      data = state_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      linewidth = 0.6
    ) +
    geom_point(
      data = state_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      size = 1
    )

  # 95% prediction interval
  if (
    "q0.025" %in% names(state_forecasts) && "q0.975" %in% names(state_forecasts)
  ) {
    p <- p +
      geom_ribbon(
        data = state_forecasts,
        aes(x = target_end_date, ymin = q0.025, ymax = q0.975),
        fill = "steelblue",
        alpha = 0.2
      )
  }

  # 50% prediction interval
  if (
    "q0.25" %in% names(state_forecasts) && "q0.75" %in% names(state_forecasts)
  ) {
    p <- p +
      geom_ribbon(
        data = state_forecasts,
        aes(x = target_end_date, ymin = q0.25, ymax = q0.75),
        fill = "steelblue",
        alpha = 0.3
      )
  }

  # Median forecast line
  if ("q0.5" %in% names(state_forecasts)) {
    p <- p +
      geom_line(
        data = state_forecasts,
        aes(x = target_end_date, y = q0.5),
        color = "steelblue",
        linewidth = 0.8
      )
    # Add points for median forecasts
    p <- p +
      geom_point(
        data = state_forecasts,
        aes(x = target_end_date, y = q0.5),
        color = "steelblue",
        size = 2
      )
  }

  # Reference date line
  p <- p +
    geom_vline(
      xintercept = as.numeric(ref_date),
      linetype = "dashed",
      color = "gray50",
      alpha = 0.5
    )

  # Count historical seasons for caption
  n_hist_seasons <- n_distinct(state_historical$season_label)

  p <- p +
    facet_wrap(~location_name, scales = "free_y", ncol = ncol) +
    labs(
      title = sprintf(
        "%s (%s) - Flu/ILI ED Visits Forecasts",
        state_name,
        state_abb
      ),
      subtitle = sprintf(
        "UMass-%s | Reference: %s | %d location%s",
        model_name,
        ref_date,
        n_locs,
        if (n_locs > 1) "s" else ""
      ),
      x = "Date",
      y = "ED visits (%)",
      caption = sprintf(
        "Black: current season | Grey: %d historical season%s | Blue: forecasts (50%% & 95%% intervals)",
        n_hist_seasons,
        if (n_hist_seasons != 1) "s" else ""
      )
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 10, color = "gray40"),
      strip.text = element_text(face = "bold", size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      axis.text.y = element_text(size = 7),
      plot.caption = element_text(size = 8, color = "gray50")
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "2 weeks")

  return(p)
}

# Get unique states from forecast locations
forecast_locations <- unique(forecasts_wide$location)
states <- locations |>
  filter(location %in% forecast_locations) |>
  pull(state) |>
  unique() |>
  sort()

cat(sprintf("\nFound %d states\n", length(states)))

# Generate PDF with one page per state
cat("\nGenerating state-grouped PDF...\n")
pdf_file <- file.path(
  output_dir,
  sprintf("%s-%s-forecasts.pdf", ref_date, model_name)
)
pdf(pdf_file, width = 14, height = 10)

for (state_name in states) {
  cat(sprintf("  %s\n", state_name))
  p <- plot_state(
    state_name,
    forecasts_wide,
    target_data,
    historical_data,
    locations,
    ref_date,
    model_name,
    current_season_year
  )
  if (!is.null(p)) {
    print(p)
  }
}

dev.off()
cat(sprintf("\nSaved: %s\n", pdf_file))

# Create summary plot with selected locations
cat("\nGenerating summary plot...\n")

summary_locs <- c(
  "colorado",
  "massachusetts",
  "texas",
  "minnesota",
  "georgia",
  "nyc",
  "denver",
  "boston",
  "houston",
  "minneapolis",
  "clt-area"
)
summary_locs <- summary_locs[summary_locs %in% forecast_locations]

if (length(summary_locs) > 0) {
  summary_forecasts <- forecasts_wide |>
    filter(location %in% summary_locs) |>
    left_join(locations |> select(location, location_name), by = "location") |>
    mutate(location_name = coalesce(location_name, location))

  summary_targets <- target_data |>
    filter(location %in% summary_locs) |>
    left_join(locations |> select(location, location_name), by = "location") |>
    mutate(location_name = coalesce(location_name, location))

  # Date range - extend to April 1 for full historical season context
  min_date <- min(summary_forecasts$target_end_date) - 56
  max_date <- as.Date(paste0(current_season_year + 1, "-04-01")) # April 1 of season end year

  summary_targets_filtered <- summary_targets |>
    filter(target_end_date >= min_date, target_end_date <= max_date)

  # Get target types for summary locations
  summary_target_types <- unique(summary_forecasts$target)

  # Prepare historical data for summary locations - show through April 1
  summary_historical <- historical_data |>
    filter(location %in% summary_locs, target %in% summary_target_types) |>
    filter(aligned_date >= min_date, aligned_date <= max_date) |>
    left_join(locations |> select(location, location_name), by = "location") |>
    mutate(location_name = coalesce(location_name, location))

  n_hist_seasons <- n_distinct(summary_historical$season_label)

  # Start with historical seasons in background
  p_summary <- ggplot()

  if (nrow(summary_historical) > 0) {
    p_summary <- p_summary +
      geom_line(
        data = summary_historical,
        aes(x = aligned_date, y = observation, group = season_label),
        color = "grey70",
        linewidth = 0.4,
        alpha = 0.6
      )
  }

  p_summary <- p_summary +
    geom_line(
      data = summary_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      linewidth = 0.5
    ) +
    geom_point(
      data = summary_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      size = 0.8
    )

  if ("q0.025" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_ribbon(
        data = summary_forecasts,
        aes(x = target_end_date, ymin = q0.025, ymax = q0.975),
        fill = "steelblue",
        alpha = 0.2
      )
  }

  if ("q0.25" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_ribbon(
        data = summary_forecasts,
        aes(x = target_end_date, ymin = q0.25, ymax = q0.75),
        fill = "steelblue",
        alpha = 0.3
      )
  }

  if ("q0.5" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_line(
        data = summary_forecasts,
        aes(x = target_end_date, y = q0.5),
        color = "steelblue",
        linewidth = 0.8
      )
    # Add points for median forecasts
    p_summary <- p_summary +
      geom_point(
        data = summary_forecasts,
        aes(x = target_end_date, y = q0.5),
        color = "steelblue",
        size = 2
      )
  }

  p_summary <- p_summary +
    geom_vline(
      xintercept = as.numeric(ref_date),
      linetype = "dashed",
      color = "gray50",
      alpha = 0.5
    ) +
    facet_wrap(~location_name, scales = "free_y", ncol = 3) +
    labs(
      title = sprintf(
        "UMass-%s Forecasts - Reference Date: %s",
        model_name,
        ref_date
      ),
      subtitle = "Selected locations",
      x = "Date",
      y = "ED visits (%)",
      caption = sprintf(
        "Black: current season | Grey: %d historical season%s | Blue: forecasts (50%% & 95%% intervals)",
        n_hist_seasons,
        if (n_hist_seasons != 1) "s" else ""
      )
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      strip.text = element_text(face = "bold", size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7)
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "2 weeks")

  summary_file <- file.path(
    output_dir,
    sprintf("%s-%s-summary.png", ref_date, model_name)
  )
  ggsave(summary_file, p_summary, width = 14, height = 10, dpi = 150)
  cat(sprintf("Saved: %s\n", summary_file))
}

cat("\nDone!\n")
