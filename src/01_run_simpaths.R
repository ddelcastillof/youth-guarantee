#!/usr/bin/env Rscript

library(data.table)
library(withr)

scenario        <- Sys.getenv("SCENARIO")
first_year      <- Sys.getenv("FIRST_YEAR") |> as.numeric()
last_year       <- Sys.getenv("LAST_YEAR") |> as.numeric()
population      <- Sys.getenv("POPULATION") |> as.numeric()
starting_seed   <- Sys.getenv("STARTING_SEED") |> as.numeric()
runs_per_batch  <- Sys.getenv("RUNS_PER_BATCH") |> as.numeric()
batches         <- Sys.getenv("BATCHES") |> as.numeric()
simpaths_path   <- Sys.getenv("SIMPATHS_PATH")

results_root_path <- here::here("data", "simpaths_output")

simpaths_input_path <- file.path(simpaths_path, "input")

timestamp(suffix = paste(" - Started scenario", scenario))

# Delete files that should be recreated during the setup process
file.remove(file.path(simpaths_input_path, "input.mv.db"))

# Store existing output directories before running the simulation, so we can keep track of which ones are new
output_dirs_before <- list.files(file.path(simpaths_path, "output"), full.names = TRUE)

print("Running SimPaths setup")

with_dir(simpaths_path, sys::exec_wait("java", c(
  "-jar", "multirun.jar",
  "-s", format(first_year),
  "-g", "false",
  "-DBSetup"
)))

for (batch in 1:batches) {
  print(paste("Running SimPaths simulation, batch", batch, "of", batches))
  batch_seed <- starting_seed + (batch - 1) * runs_per_batch
  with_dir(simpaths_path, sys::exec_wait("java", c(
    "-jar", "multirun.jar",
    "-r", format(batch_seed),
    "-p", format(population, scientific = FALSE),
    "-n", format(runs_per_batch, scientific = FALSE),
    "-s", format(first_year),
    "-e", format(last_year),
    "-g", "false"
  )))
}

# Identify the new output directories and store their paths for later use
output_dirs_after <- list.files(file.path(simpaths_path, "output"), full.names = TRUE)
new_output_dirs <- setdiff(output_dirs_after, output_dirs_before)
# Don't include "logs" directory (if there is one)
new_output_dirs <- grep(pattern = "logs$", x = new_output_dirs, invert = TRUE, value = TRUE)

results_path <- file.path(results_root_path, scenario)
if (!dir.exists(results_path)) dir.create(results_path, recursive = TRUE)
writeLines(new_output_dirs, file.path(results_path, "output_dirs.txt"))

timestamp(suffix = paste(" - Finished scenario", scenario))