#!/usr/bin/env Rscript
# Conventional sabermetric baseline for the MLB game-winner model: the benchmark the matchup model
# (matchup_model.R) has to beat. Per game, as of the day before: each actual starter's ERA, FIP, xFIP
# and SIERA (overall, and by batter side weighted by the posted lineup), posted-lineup and team OPS and
# wOBA (lineup wOBA also vs the starter's hand), team relief FIP, team run margin, home field (the
# intercept). Weekly walk-forward logistics, scored on 2017-2022 next to the matchup model's saved
# validation predictions.
#
#   Rscript research/r/mlb/sabr_baseline.R          # writes results/sabr-baseline.md
#
# Reads Retrosheet 2015-2022 only: the 2023-2025 test seasons were scored once and are not touched.
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R")) source(file.path(SRC, f))
SEASONS <- 2015:2022; WALK <- 2017:2022
out_md <- file.path(SRC, "results", "sabr-baseline.md")

# Pitcher components per batter faced: half-life (in-season days) and season carry from the model's
# PIT_CFG in matchup.R (batted-ball types, outs and earned runs take its balls-in-play window); shrink
# constant in BF from the starter reliability study (results/reliability.md) where it has one, else a
# judgement call. All set before any fit and never tuned.
PCFG <- list(k = c(120, .75, 75), ubb = c(240, .75, 230), hbp = c(240, .75, 850), hr = c(240, .75, 800),
             gb = c(Inf, .5, 100), fb = c(Inf, .5, 100), pu = c(Inf, .5, 100),
             outs = c(Inf, .5, 500), er = c(Inf, .5, 1000))
BW <- c(Inf, .75)   # hitters: the model's window for hitters' balls in play (BAT_CFG), most of OPS and wOBA
TW <- c(120, .75)   # teams: the window of matchup_model.R's team run margin
K_BAT <- 300        # PA of league-average batting added to every hitter and team line
K_SPLIT_BAT <- 600; K_SPLIT_PIT <- 600   # handedness splits, as matchup_build.R

# --- plate appearances, with the sacrifice flags retro_pa() drops ---------------------------
P <- rbindlist(lapply(SEASONS, retro_pa))
sac <- rbindlist(lapply(SEASONS, function(s) {
  x <- fread(retro_file(s, "plays"), select = c("gid", "gametype", "pa", "walk", "iw", "sh", "sf"), showProgress = FALSE)
  x[gametype == "regular" & pa == 1 & !(walk == 1 & iw == 1), .(seq = seq_len(.N), sh, sf), by = gid]   # retro_pa()'s rows, same order
}))
n0 <- nrow(P); P <- merge(P, sac, by = c("gid", "seq")); stopifnot(nrow(P) == n0)
P[!pithand %in% c("L", "R"), pithand := "R"]
P[!bathand %in% c("L", "R", "B"), bathand := "R"]
# Retrosheet codes switch hitters "B" on nearly every PA; they bat from the side opposite the pitcher.
P[, side := fifelse(bathand == "B", fifelse(pithand == "L", "R", "L"), bathand)]
for (o in c("k", "ubb", "hbp", "single", "double", "triple", "hr")) set(P, j = o, value = as.numeric(P$outcome == o))
P[, `:=`(n = 1, gb = as.numeric(bb_type %in% "gb"), fb = as.numeric(bb_type %in% "fb"), pu = as.numeric(bb_type %in% "pu"))]
P[, `:=`(ab = n - ubb - hbp - sh - sf, h = single + double + triple + hr, tb = single + 2 * double + 3 * triple + 4 * hr)]
P[, wn := woba_num(list(hits = h, doubles = double, triples = triple, homeRuns = hr, baseOnBalls = ubb, intentionalWalks = 0, hitByPitch = hbp))]
P[, wd := woba_den(list(atBats = ab, baseOnBalls = ubb, intentionalWalks = 0, sacFlies = sf, hitByPitch = hbp))]
bounds <- as.data.frame(P[, .(start = min(Date), end = max(Date)), by = season])
P[, t := season_day(Date, season, bounds)]
G <- rbindlist(lapply(SEASONS, retro_games))
G[, t := season_day(Date, season, bounds)]

# --- pitcher-games: PA components from the play-by-play, outs and earned runs from the box lines --
PC <- c("n", "k", "ubb", "hbp", "hr", "gb", "fb", "pu"); PCO <- c(PC, "outs", "er")
pit <- rbindlist(lapply(SEASONS, function(s)
  fread(retro_file(s, "pitching"), select = c("gid", "id", "gametype", "stattype", "p_ipouts", "p_er"), showProgress = FALSE)[
    gametype == "regular" & stattype == "value", .(gid, pitcher = id, outs = p_ipouts, er = p_er)]))
first <- P[order(gid, seq)]
sp <- first[, .(sp = pitcher[1], sp_hand = pithand[1]), by = .(gid, pitteam)]       # who actually started
pg <- P[, lapply(.SD, sum), by = .(gid, Date, season, t, pitcher, team = pitteam), .SDcols = PC]
pg <- merge(pg, pit, by = c("gid", "pitcher"), all.x = TRUE)   # pitcher-games with no PA (a handful) drop out
pg[is.na(outs), `:=`(outs = 0L, er = 0L)]
pg[, starter := paste(gid, pitcher) %chin% paste(sp$gid, sp$sp)]
lgd <- pg[, lapply(.SD, sum), by = Date, .SDcols = PCO][, fbpu := fb + pu]

# FIP constant per season from league data: lgERA - (13 HR + 3 (uBB + HBP) - 2 K) / IP. Season S
# uses season S - 1's constant so nothing is read from the future (it cancels in every gap anyway).
core <- function(hr, ubb, hbp, k, outs) (13 * hr + 3 * (ubb + hbp) - 2 * k) / (outs / 3)
# SIERA, FanGraphs 2011 coefficients, without its year constant and starter-share term (see the report).
siera_raw <- function(so, bb, ng) 5.534 - 15.518 * so + 9.146 * so^2 + 8.648 * bb + 27.252 * bb^2 - 2.298 * ng -
  4.920 * sign(ng) * ng^2 - 4.036 * so * bb + 5.155 * so * ng + 4.546 * bb * ng
cfip <- pg[, .(era = 27 * sum(er) / sum(outs), core = core(sum(hr), sum(ubb), sum(hbp), sum(k), sum(outs)),
               sraw = siera_raw(sum(k) / sum(n), sum(ubb) / sum(n), (sum(gb) - sum(fb) - sum(pu)) / sum(n))), by = season][order(season)]
cfip[, c_own := era - core][, c_used := shift(c_own)][, s_own := era - sraw][, s_used := shift(s_own)]   # SIERA's yearly constant, same rule

# --- as-of machinery ------------------------------------------------------------------------
# Prior plus current season: a query in season S sees events from S - 1 and S only, decayed by
# asof_decay() (windows.R), so nothing dated on or after the game's date is ever read.
asof2 <- function(ev, q, cols, h, c) {
  out <- matrix(0, nrow(q), length(cols), dimnames = list(NULL, cols))
  for (s in unique(q$season)) {
    i <- which(q$season == s)
    out[i, ] <- asof_decay(ev[ev$season %in% c(s - 1, s), , drop = FALSE], q[i, , drop = FALSE], cols, h, c)
  }
  out
}
# League rate as of each query date for that query's own key (handedness pair), trailing 365 days.
lg_key <- function(D, key, num, den, d) {
  out <- numeric(length(d))
  for (kk in unique(key)) { i <- key == kk; out[i] <- league_rate(D[D$key == kk], num, den, d[i]) }   # not `k`: a column of D
  out
}
# Every pitcher component per BF, decayed at its window and shrunk toward the league rate.
pit_rates <- function(ev, q) sapply(names(PCFG), function(x) {
  w <- PCFG[[x]]; s <- asof2(ev, q, c(x, "n"), w[1], w[2])
  (s[, 1] + w[3] * league_rate(lgd, x, "n", q$Date)) / (s[, 2] + w[3])
})
# ERA, FIP, xFIP and SIERA from per-BF rates (IP per BF = outs / 3).
pstats <- function(r, q) {
  cf <- cfip$c_used[match(q$season, cfip$season)]; cs <- cfip$s_used[match(q$season, cfip$season)]
  hrfb <- league_rate(lgd, "hr", "fbpu", q$Date)              # league HR per fly ball (popups count as flies)
  so <- r[, "k"]; bb <- r[, "ubb"]; ng <- r[, "gb"] - r[, "fb"] - r[, "pu"]
  data.table(era = 27 * r[, "er"] / r[, "outs"],
             fip = core(r[, "hr"], bb, r[, "hbp"], so, r[, "outs"]) + cf,
             xfip = core((r[, "fb"] + r[, "pu"]) * hrfb, bb, r[, "hbp"], so, r[, "outs"]) + cf,
             siera = siera_raw(so, bb, ng) + cs)
}
HC <- c("n", "ab", "h", "tb", "ubb", "hbp", "sf", "wn", "wd")
lgb <- P[, lapply(.SD, sum), by = Date, .SDcols = HC]
# OPS and wOBA from a decayed batting line plus K_BAT PA of league-average batting.
bat_stats <- function(ev, q, w) {
  s <- asof2(ev, q, HC, w[1], w[2])
  for (x in HC) s[, x] <- s[, x] + K_BAT * league_rate(lgb, x, "n", q$Date)
  obp <- (s[, "h"] + s[, "ubb"] + s[, "hbp"]) / (s[, "ab"] + s[, "ubb"] + s[, "hbp"] + s[, "sf"])
  data.table(ops = obp + s[, "tb"] / s[, "ab"], woba = s[, "wn"] / s[, "wd"])
}

# --- games, starters, lineups -----------------------------------------------------------------
GS <- G[season >= 2016 & hruns != vruns, .(gid, Date, season, t, hometeam, visteam, y = as.integer(hruns > vruns))]
GS <- merge(GS, sp[, .(gid, hometeam = pitteam, sp_h = sp, hand_h = sp_hand)], by = c("gid", "hometeam"))
GS <- merge(GS, sp[, .(gid, visteam = pitteam, sp_a = sp, hand_a = sp_hand)], by = c("gid", "visteam"))
sq <- rbind(GS[, .(gid, side = "h", entity = sp_h, hand = hand_h, Date, season, t)],
            GS[, .(gid, side = "a", entity = sp_a, hand = hand_a, Date, season, t)])
bq <- rbind(GS[, .(gid, side = "h", entity = hometeam, Date, season, t)],
            GS[, .(gid, side = "a", entity = visteam, Date, season, t)])          # same row order as sq
lineup <- first[, .SD[!duplicated(batter)][1:9], by = .(gid, batteam), .SDcols = c("batter", "bathand")][!is.na(batter)]
LQ <- merge(lineup, GS[, .(gid, Date, season, t, hometeam, hand_h, hand_a)], by = "gid")
LQ[, side := fifelse(batteam == hometeam, "h", "a")][, opp_hand := fifelse(side == "h", hand_a, hand_h)]
LQ[, vs_side := fifelse(bathand == "B", fifelse(opp_hand == "L", "R", "L"), bathand)]
message("games ", nrow(GS), ", lineup slots ", nrow(LQ))

# --- starters, bullpens, lineups, teams -------------------------------------------------------
pev <- as.data.frame(pg[, lapply(.SD, sum), by = .(entity = pitcher, Date, season, t), .SDcols = PCO])
R_sp <- pit_rates(pev, as.data.frame(sq))
ST <- pstats(R_sp, sq)
rev <- as.data.frame(pg[starter == FALSE, lapply(.SD, sum), by = .(entity = team, Date, season, t), .SDcols = PCO])
PEN <- pstats(pit_rates(rev, as.data.frame(bq)), bq)
bev <- as.data.frame(P[, lapply(.SD, sum), by = .(entity = batter, Date, season, t), .SDcols = HC])
LQ <- cbind(LQ, bat_stats(bev, as.data.frame(LQ[, .(entity = batter, Date, season, t)]), BW))
tev <- as.data.frame(P[, lapply(.SD, sum), by = .(entity = batteam, Date, season, t), .SDcols = HC])
TS <- bat_stats(tev, as.data.frame(bq), TW)
message("overall stats done")

# --- handedness splits (S5) ---------------------------------------------------------------------
# Starter vs each batter side: each component shrunk toward his overall shrunk rate times the league
# platoon ratio for his hand (league rate vs that side / league rate for that pitcher hand), K_SPLIT_PIT
# BF; IP per BF stays his overall. Then weighted by the opposing posted lineup's sides against him.
psev <- as.data.frame(P[, lapply(.SD, sum), by = .(entity = paste(pitcher, side), Date, season, t), .SDcols = PC])
lgPair <- P[, lapply(.SD, sum), by = .(Date, key = paste(pithand, side)), .SDcols = PC]
lgHand <- P[, lapply(.SD, sum), by = .(Date, key = pithand), .SDcols = PC]
split_stats <- function(bs) {
  q <- data.frame(entity = paste(sq$entity, bs), Date = sq$Date, season = sq$season, t = sq$t)
  r <- R_sp
  for (x in setdiff(PC, "n")) {
    w <- PCFG[[x]]; s <- asof2(psev, q, c(x, "n"), w[1], w[2])
    ratio <- lg_key(lgPair, paste(sq$hand, bs), x, "n", sq$Date) / lg_key(lgHand, sq$hand, x, "n", sq$Date)
    r[, x] <- (s[, 1] + K_SPLIT_PIT * R_sp[, x] * ratio) / (s[, 2] + K_SPLIT_PIT)
  }
  pstats(r, sq)
}
SL <- split_stats("L"); SR <- split_stats("R")
mix <- LQ[, .(fracL = mean(vs_side == "L")), by = .(gid, side)]
fl <- mix$fracL[match(paste(sq$gid, ifelse(sq$side == "h", "a", "h")), paste(mix$gid, mix$side))]
stopifnot(!anyNA(fl))
for (v in c("fip", "xfip", "siera")) ST[[paste0(v, "_s")]] <- fl * SL[[v]] + (1 - fl) * SR[[v]]
# Hitter vs the starter's hand: shrunk toward his overall wOBA times the league ratio for his batting
# type (L, R or switch) vs that hand, K_SPLIT_BAT PA.
hsev <- as.data.frame(P[, .(wn = sum(wn), wd = sum(wd)), by = .(entity = paste(batter, pithand), Date, season, t)])
hs <- asof2(hsev, data.frame(entity = paste(LQ$batter, LQ$opp_hand), Date = LQ$Date, season = LQ$season, t = LQ$t), c("wn", "wd"), BW[1], BW[2])
lgW <- P[, .(wn = sum(wn), wd = sum(wd)), by = .(Date, key = paste(bathand, pithand))]
lgWt <- P[, .(wn = sum(wn), wd = sum(wd)), by = .(Date, key = bathand)]
ratio <- lg_key(lgW, paste(LQ$bathand, LQ$opp_hand), "wn", "wd", LQ$Date) / lg_key(lgWt, LQ$bathand, "wn", "wd", LQ$Date)
LQ[, woba_s := (hs[, "wn"] + K_SPLIT_BAT * woba * ratio) / (hs[, "wd"] + K_SPLIT_BAT)]
message("splits done")

# --- per-game gaps, home minus away -----------------------------------------------------------
X <- data.table(sq[, .(gid, side)], ST, pen_fip = PEN$fip, t_ops = TS$ops, t_woba = TS$woba)
X <- merge(X, LQ[, .(lu_ops = mean(ops), lu_woba = mean(woba), lu_woba_s = mean(woba_s)), by = .(gid, side)], by = c("gid", "side"))
VARS <- setdiff(names(X), c("gid", "side"))
W <- merge(X[side == "h"], X[side == "a"], by = "gid", suffixes = c("_h", "_a"))
for (v in VARS) W[[paste0("d_", v)]] <- W[[paste0(v, "_h")]] - W[[paste0(v, "_a")]]
F <- merge(GS, W[, c("gid", paste0("d_", VARS)), with = FALSE], by = "gid")
# sanity: league-typical levels (a broken formula or join lands far outside these)
stopifnot(all(between(X[, sapply(.SD, median), .SDcols = c("era", "fip", "xfip", "siera", "pen_fip")], 3.3, 5.2)),
          between(median(X$lu_woba), 0.28, 0.36), between(median(X$t_ops), 0.65, 0.80))

# Team run margin, exactly matchup_model.R's drd (h = 120, carry 0.75, shrunk with 5 games).
tm <- rbind(G[, .(team = hometeam, Date, season, t, margin = hruns - vruns)], G[, .(team = visteam, Date, season, t, margin = vruns - hruns)])[, n := 1]
rdx <- function(team) {
  s <- asof_decay(transform(as.data.frame(tm), entity = team), data.frame(entity = team, Date = F$Date, season = F$season, t = F$t), c("margin", "n"), h = 120, c = 0.75)
  s[, 1] / (s[, 2] + 5)
}
F[, drd := rdx(hometeam) - rdx(visteam)]
setorder(F, Date, gid)

# --- walk-forward, as matchup_model.R: weekly blocks, each fit on every game dated before it ----
walk <- function(df, formula, seasons) {
  df$block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% seasons]))) {
    i <- which(df$block == b & df$season %in% seasons)
    m <- stats::glm(formula, stats::binomial, df[df$Date < b, ])
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}
FORMS <- list(
  S1_era_ops        = y ~ d_era + d_t_ops,
  S2_fip_woba_pen   = y ~ d_fip + d_lu_woba + d_pen_fip,
  S3_siera_xfip     = y ~ d_siera + d_xfip + d_lu_woba + d_pen_fip,
  S4_plus_team      = y ~ d_siera + d_xfip + d_lu_woba + d_pen_fip + drd,
  S5_splits         = y ~ d_siera_s + d_xfip_s + d_lu_woba_s + d_pen_fip + drd)
SM <- names(FORMS)
for (nm in SM) F[[nm]] <- walk(F, FORMS[[nm]], WALK)
F$C_chk <- walk(F, y ~ drd, WALK)          # the matchup model's team-only model, to check drd and the loop
coefs <- lapply(FORMS, function(f) round(stats::coef(stats::glm(f, stats::binomial, F[season <= 2022])), 3))
fwrite(F[season %in% WALK, c("gid", "Date", "season", "y", SM), with = FALSE], "data/mlb/matchup/sabr-predictions-validation.csv")

# --- score next to the matchup model's saved validation predictions -----------------------------
MP <- fread("data/mlb/matchup/predictions-v2-validation.csv")
mm <- setdiff(names(MP), c("gid", "game_pk", "Date", "season", "y", "p_close"))
MP <- MP[season %in% WALK][complete.cases(MP[season %in% WALK, mm, with = FALSE])]   # the frozen table's games
D <- merge(MP[, c("gid", "season", "y", mm, "p_close"), with = FALSE], F[, c("gid", "y", SM, "C_chk"), with = FALSE], by = "gid", suffixes = c("", "_s"))
stopifnot(all(D$y == D$y_s), !anyNA(D[, SM, with = FALSE]))
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
REF <- c("M5_plus_defense", "ENS", "E_recency", "C_team_only", "B_home")
cols <- c(SM, REF)
tab <- rbindlist(lapply(c(sort(unique(D$season)), 0L), function(s) {
  x <- if (s == 0) D else D[season == s]
  c(list(season = if (s == 0) "pooled" else as.character(s), games = nrow(x)), lapply(setNames(cols, cols), function(m) round(mean(ll(x[[m]], x$y)), 4)))
}))
stopifnot(nrow(D) == 12142, abs(tab[season == "pooled", M5_plus_defense] - 0.6703) < 1e-9)   # reproduces the frozen M5 number
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
cl <- paste(substr(D$gid, 1, 3), D$season)                                         # home team-season, as matchup_model.R
vsM5 <- t(sapply(SM, function(m) paired(ll(D[[m]], D$y) - ll(D$M5_plus_defense, D$y), cl)))
s5s4 <- paired(ll(D$S5_splits, D$y) - ll(D$S4_plus_team, D$y), cl)
best <- SM[which.min(unlist(tab[season == "pooled", SM, with = FALSE]))]
c_diff <- max(abs(D$C_chk - D$C_team_only))
M <- D[season %in% 2021:2022 & !is.na(p_close)]
gap_b <- paired(ll(M[[best]], M$y) - ll(M$p_close, M$y), paste(substr(M$gid, 1, 3), M$season))
gap_m <- paired(ll(M$M5_plus_defense, M$y) - ll(M$p_close, M$y), paste(substr(M$gid, 1, 3), M$season))
mt <- M[, c(list(games = .N, close = mean(ll(p_close, y)), M5 = mean(ll(M5_plus_defense, y))), setNames(list(mean(ll(get(best), y))), best)), by = season][order(season)]

# --- report -----------------------------------------------------------------------------------
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
iv <- function(v, d = 4) sprintf("%s%s [%s, %s]", ifelse(v[1] >= 0, "+", ""), fmt(v[1], d), fmt(v[2], d), fmt(v[3], d))
md_tab <- function(d) c(paste0("| ", paste(names(d), collapse = " | "), " |"), paste0("|", strrep(" --- |", ncol(d))),
                        apply(d, 1, function(r) paste0("| ", paste(trimws(r), collapse = " | "), " |")))
pv <- function(m) unlist(tab[season == "pooled", m, with = FALSE])
bs <- tab[season != "pooled"]
wins <- sum(bs$M5_plus_defense < bs[[best]]); ties <- sum(bs$M5_plus_defense == bs[[best]])
share <- (pv("B_home") - pv(best)) / (pv("B_home") - pv("M5_plus_defense"))
verdict <- c(
  sprintf("**%s** The best conventional model (%s: starter SIERA and xFIP, posted-lineup wOBA, bullpen FIP, team run margin, home field) scores %s pooled against M5's %s; it covers %s%% of the distance from home-only (%s) to M5. M5 is ahead in %d of %d seasons%s.",
          if (vsM5[best, 2] < 0) sprintf("The matchup model is ahead of a conventional sabermetric baseline by about %s log loss, an edge the interval cannot separate from zero.", fmt(vsM5[best, 1], 3))
          else sprintf("The matchup model beats a conventional sabermetric baseline by about %s log loss, and the interval excludes zero.", fmt(vsM5[best, 1], 3)),
          best, fmt(pv(best)), fmt(pv("M5_plus_defense")),
          round(100 * share), fmt(pv("B_home")), wins, nrow(bs), if (ties) sprintf(" (tied in %d)", ties) else ""), "",
  sprintf("- What the matchup structure adds (per-outcome matchups, parks, times through the order, bullpen availability, defense) over the stats an analyst reaches for first is %s: %s for %s, %s for S5.", if (vsM5[best, 2] < 0) "positive but small, and six validation seasons cannot separate it from zero" else "small but separated from zero", iv(vsM5[best, ], 5), best, iv(vsM5["S5_splits", ], 5)),
  sprintf("- ERA plus team OPS (S1) is clearly worse (%s vs M5). The conventional skill comes from FIP-family pitching, lineup wOBA and the run margin, not from ERA.", iv(vsM5["S1_era_ops", ], 5)),
  sprintf("- SIERA and xFIP do no better than plain FIP here (S3 %s vs S2 %s pooled); one candidate cause is Retrosheet's 2020 batted-ball recoding, which their fly-ball and popup counts straddle.", fmt(pv("S3_siera_xfip")), fmt(pv("S2_fip_woba_pen"))),
  sprintf("- Handedness splits add nothing measurable: S5 minus S4 %s.", iv(s5s4, 5)),
  sprintf("- Against the close (2021-2022), %s trails by %s (interval %s zero) and M5 by %s (%s zero): the matchup model sits about %s closer to the market.", best, iv(gap_b, 5), if (gap_b[2] > 0) "excludes" else "includes", iv(gap_m, 5), if (gap_m[2] > 0) "excludes" else "includes", fmt(gap_b[1] - gap_m[1], 4)),
  "- Selection runs both ways and leans toward M5: M5 was picked among matchup variants on these seasons and its components were ablated here, while the S recipe was fixed before any fit and never tuned (only the choice of the best of five S models used these seasons). A tuned conventional model would likely narrow the gap, not widen it.")
lv <- X[, lapply(.SD, function(v) fmt(median(v), 3)), .SDcols = c("era", "fip", "xfip", "siera", "pen_fip", "lu_ops", "lu_woba", "t_ops", "t_woba")]
pooled <- unlist(tab[season == "pooled", cols, with = FALSE])
lines <- c("# Conventional sabermetric baseline vs the matchup model (validation, 2017-2022)", "",
"The information used here was obtained free of charge from and is copyrighted by Retrosheet.",
"Interested parties may contact Retrosheet at \"www.retrosheet.org\".", "",
sprintf("Generated %s by [`sabr_baseline.R`](../sabr_baseline.R). Validation seasons only: Retrosheet 2015-2022 is the only data read, nothing from the 2023-2025 test seasons. Odds appear only as `p_close` from the matchup model's saved predictions, 2021-2022, aggregates only.", format(Sys.Date())), "",
"## Question", "",
"How much of the matchup model's skill would a conventional sabermetric game model, built from the stats an analyst would reach for first (ERA, FIP, xFIP, SIERA, OPS, wOBA, bullpen FIP, run margin), already capture?", "",
"## Answer", "",
sprintf("- Pooled log loss on the frozen table's %s games: %s.", format(nrow(D), big.mark = ","),
        paste(sprintf("%s %s", sub("_.*", "", SM), fmt(pooled[SM])), collapse = ", ")),
sprintf("- Matchup model on the same games: M5 %s, ensemble %s, recency E %s, team-only %s, home-only %s (all reproduce `matchup-model-v2-validation.md`).",
        fmt(pooled["M5_plus_defense"]), fmt(pooled["ENS"]), fmt(pooled["E_recency"]), fmt(pooled["C_team_only"]), fmt(pooled["B_home"])),
"- Each S model minus M5, per-game log loss, home team-season block bootstrap 95% (positive = S worse):",
sprintf("  - %s: %s", SM, apply(vsM5, 1, iv, d = 5)),
sprintf("- Handedness splits over S4 (S5 minus S4): %s.", iv(s5s4, 5)),
sprintf("- Best S model (%s) against the no-vig close, 2021-2022, %s games, S minus close: %s (M5 minus close on the same games: %s). Positive = trails the close.",
        best, format(nrow(M), big.mark = ","), iv(gap_b, 5), iv(gap_m, 5)), "",
"## Log loss by season (lower is better)", "",
"2020 is scored by neither: the frozen matchup table drops it because the recency model has no 2020 predictions. Every model here is still walked through 2020 and trains on it.", "",
md_tab(tab), "",
"## Against the no-vig close (2021-2022)", "",
md_tab(mt[, lapply(.SD, function(v) if (is.numeric(v) && !is.integer(v)) fmt(v) else v)]), "",
sprintf("%s minus close: %s. M5 minus close: %s. Positive = trails the close.", best, iv(gap_b, 5), iv(gap_m, 5)), "",
"## Models", "",
"Weekly walk-forward logistic regressions of home win, the same loop as `matchup_model.R`: for each calendar week of 2017-2022, fit on every game (2016 on) dated before the week, predict the week. Home field is the intercept. Every gap is home minus away. Ties dropped.", "",
"| model | terms | coefficients fit on 2016-2022 (descriptive only) |", "| --- | --- | --- |",
sprintf("| %s | %s | %s |", SM, vapply(FORMS, function(f) paste(deparse(f[[3]]), collapse = ""), ""),
        vapply(coefs, function(b) paste(sprintf("%s %s", names(b), b), collapse = ", "), "")), "",
"- `d_era`, `d_fip`, `d_xfip`, `d_siera`: home starter minus away starter. `_s`: the split version (below).",
sprintf("- Check: refitting the matchup model's team-only model (y ~ drd) with this script's drd and walk-forward loop reproduces its saved predictions to a maximum absolute difference of %s.", formatC(c_diff, format = "g", digits = 2)),
"- `d_t_ops`: team OPS. `d_lu_woba`: posted-lineup wOBA (mean of the nine). `d_pen_fip`: team relief FIP. `drd`: team run margin per game, exactly `matchup_model.R`'s (decayed h = 120, carry 0.75, shrunk with 5 games).", "",
"## Inputs, all as of the day before the game", "",
"- **Who:** each team's actual starter (first pitcher in the Retrosheet play-by-play) and posted lineup (first nine batters), as `matchup_build.R`. Relief = every other pitcher-game for that team.",
"- **Window:** prior plus current season only. Within that, `asof_decay()` (windows.R), the model's recency weighting: weight 0.5^(in-season days / h) times carry^(seasons back). A query on date d reads events dated d - 1 or earlier, so doubleheader game 2 never sees game 1.",
"- **Pitcher components** per batter faced, each decayed at its own window and shrunk toward the trailing-365-day league rate by adding k BF of league average, then combined into the stat (so shrinkage happens where the reliability is measured):", "",
"| component | half-life (in-season days) | carry | k (BF) | k source |", "| --- | --- | --- | --- | --- |",
sprintf("| %s | %s | %s | %s | %s |", names(PCFG), vapply(PCFG, `[`, 0, 1), vapply(PCFG, `[`, 0, 2), vapply(PCFG, `[`, 0, 3),
        c("reliability.md starters (73-76)", "reliability.md (216-241)", "reliability.md (839-880)", "reliability.md (743-897)",
          "reliability.md ground-ball share 63 batted balls", "judgement, near the hitter fly and popup shares (84-92 batted balls)", "same", "judgement", "judgement (ERA is the slowest to settle)")), "",
"  Windows: K, BB, HBP and HR are the model's `PIT_CFG` windows; batted-ball types, outs and earned runs take its balls-in-play window. Bullpens use the same components with the team as the entity.",
sprintf("- **Hitters and teams:** batting line decayed (hitters h = %s, carry %s, the model's balls-in-play window for hitters; teams h = %s, carry %s, the run-margin window), plus %d PA of league-average batting, then OPS and wOBA from the augmented line.", BW[1], BW[2], TW[1], TW[2], K_BAT),
"- **League rates:** trailing 365 days of every PA, as of the query date.",
sprintf("- **Median levels across starters and sides** (sanity): ERA %s, FIP %s, xFIP %s, SIERA %s, bullpen FIP %s; lineup OPS %s, lineup wOBA %s, team OPS %s, team wOBA %s.",
        lv$era, lv$fip, lv$xfip, lv$siera, lv$pen_fip, lv$lu_ops, lv$lu_woba, lv$t_ops, lv$t_woba), "",
"## Formulas", "",
"Rates below are per batter faced after shrinkage; IP = outs / 3 from the Retrosheet box lines. uBB = unintentional walks: `retro.R` drops intentional walks from the plate appearances, so every BB here is unintentional and BF / PA exclude them.", "",
"- **ERA** = 9 ER / IP (earned runs from the Retrosheet pitching lines).",
"- **FIP** = (13 HR + 3 (uBB + HBP) - 2 K) / IP + C. C for season S = lgERA - (13 lgHR + 3 (lguBB + lgHBP) - 2 lgK) / lgIP from season S - 1 (strictly prior; it is common to both starters, so it cancels in every gap). Source: FanGraphs Library, FIP, https://library.fangraphs.com/pitching/fip/ (Tom Tango, from Voros McCracken's DIPS work).",
"- **xFIP** = (13 (FB + PU) lgHR/FB + 3 (uBB + HBP) - 2 K) / IP + C, lgHR/FB = league HR / (FB + PU) over the trailing 365 days. Source: FanGraphs Library, xFIP, https://library.fangraphs.com/pitching/xfip/ (Dave Studeman).",
"- **SIERA** (FanGraphs 2011 coefficients) = 5.534 - 15.518 K/PA + 9.146 (K/PA)^2 + 8.648 BB/PA + 27.252 (BB/PA)^2 - 2.298 nGB/PA - 4.920 sign(nGB) (nGB/PA)^2 - 4.036 (K/PA)(BB/PA) + 5.155 (K/PA)(nGB/PA) + 4.546 (BB/PA)(nGB/PA), nGB = GB - FB - PU, PA = batters faced. The squared term follows the source's sign rule (\"+/-\" with coefficient -4.920). The published year constants and the 0.367 x share-of-innings-as-starter term are replaced by one constant per season, set so the league-average rates of season S - 1 give that season's league ERA (FanGraphs re-sets SIERA's constant yearly to the run environment); it is common to both starters and cancels in the gap. Source: Matt Swartz, \"New SIERA, Part Two (of Five)\", FanGraphs, 2011-07-19, https://blogs.fangraphs.com/new-siera-part-two-of-five-unlocking-underrated-pitching-skills/ (original SIERA: Swartz and Eric Seidman, Baseball Prospectus, 2010).",
"- **wOBA** = (0.69 uBB + 0.72 HBP + 0.88 1B + 1.25 2B + 1.58 3B + 2.03 HR) / (AB + uBB + SF + HBP), the fixed weights already in `windows.R` (FanGraphs Library, wOBA, https://library.fangraphs.com/offense/woba/; Tom Tango, *The Book*). Fixed across seasons; the season-to-season weight drift is common to both teams.",
"- **OPS** = OBP + SLG, OBP = (H + uBB + HBP) / (AB + uBB + HBP + SF), SLG = TB / AB, AB = PA - uBB - HBP - SH - SF (sacrifice flags read from the Retrosheet plays file).", "",
"FIP and SIERA constants (the constant used for season S comes from S - 1):", "",
md_tab(cfip[season >= 2016, .(season, FIP_C_own_season = fmt(c_own, 3), FIP_C_used = fmt(c_used, 3), SIERA_C_used = fmt(s_used, 3), lgERA_prior_season = fmt(shift(cfip$era)[match(season, cfip$season)], 3))]), "",
"## Handedness splits (S5)", "",
sprintf("- **Starter:** every component vs left- and right-handed batters, each shrunk with %d BF toward his overall shrunk rate times the league platoon ratio for his throwing hand (league rate vs that batter side / league rate for that pitcher hand), the side-specific prior idea of `matchup_build.R`. IP per BF stays his overall rate (outs come from the box lines, which have no batter-side split). FIP, xFIP and SIERA vs each side, then weighted by the share of the opposing posted lineup batting from that side; switch hitters bat opposite the pitcher.", K_SPLIT_PIT),
sprintf("- **Lineup:** each hitter's wOBA vs the starter's throwing hand, shrunk with %d PA toward his overall wOBA times the league ratio for his batting type (left, right or switch) vs that hand.", K_SPLIT_BAT),
"- **Switch hitters:** Retrosheet codes them `B` on nearly every PA (21,325 to 22,771 PAs in each of 2015, 2019 and 2022, the seasons checked), not the side they batted from. Here a `B` PA counts as batting opposite the pitcher. `matchup_build.R` maps `B` to `R`, so the matchup model rates every switch hitter as a right-handed batter, including against right-handed pitchers; worth a look by whoever owns that file.", "",
"## Limits", "",
"- Shrink constants and windows were set once, before any fit, and never tuned; a tuned baseline could do somewhat better. The comparison is a fixed recipe against the matchup model's chosen variant.",
"- No park adjustment: conventional ERA, FIP and OPS are not park-neutral (the matchup model neutralises parks).",
"- Retrosheet's batted-ball coding changed in 2020 (popups 0.2-1.2% of balls in play before, about 7% after; fly balls down, liners up). xFIP and SIERA counts span the change in 2020-2021; league rates are trailing, so they adapt within a season.",
"- Unintentional walks only (intentional walks are dropped upstream), so FIP and SIERA differ slightly from FanGraphs' published values.", "",
"## Verdict", "",
verdict, "",
"The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, out_md)
print(tab); print(vsM5); print(s5s4); print(gap_b); print(gap_m); print(coefs); print(lv)
message("wrote ", out_md)
