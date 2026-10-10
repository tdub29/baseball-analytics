#!/usr/bin/env Rscript
# Closing-line timing check (MATCHUP-PLAN.md, registered 2026-10-09 before scoring). Some scraped
# "closing" lines were most likely taken after first pitch: Sept-Oct 2021 is already excluded, and the review
# found 2024-07-31 to 2024-08-07 too. Rule: flag a date with at least 5 matched games whose mean
# |no-vig close minus no-vig open| is over 3 times that season's median daily mean. This rescores the
# headline market comparisons without flagged dates, beside the join-fix numbers, after checking the
# unflagged run reproduces them.
#
#   Rscript research/r/mlb/close_timing.R      # from the repo root; writes results/close-timing.md
#
# Inputs: v2's frozen walk-forward predictions, the corrected odds join and the totals test rows.
# Odds leave this script only as aggregates. Nothing in v2, its thresholds or its blend changes.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages(library(data.table))
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
BEST <- "M5_plus_defense"; TAU_CLOSE <- 0.05; TAU_OPEN <- 0.06
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
cboot <- function(d, cl, B = 1000) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
week_ci <- function(v, d) c(mean(v), cboot(v, as.Date(cut(d, "week")))[2:3])
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
ci <- function(g, d = 4, k = 1) sprintf("%s [%s, %s]", fmt(k * g[1], d), fmt(k * g[2], d), fmt(k * g[3], d))

# --- the registered flag rule ---------------------------------------------------------------
mk <- fread("data/mlb/raw/odds/market-joined.csv")[, Date := as.Date(Date)]
dm <- mk[!is.na(p_open) & !is.na(p_close), .(games = .N, move = mean(abs(p_close - p_open))), by = .(season, Date)]
dm[, ratio := move / median(move), by = season]
flag <- dm[games >= 5 & ratio > 3][order(Date)]
bad <- flag$Date
ev <- mk[!is.na(p_open) & !is.na(p_close) & season %in% 2021:2025][, .(cl = mean(ll(p_close, y)), op = mean(ll(p_open, y)), n = .N),
         keyby = .(f = !Date %in% bad)]   # f FALSE (flagged) sorts first

# --- 2023-2025: close minus M5, close bets, CLV at the open ---------------------------------
T <- fread("data/mlb/matchup/predictions-v2-joinfix-test.csv")[season %in% 2023:2025][, Date := as.Date(Date)]
T <- merge(T, mk[, .(game_pk, med_home, med_away)], by = "game_pk", all.x = TRUE)
D <- fread("data/mlb/matchup/predictions-v2-dayahead-joinfix-test.csv")[season %in% 2023:2025][, Date := as.Date(Date)]
D <- merge(D, mk[, .(game_pk, p_open, med_home_open, med_away_open)], by = "game_pk", all.x = TRUE)
gap_of <- function(x, B = 1000) { x <- x[!is.na(p_close) & !is.na(get(BEST))]
  list(n = nrow(x), g = cboot(ll(x$p_close, x$y) - ll(x[[BEST]], x$y), paste(substr(x$gid, 1, 3), x$season), B = B)) }
close_bets <- function(x) { x <- x[!is.na(p_close)]; eh <- x[[BEST]] - x$p_close
  side <- ifelse(eh >= TAU_CLOSE, "h", ifelse(-eh >= TAU_CLOSE, "a", NA)); b <- x[!is.na(side)]; side <- side[!is.na(side)]
  price <- ifelse(side == "h", b$med_home, b$med_away); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  p <- ifelse(won, price - 1, -1); list(n = length(p), roi = week_ci(p, b$Date)) }
open_bets <- function(x) { x <- x[!is.na(p_open) & !is.na(p_close) & !is.na(get(BEST))]; eh <- x[[BEST]] - x$p_open
  side <- ifelse(eh >= TAU_OPEN, "h", ifelse(-eh >= TAU_OPEN, "a", NA)); b <- x[!is.na(side)]; side <- side[!is.na(side)]
  clv <- ifelse(side == "h", b$p_close - b$p_open, b$p_open - b$p_close)
  price <- ifelse(side == "h", b$med_home_open, b$med_away_open); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  list(n = nrow(b), clv = week_ci(clv, b$Date), roi = week_ci(ifelse(won, price - 1, -1), b$Date)) }

# --- totals: market minus T2 ----------------------------------------------------------------
TT <- fread("data/mlb/raw/odds/totals-test.csv")[, Date := as.Date(Date)]
TT <- TT[season %in% 2023:2025 & !is.na(line) & !excl & !is.na(mu_T1) & total != line][, over := as.integer(total > line)]
tot_of <- function(x) list(n = nrow(x), g = cboot(ll(x$p_mkt, x$over) - ll(x$q_T2, x$over), paste(x$hometeam, x$season), B = 2000))

runs <- list(asis = list(T = T, D = D, TT = TT), fixed = list(T = T[!Date %in% bad], D = D[!Date %in% bad], TT = TT[!Date %in% bad]))
R <- lapply(runs, function(r) list(gap = gap_of(r$T), seas = lapply(2023:2025, function(s) gap_of(r$T[season == s])),
  cb = close_bets(r$T), ob = open_bets(r$D), tot = tot_of(r$TT)))

# parity with the published join-fix numbers
a <- R$asis
chk <- c(gap = round(a$gap$g[1], 5) == -0.00354, cbn = a$cb$n == 988, cbr = round(a$cb$roi[1], 3) == -0.046,
         obn = a$ob$n == 573, obc = round(100 * a$ob$clv[1], 2) == 2.01, totn = a$tot$n == 6310, totg = round(a$tot$g[1], 5) == -0.00520)
if (!all(chk)) stop("unflagged run does not reproduce the join-fix numbers: ", paste(names(chk)[!chk], collapse = ", "))
message("parity: unflagged run reproduces the join-fix numbers")

# --- 2021-2022: what the flag rule removes from validation ----------------------------------
V <- fread("data/mlb/matchup/predictions-v2-validation.csv")[season %in% 2021:2022][, Date := as.Date(Date)]
V <- merge(V[, !"p_close"], mk[, .(game_pk, p_close)], by = "game_pk")
gv <- gap_of(V); gvf <- gap_of(V[!Date %in% bad])

f <- R$fixed
# stability (post hoc): the corrected pooled gap with 10,000 draws, and a looser 2x flag
g10 <- gap_of(runs$fixed$T, B = 10000); bad2 <- dm[games >= 5 & ratio > 2, Date]; g2 <- gap_of(T[!Date %in% bad2])
row <- function(lab, x, y) sprintf("| %s | %s | %s |", lab, x, y)
lines <- c("# Closing-line timing check", "",
  sprintf("Generated %s by `close_timing.R`. Registered in MATCHUP-PLAN.md (2026-10-09) before scoring; post hoc data-quality", format(Sys.Date())),
  "correction, reported beside the join-fix numbers and never replacing them. Rule: flag a date with at least 5 matched games whose mean",
  "|no-vig close minus no-vig open| is over 3 times that season's median daily mean; flagged dates leave the moneyline and totals joins.", "",
  "Parity: without the rule, the script reproduces the join-fix numbers (close minus M5 -0.00354, 988 close bets at -0.046, 573 open",
  "bets at 2.01 points, totals -0.00520 on 6,310 games).", "",
  "## Flagged dates", "",
  "| date | games | mean open-to-close move | times season median |", "| --- | --- | --- | --- |",
  flag[, sprintf("| %s | %d | %s | %s |", Date, games, fmt(move, 3), fmt(ratio, 1))], "",
  sprintf("Season medians of the daily mean move: %s.", paste(dm[, .(m = median(move)), by = season][, sprintf("%s %s", season, fmt(m, 3))], collapse = ", ")), "",
  sprintf("Why it reads as after first pitch (descriptive, outcomes used): on flagged dates the close scores %s log loss against %s for the open over %d games; on all other dates %s against %s over %d.",
          fmt(ev$cl[1]), fmt(ev$op[1]), ev$n[1], fmt(ev$cl[2]), fmt(ev$op[2]), ev$n[2]), "",
  "## 2023-2025 test, join fix vs join fix plus timing rule", "",
  "| measure | join fix | plus timing rule |", "| --- | --- | --- |",
  row("Close minus M5, pooled (positive = M5 better)", sprintf("%s, %d games", ci(a$gap$g), a$gap$n), sprintf("%s, %d games", ci(f$gap$g), f$gap$n)),
  unlist(lapply(1:3, function(i) row(sprintf("Close minus M5, %d", 2022 + i), sprintf("%s, %d", ci(a$seas[[i]]$g), a$seas[[i]]$n), sprintf("%s, %d", ci(f$seas[[i]]$g), f$seas[[i]]$n)))),
  row(sprintf("v2 bets at the close, tau %s, ROI", TAU_CLOSE), sprintf("%s on %d", ci(a$cb$roi, 3), a$cb$n), sprintf("%s on %d", ci(f$cb$roi, 3), f$cb$n)),
  row(sprintf("Day-ahead bets at the open, tau %s, CLV points", TAU_OPEN), sprintf("%s on %d", ci(a$ob$clv, 2, 100), a$ob$n), sprintf("%s on %d", ci(f$ob$clv, 2, 100), f$ob$n)),
  row("Same bets, ROI at the median open price", ci(a$ob$roi, 3), ci(f$ob$roi, 3)),
  row("Totals, market minus T2", sprintf("%s, %d games", ci(a$tot$g, 5), a$tot$n), sprintf("%s, %d games", ci(f$tot$g, 5), f$tot$n)), "",
  "Intervals: home team-season bootstrap for log loss, week-block bootstrap for bets (1,000 draws; totals 2,000), seed 20261004.", "",
  sprintf("Stability (post hoc): with 10,000 draws the corrected pooled gap is %s. Its upper edge sits about 0.0001 from zero, so after the fix the close's lead is borderline. A looser flag (2 times the season median) drops %d dates across 2021-2025 and gives %s on %d games.",
          ci(g10$g), length(bad2), ci(g2$g), g2$n), "",
  sprintf("Totals: dropping the flagged dates widens the market's lead (%s to %s), so the totals closes show no sign of late scraping on those dates.", fmt(a$tot$g[1], 5), fmt(f$tot$g[1], 5)), "",
  "## 2021-2022 validation", "",
  sprintf("The rule flags %d validation games. Close minus M5 there: %s on %d games as run, %s on %d without them. v2's threshold and blend",
          gv$n - gvf$n, ci(gv$g, 5), gv$n, ci(gvf$g, 5), gvf$n),
  "were tuned with them in and stay frozen; dropping them is recorded as a fix for the next version.", "",
  "## Reading under the registered rule", "",
  if (f$gap$g[3] < 0) "The corrected pooled interval lies below zero: the close beats M5 on 2023-2025 stands." else
    "The corrected pooled interval reaches zero: the report no longer says the close beats M5 on 2023-2025.",
  "", "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, file.path(SRC, "results", "close-timing.md"))
message(paste(lines, collapse = "\n"))
