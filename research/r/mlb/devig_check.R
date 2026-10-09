#!/usr/bin/env Rscript
# De-vig sensitivity (MATCHUP-PLAN.md review queue item 3): do the market benchmark and the
# closing-line value of the frozen open bets depend on how the bookmaker margin is removed?
#
#   Rscript research/r/mlb/devig_check.R          # from the repo root; writes results/devig-check.md
#
# Every published market number uses the proportional no-vig price, 1/d over the sum of 1/d. Shin
# (1993) instead puts more of the margin on the longshot, the usual model of favourite-longshot bias.
# This rebuilds the consensus no-vig open and close both ways from the per-book prices, then re-scores
# the frozen predictions and the frozen tau = 0.06 open bets, split by favourite and underdog. Post hoc
# and exploratory: no model, threshold or published number changes. The parse and join repeat
# market_study.R and are checked against its market-joined.csv game by game before anything is scored.
# Odds leave this script only as aggregates.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages(library(data.table))
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("ingest.R", "gamelogs.R")) source(file.path(SRC, f))
SEED <- 20261004
TAU <- 0.06                                        # frozen on 2021-2022 (matchup-model-v2-dayahead-test.md)
BEST <- "M5_plus_defense"

`%||%` <- function(a, b) if (is.null(a)) b else a
decimal <- function(a) ifelse(a > 0, 1 + a / 100, 1 + 100 / abs(a))
prop <- function(dh, da) (1 / dh) / (1 / dh + 1 / da)
shin <- function(dh, da) {                         # Shin (1993) home probability for a two-way price
  ph <- 1 / dh; pa <- 1 / da; S <- ph + pa
  p <- function(q, z) (sqrt(z^2 + 4 * (1 - z) * q^2 / S) - z) / (2 * (1 - z))
  flat <- S <= 1                                   # no margin to remove (a stale or crossed quote): Shin is
                                                   # undefined there, so the price falls back to proportional
  lo <- 0 * S; hi <- lo + 1 - 1e-6                 # sum p(z) falls in z: > 1 at 0 when S > 1, < 1 near 1
  stopifnot(all((p(ph, hi) + p(pa, hi) < 1)[!flat])) # (z = S - 1 on an even quote, so a 2.0 overround still brackets)
  for (i in 1:60) { z <- (lo + hi) / 2; up <- p(ph, z) + p(pa, z) > 1; lo[up] <- z[up]; hi[!up] <- z[!up] }
  z <- (lo + hi) / 2
  z[flat] <- 0
  out <- ifelse(flat, ph / S, p(ph, z))
  stopifnot(all(abs(ifelse(flat, 1, p(ph, z) + p(pa, z)) - 1) < 1e-9))
  list(p = out, z = z, flat = flat)
}
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
cboot <- function(d, cl, B = 1000) {               # ratio-of-sums cluster bootstrap, as figures.R
  by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(SEED)
  b <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  c(est = mean(d), lo = unname(quantile(b, 0.025)), hi = unname(quantile(b, 0.975)))
}
week <- function(d) as.Date(cut(as.Date(d), "week"))
near <- function(a, b, tol) isTRUE(all(abs(a - b) <= tol))

# --- odds: per-book prices, consensus no-vig both ways (books filtered as market_study.R) ------------
raw <- jsonlite::fromJSON("data/mlb/raw/odds/mlb_odds_dataset.json", simplifyVector = FALSE)
bk <- rbindlist(lapply(names(raw), function(d) rbindlist(lapply(seq_along(raw[[d]]), function(i) {
  g <- raw[[d]][[i]]; v <- g$gameView; ml <- g$odds$moneyline
  if (is.null(ml) || !length(ml) || is.null(v$homeTeamScore)) return(NULL)
  pick <- function(b, line, side) { x <- b[[line]][[side]]; if (is.null(x)) NA_real_ else as.numeric(x) }
  data.table(g = paste(d, i), odds_date = as.Date(d), home = v$homeTeam$fullName, away = v$awayTeam$fullName,
             hs = as.numeric(v$homeTeamScore), as = as.numeric(v$awayTeamScore),
             ch = vapply(ml, pick, 0, "currentLine", "homeOdds"), ca = vapply(ml, pick, 0, "currentLine", "awayOdds"),
             oh = vapply(ml, pick, 0, "openingLine", "homeOdds"), oa = vapply(ml, pick, 0, "openingLine", "awayOdds"))
}))))
bk <- bk[!is.na(ch) & !is.na(ca) & ch != 0 & ca != 0]
bk[, `:=`(dh = decimal(ch), da = decimal(ca), op = !is.na(oh) & !is.na(oa) & oh != 0 & oa != 0)]
s_close <- shin(bk$dh, bk$da)
bk[, `:=`(pc = prop(dh, da), pc_s = s_close$p, z_close = s_close$z, flat = s_close$flat)]
bk[op == TRUE, c("po", "po_s") := .(prop(decimal(oh), decimal(oa)), shin(decimal(oh), decimal(oa))$p)]
odds <- bk[, .(p_close = mean(pc), p_close_s = mean(pc_s), z = mean(z_close),
               p_open = if (any(op)) mean(po[op]) else NA_real_, p_open_s = if (any(op)) mean(po_s[op]) else NA_real_),
           by = .(g, odds_date, home, away, hs, as)]

# --- join to StatsAPI games, verbatim market_study.R ---------------------------------------------------
gl <- gamelog_sources("data/mlb/raw"); cs <- cached_sources("data/mlb/raw")
sched <- rbindlist(lapply(2021:2025, function(s) {
  win <- season_window(s, fetch = cs$seasons)
  sc <- gl$schedule(as.character(win$start), as.character(win$end))
  tm <- gl$teams(s)
  data.table(game_pk = sc$game_pk, Date = sc$Date, home = tm$team[match(sc$home_id, tm$team_id)],
             away = tm$team[match(sc$away_id, tm$team_id)], hs = sc$home_score, as = sc$away_score)
}))
norm <- function(x) {
  x <- gsub("[^a-z]", "", tolower(sub("^Oakland ", "", x)))
  x[x == "clevelandindians"] <- "clevelandguardians"; x[x == "athleticsathletics"] <- "athletics"; x
}
key <- function(d, h, a, hs, as) paste(d, norm(h), norm(a), hs, as)
sk <- key(sched$Date, sched$home, sched$away, sched$hs, sched$as)
ok <- key(odds$odds_date, odds$home, odds$away, odds$hs, odds$as)
m <- match(sk, ok); m[sk %in% sk[duplicated(sk)] | sk %in% ok[duplicated(ok)]] <- NA
sv <- cbind(sched[!is.na(m), .(game_pk)], odds[m[!is.na(m)], .(p_close, p_close_s, p_open, p_open_s, z)])

# the published consensus, game by game: any drift in the parse or join stops here
mk <- fread("data/mlb/raw/odds/market-joined.csv")
mk <- mk[!(as.Date(Date) >= as.Date("2021-09-01") & as.Date(Date) <= as.Date("2021-12-31"))]
chk <- merge(mk[, .(game_pk, pc0 = p_close, po0 = p_open)], sv, by = "game_pk", all.x = TRUE)
stopifnot(!anyNA(chk$p_close), near(chk$p_close, chk$pc0, 1e-12),
          identical(is.na(chk$p_open), is.na(chk$po0)), near(na.omit(chk$p_open - chk$po0), 0, 1e-12))
SV <- merge(mk[, .(game_pk, med_home_open, med_away_open)], sv, by = "game_pk")

# --- 1. the forecast benchmark: closing log loss both ways ---------------------------------------------
rd <- function(f) { x <- fread(file.path("data/mlb/matchup", f)); x[, hometeam := substr(gid, 1, 3)]; x[] }
fc <- rbindlist(lapply(list(list("Validation 2021-2022", rd("predictions-v2-validation.csv")[season %in% 2021:2022]),
                            list("Test 2023-2025", rd("predictions-v2-test.csv"))), function(z) {
  x <- merge(z[[2]][!is.na(p_close) & !is.na(get(BEST))], SV[, .(game_pk, p_close_s)], by = "game_pk")
  cl <- paste(x$hometeam, x$season)
  gp <- cboot(ll(x$p_close, x$y) - ll(x[[BEST]], x$y), cl); gs <- cboot(ll(x$p_close_s, x$y) - ll(x[[BEST]], x$y), cl)
  data.table(period = z[[1]], n = nrow(x), close = mean(ll(x$p_close, x$y)), close_s = mean(ll(x$p_close_s, x$y)),
             m5 = mean(ll(x[[BEST]], x$y)), gp = gp[1], gp_lo = gp[2], gp_hi = gp[3], gs = gs[1], gs_lo = gs[2], gs_hi = gs[3])
}))
stopifnot(fc$n == c(4130, 6451), near(fc$close, c(0.6689, 0.6743), 6e-5), near(fc$m5[2], 0.6779, 6e-5))

# --- 2. bets at the open: CLV both ways, favourite vs underdog ------------------------------------------
open_bets <- function(x, prob, sel = "p_open") {   # prob = NULL bets home on every game
  if (is.null(prob)) side <- rep("h", nrow(x)) else {
    eh <- x[[prob]] - x[[sel]]; side <- ifelse(eh >= TAU, "h", ifelse(-eh >= TAU, "a", NA)) }
  b <- x[!is.na(side)]; h <- side[!is.na(side)] == "h"
  f <- function(p) ifelse(h, p, 1 - p)
  data.table(Date = b$Date, po = f(b$p_open), clv = f(b$p_close) - f(b$p_open), clv_s = f(b$p_close_s) - f(b$p_open_s),
             profit = ifelse(h == (b$y == 1), ifelse(h, b$med_home_open, b$med_away_open) - 1, -1))
}
LONG <- 0.35                                       # longshot: the side bet was under 35% at the proportional open
bet_rows <- function(b, label) rbindlist(lapply(c("all", "favourite", "underdog", "longshot"), function(g) {
  x <- switch(g, all = b, favourite = b[po > 0.5], underdog = b[po <= 0.5], longshot = b[po < LONG]); if (!nrow(x)) return(NULL)
  wk <- week(x$Date); cp <- cboot(x$clv, wk); cs <- cboot(x$clv_s, wk); ro <- cboot(x$profit, wk)
  data.table(set = label, side = g,
             bets = nrow(x), cp = 100 * cp[1], cp_lo = 100 * cp[2], cp_hi = 100 * cp[3],
             cs = 100 * cs[1], cs_lo = 100 * cs[2], cs_hi = 100 * cs[3], roi = ro[1], roi_lo = ro[2], roi_hi = ro[3])
}))
prep <- function(f, seasons) {
  x <- rd(f)[season %in% seasons & !is.na(p_close) & !is.na(get(BEST)) & !is.na(game_pk), !"p_close"]
  setorder(merge(x, SV, by = "game_pk")[!is.na(p_open)], Date, gid)[]
}
OV <- prep("predictions-v2-dayahead-validation.csv", 2021:2022)
OT <- prep("predictions-v2-dayahead-test.csv", 2023:2025)
OR <- prep("predictions-explore-rot-test.csv", 2023:2025)
bets <- rbindlist(list(
  bet_rows(open_bets(OV, BEST), "Validation 2021-2022: model"),
  bet_rows(open_bets(OT, BEST), "Test 2023-2025: model, MLB's listed starters"),
  bet_rows(open_bets(OR, BEST), "Test 2023-2025: model, starter guessed from rotation"),
  bet_rows(open_bets(OT, "C_team_only"), "Test 2023-2025: team run margin only"),
  bet_rows(open_bets(OT, NULL), "Test 2023-2025: every home team"),
  bet_rows(open_bets(OT, BEST, "p_open_s"), "Test 2023-2025: model, bets picked against the Shin open")))
lead <- bets[side == "all"]
stopifnot(lead[set %like% "listed", bets] == 561, near(lead[set %like% "listed", c(cp, cp_lo, cp_hi)], c(2.01, 1.67, 2.35), 0.006),
          lead[set %like% "rotation", bets] == 955, near(lead[set %like% "rotation", c(cp, cp_lo, cp_hi)], c(0.73, 0.53, 0.94), 0.006))

# --- write ------------------------------------------------------------------------------------------
f4 <- function(x) formatC(x, format = "f", digits = 4); f2 <- function(x) formatC(x, format = "f", digits = 2)
sg <- function(x, d = 2) paste0(ifelse(x >= 0, "+", ""), formatC(x, format = "f", digits = d))
ci <- function(e, l, h, d = 2) sprintf("%s [%s, %s]", sg(e, d), sg(l, d), sg(h, d))
pc <- function(x) paste0(ifelse(x >= 0, "+", ""), formatC(100 * x, format = "f", digits = 1), "%")
fav_gap <- SV[, .(fav_shift = mean(abs(pmax(p_close_s, 1 - p_close_s) - pmax(p_close, 1 - p_close))))]
out <- c(
  "# De-vig sensitivity: proportional vs Shin", "",
  "Generated by `Rscript research/r/mlb/devig_check.R`. Review queue item 3 in MATCHUP-PLAN.md. **Post hoc and",
  "exploratory**: the 2023-2025 test was already scored, and nothing here changes a model, the tau = 0.06 threshold",
  "or a published number. The consensus open and close are rebuilt from the per-book prices and match",
  "`market-joined.csv` game by game (to 1e-12) before anything is scored.", "",
  sprintf("Shin's insider share z averages %s on %s matched games; on the close, Shin moves the favourite's no-vig probability up by %s points on average. Closing book quotes with no margin (overround at or below 1), left proportional: %s of %s.",
          formatC(mean(SV$z), format = "f", digits = 4), format(nrow(SV), big.mark = ","), f2(100 * fav_gap$fav_shift),
          format(sum(bk$flat), big.mark = ","), format(nrow(bk), big.mark = ",")), "",
  "## 1. Forecast: model M5 against the closing line (log loss, lower is better)", "",
  "| period | games | close, proportional | close, Shin | M5 | M5 vs close, proportional | M5 vs close, Shin |",
  "| --- | --- | --- | --- | --- | --- | --- |",
  fc[, sprintf("| %s | %s | %s | %s | %s | %s | %s |", period, format(n, big.mark = ","), f4(close), f4(close_s), f4(m5),
               ci(gp, gp_lo, gp_hi, 4), ci(gs, gs_lo, gs_hi, 4))], "",
  "Gap = close minus M5 per game, so negative means the close is better; 95% home team-season cluster bootstrap (1,000 draws).", "",
  "## 2. Bets at the open: closing-line value both ways, by side", "",
  sprintf("Bets where the model is at least %d points off the no-vig open (frozen), at the median opening price. CLV in probability points; favourite = the side bet was above 50%% at the proportional open, longshot = under %d%% (a subset of underdog, where Shin's margin shift is largest).", round(100 * TAU), round(100 * LONG)), "",
  "| bets | side | n | CLV, proportional | CLV, Shin | ROI at median open |", "| --- | --- | --- | --- | --- | --- |",
  bets[, sprintf("| %s | %s | %s | %s | %s | %s |", set, side, format(bets, big.mark = ","), ci(cp, cp_lo, cp_hi), ci(cs, cs_lo, cs_hi),
                 sprintf("%s [%s, %s]", pc(roi), pc(roi_lo), pc(roi_hi)))], "",
  "Intervals: 95% week-block bootstrap (1,000 draws). The proportional column reproduces the published 561-bet and 955-bet figures exactly.", "",
  "Odds: SportsBookReview scrape, unlicensed, private research only; aggregates only.",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(out, file.path(SRC, "results", "devig-check.md"))
message(paste(out, collapse = "\n"))
