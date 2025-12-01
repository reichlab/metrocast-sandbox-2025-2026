library(dplyr)
library(hubData)

args <- commandArgs(trailingOnly = TRUE)
ref_date <- as.Date(args[1])

locations <- read.csv("https://raw.githubusercontent.com/reichlab/flu-metrocast/refs/heads/main/auxiliary-data/locations.csv")
fips_mappings <- readr::read_csv("https://infectious-disease-data.s3.amazonaws.com/data-raw/fips-mappings/fips_mappings.csv") |>
  dplyr::rename(fips_code = "location", state_name = "location_name")
locations_meta <- locations |>
  dplyr::left_join(
    fips_mappings,
    by = c("state_abb" = "abbreviation", "state" = "state_name")
  ) |>
  dplyr::mutate(
    agg_level = ifelse(original_location_code == "All", "state", "hsa"),
    loc_code = ifelse(agg_level == "state", fips_code, original_location_code)
  )

# load components
model_id <- "UMass-AR6_thetaP"
outputs_path <- "intermediate-output/model-output/"
state_outputs <- read.csv(paste0(outputs_path, model_id, "_state/", ref_date, "-", model_id, "_state.csv")) |>
  dplyr::mutate(agg_level = "state", location = sprintf("%02g", location))
hsa_outputs <- read.csv(paste0(outputs_path, model_id, "_hsa/", ref_date, "-", model_id, "_hsa.csv")) |>
  dplyr::mutate(agg_level = "hsa", location = as.character(location))

# load components, bind, and rename locations
model_outputs <- state_outputs |>
  dplyr::bind_rows(hsa_outputs) |>
  dplyr::rename(loc_code = location) |>
#  dplyr::filter(reference_date == ref_date, horizon >= 0) |>
  dplyr::left_join(locations_meta, by = c("loc_code", "agg_level")) |>
  dplyr::mutate(target = "Flu ED visits pct", value = value * 100) |> # prop -> pct
  dplyr::select("reference_date", "location", "horizon", "target", "target_end_date", "output_type", "output_type_id", "value")

# save
reference_date <- model_outputs$reference_date[1]

output_dir <- paste0("../../model-output/", model_id)
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

utils::write.csv(
  model_outputs,
  file = file.path(
    output_dir,
    paste0(reference_date, "-", model_id, ".csv")
  ),
  row.names = FALSE
)
