# MLB evaluate: R-squared, calibration by predicted-win bucket, and the plots.
#
# Separated from model.R so a caller can refit without producing charts, which the legacy
# file made impossible: `summary()`, `rsq()` and three `ggplot()` calls sat inline in the
# same top-level flow as the fitting.

library(dplyr)

#' Headline fit metrics for one model.
evaluate_model <- function(model) {
  s <- summary(model)
  list(
    r_squared     = as.numeric(s$r.squared),
    adj_r_squared = as.numeric(s$adj.r.squared),
    coefficient   = unname(stats::coef(model)[2]),
    n             = length(stats::residuals(model))
  )
}

#' Realised win rate among predictions above a confidence threshold.
#'
#' The legacy file computed this by hand three times with copy-pasted `select`/`rbind`
#' blocks and printed a bare number with no denominator, so a 3-for-4 stretch and a
#' 300-for-400 stretch both read as 75%. `n` is returned alongside the rate.
win_rate_above <- function(team_rows, threshold = 0.55) {
  hits <- team_rows |>
    dplyr::filter(!is.na(.data$win_pct), .data$win_pct > threshold)
  list(
    threshold = threshold,
    n         = nrow(hits),
    win_rate  = if (nrow(hits)) mean(hits$win, na.rm = TRUE) else NA_real_
  )
}

#' Calibration table: predicted win probability against realised, by bucket.
#'
#' This is the check the legacy file never had. A model can carry a good R-squared on
#' score and still be badly calibrated on the probability that actually gets bet.
calibration_table <- function(team_rows, breaks = seq(0, 1, by = 0.1)) {
  team_rows |>
    dplyr::filter(!is.na(.data$win_pct), !is.na(.data$win)) |>
    dplyr::mutate(bucket = cut(.data$win_pct, breaks = breaks, include.lowest = TRUE)) |>
    dplyr::group_by(.data$bucket) |>
    dplyr::summarise(
      n         = dplyr::n(),
      predicted = mean(.data$win_pct),
      actual    = mean(.data$win),
      .groups   = "drop"
    ) |>
    dplyr::mutate(gap = .data$actual - .data$predicted)
}

#' Scatter of a predictor against realised score, with the fit in the title.
plot_fit <- function(df, x, y = "score", title = NULL) {
  model <- stats::lm(stats::reformulate(x, y), data = df)
  ggplot2::ggplot(df, ggplot2::aes(.data[[x]], .data[[y]])) +
    ggplot2::geom_point(alpha = 0.3) +
    ggplot2::geom_smooth(method = "lm", se = FALSE) +
    ggplot2::ggtitle(title %||% sprintf(
      "%s vs %s - R-squared %.3f", x, y, summary(model)$r.squared))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- per-game scoring, for the walk-forward backtest ---------------------------------

#' Accuracy, log loss and Brier for the model beside two baselines, one row per game.
#'
#' "Home team always" predicts the home side with the training home win rate as its
#' probability. "Coin flip" is 0.5 on everything, so its accuracy is 0.5 by definition
#' (scored literally, a 0.5 tie would pick the home side and copy the home baseline).
score_predictions <- function(preds) {
  y   <- preds$home_win
  row <- function(name, p, accuracy) dplyr::tibble(
    predictor = name, n = length(y), accuracy = accuracy,
    log_loss = log_loss(p, y), brier = mean((p - y)^2))
  dplyr::bind_rows(
    row("model", preds$win_pct, mean((preds$win_pct >= 0.5) == (y == 1))),
    row("home team always", preds$home_rate, mean(y)),
    row("coin flip", rep(0.5, length(y)), 0.5)
  )
}

log_loss <- function(p, y, eps = 1e-15) {
  p <- pmin(pmax(p, eps), 1 - eps)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

#' Bootstrap 95% intervals for the model's edge over "home team always".
#'
#' Resamples games with replacement. Positive means the model is better on both rows: the
#' accuracy gap is model minus home, the log-loss gain is home minus model. Games share
#' teams and days, so this interval is if anything a little narrow.
bootstrap_gaps <- function(preds, reps = 1000, seed = 2019) {
  y  <- preds$home_win
  ll <- function(p) { p <- pmin(pmax(p, 1e-15), 1 - 1e-15); -(y * log(p) + (1 - y) * log(1 - p)) }
  d_acc <- as.numeric((preds$win_pct >= 0.5) == (y == 1)) - y
  d_ll  <- ll(preds$home_rate) - ll(preds$win_pct)
  set.seed(seed)
  draws <- replicate(reps, {
    i <- sample.int(length(y), replace = TRUE)
    c(mean(d_acc[i]), mean(d_ll[i]))
  })
  dplyr::tibble(
    metric   = c("accuracy gap", "log-loss gain"),
    estimate = c(mean(d_acc), mean(d_ll)),
    lo       = apply(draws, 1, stats::quantile, 0.025),
    hi       = apply(draws, 1, stats::quantile, 0.975)
  )
}

#' Each game from the favourite's side: its probability and whether it won.
favorite_frame <- function(preds) {
  data.frame(
    win_pct = pmax(preds$win_pct, 1 - preds$win_pct),
    win     = ifelse(preds$win_pct >= 0.5, preds$home_win, 1 - preds$home_win)
  )
}

#' The confidence cutoff with the best favourite win rate, picked on validation games only.
#'
#' The legacy file reported 0.55 and 0.60 after looking at the season it scored. Here the
#' only input is the validation frame and a cutoff must still cover `min_share` of it, so a
#' 9-for-10 corner cannot win.
choose_threshold <- function(validation_preds, min_share = 0.10,
                             grid = seq(0.50, 0.70, by = 0.005)) {
  fav   <- favorite_frame(validation_preds)
  rates <- purrr::map_dfr(grid, function(t) dplyr::as_tibble(win_rate_above(fav, t)))
  ok    <- rates[rates$n >= min_share * nrow(fav), ]
  ok$threshold[which.max(ok$win_rate)]
}

#' Wilson 95% interval for k successes in n.
wilson_ci <- function(k, n, z = 1.96) {
  if (n == 0) return(c(NA_real_, NA_real_))
  p      <- k / n
  den    <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / den
  half   <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(centre - half, centre + half)
}
