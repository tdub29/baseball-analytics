#!/usr/bin/env Rscript
# Review queue item 2 (MATCHUP-PLAN.md, registered 2026-10-09 before any scoring), exploratory on
# 2017-2022 only: does a model of the starter's batters faced beat v2's expected batters faced?
#
#   Rscript research/r/mlb/starter_length.R        # writes results/starter-length.md
#
# v2's value (matchup_build.R) is the starter's decayed mean batters faced over past starts, shrunk
# 3 starts toward the league. The candidate is a linear model on as-of inputs, fit on 2017-2019
# starts and scored on 2021-2022 starts. Every input uses games dated before the start's date.
# Stage 1 keep rule: the 2021-2022 mean squared error falls, with the week-block bootstrap interval
# on the paired per-start difference above zero. Nothing from 2023 on is used. v2 does not change.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R")) source(file.path(SRC, f))
SEED <- 20261004; FIT <- 2017:2019; SCORE <- 2021:2022; SEASONS <- 2015:2022

cboot <- function(d, cl, B = 1000) {               # ratio-of-sums cluster bootstrap, as devig_check.R
  by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(SEED)
  b <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  c(est = mean(d), lo = unname(quantile(b, 0.025)), hi = unname(quantile(b, 0.975)))
}
week <- function(d) as.Date(cut(as.Date(d), "week"))

# --- appearances: batters faced as matchup_build.R counts them, pitches from the play file -----
P <- rbindlist(lapply(SEASONS, retro_pa))          # regular season, intentional walks dropped
bounds <- P[, .(start = min(Date), end = max(Date)), by = season]
P[, t := season_day(Date, season, as.data.frame(bounds))]   # same offsets as the 2015-2025 build
sp <- P[order(gid, seq)][, .(sp = pitcher[1]), by = .(gid, pitteam)]
app <- P[, .(bf = .N), by = .(gid, pitcher, pitteam, Date, season, t)]   # one row per day pitched
app[, start := FALSE][sp, on = .(gid, pitteam, pitcher = sp), start := TRUE]
stopifnot(!anyDuplicated(app[start == TRUE, .(gid, pitcher)]))  # relievers, never starters, span both days of a suspended game
# Pitches: nump counts each row's new pitches (a stolen-base row and the plate appearance after it
# split one sequence), so the sum over every regular-season row is the pitcher's total for the day. Its NAs
# sit only on non-plate-appearance rows with no pitch string: substitutions (event NP) and, in 5
# regular-season rows over 2015-2022, a steal, balk or advance whose pitches went unrecorded. They count zero.
np <- rbindlist(lapply(SEASONS, function(s) {
  x <- fread(retro_file(s, "plays"), select = c("gid", "date", "pitcher", "gametype", "nump", "pa", "pitches"), showProgress = FALSE)
  stopifnot(x[is.na(nump), all(pa == 0 & !nzchar(pitches))])
  x[gametype == "regular", .(np = sum(nump, na.rm = TRUE)), by = .(gid, pitcher, Date = as.Date(as.character(date), "%Y%m%d"))]
}))
app <- merge(app, np, by = c("gid", "pitcher", "Date"), all.x = TRUE)
stopifnot(!anyNA(app$np))

# --- as-of inputs per start -------------------------------------------------------------------
st <- app[start == TRUE][, n := 1]
setorder(st, pitcher, Date, gid)
sq <- as.data.frame(st[, .(entity = pitcher, Date, season, t)])
sd <- as.data.frame(st)
sb <- asof_decay(transform(sd, entity = pitcher), sq, c("bf", "n", "np"), h = 60, c = 0.5)
lb <- asof_decay(transform(sd, entity = "lg"), transform(sq, entity = "lg"), c("bf", "n", "np"), h = 30, c = 1)
lg_bf <- lb[, "bf"] / pmax(lb[, "n"], 1e-9); lg_np <- lb[, "np"] / pmax(lb[, "n"], 1e-9)
st[, naive := (sb[, "bf"] + 3 * lg_bf) / (sb[, "n"] + 3)]             # v2's exp_bf, matchup_build.R
st[, ppb := (sb[, "np"] + 3 * lg_np) / (sb[, "bf"] + 3 * lg_bf)]      # decayed pitches per batter
tb <- asof_decay(transform(sd, entity = pitteam), transform(sq, entity = st$pitteam), c("bf", "n"), h = 30, c = 0.5)
st[, team_bf := (tb[, "bf"] + 3 * lg_bf) / (tb[, "n"] + 3)]           # his team's decayed starter length
st[, `:=`(prev_bf = shift(bf), prev_np = shift(np), prev_date = shift(Date)), by = pitcher]
st[!is.na(prev_date) & prev_date >= Date, c("prev_bf", "prev_np", "prev_date") := NA]
st[, gap := as.numeric(Date - prev_date)]
st[, rest := factor(fcase(is.na(gap), "none", gap <= 4, "4-", gap == 5, "5", gap == 6, "6",
                          gap <= 9, "7-9", gap <= 30, "10-30", default = "31+"),
                    levels = c("5", "4-", "6", "7-9", "10-30", "31+", "none"))]
st[is.na(prev_bf), `:=`(prev_bf = 0, prev_np = 0)]                    # "none" carries the level
st[, nstart := factor(pmin(rowid(pitcher, season) - 1L, 3L))]         # his earlier starts this season, capped at 3
rw <- app[st[, .(pitcher, lo = Date - 365, hi = Date - 1)], on = .(pitcher, Date >= lo, Date <= hi),
          .(tot = sum(bf), rel = sum(bf * !start)), by = .EACHI]      # one row per start, in st order
st[, `:=`(rel365 = fifelse(is.na(rw$tot), 0, rw$rel / rw$tot), no365 = as.integer(is.na(rw$tot)))]

# --- parity: the naive value must equal v2's exp_bf in the frozen slot checkpoint ------------
# v2 queries every start at its game's first day (retro_games). A suspended game's later plays carry
# the day they were played, so a starter who first pitched on the resumption day is dated here by the
# day he pitched. Parity queries v2's own date and must be exact on every start; at the play date the
# naive value must match wherever the two dates agree.
ck <- readRDS("data/mlb/matchup/slots.rds")$L
ck <- unique(ck[season <= 2022, .(gid, pitteam = opp, pitcher = sp, Date, season, t, exp_bf)])
stopifnot(!anyDuplicated(ck[, .(gid, pitteam)]))
pq <- as.data.frame(ck[, .(entity = pitcher, Date, season, t)])
pb <- asof_decay(transform(sd, entity = pitcher), pq, c("bf", "n"), h = 60, c = 0.5)
pl <- asof_decay(transform(sd, entity = "lg"), transform(pq, entity = "lg"), c("bf", "n"), h = 30, c = 1)
ck[, v2 := (pb[, "bf"] + 3 * pl[, "bf"] / pmax(pl[, "n"], 1e-9)) / (pb[, "n"] + 3)]
par <- merge(st[, .(gid, pitteam, pitcher, Date, naive)], ck, by = c("gid", "pitteam", "pitcher"), suffixes = c("", "_v2"))
moved <- par[Date != Date_v2]
message("parity: ", nrow(par), " of ", nrow(ck), " checkpoint starts matched; max |v2 date - exp_bf| = ", signif(max(abs(ck$v2 - ck$exp_bf)), 3),
        "; ", nrow(moved), " start(s) dated later than v2's game date")
stopifnot(nrow(par) == nrow(ck), max(abs(ck$v2 - ck$exp_bf)) < 1e-9,
          max(abs(par[Date == Date_v2, naive - exp_bf])) < 1e-9, nrow(moved) <= 5)
st <- st[ck[, .(gid, pitteam)], on = .(gid, pitteam), nomatch = NULL]  # starts in v2's game set only

# --- fit on 2017-2019, score 2021-2022 -------------------------------------------------------
fit_d <- st[season %in% FIT]; sc <- st[season %in% SCORE]
m_cand <- lm(bf ~ naive + prev_bf + prev_np + rest + nstart + rel365 + no365 + ppb + team_bf, fit_d)
m_recal <- lm(bf ~ naive, fit_d)                                      # diagnostic: level and slope only
sc[, `:=`(cand = predict(m_cand, sc), recal = predict(m_recal, sc), wk = week(Date))]
mse <- function(p) mean((p - sc$bf)^2)
d_cand <- (sc$naive - sc$bf)^2 - (sc$cand - sc$bf)^2
d_recal <- (sc$naive - sc$bf)^2 - (sc$recal - sc$bf)^2
d_cr <- (sc$recal - sc$bf)^2 - (sc$cand - sc$bf)^2
ci_cand <- cboot(d_cand, sc$wk); ci_recal <- cboot(d_recal, sc$wk); ci_cr <- cboot(d_cr, sc$wk)
KEEP <- ci_cand[["est"]] > 0 && ci_cand[["lo"]] > 0
saveRDS(list(st = st, m_cand = m_cand, m_recal = m_recal, keep = KEEP), "data/mlb/matchup/starter-length.rds")

# --- report ----------------------------------------------------------------------------------
f2 <- function(x) formatC(x, format = "f", digits = 2)
ci <- function(v) sprintf("%s [%s, %s]", f2(v[["est"]]), f2(v[["lo"]]), f2(v[["hi"]]))
by_s <- st[season %in% c(FIT, SCORE), .(starts = .N, actual = mean(bf), naive = mean(naive)), by = season][order(season)]
cf <- summary(m_cand)$coefficients
md <- c(
  "# Starter length: a model of batters faced against v2's decayed mean",
  "",
  "Generated by `Rscript research/r/mlb/starter_length.R`. Review queue item 2 in MATCHUP-PLAN.md,",
  "registered 2026-10-09 before any scoring. **Exploratory on 2017-2022 only**: nothing from 2023 on is",
  "read, and v2 does not change. Batters faced counts plate appearances as `matchup_build.R` does",
  "(intentional walks dropped). Every input uses games dated before the start.",
  "",
  sprintf("Queried at v2's game date, the naive formula reproduces v2's `exp_bf` from the frozen slot checkpoint on all %s starts (max gap %s).",
          format(nrow(par), big.mark = ","), signif(max(abs(ck$v2 - ck$exp_bf)), 2)),
  sprintf("v2 dates a suspended game by its first day; this study dates each start by the day it was pitched. %s",
          if (nrow(moved)) paste0("That moves ", nrow(moved), " start(s): ", paste(moved[, sprintf("%s (%s, %s to %s, naive %s against v2's %s)",
            gid, pitcher, Date_v2, Date, f2(naive), f2(exp_bf))], collapse = "; "), ". Every other start matches v2 exactly.")
          else "No start moves."),
  "",
  "## Stage 1: mean squared error per start, 2021-2022 (lower is better)",
  "",
  "| predictor | starts | MSE | MAE | gain over naive |",
  "| --- | --- | --- | --- | --- |",
  sprintf("| v2 naive (decayed mean, 3-start shrink) | %s | %s | %s | |", format(nrow(sc), big.mark = ","), f2(mse(sc$naive)), f2(mean(abs(sc$naive - sc$bf)))),
  sprintf("| naive recalibrated on 2017-2019 (diagnostic) | %s | %s | %s | %s |", format(nrow(sc), big.mark = ","), f2(mse(sc$recal)), f2(mean(abs(sc$recal - sc$bf))), ci(ci_recal)),
  sprintf("| candidate linear model | %s | %s | %s | %s |", format(nrow(sc), big.mark = ","), f2(mse(sc$cand)), f2(mean(abs(sc$cand - sc$bf))), ci(ci_cand)),
  "",
  sprintf("Candidate against the recalibrated naive: %s. Gain = naive squared error minus the predictor's,", ci(ci_cr)),
  "per start; 95% week-block bootstrap (1,000 draws).",
  sprintf("Variance of actual batters faced, 2021-2022: %s. Candidate R-squared on 2017-2019: %s.", f2(var(sc$bf)), f2(summary(m_cand)$r.squared)),
  "",
  sprintf("**Stage 1 %s.** %s", if (KEEP) "keeps" else "does not keep",
          if (KEEP) "Stage 2 (rebuilt game features, `matchup_model.R validation`): [starter-length-stage2.md](starter-length-stage2.md)." else "Stage 2 does not run."),
  "",
  "## Starts and means by season",
  "",
  "| season | starts | actual batters faced | naive |",
  "| --- | --- | --- | --- |",
  by_s[, sprintf("| %d | %s | %s | %s |", season, format(starts, big.mark = ","), f2(actual), f2(naive))],
  "",
  "## Candidate coefficients (fit on 2017-2019 starts)",
  "",
  "| term | estimate | std. error |",
  "| --- | --- | --- |",
  sprintf("| %s | %s | %s |", rownames(cf), formatC(cf[, 1], format = "f", digits = 3), formatC(cf[, 2], format = "f", digits = 3)),
  "",
  "Rest is in days since his previous start (base: 5); `nstart` is his earlier starts this season (base: 0,",
  "capped at 3); `rel365` is the relief share of his batters faced over the prior 365 days; `ppb` his decayed",
  "pitches per batter as a starter; `team_bf` his team's decayed starter length.",
  "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(md, file.path(SRC, "results", "starter-length.md"))
cat(md, sep = "\n")
