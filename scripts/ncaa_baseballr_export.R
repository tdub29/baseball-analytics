#!/usr/bin/env Rscript
# Pull 2026 NCAA box-score stats (batting + pitching) for the transfer-portal schools via
# baseballr, and write CSVs that `python run.py enrich-ncaa` ingests. baseballr provides the
# clean current-season box scores (IP/ERA/W-L-SV/H/BB/SO/HBP/HR + AB/H/R/RBI/BB/SO) that the
# 6-4-3 exports don't carry; FIP is derived downstream in Python from the components.
#
# Usage:  Rscript scripts/ncaa_baseballr_export.R
# Reads:  data/ncaa_exports/portal_schools.csv  (one column: school)
# Writes: data/ncaa_exports/ncaa_batting_2026.csv, ncaa_pitching_2026.csv
#
# NOTE: stats.ncaa.org sits behind Akamai bot protection that blocks by IP. baseballr's
# ncaa_* functions take a `proxy=` arg for exactly this (see request_with_proxy). Two ways
# to get a clean IP:
#   (a) run from a residential connection NCAA hasn't flagged (where the bio scrape works), or
#   (b) set a residential proxy via env vars and it's threaded into every call:
#         NCAA_PROXY_HOST / NCAA_PROXY_PORT / NCAA_PROXY_USER / NCAA_PROXY_PASS
# From a flagged/datacenter IP with no proxy, every request returns 403 / "Access Denied".

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressMessages({library(baseballr); library(httr); library(dplyr)})
set_config(user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"))

YEAR <- 2026
OUT  <- "data/ncaa_exports"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ---- optional proxy (baseballr's documented workaround for NCAA's IP block) --------------
# stats.ncaa.org blocks scrapers by IP via Akamai; baseballr's ncaa_* functions take a
# `proxy=` arg (passed through request_with_proxy -> httr). Supply a residential proxy via
# env vars to route each request through a clean IP. Leave unset to use this machine's IP
# directly (only works from a connection NCAA hasn't flagged).
#   NCAA_PROXY_HOST  NCAA_PROXY_PORT  NCAA_PROXY_USER  NCAA_PROXY_PASS
PROXY <- NULL
if (nzchar(Sys.getenv("NCAA_PROXY_HOST"))) {
  PROXY <- httr::use_proxy(url = Sys.getenv("NCAA_PROXY_HOST"),
                           port = as.integer(Sys.getenv("NCAA_PROXY_PORT", "8080")),
                           username = Sys.getenv("NCAA_PROXY_USER"),
                           password = Sys.getenv("NCAA_PROXY_PASS"))
  cat("Using proxy ", Sys.getenv("NCAA_PROXY_HOST"), ":", Sys.getenv("NCAA_PROXY_PORT", "8080"), "\n", sep = "")
}
# baseballr call with the proxy threaded through `...` when configured.
team_stats <- function(team_id, type) {
  args <- list(team_id = team_id, year = YEAR, type = type)
  if (!is.null(PROXY)) args$proxy <- PROXY
  tryCatch(do.call(ncaa_team_player_stats, args), error = function(e) NULL)
}

# ---- connectivity gate: confirm stats.ncaa.org is reachable before the long loop --------
probe_ok <- function(team_id = 627) {  # 627 = San Diego (USD)
  for (i in 1:3) {
    r <- team_stats(team_id, "pitching")
    if (!is.null(r) && is.data.frame(r) && nrow(r) > 0) return(TRUE)
    Sys.sleep(5)
  }
  FALSE
}
cat("Checking stats.ncaa.org reachability...\n")
if (!probe_ok()) {
  cat("\nBLOCKED: stats.ncaa.org did not return data (Akamai 403 / Access Denied) from this\n",
      "network. Run this script from a residential connection (where the bio scrape works).\n", sep = "")
  quit(status = 2)
}
cat("Reachable. Pulling ", YEAR, " box scores for portal schools...\n", sep = "")

# ---- map portal school names -> baseballr team_id (cached table, no live request) --------
norm <- function(s) {
  s <- tolower(trimws(s)); s <- gsub("\\bst\\.?\\b", "state", s)
  s <- gsub("\\buniv(ersity)?\\b", "", s); s <- gsub("[^a-z0-9 ]", "", s)
  trimws(gsub("\\s+", " ", s))
}
teams <- load_ncaa_baseball_teams() %>% filter(year == YEAR) %>%
  mutate(k = norm(team_name)) %>% distinct(k, .keep_all = TRUE)
schools <- read.csv(file.path(OUT, "portal_schools.csv"), stringsAsFactors = FALSE)$school
lut <- teams$team_id; names(lut) <- teams$k
ids <- data.frame(school = schools, k = norm(schools), stringsAsFactors = FALSE)
ids$team_id <- unname(lut[ids$k])
cat("schools matched to a team_id: ", sum(!is.na(ids$team_id)), " / ", nrow(ids), "\n", sep = "")
ids <- ids[!is.na(ids$team_id), ]

pull_one <- function(team_id, school, type) {
  d <- team_stats(team_id, type)
  Sys.sleep(runif(1, 2, 3.5))  # be polite
  if (is.null(d) || !is.data.frame(d) || !nrow(d)) return(NULL)
  d$portal_school <- school; d$team_id <- team_id; d
}
pull_all <- function(type) {
  res <- vector("list", nrow(ids))
  for (i in seq_len(nrow(ids))) res[[i]] <- pull_one(ids$team_id[i], ids$school[i], type)
  bind_rows(Filter(Negate(is.null), res))
}
bat <- pull_all("batting")
pit <- pull_all("pitching")

write.csv(bat, file.path(OUT, "ncaa_batting_2026.csv"), row.names = FALSE)
write.csv(pit, file.path(OUT, "ncaa_pitching_2026.csv"), row.names = FALSE)
cat("WROTE batting rows=", nrow(bat), " pitching rows=", nrow(pit), " to ", OUT, "\n", sep = "")
