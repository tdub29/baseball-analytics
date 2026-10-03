#!/usr/bin/env Rscript
# Warm the StatsAPI game-log cache (team lines, player lines, rosters) and the schedule cache.
#
#   Rscript research/r/mlb/fetch_gamelogs.R 2015 2025
#
# About a hundred calls a season, resumable: a failed call is not cached, so rerun to fill it.

suppressPackageStartupMessages({ library(dplyr); library(purrr) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
source(file.path(SRC, "ingest.R"))
source(file.path(SRC, "gamelogs.R"))

seasons <- as.integer(commandArgs(TRUE))
seasons <- seq(min(seasons), max(seasons))   # 2020 included: history for 2021, never scored
src <- cached_sources("data/mlb/raw")
gl  <- gamelog_sources("data/mlb/raw")

for (season in seasons) {
  win   <- season_window(season, fetch = src$seasons)
  g     <- tryCatch(season_gamelogs(season, win, gl), error = function(e) { message("  ", conditionMessage(e)); NULL })
  if (is.null(g)) { message(season, ": incomplete, rerun"); next }
  message(sprintf("%d: %d games (%d with both lineups), team hitting %d rows, team pitching %d, pitcher lines %d, hitter lines %d",
                  season, nrow(g$schedule), sum(!is.na(g$schedule$home_bat9) & !is.na(g$schedule$away_bat9)), nrow(g$team_hitting), nrow(g$team_pitching),
                  nrow(g$pitchers), nrow(g$hitters)))
}
