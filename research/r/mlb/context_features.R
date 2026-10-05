#!/usr/bin/env Rscript
# Per-game context features for the matchup win-probability model, and an ablation that asks
# whether each group adds anything over the base model on validation seasons.
#
#   Rscript research/r/mlb/context_features.R
#     writes data/mlb/matchup/context.rds and research/r/mlb/results/context-ablation.md
#
# Decision time is first pitch. Every history stops at the start of the game's date (earlier games
# only, so doubleheader game 2 never sees game 1); only game-time weather, the roof state and the
# plate umpire assignment come from the game itself. Features are built for 2016-2025, but the
# model is fit and scored on 2017-2022 only: no metric is ever computed on a 2023-2025 row.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.
# Interested parties may contact Retrosheet at "www.retrosheet.org".

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R")) source(file.path(SRC, f))
PRED  <- 2017:2022
POOL5 <- setdiff(PRED, 2020)          # the seasons the matchup-model reference (0.6705) was pooled over
OUT_RDS <- "data/mlb/matchup/context.rds"
OUT_MD  <- file.path(SRC, "results", "context-ablation.md")

F <- readRDS("data/mlb/matchup/features.rds")
G <- rbindlist(lapply(2015:2025, retro_games))
P <- rbindlist(lapply(2015:2025, retro_pa))
setorder(P, gid, seq)
message("features.rds modified ", format(file.mtime("data/mlb/matchup/features.rds")), "; games ", nrow(F))

# --- base features, copied from matchup_model.R (that file is not edited) --------------------
rv_fit <- {
  P2 <- outcome_matrix(P[season %in% 2015:2016])
  tg <- P2[, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
  stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg)
}
rv <- c(stats::coef(rv_fit)[OUT8[OUT8 != "out_ip"]], out_ip = 0)
runs_of <- function(prefix, side) as.matrix(F[, paste0(prefix, "_", OUT8, "_", side), with = FALSE]) %*% rv[OUT8]
for (s in c("home", "away")) for (p in c("sp12", "sp3", "pen")) F[[paste0("r_", p, "_", s)]] <- as.numeric(runs_of(p, s))
F[, d12 := r_sp12_home - r_sp12_away][, d3 := r_sp3_home - r_sp3_away][, dpen := r_pen_home - r_pen_away]

tm <- rbind(G[, .(team = hometeam, gid, Date, season, margin = hruns - vruns, site)],
            G[, .(team = visteam, gid, Date, season, margin = vruns - hruns, site)])
bounds <- tm[, .(start = min(Date), end = max(Date)), by = season]
BND <- as.data.frame(bounds)
tm[, t := season_day(Date, season, BND)][, n := 1]
tq <- function(team) data.frame(entity = team, Date = F$Date, season = F$season, t = season_day(F$Date, F$season, BND))
rdx <- function(team) { s <- asof_decay(transform(as.data.frame(tm), entity = team), tq(team), c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
F[, drd := rdx(hometeam) - rdx(visteam)]
F[, t := season_day(Date, season, BND)]

# expected outcome counts per side from the matchup engine ("home" = the home team's batters)
tot <- function(o, s) F[[paste0("sp12_", o, "_", s)]] + F[[paste0("sp3_", o, "_", s)]] + F[[paste0("pen_", o, "_", s)]]
F[, `:=`(ek_h = tot("k", "home"), ek_a = tot("k", "away"), eb_h = tot("ubb", "home"), eb_a = tot("ubb", "away"),
         ehr_h = tot("hr", "home"), ehr_a = tot("hr", "away"))]
F[, epa := Reduce(`+`, lapply(OUT8, function(o) tot(o, "home") + tot(o, "away")))]

# --- (1) team defensive efficiency ------------------------------------------------------------
# Outs on balls in play (homers excluded, reached-on-error counted as not an out) over balls in
# play allowed, per fielding team-game. Park-neutralised by the site's BIP out rate over the three
# prior seasons (shrunk to 1 with 4000 BIP), decayed (h = 120 in-season days, carry 0.75) and shrunk
# toward the trailing-year league rate with 3000 BIP. Constants were set before any scoring.
BIPO <- c("single", "double", "triple", "out_ip")
der <- P[outcome %in% BIPO, .(bip = .N, outs = sum(outcome == "out_ip")), by = .(gid, Date, season, site, team = pitteam)]
roe <- rbindlist(lapply(2015:2025, function(s)
  fread(retro_file(s, "plays"), select = c("gid", "gametype", "pa", "pitteam", "roe"), showProgress = FALSE)[
    gametype == "regular" & pa == 1, .(roe = sum(roe)), by = .(gid, team = pitteam)]))
der <- merge(der, roe, by = c("gid", "team"), all.x = TRUE)
der[is.na(roe), roe := 0][, outs := outs - roe]
pf <- rbindlist(lapply(2015:2025, function(S) {
  x <- der[season %in% (S - 3):(S - 1)]
  if (!nrow(x)) return(NULL)
  lg <- sum(x$outs) / sum(x$bip)
  x[, .(season = S, pf = ((sum(outs) + 4000 * lg) / (sum(bip) + 4000)) / lg), by = site]
}))
der <- merge(der, pf, by = c("season", "site"), all.x = TRUE)
der[is.na(pf), pf := 1][, outs_n := outs / pf][, t := season_day(Date, season, BND)]
lg_der <- league_rate(der[, .(outs_n = sum(outs_n), bip = sum(bip)), by = Date], "outs_n", "bip", F$Date, 365)
de <- as.data.frame(der[, .(entity = team, Date, season, t, outs_n, bip)])
derx <- function(team) { s <- asof_decay(de, tq(team), c("outs_n", "bip"), h = 120, c = 0.75); (s[, 1] + 3000 * lg_der) / (s[, 2] + 3000) }
F[, `:=`(der_h = derx(hometeam), der_a = derx(visteam))]
F[, dder := 100 * (der_h - der_a)]                       # points of BIP out rate, home minus away

# --- (3) plate umpire K and BB tendency --------------------------------------------------------
# Residual per game: actual K (BB) minus the matchup engine's as-of expectation for that game,
# scaled to the actual plate appearances. So "relative to league" also controls for who batted
# and pitched and for the park. Cumulative within season (no decay), carry 0.75 across seasons,
# shrunk to zero with 3000 PA for K and 5000 PA for BB. Interacted with each side's expected K
# (BB) count: an umpire who inflates strikeouts hurts the side that strikes out more.
ga <- P[, .(n = .N, k = sum(outcome == "k"), bb = sum(outcome == "ubb")), by = gid]
U <- merge(F[, .(gid, Date, season, t, umphome, ek = ek_h + ek_a, eb = eb_h + eb_a, epa)], ga, by = "gid")
U[, `:=`(rk = k - n * ek / epa, rb = bb - n * eb / epa)]
us <- asof_decay(as.data.frame(U[, .(entity = umphome, Date, season, t, rk, rb, n)]),
                 data.frame(entity = F$umphome, Date = F$Date, season = F$season, t = F$t), c("rk", "rb", "n"), h = Inf, c = 0.75)
F[, `:=`(ump_k = 100 * us[, "rk"] / (us[, "n"] + 3000), ump_bb = 100 * us[, "rb"] / (us[, "n"] + 5000))]
F[, `:=`(uk_x = ump_k * (ek_h - ek_a), ub_x = ump_bb * (eb_h - eb_a))]

# --- (4) weather and roof --------------------------------------------------------------------
# Retrosheet records sky "dome" for fixed domes and for retractable roofs that were closed. Outdoors:
# temperature in tens of degrees from 72 F, wind out (to lf/cf/rf) minus in (from lf/cf/rf) in tens
# of mph, crosswinds and unknown direction zero. Each acts on the gap in expected home runs, so the
# effect is sided: warm air or wind out helps whichever lineup projects for more homers.
F <- merge(F, G[, .(gid, sky, number, daynight)], by = "gid")
F[, dome := as.numeric(sky == "dome")]
F[, tdev := ifelse(dome == 1 | temp <= 0, 0, (temp - 72) / 10)]
F[, wout := ifelse(dome == 1, 0, pmax(windspeed, 0) / 10 *
                     fcase(winddir %in% c("tocf", "tolf", "torf"), 1, winddir %in% c("fromcf", "fromlf", "fromrf"), -1, default = 0))]
F[, dhr := ehr_h - ehr_a]
F[, `:=`(hr_temp = dhr * tdev, hr_wind = dhr * wout, hr_dome = dhr * dome)]

# --- (5) rest and travel, (6) doubleheader game 2 ----------------------------------------------
# In-season UTC offsets: every US site is on daylight time during the season and Arizona (no DST)
# then matches Pacific; Monterrey 2018-2019 games fell inside Mexico's old DST, Mexico City 2023+
# after it was abolished; London games were in June (BST).
TZ <- c(ANA01 = -7, ARL02 = -5, ARL03 = -5, ATL02 = -4, ATL03 = -4, BAL12 = -4, BIR01 = -5, BOS07 = -4,
        BST01 = -4, BUF05 = -4, CHI11 = -5, CHI12 = -5, CIN09 = -4, CLE08 = -4, DEN02 = -6, DET05 = -4,
        DUN01 = -4, DYE01 = -5, FTB01 = -4, HOU03 = -5, KAN06 = -5, LON01 = 1, LOS03 = -7, MEX02 = -6,
        MIA02 = -4, MIL06 = -5, MIN04 = -5, MNT01 = -5, NYC20 = -4, NYC21 = -4, OAK01 = -7, OMA01 = -5,
        PHI13 = -4, PHO01 = -7, PIT08 = -4, SAC01 = -7, SAN02 = -7, SEA03 = -7, SEO01 = 9, SFO03 = -7,
        SJU01 = -4, STL10 = -5, STP01 = -4, TAM02 = -4, TOK01 = 9, TOR02 = -4, WAS11 = -4, WIL02 = -4)
stopifnot(all(G$site %in% names(TZ)))
tr <- merge(tm[, .(team, gid, Date, season, site)], G[, .(gid, daynight)], by = "gid")
setorder(tr, team, Date, gid)                            # gid suffix 1 < 2 orders doubleheaders
tr[, tz := TZ[site]]
tr[, `:=`(gap = as.numeric(Date - shift(Date)), moved = as.numeric(site != shift(site)), tzd = tz - shift(tz),
          prev_night = shift(daynight) == "night"), by = .(team, season)]
tr[, `:=`(rest = pmin(fcoalesce(gap, 3), 3), moved = fcoalesce(moved, 0), east = pmax(fcoalesce(tzd, 0), 0),
          west = pmax(-fcoalesce(tzd, 0), 0), dgan = as.numeric(daynight == "day" & fcoalesce(prev_night, FALSE) & fcoalesce(gap, 0) == 1))]
side <- function(sfx) setnames(tr[, .(gid, team, rest, moved, east, west, dgan)], c("rest", "moved", "east", "west", "dgan"),
                               paste0(c("rest", "moved", "east", "west", "dgan"), sfx))
F <- merge(F, setnames(side("_h"), "team", "hometeam"), by = c("gid", "hometeam"))
F <- merge(F, setnames(side("_a"), "team", "visteam"), by = c("gid", "visteam"))
F[, `:=`(drest = rest_h - rest_a, dmoved = moved_h - moved_a, deast = east_h - east_a, dwest = west_h - west_a,
         ddgan = dgan_h - dgan_a, dh2 = as.numeric(number == 2))]

# --- (7) bullpen workload: batters faced by relievers over the three previous days ----------------
P[, sp := pitcher[1], by = .(gid, pitteam)]
relbf <- as.data.frame(P[pitcher != sp, .(bf = .N), by = .(entity = pitteam, Date)])
load3 <- function(team) asof_sums(relbf, data.frame(entity = team, Date = F$Date), "bf", trailing_sum, 3)[, 1]
F[, `:=`(load_h = load3(hometeam), load_a = load3(visteam))]
F[, dload := (load_h - load_a) / 10]

# --- save every game's context (features only, no outcomes) ------------------------------------
GROUPS <- list(defense = "dder", umpire = c("ump_k", "ump_bb", "uk_x", "ub_x"), weather = c("hr_temp", "hr_wind", "hr_dome"),
               rest_travel = c("drest", "dmoved", "deast", "dwest", "ddgan"), dh_game2 = "dh2", pen_load = "dload")
ctx_cols <- c("gid", "Date", "season", "hometeam", "visteam", "der_h", "der_a", "umphome", "ek_h", "ek_a", "eb_h", "eb_a",
              "ehr_h", "ehr_a", "dhr", "temp", "tdev", "winddir", "windspeed", "wout", "dome", "rest_h", "rest_a", "moved_h",
              "moved_a", "east_h", "east_a", "west_h", "west_a", "dgan_h", "dgan_a", "load_h", "load_a", unlist(GROUPS))
setorder(F, Date, gid)
stopifnot(!anyNA(F[, unlist(GROUPS), with = FALSE]), !anyDuplicated(F$gid))
saveRDS(F[, ..ctx_cols], OUT_RDS)
message("wrote ", OUT_RDS, ": ", nrow(F), " games")

# --- ablation on validation seasons only --------------------------------------------------------
F <- F[season <= max(PRED) & hruns != vruns]            # 2023-2025 leave here and are never seen again
F[, y := as.integer(hruns > vruns)]
setorder(F, Date, gid)
walk <- function(df, formula, seasons) {                 # copied from matchup_model.R
  df$block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% seasons]))) {
    i <- which(df$block == b & df$season %in% seasons)
    m <- stats::glm(formula, stats::binomial, df[df$Date < b, ])
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}
BASE <- c("d12", "d3", "dpen", "drd")
FORMS <- c(list(base = BASE), lapply(GROUPS, function(g) c(BASE, g)), list(all = c(BASE, unlist(GROUPS))))
for (nm in names(FORMS)) F[[paste0("p_", nm)]] <- walk(F, stats::reformulate(FORMS[[nm]], "y"), PRED)
S <- F[season %in% PRED]
stopifnot(max(S$Date) < as.Date("2023-01-01"))
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))

# reproduction check against the matchup model's own validation predictions
ref <- fread("data/mlb/matchup/predictions-validation.csv", select = c("gid", "season", "M3_plus_team", "E_recency", "C_incumbent"))
chk <- merge(S[, .(gid, y, p_base)], ref, by = "gid")
ref_rows <- chk[!is.na(E_recency) & !is.na(C_incumbent)]
repro <- list(matched = nrow(chk), maxdiff = max(abs(chk$p_base - chk$M3_plus_team)), n_ref = nrow(ref_rows),
              ll_ref = mean(ll(ref_rows$M3_plus_team, ref_rows$y)), ll_mine = mean(ll(ref_rows$p_base, ref_rows$y)))

V <- names(FORMS)
pool <- function(x, lab) c(list(season = lab, games = nrow(x)), lapply(setNames(V, V), function(v) mean(ll(x[[paste0("p_", v)]], x$y))))
tab <- rbindlist(c(lapply(PRED, function(s) pool(S[season == s], as.character(s))),
                   list(pool(S[season %in% POOL5], "pooled excl. 2020"), pool(S, "pooled 2017-2022"))))
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)   # copied from matchup_model.R
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
dlt <- rbindlist(lapply(V[-1], function(v) {
  d <- ll(S$p_base, S$y) - ll(S[[paste0("p_", v)]], S$y)       # positive = the variant is better
  a <- paired(d, paste(S$hometeam, S$season)); i5 <- S$season %in% POOL5
  b <- paired(d[i5], paste(S$hometeam, S$season)[i5])
  c(list(variant = v), setNames(as.list(a), c("d", "lo", "hi")), setNames(as.list(b), c("d5", "lo5", "hi5")),
    setNames(lapply(PRED, function(s) mean(d[S$season == s])), paste0("s", PRED)))
}))
dlt[, verdict := fifelse(lo > 0, "helps", fifelse(hi < 0, "hurts", "no clear effect"))]
keep <- dlt[verdict == "helps" & variant != "all", variant]

# coefficients of the all-groups model fit on every 2016-2022 game (for sign and size only)
cf <- summary(stats::glm(stats::reformulate(FORMS$all, "y"), stats::binomial, F))$coefficients
sdv <- vapply(rownames(cf)[-1], function(v) stats::sd(F[[v]]), 0)

fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
row <- function(...) paste0("| ", paste(..., sep = " | "), " |")
L <- c("# Context features: ablation on validation seasons", "",
  sprintf("Generated %s by research/r/mlb/context_features.R. Features for every 2016-2025 game are in %s;", format(Sys.Date()), OUT_RDS),
  "the model below is fit and scored on 2016-2022 rows only (outcomes 2017-2022). Nothing was computed on 2023-2025.", "",
  "Method: the matchup model's weekly walk-forward logistic (refit each Monday on every earlier game, predict that week),",
  "base formula y ~ d12 + d3 + dpen + drd, then the base plus each context group alone and all groups together.",
  "Paired difference = base log loss minus variant log loss per game (positive = the variant is better), with a",
  "95% interval from 1000 cluster-bootstrap draws of home team-seasons.", "",
  "## Reproducing the base", "",
  sprintf("My base predictions match matchup_model.R's M3_plus_team on %d of %d games (max absolute difference %s).",
          chk[abs(p_base - M3_plus_team) < 1e-9, .N], repro$matched, formatC(repro$maxdiff, format = "e", digits = 1)),
  sprintf("On the reference's own rows (%d games with recency predictions, 2020 has none): reference %s, mine %s.",
          repro$n_ref, fmt(repro$ll_ref), fmt(repro$ll_mine)),
  sprintf("Over every non-tie game the pools below hold %d games excluding 2020 and %d including it.",
          tab[season == "pooled excl. 2020", games], tab[season == "pooled 2017-2022", games]), "",
  "## Features", "",
  "| group | columns | definition |", "| --- | --- | --- |",
  "| defense | dder | Team BIP out rate allowed (homers out, reached-on-error not an out), park-neutralised by the site's 3 prior seasons, decayed h = 120 in-season days, carry 0.75, shrunk to the trailing-year league rate with 3000 BIP. Home minus away, in points. |",
  "| umpire | ump_k, ump_bb, uk_x, ub_x | Plate umpire's as-of K and BB residual per PA against the matchup engine's expectation for each game he worked (so league, players and park are netted out), cumulative in season, carry 0.75, shrunk to zero with 3000 (K) and 5000 (BB) PA, in points. uk_x and ub_x multiply it by the home minus away expected K and BB counts. |",
  "| weather | hr_temp, hr_wind, hr_dome | Home minus away expected homers (from features.rds) times temperature ((F - 72) / 10, zero under a roof), times wind out minus in (mph / 10, crosswinds zero), and times a closed-roof flag (Retrosheet sky = dome). |",
  "| rest_travel | drest, dmoved, deast, dwest, ddgan | Home minus away: days since the previous game (capped at 3, 0 in a doubleheader nightcap), previous game at a different site, hours of time-zone change east and west from the previous site (48-site UTC table), day game after a night game the previous day. |",
  "| dh_game2 | dh2 | Second game of a doubleheader. |",
  "| pen_load | dload | Home minus away batters faced by relievers over the three previous days, in tens. Separate from the availability discount already inside dpen. |", "",
  "Every shrink constant and window was set before scoring and never tuned on these outcomes.", "",
  "## Log loss by season (lower is better)", "",
  row("season", "games", paste(V, collapse = " | ")), paste0("|", strrep(" --- |", length(V) + 2)),
  apply(tab, 1, function(r) row(r[["season"]], r[["games"]], paste(fmt(unlist(r[V])), collapse = " | "))), "",
  "## Paired difference against the base (positive = better), x 1000", "",
  row("variant", "2017-2022 [95% CI]", "excl. 2020 [95% CI]", paste(PRED, collapse = " | "), "verdict"),
  paste0("|", strrep(" --- |", length(PRED) + 4)),
  apply(dlt, 1, function(r) row(r[["variant"]], sprintf("%s [%s, %s]", fmt(1000 * as.numeric(r[["d"]]), 3), fmt(1000 * as.numeric(r[["lo"]]), 3), fmt(1000 * as.numeric(r[["hi"]]), 3)),
                                 sprintf("%s [%s, %s]", fmt(1000 * as.numeric(r[["d5"]]), 3), fmt(1000 * as.numeric(r[["lo5"]]), 3), fmt(1000 * as.numeric(r[["hi5"]]), 3)),
                                 paste(fmt(1000 * as.numeric(r[paste0("s", PRED)]), 3), collapse = " | "), r[["verdict"]])), "",
  "Verdict rule: helps if the 2017-2022 interval sits above zero, hurts if below, otherwise no clear effect.", "",
  "## All-groups model coefficients (fit on every 2016-2022 game; sign and size only)", "",
  "| term | coef | z | coef x 1 sd |", "| --- | --- | --- | --- |",
  sprintf("| %s | %s | %s | %s |", rownames(cf)[-1], fmt(cf[-1, 1]), fmt(cf[-1, 3], 2), fmt(cf[-1, 1] * sdv)), "",
  "## Recommendation", "",
  if (length(keep)) sprintf("Add: %s. Leave the other groups out.", paste(keep, collapse = ", ")) else
    "No group clears the bar: keep the base formula y ~ d12 + d3 + dpen + drd.", "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(L, OUT_MD)
message("wrote ", OUT_MD)
