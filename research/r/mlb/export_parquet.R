#!/usr/bin/env Rscript
# Export the raw .rds caches to Parquet so DuckDB (and the dbt project in research/r/mlb/warehouse)
# can query them without R. One Parquet file per cache folder, every file's rows bound together,
# plus `source_file` because some caches carry their key only in the file name (roster 108_2015.rds,
# team log 108_2015_hitting.rds).
#
#   Rscript research/r/mlb/export_parquet.R              # from the repo root; all sources
#   Rscript research/r/mlb/export_parquet.R chadwick     # just the named folders
#
# Writes data/mlb/parquet/, which is gitignored: StatsAPI terms allow non-bulk private use only.
# The Retrosheet CSVs, Statcast CSVs and odds JSON are not exported; DuckDB reads them in place.
# The frozen R features are not ported (warehouse/README.md in research/r/mlb).

suppressPackageStartupMessages({ library(data.table) })
RAW <- "data/mlb/raw"
OUT <- "data/mlb/parquet"
SOURCES <- c("statsapi_lineups", "statsapi_schedule", "statsapi_team_log", "statsapi_player_log",
             "statsapi_roster", "statsapi_teams", "chadwick", "seasons", "bref_batter", "bref_pitcher")

args <- commandArgs(trailingOnly = TRUE)
todo <- if (length(args)) intersect(args, SOURCES) else SOURCES
if (length(args) && !length(todo)) stop("no known source in: ", paste(args, collapse = " "))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

for (s in todo) {
  files <- list.files(file.path(RAW, s), pattern = "\\.rds$", full.names = TRUE)
  if (!length(files)) { message(s, ": no .rds files, skipped"); next }
  parts <- lapply(files, function(f) {
    x <- readRDS(f)
    if (!is.data.frame(x) || !nrow(x)) return(NULL)
    x <- as.data.table(as.data.frame(x))
    x[, source_file := sub("\\.rds$", "", basename(f))]
  })
  d <- rbindlist(parts, use.names = TRUE, fill = TRUE)
  # Integer64 and other classes nanoparquet cannot map become character rather than failing.
  odd <- names(d)[!vapply(d, function(v) is.atomic(v) && (is.numeric(v) || is.character(v) ||
                    is.logical(v) || inherits(v, c("Date", "POSIXct", "factor"))), TRUE)]
  for (col in odd) set(d, j = col, value = as.character(d[[col]]))
  nanoparquet::write_parquet(as.data.frame(d), file.path(OUT, paste0(s, ".parquet")))
  message(sprintf("%-20s %4d files %9d rows %3d cols", s, length(files), nrow(d), ncol(d)))
}
