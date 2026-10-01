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
#' Every pitching input is the OPPOSING side's: its bullpen and its starter, because a
#' team's run output is driven by the pitching it faces (legacy lines 357-358). The legacy
#' file expressed this as one 180-character unnamed line repeated four times with the
#' prefixes swapped. Not used by the win prediction, which matches on `raw_exscore()`.
expected_score <- function(opp_rp_slg, opp_rp_hr, opp_sp_so_perc, opp_sp_ld, opp_sp_slg,
                           bat_slg, coef = EXPECTED_SCORE_COEF) {
  coef[["rp_slg"]] * opp_rp_slg +
    coef[["rp_hr"]] * opp_rp_hr +
    (-1 * opp_sp_so_perc) * opp_sp_ld * opp_sp_slg * bat_slg +
    coef[["interaction"]] * opp_rp_slg * opp_rp_hr
}

#' The unweighted index the comparables lookup matches on (legacy lines 355-356 and 391).
#'
#' Same inputs as `expected_score()` with no fitted coefficients, so nothing fitted on any
#' season, the test season included, reaches a prediction.
raw_exscore <- function(opp_rp_slg, opp_rp_hr, opp_sp_so_perc, opp_sp_ld, opp_sp_slg,
                        bat_slg) {
  opp_rp_slg * opp_rp_hr + (-1 * opp_sp_so_perc) * opp_sp_ld * opp_sp_slg * bat_slg
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
      dplyr::across(dplyr::any_of("Date")),
      score          = .data$teams.home.score,
      opp_score      = .data$teams.away.score,
      expected_score = .data$home_expected_score,
      exscore        = .data$home_exscore,
      is_home        = TRUE
    )
  away <- games |>
    dplyr::transmute(
      dplyr::across(dplyr::any_of("Date")),
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
#' Straight port of the legacy `for (i in 1:ncol(sigg))` imputation loop. Split into a fit
#' and an apply so a backtest can take the means from training rows only: imputing a test
#' week with its own column means lets that week's data shape its own inputs.
impute_column_means <- function(df) apply_means(df, fit_means(df))

fit_means <- function(df, cols = names(df)[vapply(df, is.numeric, logical(1))]) {
  vapply(df[cols], function(x) mean(x, na.rm = TRUE), numeric(1))
}

apply_means <- function(df, means) {
  for (col in names(means)) {
    df[[col]] <- ifelse(is.na(df[[col]]), means[[col]], df[[col]])
  }
  df
}

#' Predicted runs for each side from the realised scores of comparable past team-games.
#'
#' `history` is team rows (Date, exscore, score); only rows before `as_of` are eligible.
#' `population_mean` is the shrink target and must come from training rows. The legacy
#' version shrank toward the mean of the predictions themselves, computed over the very
#' games being predicted. A side with no comparables falls back to the target, so no game
#' drops out of the denominator (legacy dropped them, which flatters any rate).
add_historical_predictions <- function(games, history, as_of, population_mean, tol = 0.05) {
  side <- function(target) {
    res <- lapply(target, function(t) {
      if (is.na(t)) return(list(mean_score = NA_real_, occurrences = 0L, p_value = NA_real_))
      comparable_outcomes(t, history, tol = tol, as_of = as_of)
    })
    n    <- vapply(res, function(r) as.integer(r$occurrences), integer(1))
    pred <- regress_to_mean(vapply(res, `[[`, numeric(1), "mean_score"),
                            vapply(res, `[[`, numeric(1), "p_value"), population_mean)
    list(pred = ifelse(n == 0, population_mean, pred), n = n)
  }
  h <- side(games$home_exscore)
  a <- side(games$away_exscore)
  dplyr::mutate(games,
    home_pred = h$pred, home_n = h$n,
    away_pred = a$pred, away_n = a$n,
    home_advantage = .data$home_pred - .data$away_pred
  )
}

#' Map predicted run advantage to a home win probability.
#'
#' The intercept carries home field, so an advantage of zero still favours the home side by
#' whatever the training years say. One row per game, home perspective: mirrored team rows
#' would count every game twice and make calibration symmetric by construction.
fit_win_model <- function(games) {
  stats::glm(home_win ~ home_advantage, family = stats::binomial, data = games)
}

predict_win_pct <- function(model, games) {
  unname(stats::predict(model, newdata = games, type = "response"))
}

#' Walk-forward predictions: each weekly block is predicted only from games before it.
#'
#' Three passes over the same blocks, each one leak-free on its own:
#' 1. Score index. A block's missing inputs take the means of EARLIER games, then
#'    `add_expected_scores()` runs on the block, so every game is indexed once, as of its week.
#' 2. Comparables. Each side is matched against earlier team-games and shrunk toward their
#'    mean score. Burn-in blocks run too, so the win model has walk-forward training rows.
#' 3. Win probability, `predict_seasons` only. `fit_win_model()` on earlier games, applied
#'    to the block. `home_rate` is the earlier home win rate, the baseline's probability.
#' Weekly refits with the cutoff at the block start carry no look-ahead and cost a seventh
#' of daily ones. `games` needs Date, season, both scores and `SCORE_INPUTS`.
walk_forward <- function(games, predict_seasons, block = "week", tol = 0.05) {
  games <- games |>
    dplyr::mutate(
      block_start = as.Date(cut(.data$Date, block)),
      home_win    = as.integer(.data$teams.home.score > .data$teams.away.score)
    )
  games$imputed <- rowSums(is.na(games[SCORE_INPUTS])) > 0
  starts <- sort(unique(games$block_start))
  each_block <- function(f) purrr::map_dfr(starts, f)

  scored <- each_block(function(d) {
    blk   <- games[games$block_start == d, ]
    prior <- games[games$Date < d, ]
    if (nrow(prior)) blk <- apply_means(blk, fit_means(prior, SCORE_INPUTS))
    add_expected_scores(blk)
  })

  scored <- each_block(function(d) {
    blk     <- scored[scored$block_start == d, ]
    history <- to_team_rows(scored[scored$Date < d, ])
    if (!nrow(history)) return(blk)
    add_historical_predictions(blk, history, as_of = d,
                               population_mean = mean(history$score), tol = tol)
  })

  each_block(function(d) {
    blk <- scored[scored$block_start == d & scored$season %in% predict_seasons, ]
    if (!nrow(blk)) return(NULL)
    prior <- scored[scored$Date < d, ]
    blk$win_pct   <- predict_win_pct(fit_win_model(prior), blk)
    blk$home_rate <- mean(prior$home_win)
    blk
  })
}
