# ==============================================================================
# 0. LOAD LIBRARIES AND SETUP ----
# ==============================================================================

system("pip install git+https://github.com/podaac/data-subscriber.git")
system("touch ~/.netrc")
system("chmod 0600 ~/.netrc")
writeLines(c(
  "machine urs.earthdata.nasa.gov",
  "login tuturbaba",
  "password yA-je4ivFc%wxN,"
), "~/.netrc")
system("conda install -y r-terra r-sf r-ncdf4 r-R.utils")

options(timeout = 3600)

# ==============================================================================
# 1. PARAMETERS AND INPUT LOADING ----
# ==============================================================================

json_data <- fromJSON("galaxy_inputs/galaxy_inputs.json")

date       <- "2024-07-15"
date_ano   <- "2024-07"

# ==============================================================================

# Directories and bounding box
output_dir <- "./raw_data"
raster_output_dir <- "./processed_data"
bounding_box <- "-180,-90,180,-45"

if (!dir.exists(output_dir)) dir.create(output_dir)
if (!dir.exists(raster_output_dir)) dir.create(raster_output_dir)

# Parse user date input and return start/end date and type
parse_user_input <- function(input_date) {
  if (grepl("^\\d{4}-\\d{2}-\\d{2}$", input_date)) {
    start_date <- paste0(input_date, "T00:00:00Z")
    end_date <- paste0(input_date, "T00:00:00Z")
    type <- "day"
  } else if (grepl("^\\d{4}-\\d{2}$", input_date)) {
    year <- as.integer(substr(input_date, 1, 4))
    month <- as.integer(substr(input_date, 6, 7))
    start_date <- sprintf("%d-%02d-01T00:00:00Z", year, month)
    end_date <- format(as.Date(paste(year, month, "01", sep = "-")) + months(1) - days(1), "%Y-%m-%dT00:00:00Z")
    type <- "month"
  } 
  return(list(start = start_date, end = end_date, type = type))
}

# Download data using podaac-data-downloader
download_data <- function(start_date, end_date) {
  cmd <- sprintf("podaac-data-downloader -c MUR-JPL-L4-GLOB-v4.1 -d %s --start-date %s --end-date %s -b%s",
                 output_dir, start_date, end_date, bounding_box)
  system(cmd)
}

# Process NetCDF files and compute mean raster
config_nc <- function(start_date, end_date) {
  file_list <- list.files(path = output_dir, pattern = "\\.nc$", full.names = TRUE)
  if (length(file_list) == 0) {
    message("No .nc files found.")
    return(NULL)
  }

  cumulative_raster <- NULL
  file_count <- 0

  for (i in seq_along(file_list)) {
    file <- file_list[i]
    cat(sprintf("Processing file %d / %d : %s\n", i, length(file_list), basename(file)))
    nc_file <- nc_open(file)
    
    lat_vals <- ncvar_get(nc_file, "lat")
    lon_vals <- ncvar_get(nc_file, "lon")
    lat_indices <- which(lat_vals >= -90 & lat_vals <= -45)
    
    sst_raw <- ncvar_get(nc_file, "analysed_sst",
                         start = c(1, min(lat_indices), 1),
                         count = c(length(lon_vals), length(lat_indices), 1))
    
    sst_scaled <- sst_raw[, ncol(sst_raw):1]
    
    r <- rast(nrows = length(lat_indices),
              ncols = length(lon_vals),
              xmin = min(lon_vals),
              xmax = max(lon_vals),
              ymin = min(lat_vals[lat_indices]),
              ymax = max(lat_vals[lat_indices]),
              crs = "EPSG:4326")
    
    values(r) <- as.vector(sst_scaled)
    nc_close(nc_file)
    
    cumulative_raster <- if (is.null(cumulative_raster)) r else cumulative_raster + r
    file_count <- file_count + 1
  }
  
  return(cumulative_raster / file_count)
}

# ==============================================================================
# MAIN SCRIPT ----
# ==============================================================================

parsed <- parse_user_input(date)
start_date <- parsed$start
end_date <- parsed$end
type <- parsed$type

message(sprintf("Downloading data from %s to %s...", start_date, end_date))
download_data(start_date, end_date)

message("Processing NetCDF files...")
raster_result <- config_nc(start_date, end_date)

if (!is.null(raster_result)) {
  filename <- if (type == "day") {
    paste0(raster_output_dir, "/raster_", gsub("-", "", substr(start_date, 1, 10)), ".tif")
  } else {
    paste0(raster_output_dir, "/raster_mean_", substr(start_date, 1, 7), ".tif")
  }
  writeRaster(raster_result, filename = filename, overwrite = TRUE)
  message(sprintf("Raster saved: %s", filename))
}

# Compute mean raster from all available .tif files
tif_files <- list.files(path = raster_output_dir, pattern = "\\.tif$", full.names = TRUE)
if (length(tif_files) > 0) {
  message("Computing mean over all available raster files")
  tif_stack <- rast(tif_files)
  mean_tif <- mean(tif_stack)
  plot(mean_tif)
  writeRaster(mean_tif, "mean.tif", overwrite = TRUE)
  message("Final raster saved")
}
r <- rast("mean.tif")
r_project <- project(r, "EPSG:6932")
