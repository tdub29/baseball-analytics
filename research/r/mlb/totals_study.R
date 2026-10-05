#!/usr/bin/env Rscript
# Totals study (TOTALS-PLAN.md): a run-total model against the no-vig closing over/under.
#
#   Rscript research/r/mlb/totals_study.R validation   # reads nothing after 2022; writes results/totals-validation.md
#   Rscript research/r/mlb/totals_study.R test         # 2023-2025, scored once by the owner
#
# Odds: data/mlb/raw/odds/mlb_odds_dataset.json (no license, private research). Per-game odds-derived
# rows stay in data/mlb/raw/odds/ (gitignored); only aggregates go to results/.
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages(library(data.table))
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R")) source(file.path(SRC, f))
mode <- commandArgs(TRUE)[1]; if (is.na(mode)) mode <- "validation"
stopifnot(mode %in% c("validation", "test"))
RES <- file.path(SRC, "results")
out_md <- file.path(RES, sprintf("totals-%s.md", mode))
if (mode == "test" && file.exists(out_md)) stop(out_md, " exists: the test is scored once.")
LAST <- if (mode == "test") 2025L else 2022L      # nothing after this season is read
PRED <- if (mode == "test") 2021:2025 else 2017:2022
TUNE <- 2021:2022; TEST <- 2023:2025
EVAL <- if (mode == "test") TEST else TUNE
FEAT <- "data/mlb/matchup/features.rds"
feat_md5 <- unname(tools::md5sum(FEAT))
if (mode == "test" && !any(grepl(feat_md5, readLines(file.path(RES, "totals-validation.md")), fixed = TRUE)))
  stop("features.rds differs from the file validation used: re-run validation first.")

# --- games, expected runs, environment ---------------------------------------------------------

F <- readRDS(FEAT)[season <= LAST]
gi <- rbindlist(lapply(2016:LAST, function(s)
  fread(retro_file(s, "gameinfo"), select = c("gid", "gametype", "innings", "sky"), showProgress = FALSE)))
F <- merge(F, gi[gametype == "regular", .(gid, innings, sky)], by = "gid", all.x = TRUE)
F[is.na(innings), innings := 9L]

P <- outcome_matrix(rbindlist(lapply(2015:LAST, retro_pa)))
# run values from 2015-2016 team-games, intercept kept (matchup_model.R drops it; a log needs it)
tg <- P[season <= 2016, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
rv_fit <- stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg)
rv <- c(stats::coef(rv_fit)[OUT8[OUT8 != "out_ip"]], out_ip = 0)
xr <- function(side) stats::coef(rv_fit)[[1]] + Reduce(`+`, lapply(c("sp12", "sp3", "pen"), function(p)
  as.numeric(as.matrix(F[, paste0(p, "_", OUT8, "_", side), with = FALSE]) %*% rv[OUT8])))
F[, xr_h := xr("home")][, xr_a := xr("away")]
stopifnot(all(F$xr_h > 0), all(F$xr_a > 0))

# games that ended before their scheduled innings: books void totals on them
inn <- P[, .(maxinn = max(inning)), by = gid]
F <- merge(F, inn, by = "gid", all.x = TRUE)
short <- F[!is.na(maxinn) & maxinn < innings, .N, by = season][order(season)]
F <- F[is.na(maxinn) | maxinn >= innings]

# home-plate umpire: K and unintentional-walk excess per PA vs the league as of that date, as of the game
day <- P[, .(k = sum(k), ubb = sum(ubb), n = .N), by = Date][order(Date)]
den <- decay_sum(day$Date, day$n, day$Date, 30)
day[, `:=`(lk = decay_sum(Date, k, Date, 30) / den, lb = decay_sum(Date, ubb, Date, 30) / den)]
P[, `:=`(rk = k - day$lk[match(Date, day$Date)], rb = ubb - day$lb[match(Date, day$Date)])]
U <- P[is.finite(rk) & !is.na(umphome) & umphome != "", .(rk = sum(rk), rb = sum(rb), n = .N), by = .(entity = umphome, Date, season)]
U[, t := 0]
us <- asof_decay(as.data.frame(U), data.frame(entity = F$umphome, Date = F$Date, season = F$season, t = 0),
                 c("rk", "rb", "n"), h = Inf, c = 0.75)
F[, ump_k := 100 * us[, "rk"] / (us[, "n"] + 4000)][, ump_bb := 100 * us[, "rb"] / (us[, "n"] + 4000)]
rm(P, U); invisible(gc())

F[, dome := as.integer(!is.na(sky) & sky == "dome")]
temp_missing <- F[dome == 0 & (is.na(temp) | temp < 25 | temp > 115), .N]
F[, temp_c := fifelse(dome == 1 | is.na(temp) | temp < 25 | temp > 115, 0, temp - 72)]
spd <- fifelse(is.na(F$windspeed) | F$windspeed < 0, 0, F$windspeed)
F[, wind_out := fifelse(dome == 0 & winddir %in% c("tocf", "tolf", "torf"), spd, 0)]
F[, wind_in := fifelse(dome == 0 & winddir %in% c("fromcf", "fromlf", "fromrf"), spd, 0)]
F[, `:=`(total = hruns + vruns, off = log(innings / 9), lxr = log(xr_h + xr_a))]

# --- odds: one row per game at the main closing total --------------------------------------------

raw <- jsonlite::fromJSON("data/mlb/raw/odds/mlb_odds_dataset.json", simplifyVector = FALSE)
raw <- raw[as.Date(names(raw)) <= as.Date(sprintf("%d-12-31", LAST))]
dec <- function(a) ifelse(a > 0, 1 + a / 100, 1 + 100 / abs(a))
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
O <- rbindlist(lapply(names(raw), function(d) rbindlist(lapply(raw[[d]], function(g) {
  v <- g$gameView; tt <- g$odds$totals
  if (!length(tt) || is.null(v$homeTeamScore) || !startsWith(v$gameStatusText %||% "", "Final")) return(NULL)
  L  <- vapply(tt, function(x) num(x$currentLine$total), 0)
  o  <- vapply(tt, function(x) num(x$currentLine$overOdds), 0)
  u  <- vapply(tt, function(x) num(x$currentLine$underOdds), 0)
  L0 <- vapply(tt, function(x) num(x$openingLine$total), 0)
  ok <- !is.na(L) & !is.na(o) & !is.na(u) & abs(o) >= 100 & abs(u) >= 100 & L >= 4 & L <= 16
  if (!any(ok)) return(NULL)
  L <- L[ok]; do <- dec(o[ok]); du <- dec(u[ok]); L0 <- L0[ok]
  p <- (1 / do) / (1 / do + 1 / du)
  ls <- sort(unique(L)); n <- vapply(ls, function(l) sum(L == l), 0); pm <- vapply(ls, function(l) stats::median(p[L == l]), 0)
  line <- ls[order(-n, abs(pm - 0.5), ls)][1]; i <- L == line
  L0 <- L0[!is.na(L0) & L0 >= 4 & L0 <= 16]
  list(Date = as.Date(d), hn = v$homeTeam$fullName, an = v$awayTeam$fullName, hs = num(v$homeTeamScore), as = num(v$awayTeamScore),
       line = line, p_mkt = stats::median(p[i]), price_o = stats::median(do[i]), price_u = stats::median(du[i]),
       books = length(L), books_line = sum(i), overround = stats::median(1 / do[i] + 1 / du[i]),
       open_line = if (length(L0)) stats::median(L0) else NA_real_)
}))))
odds_first <- min(O$Date)
O[, oid := .I]
norm <- function(x) gsub("[^a-z]", "", tolower(sub("^Oakland ", "", x)))    # the A's dropped "Oakland" in 2025
O[, `:=`(hn = norm(hn), an = norm(an))]
cand <- merge(F[, .(gid, Date, season, hometeam, visteam, hruns, vruns)],
              O[, .(oid, Date, hruns = hs, vruns = as, hn, an)], by = c("Date", "hruns", "vruns"))
vote <- rbind(cand[, .(season, code = hometeam, nm = hn)], cand[, .(season, code = visteam, nm = an)])[
  , .N, by = .(season, code, nm)][order(-N)][!duplicated(paste(season, code))]
cand <- merge(cand, vote[, .(season, hometeam = code, hv = nm)], by = c("season", "hometeam"))
cand <- merge(cand, vote[, .(season, visteam = code, av = nm)], by = c("season", "visteam"))
cand <- cand[hn == hv & an == av]
amb <- cand[gid %in% gid[duplicated(gid)] | oid %in% oid[duplicated(oid)], uniqueN(gid)]
cand <- cand[!(gid %in% gid[duplicated(gid)]) & !(oid %in% oid[duplicated(oid)])]
F <- merge(F, cand[, .(gid, oid)], by = "gid", all.x = TRUE)
F <- merge(F, O[, .(oid, line, p_mkt, price_o, price_u, books, books_line, overround, open_line)], by = "oid", all.x = TRUE)
F[, excl := Date >= as.Date("2021-09-01") & Date <= as.Date("2021-12-31")]
setorder(F, Date, gid)

# --- walk-forward negative binomial fits -------------------------------------------------------

walk <- function(df, formula, seasons) {
  blk <- as.Date(cut(df$Date, "week")); bl <- sort(unique(blk[df$season %in% seasons]))
  mu <- th <- rep(NA_real_, nrow(df)); last <- NULL
  for (j in seq_along(bl)) {
    tr <- df[df$Date < bl[j], ]
    tr$w_ <- 0.5^(as.numeric(bl[j] - tr$Date) / 365)
    m <- suppressWarnings(MASS::glm.nb(formula, data = tr, weights = w_))
    i <- which(blk == bl[j] & df$season %in% seasons)
    mu[i] <- stats::predict(m, df[i, ], type = "response"); th[i] <- m$theta; last <- m
  }
  list(mu = mu, th = th, coef = stats::coef(last), theta = last$theta)
}
ENV <- "temp_c + wind_out + wind_in + dome + ump_k + ump_bb"
D <- as.data.frame(F)
fits <- list(
  T1 = walk(D, stats::as.formula(paste("total ~ lxr +", ENV, "+ offset(off)")), PRED),
  T3 = walk(D, total ~ lxr + offset(off), PRED),
  B  = walk(D, total ~ 1 + offset(off), PRED))
S <- rbind(transform(D, runs = hruns, lxr = log(xr_h), home = 1), transform(D, runs = vruns, lxr = log(xr_a), home = 0))
t2 <- walk(S, stats::as.formula(paste("runs ~ lxr + home +", ENV, "+ offset(off)")), PRED)
n <- nrow(D)
fits$T2 <- list(mh = t2$mu[1:n], ma = t2$mu[n + 1:n], th = t2$th[1:n], coef = t2$coef, theta = t2$theta)
CANDS <- c("T1", "T2", "T3"); MODELS <- c(CANDS, "B")
message("walk-forward fits done")

# distribution of the total for model m on rows i
cdf_t <- function(m, k, i) {
  f <- fits[[m]]
  if (m != "T2") return(stats::pnbinom(k, size = f$th[i], mu = f$mu[i]))
  out <- 0
  for (j in 0:max(k, 0)) out <- out + stats::dnbinom(j, size = f$th[i], mu = f$mh[i]) * stats::pnbinom(k - j, size = f$th[i], mu = f$ma[i])
  out
}
pmf_t <- function(m, k, i) {
  f <- fits[[m]]
  if (m != "T2") return(stats::dnbinom(k, size = f$th[i], mu = f$mu[i]))
  out <- 0
  for (j in 0:max(k)) out <- out + stats::dnbinom(j, size = f$th[i], mu = f$mh[i]) * suppressWarnings(stats::dnbinom(k - j, size = f$th[i], mu = f$ma[i]))
  out
}
mean_t <- function(m, i) if (m == "T2") fits$T2$mh[i] + fits$T2$ma[i] else fits[[m]]$mu[i]
var_t <- function(m, i) { f <- fits[[m]]; if (m == "T2") f$mh[i] + f$mh[i]^2 / f$th[i] + f$ma[i] + f$ma[i]^2 / f$th[i] else f$mu[i] + f$mu[i]^2 / f$th[i] }
# P(over | no push) at line L: P(T > L) / (P(T > L) + P(T < L))
q_over <- function(m, L, i) { under <- cdf_t(m, ceiling(L) - 1, i); over <- 1 - cdf_t(m, floor(L), i); over / (over + under) }

# --- scoring helpers ---------------------------------------------------------------------------

ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lg <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
cboot <- function(d, cl, B = 2000) {          # ratio-of-sums bootstrap over clusters
  by <- tapply(d, cl, sum); nn <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(B, { k <- sample(length(by), replace = TRUE); sum(by[k]) / sum(nn[k]) })
  c(est = mean(d), lo = unname(stats::quantile(b, 0.025)), hi = unname(stats::quantile(b, 0.975)))
}
TAUS <- c(0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10)
bets <- function(x, q, tau) {
  side <- ifelse(q - x$p_mkt >= tau, "over", ifelse(x$p_mkt - q >= tau, "under", NA))
  k <- !is.na(side); x <- x[k, ]; side <- side[k]
  win <- ifelse(side == "over", x$total > x$line, x$total < x$line); push <- x$total == x$line
  price <- ifelse(side == "over", x$price_o, x$price_u)
  data.frame(Date = x$Date, season = x$season, side = side, push = push, win = win & !push,
             profit = ifelse(push, 0, ifelse(win, price - 1, -1)))
}

# market rows: matched, not in the excluded window, scored on EVAL seasons
mrow <- function(seasons) which(F$season %in% seasons & !is.na(F$line) & !F$excl & !is.na(fits$T1$mu))
mi <- which(!is.na(F$line) & !is.na(fits$T1$mu))
for (m in MODELS) { set(F, j = paste0("q_", m), value = NA_real_); set(F, i = mi, j = paste0("q_", m), value = q_over(m, F$line[mi], mi)) }
F[, `:=`(over = as.integer(total > line), push = total == line)]

ou_table <- function(rows) {
  x <- F[rows][push == FALSE]
  rbindlist(lapply(c(sort(unique(x$season)), 0L), function(s) {
    z <- if (s == 0) x else x[season == s]
    c(list(season = if (s == 0) "pooled" else as.character(s), games = nrow(z), market = mean(ll(z$p_mkt, z$over))),
      lapply(setNames(MODELS, MODELS), function(m) mean(ll(z[[paste0("q_", m)]], z$over))))
  }))
}

# --- tuning on 2021-2022: candidate, blend, threshold (identical in both modes) --------------------

tr <- mrow(TUNE); trn <- tr[!F$push[tr]]
tune_ll <- vapply(CANDS, function(m) mean(ll(F[[paste0("q_", m)]][trn], F$over[trn])), 0)
SEL <- names(which.min(tune_ll))
F[, q := get(paste0("q_", SEL))]
blend <- stats::glm(over ~ lg(p_mkt) + lg(q), stats::binomial, F[trn])
val <- rbindlist(lapply(TAUS, function(t) { b <- bets(F[tr], F$q[tr], t)
  data.table(tau = t, bets = nrow(b), overs = sum(b$side == "over"), pushes = sum(b$push), wins = sum(b$win),
             units = sum(b$profit), roi = if (nrow(b)) mean(b$profit) else NA_real_) }))
TAU <- val[bets >= 200][which.max(roi), tau]

# --- the scored set: 2021-2022 in validation (in-sample), 2023-2025 in test ------------------------

ev <- mrow(EVAL); evn <- ev[!F$push[ev]]
X <- F[evn]
ou <- ou_table(ev)
gap <- cboot(ll(X$p_mkt, X$over) - ll(X$q, X$over), paste(X$hometeam, X$season))
X$p_blend <- stats::predict(blend, X, type = "response")
bgain <- cboot(ll(X$p_mkt, X$over) - ll(X$p_blend, X$over), paste(X$hometeam, X$season))
tb <- if (length(TAU)) bets(F[ev], F$q[ev], TAU) else bets(F[0], numeric(0), 1)
roi_ci <- if (nrow(tb)) cboot(tb$profit, as.Date(cut(tb$Date, "week"))) else c(est = NA, lo = NA, hi = NA)
roi_season <- if (nrow(tb)) as.data.table(tb)[, .(bets = .N, pushes = sum(push), units = sum(profit), roi = mean(profit)), by = season][order(season)] else NULL
verdict <- c(
  beats = if (gap[["lo"]] > 0) "beats the closing total" else "does not beat the closing total",
  info = if (bgain[["lo"]] > 0) "adds information to the close" else "adds no information to the close",
  profit = if (nrow(tb) < 100) "fewer than 100 bets: no profitability claim" else
    if (roi_ci[["lo"]] > 0 && sum(roi_season$roi > 0) >= 2) "profitable" else "not profitable")

# --- calibration of total runs (no market) -------------------------------------------------------

ci <- which(F$season %in% PRED & !is.na(fits$T1$mu) & (mode == "validation" | F$season %in% TEST))
cal <- rbindlist(lapply(c(sort(unique(F$season[ci])), 0L), function(s) {
  i <- if (s == 0) ci else ci[F$season[ci] == s]
  c(list(season = if (s == 0) "pooled" else as.character(s), games = length(i), actual = mean(F$total[i])),
    lapply(setNames(paste0("mean_", MODELS), paste0("mean_", MODELS)), function(z) mean(mean_t(sub("mean_", "", z), i))),
    lapply(setNames(paste0("logscore_", MODELS), paste0("logscore_", MODELS)), function(z) mean(log(pmf_t(sub("logscore_", "", z), F$total[i], i)))))
}))
dec_i <- ci; mu_sel <- mean_t(SEL, dec_i)
dq <- cut(mu_sel, unique(stats::quantile(mu_sel, seq(0, 1, 0.1))), include.lowest = TRUE, labels = FALSE)
p85 <- 1 - cdf_t(SEL, 8, dec_i)
deciles <- data.table(dq, mu = mu_sel, actual = F$total[dec_i], p85, o85 = F$total[dec_i] > 8.5)[
  , .(games = .N, pred_mean = mean(mu), actual_mean = mean(actual), pred_over85 = mean(p85), obs_over85 = mean(o85)), by = dq][order(dq)]
disp <- vapply(MODELS, function(m) c(pred_var = mean(var_t(m, ci)), obs_var = mean((F$total[ci] - mean_t(m, ci))^2)), c(0, 0))

# --- market sanity by month (2021-2022 only; never the test seasons) ---------------------------------

san <- F[season %in% TUNE & !is.na(line), .(games = .N, abs_move = mean(abs(line - open_line), na.rm = TRUE),
         moved_15 = mean(abs(line - open_line) >= 1.5, na.rm = TRUE), overround = mean(overround),
         push_rate = mean(push), market_ll = mean(ll(p_mkt[!push], over[!push])), excluded = any(excl)),
         by = .(month = format(Date, "%Y-%m"))][order(month)]
n_reg <- F[season %in% TUNE & !excl & Date >= odds_first, .N]

# --- report --------------------------------------------------------------------------------------

fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
row <- function(x) paste0("| ", paste(x, collapse = " | "), " |")
tab <- function(dt, d = 4) c(row(names(dt)), paste0("|", strrep(" --- |", ncol(dt))),
  apply(dt, 1, function(r) row(vapply(r, function(v) if (suppressWarnings(!is.na(as.numeric(v))) && grepl("\\.", v)) fmt(v, d) else trimws(v), ""))))
coefline <- function(m) paste(sprintf("%s %s", names(fits[[m]]$coef), fmt(fits[[m]]$coef, 4)), collapse = ", ")
mk <- F[mrow(EVAL)]
scope <- if (mode == "test") "2023-2025 (frozen, scored once)" else "2021-2022 (in-sample: the candidate, blend and tau were chosen here)"
lines <- c(sprintf("# Totals study: %s", mode), "",
  sprintf("Generated %s by `Rscript research/r/mlb/totals_study.R %s`. Charter: TOTALS-PLAN.md. features.rds md5 %s.", format(Sys.Date()), mode, feat_md5),
  if (mode == "validation") "Validation only: no 2023-2025 row was read (features, Retrosheet and odds were filtered to 2022 and earlier first)." else "",
  "",
  "## Data", "",
  sprintf("- Games 2016-%d after dropping %d that ended before their scheduled innings (%s).", LAST, sum(short$N),
          paste(sprintf("%d: %d", short$season, short$N), collapse = ", ")),
  sprintf("- Odds file starts %s (not 2021-03-20). %s matched games in %s outside the excluded window, %.1f%% of the %d Retrosheet games from the first odds date; %d dropped as ambiguous (same teams, day and score). %d more in 2021-09-01..2021-12-31 excluded.",
          format(odds_first), nrow(mk), paste(range(EVAL), collapse = "-"), if (mode == "validation") 100 * nrow(mk) / n_reg else NA, n_reg, amb,
          F[season %in% TUNE & !is.na(line) & excl, .N]),
  sprintf("- Market rows scored: %d games, %d pushes (%.1f%%), %.1f%% of lines whole numbers; books per game %.1f, at the main line %.1f; median closing overround %.3f.",
          nrow(mk), sum(mk$push), 100 * mean(mk$push), 100 * mean(mk$line %% 1 == 0), mean(mk$books), mean(mk$books_line), stats::median(mk$overround)),
  sprintf("- Temperature missing or implausible outdoors, set to 72: %d games. Run values (2015-2016 team-games): intercept %s, %s.",
          temp_missing, fmt(stats::coef(rv_fit)[1], 3), paste(sprintf("%s %s", names(rv), fmt(rv, 3)), collapse = ", ")), "",
  "## Calibration of total runs vs outcomes (no market)", "",
  sprintf("Walk-forward weekly, %s. Mean predicted total and log score of the actual total (higher is better).", paste(range(PRED), collapse = "-")), "",
  tab(cal), "",
  sprintf("Selected candidate (lowest 2021-2022 over/under log loss): **%s**. Deciles of its predicted mean, pooled:", SEL), "",
  tab(deciles[, .(decile = dq, games, pred_mean, actual_mean, pred_over85, obs_over85)]), "",
  paste0("Variance, predicted vs observed squared error: ", paste(sprintf("%s %s vs %s", MODELS, fmt(disp[1, ], 2), fmt(disp[2, ], 2)), collapse = "; "), "."), "",
  sprintf("Last weekly fit, T1: %s; theta %s.", coefline("T1"), fmt(fits$T1$theta, 2)),
  sprintf("Last weekly fit, T2 (per side): %s; theta %s.", coefline("T2"), fmt(fits$T2$theta, 2)), "",
  "## Market sanity by month, 2021-2022", "",
  "Closing (current) line vs opening line, overround and no-vig closing log loss on non-push games. In-game scrapes show as big moves and low log loss.", "",
  tab(san), "",
  sprintf("## Over/under log loss vs the no-vig close, %s", scope), "",
  "Pushes excluded. Lower is better.", "",
  tab(ou), "",
  sprintf("Market minus %s, per game (positive = model better): %s [%s, %s], home-team-season cluster bootstrap 95%%.", SEL, fmt(gap[["est"]], 5), fmt(gap[["lo"]], 5), fmt(gap[["hi"]], 5)),
  sprintf("Over rate on non-push games: actual %s, market mean %s, %s mean %s. Model mean total minus line %s runs (a right-skewed count's mean sits above the median the line targets, so this alone is not bias); correlation of model mean with the line %s.",
          fmt(mean(X$over), 4), fmt(mean(X$p_mkt), 4), SEL, fmt(mean(X$q), 4),
          fmt(mean(mean_t(SEL, mrow(EVAL)) - mk$line), 3), fmt(stats::cor(mean_t(SEL, mrow(EVAL)), mk$line), 3)), "",
  sprintf("Blend fit on 2021-2022: logit p = %s + %s logit(market) + %s logit(%s). Gain over the market alone on %s: %s [%s, %s].",
          fmt(stats::coef(blend)[1], 3), fmt(stats::coef(blend)[2], 3), fmt(stats::coef(blend)[3], 3), SEL, paste(range(EVAL), collapse = "-"),
          fmt(bgain[["est"]], 5), fmt(bgain[["lo"]], 5), fmt(bgain[["hi"]], 5)), "",
  "## Betting at the median closing price", "",
  sprintf("Every threshold on 2021-2022 (%s, one unit per bet, pushes refund):", SEL), "",
  tab(val, 3), "",
  if (!length(TAU)) "No threshold reached 200 bets on 2021-2022." else
    sprintf("Chosen tau %s. On %s: %d bets, %d pushes, %s units, ROI %s, week-block 95%% [%s, %s].", TAU, paste(range(EVAL), collapse = "-"),
            nrow(tb), sum(tb$push), fmt(sum(tb$profit), 1), fmt(roi_ci[["est"]], 3), fmt(roi_ci[["lo"]], 3), fmt(roi_ci[["hi"]], 3)), "",
  if (!is.null(roi_season)) tab(roi_season, 3) else "", "",
  sprintf("## Decision rules %s", if (mode == "test") "(TOTALS-PLAN.md)" else "applied to 2021-2022 (code-path check only; the real verdict is the test)"), "",
  sprintf("- Forecast: %s.", verdict[["beats"]]), sprintf("- Information: %s.", verdict[["info"]]), sprintf("- Betting: %s.", verdict[["profit"]]), "",
  "Private research on scraped odds; not betting advice.",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, out_md)
keep <- c("gid", "Date", "season", "hometeam", "visteam", "total", "line", "open_line", "p_mkt", "price_o", "price_u", "excl", paste0("q_", MODELS))
fwrite(F[season %in% PRED, ..keep][, (paste0("mu_", MODELS)) := lapply(MODELS, function(m) mean_t(m, which(F$season %in% PRED)))],
       sprintf("data/mlb/raw/odds/totals-%s.csv", mode))      # odds-derived per game: stays local
message("wrote ", out_md)
