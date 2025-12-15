#!/usr/bin/env Rscript
# Plot forecasts from gbqr_3src model
# Creates forecast plots showing predictions with uncertainty intervals and observations

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(stringr)

# Set up paths
# Get script directory - works both when sourced and when run via Rscript
get_script_dir <- function() {
  # Try various methods to get script directory
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("--file=", "", file_arg))))
  }
  # If sourced or running interactively
  if (exists("ofile", envir = sys.frame(1))) {
    return(dirname(sys.frame(1)$ofile))
  }
  # Default to current directory
  return(getwd())
}

script_dir <- get_script_dir()
repo_root <- normalizePath(file.path(script_dir, "../.."))

# Directories
model_output_dir <- file.path(repo_root, "model-output", "UMass-gbqr_3src")
target_data_file <- file.path(repo_root, "target-data", "latest-data.csv")
locations_file <- file.path(repo_root, "auxiliary-data", "locations.csv")
output_dir <- file.path(script_dir, "plots")

# Create output directory
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("Loading data...\n")

# Load locations for display names
locations <- read_csv(locations_file, show_col_types = FALSE)

# Load target data
target_data <- read_csv(target_data_file, show_col_types = FALSE) |>
  mutate(target_end_date = as.Date(target_end_date))

# Get list of forecast files
forecast_files <- list.files(model_output_dir, pattern = "*.csv", full.names = TRUE)
cat(sprintf("Found %d forecast files\n", length(forecast_files)))

# Load all forecasts
forecasts <- lapply(forecast_files, function(f) {
  read_csv(f, show_col_types = FALSE)
}) |>
  bind_rows() |>
  mutate(
    reference_date = as.Date(reference_date),
    target_end_date = as.Date(target_end_date),
    output_type_id = as.numeric(output_type_id)
  )

cat(sprintf("Loaded %d forecast rows\n", nrow(forecasts)))

# Get unique locations
forecast_locations <- unique(forecasts$location)
cat(sprintf("Forecasting for %d locations\n", length(forecast_locations)))

# Function to create forecast plot for a single location
plot_location_forecast <- function(loc, forecasts_df, target_df, locations_df) {

  # Get location display name
  loc_info <- locations_df |> filter(location == loc)
  display_name <- if (nrow(loc_info) > 0) loc_info$location_name[1] else loc

  # Filter forecasts for this location
  loc_forecasts <- forecasts_df |>
    filter(location == loc)

  if (nrow(loc_forecasts) == 0) {
    return(NULL)
  }

  # Get target type for this location
  target_type <- unique(loc_forecasts$target)[1]

  # Filter target data for this location and target
  loc_targets <- target_df |>
    filter(location == loc, target == target_type)

  # Pivot forecasts to wide format for plotting quantiles
  forecasts_wide <- loc_forecasts |>
    select(reference_date, target_end_date, output_type_id, value) |>
    group_by(reference_date, target_end_date, output_type_id) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(
      names_from = output_type_id,
      values_from = value,
      names_prefix = "q"
    )

  # Get date range for plot
  min_date <- min(forecasts_wide$target_end_date) - 56  # 8 weeks before first forecast
  max_date <- max(forecasts_wide$target_end_date) + 7

  # Filter target data to relevant date range
  loc_targets_filtered <- loc_targets |>
    filter(target_end_date >= min_date, target_end_date <= max_date)

  # Create plot
  p <- ggplot() +
    # Historical observations
    geom_line(
      data = loc_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      linewidth = 0.8
    ) +
    geom_point(
      data = loc_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      size = 1.5
    )

  # Add forecast ribbons if we have the quantiles
  if ("q0.025" %in% names(forecasts_wide) && "q0.975" %in% names(forecasts_wide)) {
    p <- p +
      geom_ribbon(
        data = forecasts_wide,
        aes(x = target_end_date, ymin = q0.025, ymax = q0.975, group = reference_date),
        fill = "steelblue",
        alpha = 0.2
      )
  }

  if ("q0.25" %in% names(forecasts_wide) && "q0.75" %in% names(forecasts_wide)) {
    p <- p +
      geom_ribbon(
        data = forecasts_wide,
        aes(x = target_end_date, ymin = q0.25, ymax = q0.75, group = reference_date),
        fill = "steelblue",
        alpha = 0.3
      )
  }

  # Add median line
  if ("q0.5" %in% names(forecasts_wide)) {
    p <- p +
      geom_line(
        data = forecasts_wide,
        aes(x = target_end_date, y = q0.5, group = reference_date),
        color = "steelblue",
        linewidth = 1
      ) +
      geom_point(
        data = forecasts_wide,
        aes(x = target_end_date, y = q0.5),
        color = "steelblue",
        size = 2
      )
  }

  # Add vertical lines for reference dates
  ref_dates <- unique(forecasts_wide$reference_date)
  p <- p +
    geom_vline(
      xintercept = as.numeric(ref_dates),
      linetype = "dashed",
      color = "gray50",
      alpha = 0.5
    )

  # Finalize plot
  p <- p +
    labs(
      title = sprintf("Forecasts for %s", display_name),
      subtitle = sprintf("Target: %s", target_type),
      x = "Date",
      y = target_type,
      caption = sprintf("Model: UMass-gbqr_3src | Reference dates: %s",
                       paste(format(ref_dates, "%Y-%m-%d"), collapse = ", "))
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 10, color = "gray40"),
      plot.caption = element_text(size = 8, color = "gray50"),
      axis.text.x = element_text(angle = 45, hjust = 1)
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "1 week")

  return(p)
}

# Generate plots for all locations
cat("\nGenerating plots...\n")

# Create list to store all plots for PDF
all_plots <- list()

for (loc in forecast_locations) {
  cat(sprintf("  Plotting %s...\n", loc))

  p <- plot_location_forecast(loc, forecasts, target_data, locations)

  if (!is.null(p)) {
    # Store plot for PDF
    all_plots[[loc]] <- p
  }
}

# Create multi-page PDF with all forecasts
cat("\nGenerating multi-page PDF...\n")
pdf_file <- file.path(output_dir, "all_forecasts.pdf")
pdf(pdf_file, width = 12, height = 6)
for (loc in names(all_plots)) {
  print(all_plots[[loc]])
}
dev.off()
cat(sprintf("  Saved PDF: %s\n", pdf_file))

# Create a summary plot with multiple locations
cat("\nGenerating summary plot...\n")

# Select a few representative locations (states)
summary_locations <- c("colorado", "massachusetts", "texas", "minnesota", "georgia", "nyc")
summary_locations <- summary_locations[summary_locations %in% forecast_locations]

if (length(summary_locations) > 0) {
  # Create faceted plot
  summary_forecasts <- forecasts |>
    filter(location %in% summary_locations) |>
    select(location, reference_date, target_end_date, output_type_id, value, target) |>
    group_by(location, reference_date, target_end_date, output_type_id, target) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(
      names_from = output_type_id,
      values_from = value,
      names_prefix = "q"
    ) |>
    left_join(
      locations |> select(location, location_name),
      by = "location"
    ) |>
    mutate(location_name = coalesce(location_name, location))

  summary_targets <- target_data |>
    filter(location %in% summary_locations) |>
    left_join(
      locations |> select(location, location_name),
      by = "location"
    ) |>
    mutate(location_name = coalesce(location_name, location))

  # Get date range
  min_date <- min(summary_forecasts$target_end_date) - 56
  max_date <- max(summary_forecasts$target_end_date) + 7

  summary_targets_filtered <- summary_targets |>
    filter(target_end_date >= min_date, target_end_date <= max_date)

  p_summary <- ggplot() +
    geom_line(
      data = summary_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      linewidth = 0.6
    ) +
    geom_point(
      data = summary_targets_filtered,
      aes(x = target_end_date, y = observation),
      color = "black",
      size = 1
    )

  if ("q0.025" %in% names(summary_forecasts) && "q0.975" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_ribbon(
        data = summary_forecasts,
        aes(x = target_end_date, ymin = q0.025, ymax = q0.975, group = reference_date),
        fill = "steelblue",
        alpha = 0.2
      )
  }

  if ("q0.25" %in% names(summary_forecasts) && "q0.75" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_ribbon(
        data = summary_forecasts,
        aes(x = target_end_date, ymin = q0.25, ymax = q0.75, group = reference_date),
        fill = "steelblue",
        alpha = 0.3
      )
  }

  if ("q0.5" %in% names(summary_forecasts)) {
    p_summary <- p_summary +
      geom_line(
        data = summary_forecasts,
        aes(x = target_end_date, y = q0.5, group = reference_date),
        color = "steelblue",
        linewidth = 0.8
      )
  }

  p_summary <- p_summary +
    facet_wrap(~location_name, scales = "free_y", ncol = 2) +
    labs(
      title = "Flu/ILI ED Visits Forecasts - Selected Locations",
      subtitle = "UMass-gbqr_3src Model",
      x = "Date",
      y = "ED visits (%)",
      caption = "Black: observations | Blue: forecasts with 50% and 95% prediction intervals"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      strip.text = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 8)
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "2 weeks")

}

# Create state-grouped PDF (state + HSAs per page)
cat("\nGenerating state-grouped PDF...\n")

# Get state groupings from locations data
state_groups <- locations |>
  filter(location %in% forecast_locations) |>
  select(location, state, state_abb, location_name, original_location_code) |>
  arrange(state, desc(original_location_code == "All"), location_name)

# Get unique states
states <- unique(state_groups$state)
cat(sprintf("  Found %d states\n", length(states)))

# Function to create state-grouped plot
plot_state_group <- function(state_name, forecasts_df, target_df, locations_df) {

  # Get locations for this state
  state_locs <- locations_df |>
    filter(state == state_name, location %in% unique(forecasts_df$location)) |>
    select(location, state, state_abb, location_name, original_location_code) |>
    arrange(desc(original_location_code == "All"), location_name)

  if (nrow(state_locs) == 0) {
    return(NULL)
  }

  loc_list <- state_locs$location

  # Prepare forecast data for these locations
  state_forecasts <- forecasts_df |>
    filter(location %in% loc_list) |>
    select(location, reference_date, target_end_date, output_type_id, value, target) |>
    group_by(location, reference_date, target_end_date, output_type_id, target) |>
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(
      names_from = output_type_id,
      values_from = value,
      names_prefix = "q"
    ) |>
    left_join(
      state_locs |> select(location, location_name),
      by = "location"
    ) |>
    mutate(
      location_name = coalesce(location_name, location),
      # Put state-level first by using a sort key
      sort_key = ifelse(location == tolower(state_name), 0, 1),
      location_name = factor(location_name, levels = state_locs$location_name)
    )

  # Prepare target data for these locations
  state_targets <- target_df |>
    filter(location %in% loc_list) |>
    left_join(
      state_locs |> select(location, location_name),
      by = "location"
    ) |>
    mutate(
      location_name = coalesce(location_name, location),
      location_name = factor(location_name, levels = state_locs$location_name)
    )

  # Get date range
  min_date <- min(state_forecasts$target_end_date) - 56
  max_date <- max(state_forecasts$target_end_date) + 7

  state_targets_filtered <- state_targets |>
    filter(target_end_date >= min_date, target_end_date <= max_date)

  # Determine grid layout based on number of locations
  n_locs <- length(loc_list)
  ncol <- if (n_locs <= 2) 1 else if (n_locs <= 6) 2 else 3

  # Create faceted plot
  p <- ggplot() +
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

  if ("q0.025" %in% names(state_forecasts) && "q0.975" %in% names(state_forecasts)) {
    p <- p +
      geom_ribbon(
        data = state_forecasts,
        aes(x = target_end_date, ymin = q0.025, ymax = q0.975, group = reference_date),
        fill = "steelblue",
        alpha = 0.2
      )
  }

  if ("q0.25" %in% names(state_forecasts) && "q0.75" %in% names(state_forecasts)) {
    p <- p +
      geom_ribbon(
        data = state_forecasts,
        aes(x = target_end_date, ymin = q0.25, ymax = q0.75, group = reference_date),
        fill = "steelblue",
        alpha = 0.3
      )
  }

  if ("q0.5" %in% names(state_forecasts)) {
    p <- p +
      geom_line(
        data = state_forecasts,
        aes(x = target_end_date, y = q0.5, group = reference_date),
        color = "steelblue",
        linewidth = 0.8
      )
  }

  # Get state abbreviation
  state_abb <- locations_df |>
    filter(state == state_name) |>
    pull(state_abb) |>
    unique() |>
    first()

  p <- p +
    facet_wrap(~location_name, scales = "free_y", ncol = ncol) +
    labs(
      title = sprintf("%s (%s) - Flu/ILI ED Visits Forecasts", state_name, state_abb),
      subtitle = sprintf("UMass-gbqr_3src Model | %d locations", n_locs),
      x = "Date",
      y = "ED visits (%)",
      caption = "Black: observations | Blue: forecasts with 50% and 95% prediction intervals"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      strip.text = element_text(face = "bold", size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      axis.text.y = element_text(size = 7)
    ) +
    scale_x_date(date_labels = "%b %d", date_breaks = "2 weeks")

  return(list(plot = p, n_locs = n_locs))
}

# Generate state-grouped PDF
state_pdf_file <- file.path(output_dir, "forecasts_by_state.pdf")
pdf(state_pdf_file, width = 14, height = 10)

for (state_name in states) {
  cat(sprintf("  Plotting %s...\n", state_name))

  result <- plot_state_group(state_name, forecasts, target_data, locations)

  if (!is.null(result)) {
    print(result$plot)
  }
}

dev.off()
cat(sprintf("  Saved state-grouped PDF: %s\n", state_pdf_file))

cat(sprintf("\nPlots saved to: %s\n", output_dir))
cat("Done!\n")
