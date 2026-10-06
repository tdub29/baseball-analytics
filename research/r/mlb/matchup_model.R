#!/usr/bin/env Rscript
# Matchup model: expected runs per side from the matchup features, then a weekly walk-forward
# logistic to a win probability, scored against outcomes and the closing line (MATCHUP-PLAN.md).
#
#   Rscript research/r/mlb/matchup_model.R validation    # 2017-2022 outcomes, 2021-2022 vs market
#   Rscript research/r/mlb/matchup_model.R test          # 2023-2025, scored once
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("ingest.R", "gamelogs.R", "windows.R", "retro.R", "matchup.R")) source(file.path(SRC, f))
mode <- commandArgs(TRUE)[1]; stopifnot(mode %in% c("validation", "test"))
TAG <- Sys.getenv("OUT_TAG", "")                       # e.g. "-dayahead" for projected-lineup features
RECAL <- Sys.getenv("RECAL", "0") == "1"               # 1: recalibrate the best variant on its 2017-2020 walk-forward predictions
out_md <- file.path(SRC, "results", sprintf("matchup-model%s-%s.md", TAG, mode))
if (mode == "test" && file.exists(out_md) && !"--force" %in% commandArgs(TRUE)) stop(out_md, " exists: scored once.")
PRED <- if (mode == "test") 2023:2025 else 2017:2022
MKT_VAL <- 2021:2022

F <- readRDS(Sys.getenv("FEAT_IN", "data/mlb/matchup/features.rds"))
# Features built with ASOF_LAG = 1 carry it as an attribute; the team inputs below (run margin,
# defensive efficiency, the walk-forward fit) then stop two days before each game as well.
LAG <- as.integer(Sys.getenv("ASOF_LAG", if (is.null(attr(F, "asof_lag"))) "0" else attr(F, "asof_lag")))
G <- rbindlist(lapply(2015:2025, retro_games))

# --- run values per outcome, fit on 2015-2016 team-games only -----------------------------
rv_fit <- {
  P <- rbindlist(lapply(2015:2016, retro_pa))
  P <- outcome_matrix(P)
  tg <- P[, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
  stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg)        # out_ip is the base, absorbed in the intercept
}
rv <- c(stats::coef(rv_fit)[OUT8[OUT8 != "out_ip"]], out_ip = 0)
runs_of <- function(prefix, side) as.matrix(F[, paste0(prefix, "_", OUT8, "_", side), with = FALSE]) %*% rv[OUT8]
for (s in c("home", "away")) for (p in c("sp12", "sp3", "pen")) F[[paste0("r_", p, "_", s)]] <- as.numeric(runs_of(p, s))
F[, d12 := r_sp12_home - r_sp12_away][, d3 := r_sp3_home - r_sp3_away][, dpen := r_pen_home - r_pen_away]
F[, rh := r_sp12_home + r_sp3_home + r_pen_home][, ra := r_sp12_away + r_sp3_away + r_pen_away]

# --- team strength residual (run margin, recency window) and rest/travel -------------------
tm <- rbind(G[, .(team = hometeam, gid, Date, season, margin = hruns - vruns, site)],
            G[, .(team = visteam, gid, Date, season, margin = vruns - hruns, site)])
bounds <- tm[, .(start = min(Date), end = max(Date)), by = season]
tm[, t := season_day(Date, season, as.data.frame(bounds))][, n := 1]
tq <- function(team) data.frame(entity = team, Date = F$Date - LAG, season = F$season, t = season_day(F$Date - LAG, F$season, as.data.frame(bounds)))
rdx <- function(team) { s <- asof_decay(transform(as.data.frame(tm), entity = team), tq(team), c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
F[, drd := rdx(hometeam) - rdx(visteam)]
setorder(tm, team, Date, gid)
tm[, `:=`(rest = pmin(as.numeric(Date - shift(Date)), 3), moved = as.numeric(site != shift(site))), by = team]
tm[is.na(rest), rest := 3][is.na(moved), moved := 0]
F <- merge(F, tm[, .(gid, hometeam = team, rest_h = rest, moved_h = moved)], by = c("gid", "hometeam"))
F <- merge(F, tm[, .(gid, visteam = team, rest_a = rest, moved_a = moved)], by = c("gid", "visteam"))
F[, drest := rest_h - rest_a][, dmoved := moved_h - moved_a]
ctx <- readRDS("data/mlb/matchup/context.rds")[, .(gid, dder)]      # team defensive efficiency gap (context_features.R)
if (LAG > 0) ctx <- der_gap(F[, .(gid, Date, season, hometeam, visteam)], LAG)   # same definition, LAG days earlier
F <- merge(F, ctx, by = "gid", all.x = TRUE); F[is.na(dder), dder := 0]
F[, y := as.integer(hruns > vruns)]
F <- F[hruns != vruns]
setorder(F, Date, gid)

# --- walk-forward ---------------------------------------------------------------------------
walk <- function(df, formula, seasons) {
  df$block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% seasons]))) {
    i <- which(df$block == b & df$season %in% seasons)
    m <- stats::glm(formula, stats::binomial, df[df$Date < b - LAG, ])
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}
F[, lr := log(rh / ra)]
FORMS <- list(
  M1_runs_ratio   = y ~ lr,
  M2_components   = y ~ d12 + d3 + dpen,
  M3_plus_team    = y ~ d12 + d3 + dpen + drd,
  M4_plus_rest    = y ~ d12 + d3 + dpen + drd + drest + dmoved,
  M5_plus_defense = y ~ d12 + d3 + dpen + drd + dder,
  B_home          = y ~ 1,
  C_team_only     = y ~ drd)
# Test mode also predicts 2017-2022 (walk-forward, identical to validation) so every choice below
# is made on validation seasons and frozen before a test row is scored.
WALK <- 2017:(if (mode == "test") 2025L else 2022L)
for (nm in names(FORMS)) F[[nm]] <- walk(F, FORMS[[nm]], WALK)

# --- join to StatsAPI games, the recency model and the market --------------------------------
gl <- gamelog_sources("data/mlb/raw"); cs <- cached_sources("data/mlb/raw")
sch <- rbindlist(lapply(2016:2025, function(s) {
  win <- season_window(s, fetch = cs$seasons)
  x <- as.data.table(gl$schedule(as.character(win$start), as.character(win$end)))
  x[, .(game_pk, Date, home_id, away_id, home_score, away_score)]
}))
cand <- merge(F[, .(gid, Date, hometeam, visteam, hruns, vruns)], sch, by.x = c("Date", "hruns", "vruns"),
              by.y = c("Date", "home_score", "away_score"))
hmap <- cand[, .N, by = .(hometeam, home_id)][order(-N)][!duplicated(hometeam)]
amap <- cand[, .N, by = .(visteam, away_id)][order(-N)][!duplicated(visteam)]
cand <- merge(merge(cand, hmap[, .(hometeam, hid = home_id)], by = "hometeam"), amap[, .(visteam, aid = away_id)], by = "visteam")
cand <- cand[home_id == hid & away_id == aid]
cand <- cand[!duplicated(gid) & !duplicated(game_pk)]
F <- merge(F, cand[, .(gid, game_pk)], by = "gid", all.x = TRUE)
rec <- rbind(fread(file.path(SRC, "results", "recency", "model-predictions-validation.csv")),
             fread(file.path(SRC, "results", "recency", "model-predictions-test.csv")), fill = TRUE)
F <- merge(F, rec[, .(game_pk, E_recency = E, C_incumbent = C)], by = "game_pk", all.x = TRUE)
mk <- fread("data/mlb/raw/odds/market-joined.csv")
mk <- mk[!(as.Date(Date) >= as.Date("2021-09-01") & as.Date(Date) <= as.Date("2021-12-31"))]
F <- merge(F, mk[, .(game_pk, p_close, p_open, med_home, med_away, med_home_open, med_away_open)], by = "game_pk", all.x = TRUE)

# --- score ---------------------------------------------------------------------------------
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
S <- F[season %in% PRED]
models <- c(names(FORMS), "E_recency", "C_incumbent")
tab <- rbindlist(lapply(c(sort(unique(S$season)), 0L), function(s) {
  x <- if (s == 0) S else S[season == s]
  x <- x[complete.cases(x[, models, with = FALSE])]
  c(list(season = if (s == 0) "pooled" else as.character(s), games = nrow(x)),
    lapply(setNames(models, models), function(m) round(mean(ll(x[[m]], x$y)), 4)))
}))
cands <- grep("^M", names(FORMS), value = TRUE)
V <- F[season %in% 2017:2022]; V <- V[complete.cases(V[, models, with = FALSE])]
best <- cands[which.min(vapply(cands, function(m) round(mean(ll(V[[m]], V$y)), 4), 0))]   # chosen on 2017-2022 only
# Ensemble with the recency model: logit-space blend, weight chosen on 2017-2019 only (both inputs
# are walk-forward predictions), frozen for every later season.
lgt <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
recal <- NULL
if (RECAL) {   # logit p' = a + b logit p, fit on the 2017-2020 walk-forward predictions, frozen for every season
  rc <- F[season %in% 2017:2020 & !is.na(get(best))]
  recal <- stats::coef(stats::glm(y ~ x, stats::binomial, data.frame(y = rc$y, x = lgt(rc[[best]]))))
  F[, (best) := stats::plogis(recal[1] + recal[2] * lgt(get(best)))]
}
ens_src <- F[season %in% 2017:2019 & !is.na(E_recency) & !is.na(get(best))]
wgrid <- seq(0, 1, 0.05)
ens_w <- wgrid[which.min(vapply(wgrid, function(w) mean(ll(stats::plogis(w * lgt(ens_src[[best]]) + (1 - w) * lgt(ens_src$E_recency)), ens_src$y)), 0))]
F[, ENS := stats::plogis(ens_w * lgt(get(best)) + (1 - ens_w) * lgt(E_recency))]
S <- F[season %in% PRED]
models <- c(models, "ENS")
tab <- rbindlist(lapply(c(sort(unique(S$season)), 0L), function(s) {
  x <- if (s == 0) S else S[season == s]
  x <- x[complete.cases(x[, models, with = FALSE])]
  c(list(season = if (s == 0) "pooled" else as.character(s), games = nrow(x)),
    lapply(setNames(models, models), function(m) round(mean(ll(x[[m]], x$y)), 4)))
}))
M <- S[!is.na(p_close) & complete.cases(S[, c(best), with = FALSE])]
mtab <- M[, .(games = .N, close = mean(ll(p_close, y)), model = mean(ll(get(best), y)), recency = mean(ll(E_recency, y), na.rm = TRUE),
              ensemble = mean(ll(ENS, y), na.rm = TRUE)), by = season]
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
gap <- paired(ll(M$p_close, M$y) - ll(M[[best]], M$y), paste(M$hometeam, M$season))
# market blend and betting threshold, tuned on 2021-2022 (in validation they are also scored there)
MV <- F[season %in% MKT_VAL & !is.na(p_close) & !is.na(get(best))]
lg <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
blend <- stats::glm(y ~ lg(p_close) + lg(get(best)), stats::binomial, MV)
bet <- function(x, tau) {
  eh <- x[[best]] - x$p_close; side <- ifelse(eh >= tau, "h", ifelse(-eh >= tau, "a", NA))
  b <- x[!is.na(side)]; side <- side[!is.na(side)]
  price <- ifelse(side == "h", b$med_home, b$med_away); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  data.table(Date = b$Date, season = b$season, profit = ifelse(won, price - 1, -1))
}
taus <- c(0.01, 0.02, 0.03, 0.04, 0.05, 0.06)
tv <- rbindlist(lapply(taus, function(t) { b <- bet(MV, t); data.table(tau = t, bets = nrow(b), roi = mean(b$profit)) }))
tau <- tv[bets >= 200][which.max(roi), tau]
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
lines <- c(sprintf("# Matchup model: %s", mode), "",
  sprintf("Generated %s. Run values from 2015-2016 team-games: %s.", format(Sys.Date()),
          paste(sprintf("%s %.3f", names(rv), rv), collapse = ", ")), "",
  "## Log loss vs outcomes (lower is better)", "",
  paste0("| ", paste(names(tab), collapse = " | "), " |"), paste0("|", strrep(" --- |", ncol(tab))),
  apply(tab, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")), "",
  sprintf("Best matchup variant on 2017-2022 (validation): %s.", best), "",
  if (RECAL) c(sprintf("RECAL=1: %s recalibrated as logit p' = %s + %s logit p, fit on its 2017-2020 walk-forward predictions (in sample there).",
                       best, fmt(recal[1], 3), fmt(recal[2], 3)), ""),
  "## Against the no-vig closing line (games with odds)", "",
  sprintf("Ensemble weight on the matchup model (chosen on 2017-2019): %s.", ens_w), "",
  "| season | games | close | matchup | recency E | ensemble |", "| --- | --- | --- | --- | --- | --- |",
  apply(mtab, 1, function(r) sprintf("| %s | %s | %s | %s | %s | %s |", r[["season"]], r[["games"]], fmt(r[["close"]]), fmt(r[["model"]]), fmt(r[["recency"]]), fmt(r[["ensemble"]]))), "",
  sprintf("Close minus matchup per-game log loss (positive = matchup better): %s [%s, %s].", fmt(gap[1], 5), fmt(gap[2], 5), fmt(gap[3], 5)),
  sprintf("Blend fit on 2021-2022: logit p = %s + %s logit(close) + %s logit(model).", fmt(coef(blend)[1], 3), fmt(coef(blend)[2], 3), fmt(coef(blend)[3], 3)),
  "", "Betting thresholds on 2021-2022 at median-book closing prices:", "", "| tau | bets | ROI |", "| --- | --- | --- |",
  apply(tv, 1, function(r) sprintf("| %s | %s | %s |", r[["tau"]], r[["bets"]], fmt(r[["roi"]], 3))), "",
  sprintf("Chosen tau: %s.", if (length(tau)) tau else "none with 200+ bets"))
if (mode == "test" && length(tau)) {
  tb <- bet(F[season %in% 2023:2025 & !is.na(p_close)], tau)
  w <- as.Date(cut(tb$Date, "week")); by <- tapply(tb$profit, w, sum); n <- tapply(tb$profit, w, length)
  set.seed(20261004); ci <- stats::quantile(replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }), c(.025, .975))
  lines <- c(lines, sprintf("Test 2023-2025 at tau %s: %d bets, ROI %s, week-block 95%% [%s, %s].", tau, nrow(tb), fmt(mean(tb$profit), 3), fmt(ci[1], 3), fmt(ci[2], 3)),
             paste(tb[, .(roi = round(mean(profit), 3), bets = .N), by = season][, sprintf("%s: %s on %d", season, roi, bets)], collapse = "; "))
}
# --- opening line: day-ahead skill test (closing-line value of bets placed at the open) ------
O <- F[season %in% WALK & !is.na(p_open) & !is.na(p_close) & !is.na(get(best))]
clv_bets <- function(x, tau) {
  eh <- x[[best]] - x$p_open; side <- ifelse(eh >= tau, "h", ifelse(-eh >= tau, "a", NA))
  b <- x[!is.na(side)]; side <- side[!is.na(side)]
  open_p <- ifelse(side == "h", b$p_open, 1 - b$p_open); close_p <- ifelse(side == "h", b$p_close, 1 - b$p_close)
  price <- ifelse(side == "h", b$med_home_open, b$med_away_open); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  data.table(Date = b$Date, season = b$season, clv = close_p - open_p, profit = ifelse(won, price - 1, -1))
}
week_ci <- function(v, d) { w <- as.Date(cut(d, "week")); by <- tapply(v, w, sum); n <- tapply(v, w, length); set.seed(20261004)
  stats::quantile(replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }), c(.025, .975)) }
ot <- rbindlist(lapply(taus, function(t) { b <- clv_bets(O[season %in% MKT_VAL], t)
  if (!nrow(b)) return(NULL); ci <- week_ci(b$clv, b$Date)
  data.table(tau = t, bets = nrow(b), mean_clv = mean(b$clv), clv_lo = ci[1], clv_hi = ci[2], roi_open = mean(b$profit)) }))
lines <- c(lines, "", "## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open", "",
  sprintf("Log loss on %d games: open %s, close %s, model %s.", nrow(O[season %in% MKT_VAL]), fmt(mean(ll(O[season %in% MKT_VAL]$p_open, O[season %in% MKT_VAL]$y))),
          fmt(mean(ll(O[season %in% MKT_VAL]$p_close, O[season %in% MKT_VAL]$y))), fmt(mean(ll(O[season %in% MKT_VAL][[best]], O[season %in% MKT_VAL]$y)))), "",
  "| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |", "| --- | --- | --- | --- | --- |",
  apply(ot, 1, function(r) sprintf("| %s | %s | %s | [%s, %s] | %s |", r[["tau"]], r[["bets"]], fmt(100 * as.numeric(r[["mean_clv"]]), 2),
        fmt(100 * as.numeric(r[["clv_lo"]]), 2), fmt(100 * as.numeric(r[["clv_hi"]]), 2), fmt(r[["roi_open"]], 3))))
if (mode == "test" && nrow(ot)) {
  tau_o <- ot[bets >= 200][which.max(mean_clv), tau]
  tb <- clv_bets(O[season %in% 2023:2025], tau_o); ci <- week_ci(tb$clv, tb$Date); ri <- week_ci(tb$profit, tb$Date)
  lines <- c(lines, sprintf("Test 2023-2025 at tau %s (chosen on 2021-2022 by CLV): %d bets, mean CLV %s points [%s, %s], ROI at median open %s [%s, %s].",
    tau_o, nrow(tb), fmt(100 * mean(tb$clv), 2), fmt(100 * ci[1], 2), fmt(100 * ci[2], 2), fmt(mean(tb$profit), 3), fmt(ri[1], 3), fmt(ri[2], 3)))
}
writeLines(c(lines, "", "The information used here was obtained free of charge from and is copyrighted by Retrosheet."), out_md)
fwrite(F[season %in% PRED, c("gid", "game_pk", "Date", "season", "y", models, "p_close"), with = FALSE],
       sprintf("data/mlb/matchup/predictions%s-%s.csv", TAG, mode))
message("wrote ", out_md)
