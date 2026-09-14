# Fetch PBP for one game via baseballr::ncaa_pbp and write baseballr-style CSV.
# Usage: Rscript r_fetch_pbp_one_url.R
# Or in R: source("Baseball/r_fetch_pbp_one_url.R")

if (!requireNamespace("baseballr", quietly = TRUE)) {
  stop("Install baseballr: install.packages(\"baseballr\")")
}
library(baseballr)

game_info_url <- "https://stats.ncaa.org/contests/6500370/box_score"

message("Fetching PBP (game_info_url): ", game_info_url)
pbp <- tryCatch(
  ncaa_pbp(game_info_url = game_info_url),
  error = function(e) {
    message("Error: ", conditionMessage(e))
    NULL
  }
)

if (is.null(pbp) || !is.data.frame(pbp) || nrow(pbp) == 0) {
  message("No PBP returned.")
  quit(save = "no", status = 1)
}

message("Rows: ", nrow(pbp))
message("Columns: ", paste(names(pbp), collapse = ", "))
out_dir <- if (dir.exists("Baseball")) "Baseball" else "."
out_csv <- file.path(out_dir, "pbp_one_game_baseballr_style.csv")
write.csv(pbp, out_csv, row.names = FALSE)
message("Written: ", out_csv)
