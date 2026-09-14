# MLB ingest: schedule, daily batting, daily pitching, probable starters.
#
# Every function takes its season and dates as arguments. Nothing in this file reads a
# global, and nothing grows a data frame inside a loop. The legacy pipeline did both.
#
# The network is confined to the four fetch_* wrappers so the feature and model layers
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

#' Every game_pk in a season, one request per date, collected once.
#'
#' The legacy version was `odf <- rbind(odf, f, fill = TRUE)` inside a `while` loop over
#' every day of the season. Two defects, not one:
#'   1. Quadratic. rbind reallocates the whole frame each iteration, ~180 times a season.
#'   2. `fill = TRUE` is data.table syntax. base rbind has no `fill` argument, so it lands
#'      in `...` and is bound as ANOTHER ROW, recycled across every column. That injects
#'      one all-TRUE row per iteration, which is why the legacy file carries the line
#'      `NEW <- filter(NEW, game_pk != 1)  #remove error row` 280 lines later. The dedupe
#'      on game_pk collapsed ~180 garbage rows into one, and the one got patched by hand.
#' map_dfr collects into a list and binds once, and there is no fill argument to misuse.
fetch_schedule <- function(start, end, fetch = baseballr::mlb_game_pks) {
  dates <- seq(as.Date(start), as.Date(end), by = "day")
  purrr::map_dfr(as.character(dates), function(d) {
    out <- safe_fetch(fetch, d)
    if (is.null(out) || nrow(out) == 0) NULL else out
  }) |>
    dplyr::filter(!is.na(.data$game_pk)) |>
    dplyr::distinct(.data$game_pk, .keep_all = TRUE) |>
    dplyr::rename(
      ATeam = teams.away.team.name,
      HTeam = teams.home.team.name,
      Date  = officialDate
    ) |>
    dplyr::mutate(Date = as.Date(.data$Date)) |>
    dplyr::arrange(.data$Date)
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

#' Probable starters for a set of game_pks.
fetch_probables <- function(game_pks, fetch = baseballr::mlb_probables) {
  purrr::map_dfr(unique(game_pks), function(pk) {
    out <- safe_fetch(fetch, pk)
    if (is.null(out) || nrow(out) == 0) NULL else out
  })
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
    if (is.null(out) || nrow(out) == 0) return(NULL)
    out$as_of <- d + 1        # the line is known the morning AFTER the window closes
    out
  })
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
