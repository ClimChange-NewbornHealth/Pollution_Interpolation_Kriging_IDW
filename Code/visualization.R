#################
### LIBRARIES ###
#################

# Data import/export
library(rio)

# Data manipulation and visualization
library(tidyverse)

# Data cleaning
library(janitor)

# Spatial vector data handling
library(sf)

# Plotting system
library(ggplot2)

# Multi-panel figure arrangement
library(gridExtra)

# Color palettes
library(viridisLite)
library(RColorBrewer)

# GIF generation
library(gifski)

# PNG image handling
library(png)

# Scaling utilities
library(scales)

####################
### LOAD DATASET ###
####################

# Load interpolated municipality-level air pollution dataset
# The object should contain:
# - Daily interpolation outputs
# - Municipality identifiers
# - IDW predictions
# - Ordinary Kriging predictions
# - Kriging variances
# - Confidence intervals
# - Geometry column
load("results/interpolated_series.RData")

########################
### LOAD SHAPEFILE ###
########################

# Load municipality shapefile object
# The object should contain:
# - Municipality polygons
# - Municipality names
# - The same coordinate reference system (EPSG)
#   as the interpolated dataset
load("results/municipalities_shape.RData")

###################################
### INTERPOLATION PLOT FUNCTION ###
###################################

graficar_interpolacion <- function(
    data,
    contaminante = "PM25",
    variable = NULL,
    fecha = "2015-12-20",
    comunas = comunas_santiago,
    color_scale = "viridis",
    mostrar_ejes = FALSE,
    limites = NULL,
    guardar = FALSE,
    ruta_guardado = "outputs/mapas/",
    nombre_archivo = NULL
) {
  
  # Remove geometry if input is sf object
  if (inherits(data, "sf")) {
    data <- data %>% st_drop_geometry()
  }
  
  # Standardize pollutant name
  contaminante <- toupper(contaminante)
  
  # Automatically define prediction variable
  if (is.null(variable)) {
    
    variable <- switch(
      contaminante,
      "PM25" = "pm25_ok_pred",
      "O3"   = "o3_ok_pred",
      "NO2"  = "no2_ok_pred",
      stop("Unknown pollutant")
    )
  }
  
  # Filter selected interpolation date
  data_filtered <- data %>%
    filter(date == fecha) %>%
    select(comuna, all_of(variable))
  
  names(data_filtered)[2] <- "valor"
  
  # Merge predictions with municipality polygons
  data_comunas <- comunas %>%
    left_join(data_filtered, by = "comuna")
  
  # Plot titles and legend labels
  if (contaminante == "PM25") {
    
    title <- expression("Atmospheric Concentration of PM"[2.5])
    
    legend_name <- expression(
      "PM"[2.5] * " (" * mu * "g/m³)"
    )
    
  } else if (contaminante == "O3") {
    
    title <- expression("Atmospheric Concentration of O"[3])
    
    legend_name <- "O3 concentration (ppb)"
    
  } else if (contaminante == "NO2") {
    
    title <- expression("Atmospheric Concentration of NO"[2])
    
    legend_name <- "NO2 concentration (ppb)"
  }
  
  # Color scale selection
  color_scale_used <- switch(
    
    tolower(color_scale),
    
    viridis = scale_fill_gradientn(
      name = legend_name,
      colors = viridisLite::viridis(9),
      limits = limites,
      oob = scales::squish
    ),
    
    blues = scale_fill_gradientn(
      name = legend_name,
      colors = RColorBrewer::brewer.pal(9, "Blues"),
      limits = limites,
      oob = scales::squish
    ),
    
    reds = scale_fill_gradientn(
      name = legend_name,
      colors = RColorBrewer::brewer.pal(9, "Reds"),
      limits = limites,
      oob = scales::squish
    ),
    
    stop("Unknown color scale")
  )
  
  # Base figure theme
  base_theme <- theme_minimal() +
    theme(
      legend.position = "bottom",
      legend.title = element_text(size = 9),
      legend.text = element_text(size = 7),
      
      plot.title = element_text(
        hjust = 0.5,
        face = "bold",
        size = 16
      ),
      
      plot.subtitle = element_text(
        hjust = 0.5,
        face = "bold",
        size = 12
      )
    )
  
  # Remove axes if requested
  if (!mostrar_ejes) {
    
    base_theme <- base_theme +
      theme(
        axis.text = element_blank(),
        axis.title = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank()
      )
  }
  
  # Generate interpolation figure
  plot <- ggplot() +
    
    geom_sf(
      data = data_comunas,
      aes(fill = valor),
      color = "black"
    ) +
    
    color_scale_used +
    
    ggtitle(title) +
    
    labs(subtitle = fecha) +
    
    base_theme
  
  # Save figure if requested
  if (guardar) {
    
    dir.create(
      ruta_guardado,
      showWarnings = FALSE,
      recursive = TRUE
    )
    
    if (is.null(nombre_archivo)) {
      
      nombre_archivo <- paste0(
        tolower(contaminante),
        "_",
        fecha,
        ".png"
      )
    }
    
    ruta_completa <- file.path(
      ruta_guardado,
      nombre_archivo
    )
    
    ggsave(
      filename = ruta_completa,
      plot = plot,
      width = 6,
      height = 6,
      units = "in",
      dpi = 300
    )
    
    message("File saved at: ", ruta_completa)
  }
  
  return(plot)
}

###########################################
### INTERPOLATION ANIMATED GIF FUNCTION ###
###########################################

gif_interpolacion <- function(
    data,
    contaminante = "PM25",
    variable = NULL,
    fecha_inicio,
    fecha_fin,
    comunas = comunas_santiago,
    color_scale = "viridis",
    mostrar_ejes = FALSE,
    output = "outputs/animacion.gif",
    fps = 2
) {
  
  # Standardize pollutant name
  contaminante <- toupper(contaminante)
  
  # Automatically define prediction variable
  if (is.null(variable)) {
  
  variable <- switch(
    contaminante,
    "PM25" = "pm25_ok_pred",
    "O3"   = "o3_ok_pred",
    "NO2"  = "no2_ok_pred",
    stop("Contaminante no reconocido")
  )
}

  # Define date sequence
  fechas <- seq(
    as.Date(fecha_inicio),
    as.Date(fecha_fin),
    by = "day"
  )
  
  # Filter selected period
  data_rango <- data %>%
    filter(date %in% fechas)
  
  # Global color scale limits
  limites <- range(
    data_rango[[variable]],
    na.rm = TRUE
  )
  
  message(
    "Global scale: ",
    round(limites[1], 2),
    " - ",
    round(limites[2], 2)
  )
  
  # Create temporary directory for frames
  dir.create(
    "temp_frames",
    showWarnings = FALSE
  )
  
  archivos <- c()
  
  # Generate frame for each date
  for (i in seq_along(fechas)) {
    
    fecha_i <- fechas[i]
    
    p <- graficar_interpolacion(
      data = data,
      contaminante = contaminante,
      variable = variable,
      fecha = as.character(fecha_i),
      comunas = comunas,
      color_scale = color_scale,
      mostrar_ejes = mostrar_ejes,
      limites = limites
    )
    
    archivo <- paste0(
      "temp_frames/frame_",
      sprintf("%03d", i),
      ".png"
    )
    
    ggsave(
      archivo,
      plot = p,
      width = 6,
      height = 6,
      dpi = 300
    )
    
    archivos <- c(archivos, archivo)
  }
  
  # Generate animated GIF
  gifski(
    png_files = archivos,
    gif_file = output,
    width = 1200,
    height = 1200,
    delay = 1 / fps
  )
  
  message("GIF saved at: ", output)
}

#########################
### GENERATE FIGURES ###
#########################

# Arguments that can be customized inside graficar_interpolacion():
#
# data             -> Interpolated dataset
# contaminante     -> Pollutant to visualize ("PM25", "O3", "NO2")
# variable         -> Prediction variable to plot
# fecha            -> Date to visualize
# comunas          -> Municipality shapefile object
# color_scale      -> Color palette ("viridis", "blues", "reds")
# mostrar_ejes     -> Logical; display axes and coordinates
# limites          -> Numeric vector defining color scale limits
# guardar          -> Logical; save figure to disk
# ruta_guardado    -> Output directory for saved figures
# nombre_archivo   -> Output figure filename

# PM2.5 interpolation map
graficar_interpolacion(
  data = interp_all,
  contaminante = "PM25",
  variable = "pm25_ok_pred",
  fecha = "2019-07-02",
  comunas = comunas_santiago,
  mostrar_ejes = FALSE,
  color_scale = "blues",
  guardar = TRUE,
  ruta_guardado = "outputs",
  nombre_archivo = "pm25_2019-07-02.png"
)

# O3 interpolation map
graficar_interpolacion(
  data = interp_all,
  contaminante = "O3",
  variable = "o3_ok_pred",
  fecha = "2019-07-02",
  comunas = comunas_santiago,
  mostrar_ejes = FALSE,
  color_scale = "reds",
  guardar = TRUE,
  ruta_guardado = "outputs",
  nombre_archivo = "o3_2019-07-02.png"
)

# NO2 interpolation map
graficar_interpolacion(
  data = interp_all,
  contaminante = "NO2",
  variable = "no2_ok_pred",
  fecha = "2019-07-02",
  comunas = comunas_santiago,
  mostrar_ejes = FALSE,
  color_scale = "viridis",
  guardar = TRUE,
  ruta_guardado = "outputs",
  nombre_archivo = "no2_2019-07-02.png"
)

######################
### GENERATE GIFS ###
######################

# Arguments that can be customized inside gif_interpolacion():
#
# data             -> Interpolated dataset
# contaminante     -> Pollutant to visualize ("PM25", "O3", "NO2")
# variable         -> Prediction variable to animate
# fecha_inicio     -> Initial date of animation
# fecha_fin        -> Final date of animation
# comunas          -> Municipality shapefile object
# color_scale      -> Color palette ("viridis", "blues", "reds")
# mostrar_ejes     -> Logical; display axes and coordinates
# output           -> Output GIF filename
# fps              -> Animation speed (frames per second); integer or decimal values

# PM2.5 animated interpolation
gif_interpolacion(
  data = interp_all,
  contaminante = "PM25",
  variable = "pm25_ok_pred",
  fecha_inicio = "2020-12-01",
  fecha_fin = "2020-12-31",
  comunas = comunas_santiago,
  color_scale = "blues",
  mostrar_ejes = FALSE,
  fps = 1,
  output = "outputs/pm25_anim.gif"
)

# O3 animated interpolation
gif_interpolacion(
  data = interp_all,
  contaminante = "O3",
  variable = "o3_ok_pred",
  fecha_inicio = "2020-12-01",
  fecha_fin = "2020-12-31",
  comunas = comunas_santiago,
  color_scale = "reds",
  mostrar_ejes = FALSE,
  fps = 1,
  output = "outputs/o3_anim.gif"
)

# NO2 animated interpolation
gif_interpolacion(
  data = interp_all,
  contaminante = "NO2",
  variable = "no2_ok_pred",
  fecha_inicio = "2020-12-01",
  fecha_fin = "2020-12-31",
  comunas = comunas_santiago,
  color_scale = "viridis",
  mostrar_ejes = FALSE,
  fps = 1,
  output = "outputs/no2_anim.gif"
)
