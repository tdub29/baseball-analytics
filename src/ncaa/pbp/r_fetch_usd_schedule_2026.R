# Fetch USD 2026 baseball schedule with contest_id via baseballr ncaa_schedule_info().
# stats.ncaa.org URL used: https://stats.ncaa.org/team/{team_id}/{season_id}
#
# Run: Rscript r_fetch_usd_schedule_2026.R
# Or in R: source("r_fetch_usd_schedule_2026.R")
#
# Requires: install.packages("baseballr")

if (!requireNamespace("baseballr", quietly = TRUE)) {
  stop("Install baseballr first: install.packages(\"baseballr\")")
}

library(baseballr)

# USD = San Diego Toreros (team_id from stats.ncaa.org/teams/614731)
team_id <- 614731L
year <- 2026L

message("Fetching ", year, " schedule via ncaa_schedule_info(team_id = ", team_id, ", year = ", year, ")...")
sched <- NULL
tryCatch(
  { sched <- ncaa_schedule_info(team_id = team_id, year = year, pbp_links = FALSE) },
  error = function(e) {
    message("Error: ", conditionMessage(e))
    sched <<- NULL
  }
)

if (is.null(sched) || !is.data.frame(sched) || nrow(sched) == 0) {
  message("No ", year, " games returned. Schedule may not be posted yet or NCAA may block direct HTTP.")
  quit(save = "no", status = 1)
}

out_dir <- if (dir.exists("battles")) "battles" else "."
if (dir.exists("Baseball")) out_dir <- "Baseball"
# Write to usd_2026_schedule.csv so R output alone is the schedule (with contest_id)
out_csv <- file.path(out_dir, "usd_2026_schedule.csv")
write.csv(sched, out_csv, row.names = FALSE)
message("Wrote ", nrow(sched), " games to ", out_csv)
cols_show <- intersect(c("date", "opponent", "contest_id", "game_info_url"), names(sched))
if (length(cols_show) > 0) print(head(sched[, cols_show], 20))
