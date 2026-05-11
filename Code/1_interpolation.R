####################
### LOAD DATASET ###
####################

# Load the imputed air pollution time series dataset
# The object should contain:
# - Daily observations
# - Monitoring station coordinates
# - Pollutant concentrations
# - A date column
load("results/imputed_series.RData")

# Load municipality coordinates where interpolation will be performed
interpol <- read_excel("data/municipalidades.xlsx")

# Separate coordinate string into latitude and longitude columns
interpol <- interpol %>%
  separate(municipalidad, into = c("lat", "long"), sep = ",") %>%
  mutate(
    lat = as.numeric(lat),
    long = as.numeric(long)
  )

# Convert to sf spatial object using geographic coordinates
interpol <- st_as_sf(interpol, coords = c("long", "lat"), crs = 4326)

# Transform coordinates to UTM projection for spatial interpolation
interpol <- st_transform(interpol, crs = 32719)

######################################
### SPATIAL INTERPOLATION FUNCTION ###
######################################

interpolate_spatial <- function(
    data_sf,
    newdata_sf,
    date_var = "date",
    comuna_var = "comuna",
    pollutant = "no2",
    variable = "daily_no2",
    method = c("idw", "ok"),
    idw_power = 2,
    idw_nmax = 5,
    idw_maxdist = 15000,
    ok_nmin   = 3,
    conf_level = 0.95
) {
  
  # Match selected interpolation methods
  method <- match.arg(method, several.ok = TRUE)
  
  # Unique interpolation dates
  unique_dates <- unique(data_sf[[date_var]])
  
  # Store daily interpolation outputs
  results_list <- list()
  
  # Interpolation formula
  formula_interp <- as.formula(paste(variable, "~ 1"))
  
  # Iterate over each date
  for (current_date in unique_dates) {
    
    # Subset available observations for current day
    day_data <- data_sf[
      data_sf[[date_var]] == current_date &
        !is.na(data_sf[[variable]]), ]
    
    # Skip interpolation if there are too few observations
    if (nrow(day_data) < ok_nmin) next
    
    # Create daily prediction object
    daily_sf <- newdata_sf
    
    ###################
    ### IDW METHOD ###
    ###################
    
    if ("idw" %in% method) {
      
      # Define IDW interpolation model
      idw_model <- gstat(
        formula = formula_interp,
        locations = day_data,
        nmax = idw_nmax,
        maxdist = idw_maxdist,
        set = list(idp = idw_power)
      )
      
      # Predict concentrations at interpolation locations
      idw_pred <- predict(idw_model, newdata_sf)
      
      # Store predictions
      daily_sf[[paste0(pollutant, "_idw_pred")]] <-
        idw_pred$var1.pred
    }
    
    #################
    ### OK METHOD ###
    #################
    
    if ("ok" %in% method) {
      
      # Convert sf object to sp object
      day_data_sp <- as(day_data, "Spatial")
      
      # Automatically fit variogram model
      variogram_fit <- autofitVariogram(
        formula_interp,
        day_data_sp,
        verbose = FALSE
      )
      
      # Perform Ordinary Kriging interpolation
      ok_pred <- krige(
        formula_interp,
        locations = day_data,
        newdata   = newdata_sf,
        model     = variogram_fit$var_model
      )
      
      # Compute z-score for confidence intervals
      z_value <- qnorm(1 - (1 - conf_level) / 2)
      
      # Store kriging predictions and variances
      daily_sf[[paste0(pollutant, "_ok_pred")]] <- ok_pred$var1.pred
      daily_sf[[paste0(pollutant, "_ok_var")]]  <- ok_pred$var1.var
      
      # Lower confidence interval
      daily_sf[[paste0(pollutant, "_ok_lci")]] <-
        ok_pred$var1.pred - z_value * sqrt(ok_pred$var1.var)
      
      # Upper confidence interval
      daily_sf[[paste0(pollutant, "_ok_uci")]] <-
        ok_pred$var1.pred + z_value * sqrt(ok_pred$var1.var)
    }
    
    # Add current date to output
    daily_sf[[date_var]] <- current_date
    
    # Store daily interpolation result
    results_list[[as.character(current_date)]] <- daily_sf
  }
  
  # Merge all daily interpolations
  final_sf <- do.call(rbind, results_list)
  
  rownames(final_sf) <- NULL
  
  # Keep relevant output columns
  final_sf <- final_sf |>
    dplyr::select(
      !!date_var,
      !!comuna_var,
      dplyr::ends_with("idw_pred"),
      dplyr::ends_with("ok_pred"),
      dplyr::ends_with("ok_var"),
      dplyr::ends_with("ok_lci"),
      dplyr::ends_with("ok_uci"),
      geometry
    )
  
  return(final_sf)
}

#############################
### INTERPOLATION BY YEAR ###
#############################

# Create temporary directory for yearly outputs
dir.create("results/interpolation_temp", showWarnings = FALSE)

interp_save_year <- function(data, pollutant, variable){
  
  # Extract available years
  years <- sort(unique(year(data$date)))
  
  # Iterate over years
  for(y in years){
    
    message("Interpolating year ", y, " (", pollutant, ")")
    
    # Subset yearly data
    data_year <- data %>%
      filter(year(date) == y)
    
    # Run spatial interpolation
    res <- interpolate_spatial(
      data_sf    = data_year,
      newdata_sf = interpol,
      date_var   = "date",
      pollutant  = pollutant,
      variable   = variable,
      method     = c("idw","ok")
    )
    
    # Save yearly interpolation result
    save(
      res,
      file = paste0("results/interpolation_temp/", pollutant, "_", y, ".RData")
    )
    
    # Free memory
    rm(res)
    
    gc()
  }
}

##########################
### RUN INTERPOLATIONS ###
##########################

# Arguments that can be customized inside interpolate_spatial():
#
# data_sf      -> Input monitoring station dataset
# newdata_sf   -> Spatial locations where predictions are generated
# date_var     -> Name of the date column
# comuna_var   -> Name of the municipality/location column
# pollutant    -> Pollutant label used in output column names
# variable     -> Pollutant concentration variable to interpolate
#
# method       -> Interpolation method:
#                 "idw" = Inverse Distance Weighting
#                 "ok"  = Ordinary Kriging
#                 Both methods can be used simultaneously
#
# idw_power    -> IDW distance decay parameter
# idw_nmax     -> Maximum number of neighboring stations used in IDW
# idw_maxdist  -> Maximum interpolation distance for IDW (in meters)
#
# ok_nmin      -> Minimum number of observations required for kriging
# conf_level   -> Confidence interval level for kriging predictions

interp_save_year(imputed_series, "no2",  "daily_no2")
interp_save_year(imputed_series, "pm25", "daily_pm25")
interp_save_year(imputed_series, "o3",   "daily_o3")

#############################
### REBUILD FINAL DATASET ###
#############################

# List all generated interpolation files
files <- list.files(
  "results/interpolation_temp",
  pattern = "\\.RData$",
  full.names = TRUE
)

#####################
### LOAD FUNCTION ###
#####################

load_interp <- function(f){
  
  # Load interpolation object
  load(f)
  
  # Remove geometry for merging
  out <- res %>%
    st_drop_geometry()
  
  rm(res)
  
  return(out)
}

##########################
### SPLIT BY POLLUTANT ###
##########################

files_no2  <- files[grepl("no2_", files)]
files_pm25 <- files[grepl("pm25_", files)]
files_o3   <- files[grepl("o3_", files)]

################################
### MERGE FILES BY POLLUTANT ###
################################

no2  <- bind_rows(lapply(files_no2, load_interp))
pm25 <- bind_rows(lapply(files_pm25, load_interp))
o3   <- bind_rows(lapply(files_o3, load_interp))

########################
### MERGE POLLUTANTS ###
########################

interp_all <- no2 %>%
  full_join(pm25, by = c("date","comuna")) %>%
  full_join(o3, by = c("date","comuna"))

#########################
### ADD GEOMETRY BACK ###
#########################

interp_all <- interpol %>%
  select(comuna, geometry) %>%
  right_join(interp_all, by = "comuna") %>%
  st_as_sf()

#################
### SORT DATA ###
#################

interp_all <- interp_all %>%
  arrange(comuna, date)

# Ensure date format consistency
interp_all <- interp_all %>%
  mutate(date = as.Date(date, origin = "1970-01-01"))

#########################
### SAVE FINAL OUTPUT ###
#########################

save(
  interp_all,
  file = "results/interpolated_series.RData"
)
