#!/usr/bin/env Rscript
# Build the joined game table for one or more seasons from the raw-pull cache.
#
#   Rscript research/r/mlb/run_season.R 2019
#   Rscript research/r/mlb/run_season.R 2016 2019 --out data/mlb
#
# Predictions live in backtest.R, which walks forward so no game is scored from its future.
#
# The legacy file opened with `currentyearcreating <- 2015`, `endyear <- 2019`, then
# `currentyearcreating <- currentyearcreating + 1` three lines later, so the season it
# actually ran was 2016 and neither literal matched what came out. It also never looped
# over endyear at all, despite defining it.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
source(file.path(SRC, "ingest.R"))
source(file.path(SRC, "features.R"))
source(file.path(SRC, "model.R"))
source(file.path(SRC, "evaluate.R"))

#' One season's game table: schedule, both probables, and every side's trailing lines.
#' A cache miss fetches live (Baseball-Reference paced), so a cold run is slow, not wrong.
run_season <- function(season, window_days = 15, src = cached_sources("data/mlb/raw")) {
  win <- season_window(season, fetch = src$seasons)
  stopifnot(nrow(win) == 1)
  message("season ", season, ": ", win$start, " to ", win$end)

  schedule <- fetch_schedule(win$start, win$end, fetch = src$schedule)
  batting  <- team_batting(fetch_daily_batting(win$start, win$end, window_days, fetch = src$batter))
  pitching <- split_pitching(fetch_daily_pitching(win$start, win$end, window_days, fetch = src$pitcher))
  ids      <- chadwick_ids(fetch = src$register)

  build_game_features(schedule, batting, pitching$starters, pitching$relievers, ids) |>
    add_slugging() |>
    dplyr::mutate(season = as.integer(season))
}

main <- function(args = commandArgs(TRUE)) {
  out_dir <- "data/mlb"
  if ("--out" %in% args) {
    i <- which(args == "--out")
    out_dir <- args[i + 1]
    args <- args[-c(i, i + 1)]
  }
  seasons <- suppressWarnings(as.integer(args))
  seasons <- seasons[!is.na(seasons)]
  if (!length(seasons)) stop("give at least one season, e.g. Rscript run_season.R 2019")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  games <- dplyr::bind_rows(purrr::map(seasons, run_season))
  utils::write.csv(games, file.path(out_dir, "mlb_games.csv"), row.names = FALSE)
  message("wrote ", nrow(games), " game rows to ", file.path(out_dir, "mlb_games.csv"))
  invisible(games)
}

if (sys.nframe() == 0L) main()
