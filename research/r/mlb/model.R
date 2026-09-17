# MLB model: expected score, the historical-comparable lookup, and the win-probability
# regression back to the mean.
#
# The legacy file interleaved model fitting, three ggplot calls and two ad-hoc threshold
# printouts in the same top-level flow, so nothing could be run without also fitting and
# plotting everything else. Here each step is a function and the caller composes them.

library(dplyr)

# Coefficients fitted on 2016-2019 in the original work and carried forward verbatim.
# They are data, not literals buried in an expression, so refitting is a one-line change.
EXPECTED_SCORE_COEF <- c(
  rp_slg       = 10.79940,
  rp_hr        =  0.33009,
  interaction  = -0.74867
)

#' Expected runs for one side.
#'
#' side_* are that side's OWN bullpen and the OPPOSING starter, because a team's run
#' output is driven by the pitching it faces. The legacy file got this right but expressed
#' it as one 180-character unnamed line repeated four times with the prefixes swapped.
expected_score <- function(rp_slg, rp_hr, opp_sp_so_perc, opp_sp_ld, opp_sp_slg,
                           bat_slg, coef = EXPECTED_SCORE_COEF) {
  coef[["rp_slg"]] * rp_slg +
    coef[["rp_hr"]] * rp_hr +
    (-1 * opp_sp_so_perc) * opp_sp_ld * opp_sp_slg * bat_slg +
    coef[["interaction"]] * rp_slg * rp_hr
}

#' Mean outcome among historical games whose expected score sat within `tol` of this one.
#'
#' The legacy version was a `for (x in 1:nrow(baseball))` loop writing six columns back
#' into `baseball` one row at a time. Same arithmetic, vectorised per row into a function,
#' so it can be tested on 6 rows instead of a season.
#' @param as_of Predict-as-of date. Only games strictly BEFORE this date are eligible
#'   comparables. Required whenever `history` carries a `Date` column, because a
#'   nearest-neighbour lookup over an unfiltered season silently matches games that had not
#'   been played yet when the prediction was made, which inflates every downstream metric.
#'   A fixture with no `Date` column (the unit tests) is exempt, since there is no time to
#'   leak. The guard errors rather than defaulting, because the caller that forgets it is
#'   exactly the caller that produces a good-looking wrong number.
comparable_outcomes <- function(target, history, tol = 0.05, as_of = NULL) {
  has_dates <- "Date" %in% names(history)
  if (has_dates && is.null(as_of)) {
    stop("comparable_outcomes(): history carries a Date column, so as_of is required. ",
         "Passing the whole season lets a game be predicted from games played after it.")
  }
  if (has_dates) {
    history <- history[!is.na(history$Date) & history$Date < as.Date(as_of), , drop = FALSE]
  }
  lo <- target * (1 - tol)
  hi <- target * (1 + tol)
  if (target < 0) { tmp <- lo; lo <- hi; hi <- tmp }
  hits <- history[!is.na(history$exscore) &
                    history$exscore >= lo & history$exscore <= hi, , drop = FALSE]
  list(
    mean_score  = if (nrow(hits)) mean(hits$score, na.rm = TRUE) else NA_real_,
    occurrences = nrow(hits),
    p_value     = normality_p(hits$score)
  )
}

#' Jarque-Bera p-value, guarded.
#'
#' tseries::jarque.bera.test errors on fewer than 2 non-NA values, which in the legacy
#' loop killed the whole run on the first thin comparable set. A thin set is a data
#' condition, so it returns NA and the caller's existing 0.75 default takes over.
normality_p <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3) return(NA_real_)
  out <- tryCatch(tseries::jarque.bera.test(x)$p.value, error = function(e) NA_real_)
  as.numeric(out)
}

#' Shrink a prediction toward the population mean when its comparable set is not
#' distinguishable from noise.
#'
#' Shrinkage is 0.2 + 0.5p, so a p of 0.05 shrinks 22.5% and a p of 1.0 shrinks 70%.
#' Below the threshold nothing moves. This is the legacy rule, extracted so the threshold
#' and the two constants are arguments instead of magic numbers inside an if.
regress_to_mean <- function(pred, p_value, population_mean,
                            threshold = 0.05, base = 0.2, slope = 0.5,
                            default_p = 0.75) {
  p <- ifelse(is.na(p_value), default_p, p_value)
  shrink <- base + slope * p
  ifelse(p > threshold, pred - (pred - population_mean) * shrink, pred)
}

#' Fit the single-predictor score model.
fit_expected_score <- function(df) stats::lm(score ~ expected_score, data = df)

#' Long-format one row per team per game, so home and away share one model.
#'
#' The legacy file did this with `select(sig, 1, 27:50, ...)` on hardcoded index ranges
#' followed by `names(hsig) -> names(asig)`, which is correct only while the column count
#' is exactly what it was the day it was written.
to_team_rows <- function(games) {
  home <- games |>
    dplyr::transmute(
      score          = .data$teams.home.score,
      opp_score      = .data$teams.away.score,
      expected_score = .data$home_expected_score,
      exscore        = .data$home_exscore,
      is_home        = TRUE
    )
  away <- games |>
    dplyr::transmute(
      score          = .data$teams.away.score,
      opp_score      = .data$teams.home.score,
      expected_score = .data$away_expected_score,
      exscore        = .data$away_exscore,
      is_home        = FALSE
    )
  dplyr::bind_rows(home, away) |>
    dplyr::mutate(
      actual_diff = .data$score - .data$opp_score,
      win         = as.integer(.data$actual_diff > 0)
    )
}

#' Replace remaining NAs with that column's mean.
#'
#' Straight port of the legacy `for (i in 1:ncol(sigg))` imputation loop, kept because
#' changing the imputation would change the fitted coefficients and break the diff against
#' the original. `across` does it in one pass instead of ncol assignments.
impute_column_means <- function(df) {
  dplyr::mutate(df, dplyr::across(
    dplyr::where(is.numeric),
    ~ ifelse(is.na(.x), mean(.x, na.rm = TRUE), .x)
  ))
}
