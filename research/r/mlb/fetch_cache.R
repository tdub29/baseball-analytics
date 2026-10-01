#!/usr/bin/env Rscript
# Warm the raw-pull cache for one source, so the slow sources can run side by side.
#
#   Rscript research/r/mlb/fetch_cache.R batter 2016 2019
#   Rscript research/r/mlb/fetch_cache.R pitcher 2016 2019
#   Rscript research/r/mlb/fetch_cache.R mlb 2016 2019      # schedule, probables, Chadwick ids
#
# batter and pitcher both hit Baseball-Reference, which jails a client past ~20 requests a
# minute; cached_sources() paces them. A failed call is not cached, so rerun until the log
# shows no "fetch failed" warnings.

suppressPackageStartupMessages({ library(dplyr); library(purrr) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
source(file.path(SRC, "ingest.R"))

args    <- commandArgs(TRUE)
source  <- args[1]
seasons <- as.integer(args[-1])
seasons <- setdiff(seq(min(seasons), max(seasons)), 2020)
src     <- cached_sources("data/mlb/raw")
window_days <- 15

for (season in seasons) {
  win <- season_window(season, fetch = src$seasons)
  message(source, " ", season, ": ", win$start, " to ", win$end)
  if (source == "batter") {
    fetch_daily_batting(win$start, win$end, window_days, fetch = src$batter)
  } else if (source == "pitcher") {
    fetch_daily_pitching(win$start, win$end, window_days, fetch = src$pitcher)
  } else if (source == "mlb") {
    sched <- fetch_schedule(win$start, win$end, fetch = src$schedule)
    message(source, " ", season, ": ", nrow(sched), " final games, ",
            sum(!is.na(sched$h_sp_mlbam) & !is.na(sched$a_sp_mlbam)), " with both probables")
  } else stop("source must be batter, pitcher or mlb")
  message(source, " ", season, ": done")
}
if (source == "mlb") message("chadwick: ", nrow(chadwick_ids(fetch = src$register)), " MLBAM to bbref ids")
w <- warnings()
if (length(w)) { message(length(w), " calls failed; rerun to fill them"); print(w) }
