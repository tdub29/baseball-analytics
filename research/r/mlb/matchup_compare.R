#!/usr/bin/env Rscript
# Paired comparison of matchup-model validation runs against a reference run (MATCHUP-PLAN.md).
#
#   Rscript research/r/mlb/matchup_compare.R -v2 -v4-regime -v4-switch -v4-k -v4 -v4-recal
#
# Each tag is an OUT_TAG of `matchup_model.R validation`; the first is the reference. Reads
# data/mlb/matchup/predictions<tag>-validation.csv and results/matchup-model<tag>-validation.md,
# writes results/matchup-model-v4-ablation.md (OUT env to rename). Differences are reference minus
# run, per game, so positive means the run is better; 95% intervals resample team-seasons, as the
# close comparison in matchup_model.R does.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
tags <- commandArgs(TRUE); stopifnot(length(tags) >= 2)
out_md <- file.path(SRC, "results", Sys.getenv("OUT", "matchup-model-v4-ablation.md"))
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lgt <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
fmt <- function(x, d = 5) formatC(as.numeric(x), format = "f", digits = d)
ci <- function(g) sprintf("%s [%s, %s]", fmt(g[1]), fmt(g[2]), fmt(g[3]))

run <- function(tag) {
  md <- readLines(file.path(SRC, "results", sprintf("matchup-model%s-validation.md", tag)))
  best <- sub(".*: (\\S+)[.]$", "\\1", grep("^Best matchup variant", md, value = TRUE))
  close <- sub("^Close minus matchup[^:]*: ", "", grep("^Close minus matchup", md, value = TRUE))
  x <- fread(sprintf("data/mlb/matchup/predictions%s-validation.csv", tag))
  ms <- setdiff(names(x), c("gid", "game_pk", "Date", "season", "y", "p_close"))
  x[, cc := complete.cases(x[, ms, with = FALSE])]             # the games of matchup_model.R's tables
  list(tag = tag, best = best, close = sub("[.]$", "", close), x = x[, .(gid, season, y, cc, p = get(best), ens = ENS)])
}
slope <- function(x, s) { z <- x[season %in% s & !is.na(p)]; stats::coef(stats::glm(y ~ lgt(p), stats::binomial, z))[2] }
R <- lapply(tags, run); ref <- R[[1]]
rows <- rbindlist(lapply(R, function(r) {
  x <- merge(ref$x, r$x, by = c("gid", "season", "y"), suffixes = c("_0", ""))
  stopifnot(nrow(x) == nrow(ref$x), all(x$cc == x$cc_0))
  v <- x[cc == TRUE]; cl <- paste(substr(v$gid, 1, 3), v$season)
  w <- v[season %in% 2021:2022]; clw <- paste(substr(w$gid, 1, 3), w$season)
  data.table(run = r$tag, best = r$best, games = nrow(v), ll = fmt(mean(ll(v$p, v$y)), 4), ll_2122 = fmt(mean(ll(w$p, w$y)), 4), ens = fmt(mean(ll(v$ens, v$y)), 4),
             d_best = ci(paired(ll(v$p_0, v$y) - ll(v$p, v$y), cl)), d_ens = ci(paired(ll(v$ens_0, v$y) - ll(v$ens, v$y), cl)),
             d_2122 = ci(paired(ll(w$p_0, w$y) - ll(w$p, w$y), clw)),
             slope_1720 = fmt(slope(r$x, 2017:2020), 3), slope_2122 = fmt(slope(r$x, 2021:2022), 3), close = r$close)
}))
lines <- c("# Matchup model v4: validation ablation against v2", "",
  sprintf("Generated %s by `matchup_compare.R %s`. Validation seasons only; the 2023-2025 test is not read.", format(Sys.Date()), paste(tags, collapse = " ")), "",
  sprintf("Reference: `%s`. Log loss on the %s games of matchup_model.R's pooled 2017-2022 row (2020 has no recency model, so it is",
          ref$tag, rows$games[1]),
  "out of every pooled number). \"Best\" is each run's best matchup variant on 2017-2022; \"vs ref\" is reference minus run per game",
  "(positive = run better) with a team-season cluster bootstrap 95% interval. Calibration slope: logistic slope of the outcome on the",
  "logit of the best variant (1 = calibrated, below 1 = too extreme); 2017-2020 includes 2020. \"Close\" is matchup_model.R's close minus",
  "matchup on 2021-2022 games with odds (positive = model better).", "",
  "| run | best | log loss | log loss 2021-2022 | ensemble | best vs ref | ensemble vs ref | best vs ref, 2021-2022 | slope 2017-2020 | slope 2021-2022 | close minus model, 2021-2022 |",
  "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  rows[, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", run, best, ll, ll_2122, ens, d_best, d_ens, d_2122, slope_1720, slope_2122, close)], "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, out_md)
message(paste(lines, collapse = "\n"))
