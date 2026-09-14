#!/usr/bin/env Rscript
# Entry point. Seasons are arguments, not globals mutated in place.
#
#   Rscript research/r/mlb/run_season.R 2019
#   Rscript research/r/mlb/run_season.R 2016 2019 --out data/mlb
#
# The legacy file opened with `currentyearcreating <- 2015`, `endyear <- 2019`, then
# `currentyearcreating <- currentyearcreating + 1` three lines later, so the season it
# actually ran was 2016 and neither literal matched what came out. It also never looped
# over endyear at all, despite defining it.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
})

here <- function(...) file.path(dirname(sys.frame(1)$ofile %||% "research/r/mlb"), ...)
`%||%` <- function(a, b) if (is.null(a)) b else a

SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
source(file.path(SRC, "ingest.R"))
source(file.path(SRC, "features.R"))
source(file.path(SRC, "model.R"))
source(file.path(SRC, "evaluate.R"))

#' Build one season end to end and return the game table plus the fitted model.
run_season <- function(season, window_days = 15) {
  message("season ", season, ": window")
  win <- season_window(season)
  stopifnot(nrow(win) == 1)

  message("season ", season, ": schedule")
  schedule <- fetch_schedule(win$start, win$end)

  message("season ", season, ": daily lines")
  batting  <- team_batting(fetch_daily_batting(win$start, win$end, window_days))
  pitching <- split_pitching(fetch_daily_pitching(win$start, win$end, window_days))

  message("season ", season, ": probables")
  probables <- fetch_probables(schedule$game_pk)

  games <- build_game_features(schedule, batting, pitching$starters,
                               pitching$relievers, probables) |>
    add_expected_scores()

  list(season = season, games = games)
}

#' Attach both sides' slugging and expected score to the joined game table.
add_expected_scores <- function(games) {
  games |>
    dplyr::mutate(
      h_rp_slg = slugging(.data$hrp_X1B, .data$hrp_X2B, .data$hrp_X3B,
                          .data$hrp_HR, .data$hrp_AB),
      a_rp_slg = slugging(.data$arp_X1B, .data$arp_X2B, .data$arp_X3B,
                          .data$arp_HR, .data$arp_AB),
      h_sp_slg = slugging(.data$hsp_X1B, .data$hsp_X2B, .data$hsp_X3B,
                          .data$hsp_HR, .data$hsp_AB),
      a_sp_slg = slugging(.data$asp_X1B, .data$asp_X2B, .data$asp_X3B,
                          .data$asp_HR, .data$asp_AB),
      home_expected_score = expected_score(
        .data$h_rp_slg, .data$hrp_HR, .data$asp_SO_perc, .data$asp_LD,
        .data$a_sp_slg, .data$hbat_slg),
      away_expected_score = expected_score(
        .data$a_rp_slg, .data$arp_HR, .data$hsp_SO_perc, .data$hsp_LD,
        .data$h_sp_slg, .data$abat_slg)
    )
}

#' Score every game against the history of comparable expected scores.
add_historical_predictions <- function(games, history, tol = 0.05) {
  score_side <- function(target) {
    res <- purrr::map(target, comparable_outcomes, history = history, tol = tol)
    list(
      pred = purrr::map_dbl(res, "mean_score"),
      n    = purrr::map_int(res, "occurrences"),
      p    = purrr::map_dbl(res, "p_value")
    )
  }
  h <- score_side(games$home_expected_score)
  a <- score_side(games$away_expected_score)

  out <- games |>
    dplyr::mutate(
      home_pred = h$pred, home_n = h$n, home_p = h$p,
      away_pred = a$pred, away_n = a$n, away_p = a$p
    ) |>
    dplyr::filter(.data$home_n > 0, .data$away_n > 0)

  out |>
    dplyr::mutate(
      home_pred = regress_to_mean(.data$home_pred, .data$home_p,
                                  mean(.data$home_pred, na.rm = TRUE)),
      away_pred = regress_to_mean(.data$away_pred, .data$away_p,
                                  mean(.data$away_pred, na.rm = TRUE)),
      home_advantage = .data$home_pred - .data$away_pred,
      away_advantage = .data$away_pred - .data$home_pred
    ) |>
    tidyr::replace_na(list(home_advantage = 0, away_advantage = 0))
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
  results <- purrr::map(seasons, run_season)
  games <- dplyr::bind_rows(purrr::map(results, "games"))

  utils::write.csv(games, file.path(out_dir, "mlb_games.csv"), row.names = FALSE)
  message("wrote ", nrow(games), " game rows to ",
          file.path(out_dir, "mlb_games.csv"))
  invisible(games)
}

if (sys.nframe() == 0L) main()
