#!/usr/bin/env Rscript
# Review queue item 10 (MATCHUP-PLAN.md): does the 2021-2022 market blend's weight on M5 hold out of
# sample? matchup_model.R fits logit p = a + b logit(close) + c logit(M5) on 2021-2022 and reads it on
# the same games. This scores it (a) cross-fit, 2021 to 2022 and back; (b) with a home team-season
# bootstrap interval on c; (c) post hoc on the spent 2023-2025 test with the frozen 2021-2022 fit.
#
#   Rscript research/r/mlb/blend_oos.R          # from the repo root; writes results/blend-oos.md
#
# Inputs: v2's frozen walk-forward predictions and the corrected odds join (market-joined.csv). Odds
# leave this script only as aggregates. Nothing in v2, its thresholds or any published number changes.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages(library(data.table))
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
BEST <- "M5_plus_defense"
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lg <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
fmt <- function(x, d = 5) formatC(as.numeric(x), format = "f", digits = d)
ci <- function(g, d = 5) sprintf("%s [%s, %s]", fmt(g[1], d), fmt(g[2], d), fmt(g[3], d))

mk <- fread("data/mlb/raw/odds/market-joined.csv")[, .(game_pk, p_close)]
load_pred <- function(f, s) {
  x <- fread(f)[season %in% s, c("gid", "game_pk", "season", "Date", "y", BEST), with = FALSE]
  x <- merge(x, mk, by = "game_pk")[!is.na(p_close) & !is.na(get(BEST))]
  x[, `:=`(m = get(BEST), cl = paste(substr(gid, 1, 3), season))]
}
V <- load_pred("data/mlb/matchup/predictions-v2-validation.csv", 2021:2022)
T <- load_pred("data/mlb/matchup/predictions-v2-joinfix-test.csv", 2023:2025)
# the as-run and join-fixed test runs share every prediction; only the odds join differs
a <- fread("data/mlb/matchup/predictions-v2-test.csv")[, c("gid", BEST), with = FALSE]
j <- merge(a, T[, .(gid, m)], by = "gid"); stopifnot(nrow(j) > 6000, isTRUE(all.equal(j[[BEST]], j$m)))

fit <- function(x) stats::glm(y ~ lg(p_close) + lg(m), stats::binomial, x)
b0 <- stats::coef(fit(V))
if (!isTRUE(all.equal(round(unname(b0), 3), c(0.018, 0.856, 0.173))))
  stop("2021-2022 fit does not reproduce the published blend: ", paste(round(b0, 3), collapse = ", "))
message("parity: 2021-2022 fit reproduces the published blend on ", nrow(V), " games")
score <- function(f, x) { p <- stats::predict(f, x, type = "response"); ll(x$p_close, x$y) - ll(p, x$y) }
# nested: the close recalibrated alone vs close plus M5, so M5's information is not mixed with recalibrating the close
fitc <- function(x) stats::glm(y ~ lg(p_close), stats::binomial, x)
nested <- function(f, fc, x) ll(stats::predict(fc, x, type = "response"), x$y) - ll(stats::predict(f, x, type = "response"), x$y)

# (a) cross-fit
cf <- rbindlist(lapply(list(c(2021, 2022), c(2022, 2021)), function(s) {
  f <- fit(V[season == s[1]]); x <- V[season == s[2]]
  data.table(fit = s[1], scored = s[2], gid = x$gid, cl = x$cl, d = score(f, x), dn = nested(f, fitc(V[season == s[1]]), x),
             c = stats::coef(f)[3], b = stats::coef(f)[2])
}))
cf_rows <- cf[, .(games = .N, b = fmt(b[1], 3), c = fmt(c[1], 3), d = ci(paired(d, cl)), dn = ci(paired(dn, cl))), by = .(fit, scored)]
cf_rows[, scored := as.character(scored)][as.integer(scored) < fit, scored := sprintf("%s (backward in time)", scored)]
cf_pool <- paired(cf$d, cf$cl); cf_pool_n <- paired(cf$dn, cf$cl)

# (b) bootstrap on c, resampling home team-seasons of 2021-2022
cls <- unique(V$cl); idx <- split(seq_len(nrow(V)), V$cl); set.seed(20261004)
cb <- replicate(1000, stats::coef(fit(V[unlist(idx[sample(cls, replace = TRUE)])]))[3])
c_ci <- c(b0[3], stats::quantile(cb, c(.025, .975)))

# (c) post hoc on 2023-2025, frozen 2021-2022 fit
f0 <- fit(V); T[, `:=`(d = score(f0, T), dn = nested(f0, fitc(V), T))]
ph_rows <- T[, .(games = .N, d = ci(paired(d, cl))), by = season][order(season)]
ph_pool <- paired(T$d, T$cl); ph_pool_n <- paired(T$dn, T$cl)
bt <- stats::coef(fit(T))
# post hoc: the same reading without the 12 late-close dates (close_timing.R's rule, results/close-timing.md)
mo <- fread("data/mlb/raw/odds/market-joined.csv")[!is.na(p_open) & !is.na(p_close),
        .(games = .N, move = mean(abs(p_close - p_open))), by = .(season, Date = as.Date(Date))]
bad <- mo[, ratio := move / median(move), by = season][games >= 5 & ratio > 3, Date]; stopifnot(length(bad) == 12)
L <- T[!as.Date(Date) %in% bad]; lt_pool <- paired(L$d, L$cl); lt_pool_n <- paired(L$dn, L$cl); blt <- stats::coef(fit(L))
claim <- cf_pool[2] > 0

lines <- c("# Market blend weight out of sample (review queue item 10)", "",
  sprintf("Generated %s by `blend_oos.R`. Registered in MATCHUP-PLAN.md (2026-10-09) before scoring. Model: v2 %s, frozen", format(Sys.Date()), BEST),
  "walk-forward predictions. Close: proportional no-vig consensus closing line, corrected odds join. Blend: logit p = a + b logit(close)",
  "+ c logit(model). \"Close minus blend\" is per-game log loss, positive when the blend beats the close; 95% intervals resample home",
  "team-seasons (1,000 draws, seed 20261004).", "",
  sprintf("Parity: the 2021-2022 fit reproduces the published blend, a %s, b %s, c %s, on %d games.", fmt(b0[1], 3), fmt(b0[2], 3), fmt(b0[3], 3), nrow(V)), "",
  "## (a) Cross-fit on the market-tuning seasons", "",
  "| fit on | scored on | games | b (close) | c (model) | close minus blend | recalibrated close minus blend |", "| --- | --- | --- | --- | --- | --- | --- |",
  cf_rows[, sprintf("| %s | %s | %s | %s | %s | %s | %s |", fit, scored, games, b, c, d, dn)], "",
  sprintf("Pooled over both scored seasons (%d games): %s against the raw close; %s against the close recalibrated alone (the nested test of M5's information).",
          nrow(cf), ci(cf_pool), ci(cf_pool_n)), "",
  "## (b) Uncertainty in the model weight", "",
  sprintf("c on 2021-2022: %s (home team-season bootstrap).", ci(c_ci, 3)), "",
  "## (c) Post hoc: the frozen 2021-2022 blend on the spent 2023-2025 test", "",
  "Post hoc. The test was scored once on 2026-10-04; this reads it again and changes nothing.", "",
  "| season | games | close minus blend |", "| --- | --- | --- |",
  ph_rows[, sprintf("| %s | %s | %s |", season, games, d)], "",
  sprintf("Pooled (%d games): %s against the raw close; %s against the close recalibrated alone on 2021-2022. Refit on 2023-2025 (in sample, descriptive only): a %s, b %s, c %s.",
          nrow(T), ci(ph_pool), ci(ph_pool_n), fmt(bt[1], 3), fmt(bt[2], 3), fmt(bt[3], 3)), "",
  sprintf("Without the 12 late-close dates (`close_timing.R`'s rule, %d games): %s against the raw close; %s against the recalibrated close. Refit: a %s, b %s, c %s.",
          nrow(L), ci(lt_pool), ci(lt_pool_n), fmt(blt[1], 3), fmt(blt[2], 3), fmt(blt[3], 3)), "",
  "## Reading under the registered claim rule", "",
  if (claim) "The pooled cross-fit interval lies above zero: M5 adds information to the close out of sample on 2021-2022." else
    "The pooled cross-fit interval does not lie above zero, so the report does not say M5 adds information to the close out of sample. The 0.17 weight is an in-sample fit.",
  "", "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, file.path(SRC, "results", "blend-oos.md"))
message(paste(lines, collapse = "\n"))
