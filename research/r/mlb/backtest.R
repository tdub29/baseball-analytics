#!/usr/bin/env Rscript
# Walk-forward out-of-sample backtest of the game-by-game win model.
#
#   Rscript research/r/mlb/backtest.R 2016 2018              # validation report only
#   Rscript research/r/mlb/backtest.R 2016 2019 --test 2019  # scores the test season, once
#
# The first season is burn-in (training only). Every later season is predicted one weekly
# block at a time from games strictly before the block (walk_forward() in model.R). The
# threshold is chosen on the validation seasons before the test season is scored, and a
# second --test run refuses to overwrite the first unless --force is given, because a test
# season looked at twice is a validation season. 2020 (60 games) is always skipped.

SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
source(file.path(SRC, "run_season.R"))

pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
num <- function(x, d = 3) sprintf(paste0("%.", d, "f"), x)
md_table <- function(df) {
  c(paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
}

#' Scores, edge over home field, threshold win rate and calibration for one set of games.
season_section <- function(preds, threshold, label) {
  s    <- score_predictions(preds)
  g    <- bootstrap_gaps(preds)
  fav  <- favorite_frame(preds)
  hits <- fav[fav$win_pct > threshold, ]
  ci   <- wilson_ci(sum(hits$win), nrow(hits))
  cal  <- calibration_table(dplyr::mutate(preds, win = .data$home_win))
  list(scores = s, gaps = g, lines = c(
    paste0("## ", label), "",
    md_table(dplyr::transmute(s, predictor, games = format(n, big.mark = ","),
                              accuracy = pct(accuracy), `log loss` = num(log_loss, 4),
                              Brier = num(brier, 4))), "",
    "Edge over \"home team always\", 1,000 game resamples (positive = model better):", "",
    md_table(dplyr::transmute(g, metric, estimate = num(estimate, 4),
                              `95% interval` = paste0("[", num(lo, 4), ", ", num(hi, 4), "]"))), "",
    sprintf("Favourites above the %.3f threshold: %d of %d games (%s), won %s, Wilson 95%% [%s, %s].",
            threshold, nrow(hits), nrow(fav), pct(nrow(hits) / nrow(fav)),
            pct(mean(hits$win)), pct(ci[1]), pct(ci[2])), "",
    "Calibration, home win probability:", "",
    md_table(dplyr::transmute(cal, bucket = as.character(bucket), games = n,
                              predicted = pct(predicted), actual = pct(actual), gap = pct(gap))), ""
  ))
}

coverage_lines <- function(games, preds) {
  g <- games[games$season %in% unique(preds$season), ]
  share <- function(x) pct(mean(x))
  c("## Coverage", "",
    sprintf("- Games predicted: %s. Every final game is kept; nothing is dropped for thin data.",
            format(nrow(preds), big.mark = ",")),
    sprintf("- Sides with no comparable past team-game (fell back to the training mean): %s.",
            share(c(preds$home_n, preds$away_n) == 0)),
    sprintf(paste("- Games with at least one score input imputed from earlier games' means: %s.",
                  "Most are the first ~16 days of each season, before a 15-day window exists."),
            share(preds$imputed)),
    sprintf("- Both probable starters listed by StatsAPI: %s. Mapped to a Baseball-Reference id via Chadwick: home %s, away %s.",
            share(!is.na(g$h_sp_mlbam) & !is.na(g$a_sp_mlbam)),
            share(!is.na(g$hsp_bbref)), share(!is.na(g$asp_bbref))),
    sprintf("- Starter has a trailing-window line (none on a first start or a return from injury): home %s, away %s.",
            share(!is.na(g$hsp_IP)), share(!is.na(g$asp_IP))),
    sprintf("- Team batting line joined: home %s, away %s. Bullpen line joined: home %s, away %s.",
            share(!is.na(g$hbat_slg)), share(!is.na(g$abat_slg)),
            share(!is.na(g$hrp_IP)), share(!is.na(g$arp_IP))), "")
}

method_lines <- function(burn_in, validation, test) c(
  "## Method", "",
  sprintf("- Burn-in %d (training only). Validation %s. Test %s. 2020 excluded.", burn_in,
          paste(unique(range(validation)), collapse = "-"),
          if (is.na(test)) "not scored in this run" else test),
  paste("- Each Monday-to-Sunday block is predicted from games before that Monday only: imputation",
        "means, the comparable pool, the shrink target and the win model are all refit per block."),
  paste("- A side's predicted runs are the mean realised score of past team-games whose raw index",
        "sat within 5% of its own, shrunk toward the training mean by 0.2 + 0.5p when the",
        "Jarque-Bera p exceeds 0.05. All three constants are the legacy values, frozen before any",
        "season was scored."),
  paste("- The comparables match on the raw index, which has no fitted coefficients, so the shipped",
        "EXPECTED_SCORE_COEF (fitted on 2016-2019) never reach a prediction. The plan's per-fold",
        "coefficient refit was therefore unnecessary."),
  paste("- Win probability: logistic regression of home win on the predicted run gap and on the",
        "gap in season-to-date run differential per game (each side's runs scored minus allowed in",
        "this season's games before the block, over games played plus 20); the intercept carries",
        "home field. One row per game, home perspective."),
  paste("- Chosen on validation, so validation rates flatter the model: the run-differential term",
        "(added after the first validation run showed the run gap alone tied home field, 53.3% vs",
        "53.4%), its shrink of 20 games (fit 2017, scored 2018; flat from 10 to 40) and the",
        "threshold. The test season is the only clean number."),
  paste("- Two rebuild defects were fixed before any season was scored: each side read its own",
        "bullpen instead of the opponent's, and the comparables matched the weighted score against",
        "the raw index (different units)."),
  paste("- The bootstrap resamples games independently. Games share teams and dates, so the true",
        "interval is if anything wider."), "")

main <- function(args = commandArgs(TRUE)) {
  cmd   <- paste(args, collapse = " ")
  force <- "--force" %in% args
  args  <- args[args != "--force"]   # not setdiff(): it would drop the repeated year
  test  <- NA_integer_
  if ("--test" %in% args) {
    i <- which(args == "--test")
    test <- as.integer(args[i + 1])
    args <- args[-c(i, i + 1)]
  }
  years   <- as.integer(args)
  seasons <- setdiff(seq(min(years), max(years)), 2020)
  burn_in <- seasons[1]
  predict <- seasons[-1]
  if (!is.na(test) && test != max(seasons)) stop("the test season must be the last season")
  validation <- setdiff(predict, test)
  if (!length(validation)) stop("need at least one validation season before the test season")

  out_md <- file.path(SRC, "results",
                      if (is.na(test)) "backtest-validation.md" else sprintf("backtest-%d.md", test))
  if (!is.na(test) && file.exists(out_md) && !force) {
    stop(test, " is already scored (", out_md, "). Rescoring it makes it a validation season; ",
         "pass --force only if that is the intent.")
  }

  games <- dplyr::bind_rows(purrr::map(seasons, run_season))
  preds <- walk_forward(games, predict) |>
    dplyr::mutate(role = ifelse(.data$season %in% test, "test", "validation"))
  val <- preds[preds$role == "validation", ]
  threshold <- choose_threshold(val)          # fixed before any test row is scored below

  dir.create("data/mlb/backtest", recursive = TRUE, showWarnings = FALSE)
  keep <- c("game_pk", "Date", "season", "role", "HTeam", "ATeam", "teams.home.score",
            "teams.away.score", "home_win", "home_exscore", "away_exscore", "home_n", "away_n",
            "home_pred", "away_pred", "home_advantage", "rd_gap", "win_pct", "home_rate", "imputed")
  utils::write.csv(preds[keep], "data/mlb/backtest/predictions.csv", row.names = FALSE)

  v <- season_section(val, threshold, sprintf("Validation %s (threshold chosen here)",
                                              paste(unique(range(validation)), collapse = "-")))
  head <- c(sprintf("# MLB walk-forward backtest: %s", if (is.na(test)) "validation" else test), "",
            sprintf("Generated %s by `Rscript research/r/mlb/backtest.R %s`. Predictions: `data/mlb/backtest/predictions.csv`.",
                    format(Sys.Date()), cmd), "",
            sprintf(paste("Threshold, chosen on validation games only (best favourite win rate among",
                          "cutoffs covering at least 10%% of games): **%.3f**."), threshold), "")
  body <- v$lines
  if (!is.na(test)) {
    t   <- season_section(preds[preds$role == "test", ], threshold, sprintf("Test %d, scored once", test))
    acc <- t$gaps[t$gaps$metric == "accuracy gap", ]
    ll  <- t$scores$log_loss
    gate <- acc$lo > 0 && ll[1] < ll[2]
    body <- c(t$lines,
              sprintf(paste("**Slide gate: %s.** Needs the accuracy gap's 95%% interval above zero",
                            "(it is [%s, %s]) and model log loss under home's (%s vs %s)."),
                      if (gate) "PASS" else "FAIL", num(acc$lo, 4), num(acc$hi, 4),
                      num(ll[1], 4), num(ll[2], 4)), "",
              body)
  }
  dir.create(dirname(out_md), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(head, body, coverage_lines(games, preds), method_lines(burn_in, validation, test)), out_md)
  message("wrote ", out_md, " and data/mlb/backtest/predictions.csv")
  invisible(preds)
}

if (sys.nframe() == 0L) main()
