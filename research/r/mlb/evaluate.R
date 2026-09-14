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
