#!/usr/bin/env Rscript
# Robustness checks on the v4 ablation asked for by the iteration 8 review (validation seasons only).
#   Rscript research/r/mlb/matchup_v4_checks.R -v2r -v4-k -v4-switch -v4
# Per-season split of each run minus the reference (first tag) on 2021 and 2022, the same pooled
# difference under three resampling schemes (home team-season, two-way home and away team-season,
# week blocks), and expected calibration error with the binning stated. Reads the walk-forward
# validation predictions under data/mlb/matchup/ and the visiting team from features.rds.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
tags <- commandArgs(TRUE); stopifnot(length(tags) >= 2)
out_md <- file.path(SRC, "results", Sys.getenv("OUT", "matchup-model-v4-checks.md"))
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
fmt <- function(x, d = 5) formatC(as.numeric(x), format = "f", digits = d)
ci <- function(g) sprintf("%s [%s, %s]", fmt(g[1]), fmt(g[2]), fmt(g[3]))
B <- 1000
q <- function(b, d) c(mean(d), stats::quantile(b, c(.025, .975)))
one_way <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  q(replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }), d) }
two_way <- function(d, h, a) {                       # pigeonhole bootstrap: home and away clusters resampled independently
  h <- factor(h); a <- factor(a, levels = union(levels(h), unique(a))); set.seed(20261004)
  q(replicate(B, { wh <- tabulate(sample(nlevels(h), replace = TRUE), nlevels(h)); wa <- tabulate(sample(nlevels(a), replace = TRUE), nlevels(a))
    w <- wh[as.integer(h)] * wa[as.integer(a)]; sum(w * d) / sum(w) }), d)
}
ece <- function(p, y, k = 10) { b <- cut(rank(p, ties.method = "first"), k, labels = FALSE)   # 10 equal-count bins
  sum(tapply(seq_along(p), b, function(i) length(i) * abs(mean(p[i]) - mean(y[i])))) / length(p) }

vis <- readRDS("data/mlb/matchup/features.rds")[, .(gid, vis = visteam)]
rd <- function(tag) {
  md <- readLines(file.path(SRC, "results", sprintf("matchup-model%s-validation.md", tag)))
  best <- sub(".*: (\\S+)[.]$", "\\1", grep("^Best matchup variant", md, value = TRUE))
  x <- fread(sprintf("data/mlb/matchup/predictions%s-validation.csv", tag))
  ms <- setdiff(names(x), c("gid", "game_pk", "Date", "season", "y", "p_close"))
  x <- x[complete.cases(x[, ms, with = FALSE])]                # the pooled games of matchup_model.R's tables
  x[, .(gid, Date, season, y, p = get(best))]
}
ref <- rd(tags[1])
ref <- merge(ref, vis, by = "gid"); stopifnot(nrow(ref) == nrow(rd(tags[1])))
ref[, `:=`(home = paste(substr(gid, 1, 3), season), away = paste(vis, season), wk = paste(season, format(as.Date(Date), "%V")))]

rows <- rbindlist(lapply(tags, function(tag) {
  x <- merge(ref, rd(tag)[, .(gid, p1 = p)], by = "gid"); stopifnot(nrow(x) == nrow(ref))
  x[, d := ll(p, y) - ll(p1, y)]                                 # reference minus run: positive = run better
  w <- x[season %in% 2021:2022]
  data.table(run = tag,
    d2021 = ci(one_way(w[season == 2021]$d, w[season == 2021]$home)), d2022 = ci(one_way(w[season == 2022]$d, w[season == 2022]$home)),
    home = ci(one_way(w$d, w$home)), twoway = ci(two_way(w$d, w$home, w$away)), week = ci(one_way(w$d, w$wk)),
    ece = fmt(ece(w$p1, w$y), 4), ece_pool = fmt(ece(x$p1, x$y), 4))
}))

lines <- c("# Matchup model v4: robustness checks on the ablation", "",
  sprintf("Generated %s by `matchup_v4_checks.R %s`. Validation seasons only; the 2023-2025 test is not read. Reference: `%s`.",
          format(Sys.Date()), paste(tags, collapse = " "), tags[1]), "",
  sprintf("Games: the %d pooled 2017-2022 games of matchup_model.R (2020 has no recency model and is out), %d of them in 2021-2022.",
          nrow(ref), ref[season %in% 2021:2022, .N]),
  "Differences are reference minus run log loss per game on each run's best variant (positive = run better), 1,000 draws.",
  "Per-season and 2021-2022 columns resample home team-seasons. Two-way resamples home and away team-seasons independently and",
  "weights each game by the product of its two draw counts. Week resamples ISO weeks within season. ECE: 10 equal-count bins of",
  "the predicted home win probability, weighted mean of |mean prediction - win rate|.", "",
  "| run | 2021 | 2022 | 2021-2022, home team-season | 2021-2022, two-way | 2021-2022, week blocks | ECE 2021-2022 | ECE pooled |",
  "| --- | --- | --- | --- | --- | --- | --- | --- |",
  rows[, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |", run, d2021, d2022, home, twoway, week, ece, ece_pool)], "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, out_md)
message(paste(lines, collapse = "\n"))
