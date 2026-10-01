# MLB ingest: schedule with probable starters, daily batting, daily pitching, player ids.
#
# Every function takes its season and dates as arguments. Nothing in this file reads a
# global, and nothing grows a data frame inside a loop. The legacy pipeline did both.
#
# The network is confined to the fetch wrappers so the feature and model layers
# can be tested offline against plain data frames.

library(dplyr)
library(purrr)

# --- network wrappers, one baseballr call each -------------------------------------

#' Regular-season start and end dates for one season.
season_window <- function(season, fetch = baseballr::mlb_seasons_all) {
  fetch(sport_id = 1, with_game_type_dates = TRUE) |>
    dplyr::filter(.data$season_id == season) |>
    dplyr::select(
      season_id,
      start = regular_season_start_date,
      end   = regular_season_end_date
    ) |>
    dplyr::slice(1)
}

#' Every final regular-season game in a date range, both probable starters included.
#'
#' One StatsAPI request per range (`hydrate=probablePitcher`) replaces two per-item loops:
#' a request per date for game_pks, then a request per game for its probables, ~9,900 calls
#' for four seasons against 4 here. The legacy date loop also had a real defect:
#' `odf <- rbind(odf, f, fill = TRUE)`. `fill = TRUE` is data.table syntax; base rbind has
#' no such argument, so it bound TRUE as ANOTHER ROW every iteration, which is why the
#' legacy file carries `NEW <- filter(NEW, game_pk != 1)  #remove error row` 280 lines
#' later. Probable ids are MLBAM ids; `chadwick_ids()` maps them to Baseball-Reference.
statsapi_schedule <- function(start, end) {
  url <- paste0("https://statsapi.mlb.com/api/v1/schedule?sportId=1&gameType=R",
                "&startDate=", start, "&endDate=", end, "&hydrate=probablePitcher")
  dplyr::bind_rows(jsonlite::fromJSON(url, flatten = TRUE)$dates$games)
}

fetch_schedule <- function(start, end, fetch = statsapi_schedule) {
  fetch(as.character(start), as.character(end)) |>
    # A postponed game is listed on its original date with no score and again on the
    # makeup date under the same game_pk, so keep only the copy that has a score.
    dplyr::filter(.data$status.abstractGameState == "Final",
                  !is.na(.data$teams.home.score), !is.na(.data$teams.away.score)) |>
    dplyr::distinct(.data$gamePk, .keep_all = TRUE) |>
    dplyr::transmute(
      game_pk = .data$gamePk,
      Date    = as.Date(.data$officialDate),
      HTeam   = .data$teams.home.team.name,
      ATeam   = .data$teams.away.team.name,
      teams.home.score = .data$teams.home.score,
      teams.away.score = .data$teams.away.score,
      h_sp_mlbam = .data$teams.home.probablePitcher.id,
      a_sp_mlbam = .data$teams.away.probablePitcher.id
    ) |>
    dplyr::arrange(.data$Date, .data$game_pk)
}

#' MLBAM id to Baseball-Reference id, from the Chadwick Bureau register via baseballr.
#'
#' StatsAPI names a probable starter by MLBAM id and Baseball-Reference names a pitcher line
#' by bbref id. Joining on display name instead loses accents, Jr. suffixes and the two
#' Will Smiths, silently.
chadwick_ids <- function(fetch = baseballr::chadwick_player_lu) {
  fetch() |>
    dplyr::filter(!is.na(.data$key_mlbam), !is.na(.data$key_bbref), .data$key_bbref != "") |>
    dplyr::transmute(mlbam = as.integer(.data$key_mlbam), bbref_id = .data$key_bbref) |>
    dplyr::distinct(.data$mlbam, .keep_all = TRUE)
}

#' Trailing-window daily batting lines, one row per team per as-of date.
fetch_daily_batting <- function(start, end, window_days = 15,
                                fetch = baseballr::bref_daily_batter) {
  fetch_rolling(start, end, window_days, fetch)
}

#' Trailing-window daily pitching lines, one row per pitcher per as-of date.
fetch_daily_pitching <- function(start, end, window_days = 15,
                                 fetch = baseballr::bref_daily_pitcher) {
  fetch_rolling(start, end, window_days, fetch)
}

# --- shared helpers ----------------------------------------------------------------

#' One rolling pass: for each as-of date, request the trailing window ending there.
#'
#' Returns a single data frame with an `as_of` column, bound once. The caller decides
#' what to aggregate; this layer only fetches.
fetch_rolling <- function(start, end, window_days, fetch) {
  start <- as.Date(start)
  end   <- as.Date(end)
  as_of <- seq(start + window_days, end, by = "day")

  purrr::map_dfr(as_of, function(d) {
    out <- safe_fetch(fetch, as.character(d - window_days), as.character(d))
    if (!is.data.frame(out) || nrow(out) == 0) return(NULL)
    out$as_of <- d + 1        # the line is known the morning AFTER the window closes
    out
  })
}

#' Wrap a fetch so each distinct call lands once on disk and is read from there after.
#'
#' A season is ~170 Baseball-Reference calls per source, and the site jails clients that go
#' past ~20 requests a minute. Without a cache every refit or bug fix meant re-pulling hours
#' of identical data. baseballr does not raise on a failed call: it prints a message and
#' returns a function or a bare list. Only a data frame counts as a result; anything else
#' raises before saveRDS, so failures are never cached and a rerun fills the holes.
#' `pause` is the sleep after each live call, which is what keeps two processes under the cap.
cache_fetch <- function(fetch, dir, pause = 0) {
  force(fetch)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  function(...) {
    key  <- gsub("[^0-9A-Za-z_-]", "-", paste(c(...), collapse = "_"))
    path <- file.path(dir, paste0(key, ".rds"))
    if (file.exists(path)) return(readRDS(path))
    out <- fetch(...)
    Sys.sleep(pause)
    if (!is.data.frame(out)) stop("no data frame returned for ", key)
    saveRDS(out, path)
    out
  }
}

#' Every cached fetcher, so the cache layout under `dir` is defined once.
#'
#' The two Baseball-Reference sources pause `bref_pause` seconds after each live call; at
#' 8 s two processes stay near 11 requests a minute, under the ~20 that gets a client jailed.
cached_sources <- function(dir = "data/mlb/raw", bref_pause = 8) {
  register <- cache_fetch(function(key) baseballr::chadwick_player_lu(), file.path(dir, "chadwick"))
  list(
    seasons  = cache_fetch(baseballr::mlb_seasons_all, file.path(dir, "seasons")),
    schedule = cache_fetch(statsapi_schedule, file.path(dir, "statsapi_schedule")),
    batter   = cache_fetch(baseballr::bref_daily_batter, file.path(dir, "bref_batter"), bref_pause),
    pitcher  = cache_fetch(baseballr::bref_daily_pitcher, file.path(dir, "bref_pitcher"), bref_pause),
    register = function() register("register")
  )
}

#' Retry a network call, then give up on that item rather than the whole run.
#'
#' The legacy loop had no error handling at all: one MLB API failure on day 84 lost the
#' other 180 days with it.
safe_fetch <- function(fetch, ..., attempts = 3, pause = 2) {
  for (i in seq_len(attempts)) {
    out <- tryCatch(fetch(...), error = function(e) e)
    if (!inherits(out, "error")) return(out)
    if (i < attempts) Sys.sleep(pause * i)
  }
  warning("fetch failed after ", attempts, " attempts: ", conditionMessage(out))
  NULL
}
