#!/usr/bin/env Rscript
# Stat reliability (stabilization) study for the matchup model's per-PA rates.
#
#   Rscript research/r/mlb/reliability.R        # run from the repo root
#   env: REL_B (bootstrap replicates, 200), REL_B_ERA (100), REL_D (random draws, 100), REL_WORKERS (10)
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.
# Interested parties may contact Retrosheet at "www.retrosheet.org".
#
# Question: at what sample size does each per-PA rate become reliable for hitters, starting
# pitchers and relievers, and do the shrink constants in matchup.R (BAT_CFG, PIT_CFG) match?
#
# Unit: a player-season in one role. Hitters exclude pitchers batting (BF >= PA that season);
# pitchers exclude position players pitching (PA > BF and BF < 150). A pitcher-season is a
# starter if half or more of its BF came in starts; its unit then holds only the BF in starts,
# a reliever's only the BF in relief. Estimation seasons 2015-2022 (2020 kept, see the md);
# 2023-2025 run separately as an era check and feed no choice.
#
# Methods, each a cross-check on the others:
#  1. KR-21 alpha (Carleton): units with at least N events, N drawn at random, alpha of the N-event
#     total, averaged over REL_D draws; items are centred on the role-season league rate so a
#     league-wide level shift between seasons is not counted as player spread. Split-half r on two
#     disjoint N-event halves (units with 2N or more) is the second version. The exact expectation
#     of KR-21 over all random draws (hypergeometric moments) is computed too, for the bootstrap.
#  2. Spearman-Brown fit alpha(N) = N / (N + k) across the whole N grid (weighted by units).
#  3. Beta-binomial MLE on every unit, no minimum: one mean per season, one common k = alpha +
#     beta. Continuous model inputs (batted-ball expected outcomes) use the one-way ANOVA moment
#     estimator k = within variance / between variance, which is the same quantity.
#  4. Player-cluster bootstrap (players resampled with all their seasons) for 95% intervals.
#  5. Year t to t+1 correlations against the correlation stable talent would give.

suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(parallel) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
source(file.path(SRC, "retro.R"))
RES <- file.path(SRC, "results"); OUT <- file.path(RES, "reliability")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

B       <- as.integer(Sys.getenv("REL_B", "200"))
B_ERA   <- as.integer(Sys.getenv("REL_B_ERA", "100"))
D       <- as.integer(Sys.getenv("REL_D", "100"))
WORKERS <- as.integer(Sys.getenv("REL_WORKERS", "10"))
MAIN <- 2015:2022; ERA <- 2023:2025
PAIRS_T <- c(2015:2018, 2021)                  # t to t+1 pairs that do not touch 2020
NGRID <- c(25, 50, 75, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800)
MIN_UNITS <- 30                                # a grid point needs this many units
KMAX <- 1e5                                    # k at this bound = no detectable player spread
NSTAR <- c(hitter = 200, starter = 200, reliever = 100)   # survivorship diagnostic threshold
MPAIR <- c(hitter = 300, starter = 300, reliever = 150)   # cross-season minimum, both seasons
BIP5 <- c("single", "double", "triple", "hr", "out_ip")
set.seed(20261005)
t0 <- Sys.time()
say <- function(...) message(sprintf("[%5.0fs] ", as.numeric(Sys.time() - t0, units = "secs")), ...)

# --- model constants, read from matchup.R without running it ----------------------------------
model_cfg <- function() {
  env <- new.env()
  ex <- tryCatch(parse(file.path(SRC, "matchup.R")), error = function(e) NULL)
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
                    as.character(e[[2]]) %in% c("BAT_CFG", "PIT_CFG")) eval(e, env)
  if (!exists("BAT_CFG", env, inherits = FALSE) || !exists("PIT_CFG", env, inherits = FALSE)) {
    message("matchup.R did not parse; using the 2026-10-05 copy of BAT_CFG and PIT_CFG")
    env$BAT_CFG <- list(k = c(120, 1, 60), ubb = c(240, .75, 110), hbp = c(240, .75, 300), single = c(Inf, .75, 800),
                        double = c(Inf, .75, 1000), triple = c(Inf, .75, 1500), hr = c(Inf, .5, 200), out_ip = c(Inf, .75, 800))
    env$PIT_CFG <- list(k = c(120, .75, 90), ubb = c(240, .75, 300), hbp = c(240, .75, 500), single = c(Inf, .5, 1500),
                        double = c(Inf, .5, 1500), triple = c(Inf, .5, 3000), hr = c(240, .75, 1300), out_ip = c(Inf, .5, 1500))
  }
  list(bat = sapply(env$BAT_CFG, `[`, 3), pit = sapply(env$PIT_CFG, `[`, 3))
}
MK <- model_cfg()

# --- data ----------------------------------------------------------------------------------------
P <- rbindlist(lapply(c(MAIN, ERA), retro_pa))
setorder(P, gid, seq)
P[, start := pitcher == pitcher[1L], by = .(gid, pitteam)]
who <- merge(P[, .(pa = .N), by = .(season, id = batter)],
             P[, .(bf = .N, bf_st = sum(start)), by = .(season, id = pitcher)], by = c("season", "id"), all = TRUE)
for (v in c("pa", "bf", "bf_st")) set(who, which(is.na(who[[v]])), v, 0L)
who[, `:=`(hitter_ok = pa > bf, pitcher_ok = bf > 0 & !(pa > bf & bf < 150),
           role = fifelse(bf_st >= 0.5 * bf, "starter", "reliever"))]

# Pitchers' model inputs: each ball in play becomes the league outcome mix of its batted-ball type
# over the prior three seasons (the first season uses itself), as in matchup_build.R.
bbd <- P[!is.na(bb_type) & outcome %in% BIP5, .N, by = .(season, bb_type, outcome)]
xmix <- rbindlist(lapply(sort(unique(P$season)), function(S) {
  src <- bbd[season %in% if (S == min(P$season)) S else (S - 3):(S - 1)]
  m <- dcast(src[, .(N = sum(N)), by = .(bb_type, outcome)], bb_type ~ outcome, value.var = "N", fill = 0)
  for (o in BIP5) if (!o %in% names(m)) m[[o]] <- 0
  tot <- rowSums(m[, BIP5, with = FALSE])
  out <- data.table(season = S, bb_type = m$bb_type)
  for (o in BIP5) out[[paste0("x_", o)]] <- m[[o]] / tot
  out
}))
for (o in OUTCOMES) set(P, j = o, value = as.numeric(P$outcome == o))
P <- merge(P, xmix, by = c("season", "bb_type"), all.x = TRUE, sort = FALSE)
has <- P$outcome %in% BIP5 & !is.na(P$x_single)
for (o in BIP5) { v <- P[[o]]; v[has] <- P[[paste0("x_", o)]][has]; set(P, j = paste0("x_", o), value = v) }
P[, `:=`(babip = as.numeric(outcome %in% c("single", "double", "triple")),
         gb = as.numeric(bb_type %in% "gb"), fb = as.numeric(bb_type %in% "fb"),
         ld = as.numeric(bb_type %in% "ld"), pu = as.numeric(bb_type %in% "pu"))]

# Park factors for the park sensitivity: (site, batter hand, outcome) over the scope, shrunk with
# 4000 PA toward the hand's league rate (matchup.R's form, pooled rather than prior seasons).
park_neutral_cols <- function(E, scope) {
  x <- P[season %in% scope]
  lg <- x[, c(list(n = .N), lapply(.SD, sum)), by = bathand, .SDcols = OUTCOMES]
  st <- x[, c(list(n = .N), lapply(.SD, sum)), by = .(site, bathand), .SDcols = OUTCOMES]
  st <- merge(st, lg, by = "bathand", suffixes = c("", "_lg"))
  for (o in OUTCOMES) {
    lr <- st[[paste0(o, "_lg")]] / st$n_lg
    st[[paste0("pf_", o)]] <- ((st[[o]] + 4000 * lr) / (st$n + 4000)) / lr
  }
  E <- merge(E, st[, c("site", "bathand", paste0("pf_", OUTCOMES)), with = FALSE], by = c("site", "bathand"),
             all.x = TRUE, sort = FALSE)
  for (o in OUTCOMES) { f <- E[[paste0("pf_", o)]]; f[is.na(f)] <- 1; set(E, j = paste0("pn_", o), value = E[[o]] / f) }
  E
}

# --- metrics ---------------------------------------------------------------------------------------
SPECS <- rbindlist(list(
  data.table(metric = OUTCOMES, set = "pa", binary = TRUE,
             label = c("Strikeout", "Unintentional walk", "Hit by pitch", "Single", "Double", "Triple", "Home run", "Out in play")),
  data.table(metric = paste0("x_", BIP5), set = "pa", binary = FALSE,
             label = paste(c("Single", "Double", "Triple", "Home run", "Out in play"), "(x, model input)")),
  data.table(metric = "babip", set = "bip", binary = TRUE, label = "BABIP-like (hits / balls in play, no HR)"),
  data.table(metric = c("gb", "fb", "ld", "pu"), set = "bb", binary = TRUE,
             label = paste(c("Ground ball", "Fly ball", "Line drive", "Popup"), "share of batted balls"))))
SPECS[, from2020 := metric %in% c("fb", "ld", "pu")]   # Retrosheet batted-ball coding changed in 2020
SET_FILTER <- list(pa = function(E) E,
                   bip = function(E) E[outcome %in% c("single", "double", "triple", "out_ip")],
                   bb = function(E) E[outcome %in% BIP5 & !is.na(bb_type)])

role_events <- function(role) {
  if (role == "hitter") {
    E <- P[who[hitter_ok == TRUE, .(season, batter = id)], on = .(season, batter), nomatch = NULL]
    E[, pid := batter]
  } else {
    want <- role; want_start <- role == "starter"
    pit <- who[pitcher_ok == TRUE & role == want, .(season, pitcher = id)]
    E <- P[pit, on = .(season, pitcher), nomatch = NULL]
    E <- E[E$start == want_start]
    E[, pid := pitcher]
  }
  E[, unit := paste(pid, season)]
  E
}
role_specs <- function(role, scope) {
  s <- if (role == "hitter") SPECS[!grepl("^x_", metric)] else copy(SPECS)
  s[, seasons := lapply(from2020, function(f) if (f) scope[scope >= 2020] else scope)]
  s[lengths(seasons) > 0]
}

#' One row per unit: n per event set, and per metric the sum (s1) and, for continuous ones, the sum of squares.
unit_stats <- function(E, specs, extra = NULL) {
  U <- unique(E[, .(unit, pid, season)])
  for (st in unique(specs$set)) {
    ms <- specs[set == st]; Es <- SET_FILTER[[st]](E)
    cols <- c(ms$metric, if (st == "pa") extra)
    a <- Es[, c(list(n = .N), lapply(.SD, sum)), by = unit, .SDcols = cols]
    setnames(a, c("unit", paste0("n_", st), paste0("s1_", cols)))
    sq <- c(ms$metric[!ms$binary], if (st == "pa") extra)
    if (length(sq)) {
      a2 <- Es[, lapply(.SD, function(v) sum(v^2)), by = unit, .SDcols = sq]
      setnames(a2, c("unit", paste0("s2_", sq))); a <- merge(a, a2, by = "unit")
    }
    U <- merge(U, a, by = "unit", all.x = TRUE)
  }
  for (v in setdiff(names(U), c("unit", "pid", "season"))) set(U, which(is.na(U[[v]])), v, 0)
  setorder(U, unit); U[, uid := .I]
  U
}
s2_of <- function(U, m, binary) if (binary) U[[paste0("s1_", m)]] else U[[paste0("s2_", m)]]
league_mu <- function(U, m, st) {            # role-season league rate per unit
  num <- U[[paste0("s1_", m)]]; den <- U[[paste0("n_", st)]]
  mu <- data.table(season = U$season, num, den)[, .(mu = sum(num) / pmax(sum(den), 1)), by = season]
  mu$mu[match(U$season, mu$season)]
}

# --- estimators ------------------------------------------------------------------------------------
#' KR-21 of N-event totals on season-centred items (continuous analog when items are not 0/1).
kr21 <- function(Tc, Qc, N) {
  m <- length(Tc); g <- sum(Tc) / (m * N)
  s2item <- sum(Qc) / (m * N) - g^2
  N / (N - 1) * (1 - N * s2item / stats::var(Tc))
}
#' Exact expectation of the same KR-21 over all random draws of N events without replacement.
#' Weights w replicate units (bootstrap); replicated units draw independently.
kr21_exact <- function(n, s1, s2, mu, N, w = NULL) {
  if (is.null(w)) w <- rep(1, length(n))
  k <- n >= N & w > 0
  n <- n[k]; s1 <- s1[k]; s2 <- s2[k]; mu <- mu[k]; w <- w[k]
  yb <- s1 / n - mu; q <- s2 / n - 2 * mu * s1 / n + mu^2      # centred mean and mean square
  sig2 <- pmax(s2 / n - (s1 / n)^2, 0)
  V <- ifelse(n > 1, N * sig2 * (n - N) / (n - 1), 0)
  W <- sum(w); g <- sum(w * yb) / W
  SS <- sum(w * (N^2 * yb^2 + V)) - W * (N * g)^2 - sum(w * V) / W
  N / (N - 1) * (1 - N * (sum(w * q) / W - g^2) / (SS / (W - 1)))
}
#' Spearman-Brown fit alpha(N) = N / (N + k), least squares weighted by units, k in [1, KMAX].
sb_fit <- function(N, a, wt) {
  ok <- is.finite(a) & is.finite(wt) & wt > 0
  if (sum(ok) < 2) return(NA_real_)
  N <- N[ok]; a <- a[ok]; wt <- wt[ok]
  f <- function(lk) sum(wt * (a - N / (N + exp(lk)))^2)
  g <- seq(0, log(KMAX), length.out = 300); i <- which.min(vapply(g, f, 0))
  exp(optimize(f, c(g[max(1, i - 1)], g[min(300, i + 1)]))$minimum)
}
#' Beta-binomial MLE: one mean per season, one common k = alpha + beta, on every unit.
bb_fit <- function(x, n, s, w = NULL, start = NULL) {
  keep <- n > 0 & (if (is.null(w)) TRUE else w > 0)
  x <- x[keep]; n <- n[keep]; s <- as.integer(factor(s[keep]))
  w <- if (is.null(w)) rep(1, length(x)) else w[keep]
  S <- max(s)
  mu0 <- pmin(pmax(as.vector(rowsum(w * x, s) / rowsum(w * n, s)), 1e-6), 1 - 1e-6)
  p0 <- if (length(start) == S + 1) start else c(qlogis(mu0), log(200))
  nll <- function(p) { mu <- plogis(p[s]); k <- exp(p[S + 1]); a <- mu * k
    -sum(w * (lbeta(x + a, n - x + k - a) - lbeta(a, k - a))) }
  gr <- function(p) { mu <- plogis(p[s]); k <- exp(p[S + 1]); a <- mu * k; b <- k - a
    dk <- digamma(k) - digamma(n + k)
    da <- digamma(x + a) - digamma(a) + dk; db <- digamma(n - x + b) - digamma(b) + dk
    -c(as.vector(rowsum(w * k * mu * (1 - mu) * (da - db), s)), sum(w * (a * da + b * db))) }
  o <- optim(p0, nll, gr, method = "L-BFGS-B", lower = c(rep(-12, S), log(0.5)), upper = c(rep(12, S), log(KMAX)))
  list(k = exp(o$par[S + 1]), par = o$par, conv = o$convergence)
}
#' One-way random-effects ANOVA moment estimator, pooled over seasons: k = within / between variance.
mom_k <- function(n, s1, s2, s, w = NULL) {
  if (is.null(w)) w <- rep(1, length(n))
  k <- n > 0 & w > 0
  d <- data.table(n = n[k], s1 = s1[k], s2 = s2[k], s = s[k], w = w[k])
  r <- d[, { Nt <- sum(w * n); yb <- sum(w * s1) / Nt
    .(SSB = sum(w * n * (s1 / n - yb)^2), SSW = sum(w * (s2 - s1^2 / n)), dfB = sum(w) - 1,
      dfW = Nt - sum(w), n0dfB = Nt - sum(w * n^2) / Nt) }, by = s]
  msw <- sum(r$SSW) / sum(r$dfW)
  tau2 <- (sum(r$SSB) - msw * sum(r$dfB)) / sum(r$n0dfB)
  if (!is.finite(tau2) || tau2 <= 0) KMAX else min(KMAX, msw / tau2)
}

# --- method 1: KR-21 and split-half over random draws -------------------------------------------
sim_grid <- function(E, U, specs) {
  rows <- list()
  for (st in unique(specs$set)) {
    ms <- specs[set == st]; Es <- SET_FILTER[[st]](E)
    uid <- U$uid[match(Es$unit, U$unit)]
    n <- tabulate(uid, nrow(U)); first <- cumsum(c(1L, head(n, -1)))
    nm <- nrow(ms); nn <- length(NGRID)
    A <- A2 <- R <- matrix(0, nm, nn); cntA <- cntR <- matrix(0L, nm, nn)
    mus <- lapply(ms$metric, function(m) league_mu(U, m, st))
    oks <- lapply(seq_len(nm), function(j) U$season %in% ms$seasons[[j]])
    for (d in seq_len(D)) {
      o <- order(uid + stats::runif(length(uid)), method = "radix")   # random order within each unit
      for (j in seq_len(nm)) {
        v <- Es[[ms$metric[j]]][o]
        cs <- c(0, cumsum(v)); cs2 <- if (ms$binary[j]) cs else c(0, cumsum(v^2))
        for (i in seq_len(nn)) {
          N <- NGRID[i]
          sel <- which(n >= N & oks[[j]])
          if (length(sel) >= MIN_UNITS) {
            T <- cs[first[sel] + N] - cs[first[sel]]; Q <- cs2[first[sel] + N] - cs2[first[sel]]
            mu <- mus[[j]][sel]
            a <- kr21(T - N * mu, Q - 2 * mu * T + N * mu^2, N)
            A[j, i] <- A[j, i] + a; A2[j, i] <- A2[j, i] + a^2; cntA[j, i] <- length(sel)
          }
          sel <- which(n >= 2 * N & oks[[j]])
          if (length(sel) >= MIN_UNITS) {
            h1 <- cs[first[sel] + N] - cs[first[sel]]; h2 <- cs[first[sel] + 2 * N] - cs[first[sel] + N]
            mu <- mus[[j]][sel]
            R[j, i] <- R[j, i] + stats::cor(h1 - N * mu, h2 - N * mu); cntR[j, i] <- length(sel)
          }
        }
      }
    }
    for (j in seq_len(nm)) rows[[length(rows) + 1]] <- data.table(
      metric = ms$metric[j], N = NGRID, units = cntA[j, ], kr21_sim = ifelse(cntA[j, ] > 0, A[j, ] / D, NA),
      kr21_mcse = ifelse(cntA[j, ] > 0, sqrt(pmax(A2[j, ] / D - (A[j, ] / D)^2, 0) / D), NA),
      units_2N = cntR[j, ], split_sim = ifelse(cntR[j, ] > 0, R[j, ] / D, NA))
  }
  rbindlist(rows)
}

#' Exact KR-21 over the grid for one metric (weights optional); returns alpha and units per N.
exact_curve <- function(U, sp, w = NULL, seasons = sp$seasons[[1]]) {
  m <- sp$metric; st <- sp$set
  ok <- U$season %in% seasons
  n <- U[[paste0("n_", st)]][ok]; s1 <- U[[paste0("s1_", m)]][ok]; s2 <- s2_of(U, m, sp$binary)[ok]
  mu <- league_mu(U, m, st)[ok]; ww <- if (is.null(w)) rep(1, sum(ok)) else w[ok]
  units <- vapply(NGRID, function(N) sum(ww[n >= N]), 0)
  a <- vapply(NGRID, function(N) if (sum(n >= N & ww > 0) >= MIN_UNITS) kr21_exact(n, s1, s2, mu, N, ww) else NA_real_, 0)
  list(alpha = a, units = units)
}
re_fit <- function(U, sp, w = NULL, seasons = sp$seasons[[1]], start = NULL, nmin = 0) {
  m <- sp$metric; st <- sp$set
  ok <- U$season %in% seasons & U[[paste0("n_", st)]] >= max(1, nmin)
  n <- U[[paste0("n_", st)]][ok]; s1 <- U[[paste0("s1_", m)]][ok]
  ww <- if (is.null(w)) NULL else w[ok]
  if (sp$binary) bb_fit(s1, n, U$season[ok], ww, start)
  else list(k = mom_k(n, s1, s2_of(U, m, FALSE)[ok], U$season[ok], ww), par = NULL)
}


# --- methods 2 to 4 for one role and scope --------------------------------------------------------
boot_worker <- function(b) {          # runs on a cluster node; U, specs, pidx, pars, wmat exported
  w <- wmat[pidx, b]
  vapply(seq_len(nrow(specs)), function(j) {
    sp <- specs[j]; ex <- exact_curve(U, sp, w)
    c(sb_fit(NGRID, ex$alpha, ex$units), re_fit(U, sp, w, start = pars[[j]])$k)
  }, c(0, 0))
}

run_role <- function(role, scope, nboot, cl, sens = FALSE) {
  lab <- paste(min(scope), max(scope), sep = "-")
  say(role, " ", lab)
  E <- role_events(role)[season %in% scope]
  specs <- role_specs(role, scope)
  if (sens) E <- park_neutral_cols(E, scope)
  U <- unit_stats(E, specs, extra = if (sens) paste0("pn_", OUTCOMES))
  grid <- sim_grid(E, U, specs)
  grid[, `:=`(role = role, scope = lab, kr21_exact = NA_real_)]
  say(role, " ", lab, ": ", D, " draws done")
  ests <- pars <- vector("list", nrow(specs))
  for (j in seq_len(nrow(specs))) {
    sp <- specs[j]; m <- sp$metric; ok <- U$season %in% sp$seasons[[1]]
    nset <- U[[paste0("n_", sp$set)]]; s1 <- U[[paste0("s1_", m)]]; s2 <- s2_of(U, m, sp$binary)
    g <- grid[metric == m]
    ex <- exact_curve(U, sp); grid[metric == m, kr21_exact := ex$alpha]
    re <- re_fit(U, sp); pars[[j]] <- re$par
    ns <- NSTAR[[role]]; a_ns <- ex$alpha[match(ns, NGRID)]
    fin <- is.finite(g$kr21_sim)
    o <- data.table(role = role, scope = lab, metric = m, label = sp$label, set = sp$set, binary = sp$binary,
                    seasons = paste(range(sp$seasons[[1]]), collapse = "-"), units = sum(ok & nset > 0),
                    players = uniqueN(U$pid[ok & nset > 0]), events = sum(nset[ok]),
                    mean_rate = sum(s1[ok]) / sum(nset[ok]), n_grid = sum(fin), max_N = max(g$N[fin]),
                    k_kr21 = sb_fit(g$N, g$kr21_sim, g$units), k_kr21_exact = sb_fit(NGRID, ex$alpha, ex$units),
                    k_split = sb_fit(g$N, g$split_sim, g$units_2N), k_re = re$k,
                    re_method = if (sp$binary) "beta-binomial MLE" else "ANOVA moments",
                    k_mom = mom_k(nset[ok], s1[ok], s2[ok], U$season[ok]),
                    k_re_surv = re_fit(U, sp, nmin = ns)$k, k_kr21_at_nstar = ns * (1 - a_ns) / a_ns, nstar = ns)
    if (sens) {
      s20 <- setdiff(sp$seasons[[1]], 2020)
      ex2 <- exact_curve(U, sp, seasons = s20)
      o[, `:=`(k_kr21_no2020 = sb_fit(NGRID, ex2$alpha, ex2$units), k_re_no2020 = re_fit(U, sp, seasons = s20)$k)]
      if (m %in% OUTCOMES) {
        pm <- paste0("pn_", m)
        o[, k_mom_park := mom_k(U$n_pa[ok], U[[paste0("s1_", pm)]][ok], U[[paste0("s2_", pm)]][ok], U$season[ok])]
      }
    }
    ests[[j]] <- o
  }
  est <- rbindlist(ests, fill = TRUE)
  if (nboot > 0) {
    pids <- unique(U$pid); pidx <- match(U$pid, pids)
    wmat <- replicate(nboot, tabulate(sample.int(length(pids), length(pids), TRUE), length(pids)))
    Ub <- U[, c("unit", "pid", "season", "uid", grep("^(n_|s1_|s2_)", names(U), value = TRUE)), with = FALSE]
    clusterCall(cl, function(u, s, pi, pa, wm) {
      assign("U", u, envir = .GlobalEnv); assign("specs", s, envir = .GlobalEnv); assign("pidx", pi, envir = .GlobalEnv)
      assign("pars", pa, envir = .GlobalEnv); assign("wmat", wm, envir = .GlobalEnv); NULL
    }, Ub, specs, pidx, pars, wmat)
    arr <- simplify2array(parLapply(cl, seq_len(nboot), boot_worker))   # 2 x metrics x replicates
    q <- function(i, p) apply(arr[i, , , drop = FALSE], 2, stats::quantile, p, na.rm = TRUE)
    est[, `:=`(kr_lo = q(1, .025), kr_hi = q(1, .975), re_lo = q(2, .025), re_hi = q(2, .975), boot = nboot)]
    say(role, " ", lab, ": ", nboot, " bootstrap replicates done")
  }
  list(est = est, grid = grid, U = U, specs = specs)
}

# --- method 5: year t to t+1 ------------------------------------------------------------------------
#' Correlation of season-centred rates in consecutive seasons (both with MPAIR or more events in the
#' role), against the correlation stable talent would give: 1 / sqrt((1 + k E[1/n_t]) (1 + k E[1/n_t+1]))
#' with k estimated (ANOVA moments) on the same paired player-seasons. Ratio = talent persistence.
cross_season <- function(role, U, specs, nboot) {
  q <- U[n_pa >= MPAIR[[role]], .(pid, season, uid)]
  pr <- merge(q, q[, .(pid, season = season - 1L, uid2 = uid)], by = c("pid", "season"))[season %in% PAIRS_T]
  pids <- unique(pr$pid)
  wmat <- replicate(nboot, tabulate(sample.int(length(pids), length(pids), TRUE), length(pids)))
  rbindlist(lapply(seq_len(nrow(specs)), function(j) {
    sp <- specs[j]; m <- sp$metric; st <- sp$set
    p <- pr[season %in% sp$seasons[[1]] & (season + 1L) %in% sp$seasons[[1]]]
    n <- U[[paste0("n_", st)]]; s1 <- U[[paste0("s1_", m)]]; s2 <- s2_of(U, m, sp$binary); mu <- league_mu(U, m, st)
    p <- p[n[uid] > 0 & n[uid2] > 0]
    i1 <- p$uid; i2 <- p$uid2; pp <- match(p$pid, pids)
    c1 <- s1[i1] / n[i1] - mu[i1]; c2 <- s1[i2] / n[i2] - mu[i2]
    us <- unique(c(i1, i2)); up <- match(U$pid[us], pids)
    stat <- function(wp) {
      wpair <- wp[pp]
      r <- stats::cov.wt(cbind(c1, c2), wt = wpair / sum(wpair), cor = TRUE)$cor[1, 2]
      k <- mom_k(n[us], s1[us], s2[us], U$season[us], wp[up])
      rexp <- 1 / sqrt((1 + k * sum(wpair / n[i1]) / sum(wpair)) * (1 + k * sum(wpair / n[i2]) / sum(wpair)))
      c(r, k, rexp, r / rexp)
    }
    pt <- stat(rep(1, length(pids)))
    bt <- apply(wmat, 2, stat)
    ci <- apply(bt, 1, stats::quantile, c(.025, .975), na.rm = TRUE)
    data.table(role = role, metric = m, label = sp$label, pairs = nrow(p), players = uniqueN(p$pid),
               min_events = MPAIR[[role]], r = pt[1], r_lo = ci[1, 1], r_hi = ci[2, 1], k_pairs = pt[2],
               r_stable = pt[3], persistence = pt[4], pers_lo = ci[1, 4], pers_hi = ci[2, 4])
  }))
}

# --- run -----------------------------------------------------------------------------------------------
cl <- makePSOCKcluster(WORKERS)
invisible(clusterEvalQ(cl, suppressPackageStartupMessages(library(data.table))))
clusterExport(cl, c("exact_curve", "kr21_exact", "sb_fit", "re_fit", "bb_fit", "mom_k", "s2_of", "league_mu",
                    "NGRID", "MIN_UNITS", "KMAX"))
ROLES <- c("hitter", "starter", "reliever")
main <- lapply(ROLES, function(r) run_role(r, MAIN, B, cl, sens = TRUE)); names(main) <- ROLES
era  <- lapply(ROLES, function(r) run_role(r, ERA, B_ERA, cl)); names(era) <- ROLES
stopCluster(cl)
cross <- rbindlist(lapply(ROLES, function(r) cross_season(r, main[[r]]$U, main[[r]]$specs, B)))
say("cross-season done")

est  <- rbindlist(c(lapply(main, `[[`, "est"), lapply(era, `[[`, "est")), fill = TRUE)
grid <- rbindlist(c(lapply(main, `[[`, "grid"), lapply(era, `[[`, "grid")), fill = TRUE)
grid[, implied_k := N * (1 - kr21_sim) / kr21_sim]

# model and recency-study comparisons
est[, model_key := sub("^x_", "", metric)]
est[, model_k := NA_real_]
est[role == "hitter" & metric %in% OUTCOMES, model_k := MK$bat[model_key]]
est[role != "hitter" & (metric %in% c("k", "ubb", "hbp") | grepl("^x_", metric)), model_k := MK$pit[model_key]]
est[, recency_k := NA_real_]
rec <- tryCatch(fread(file.path(RES, "recency", "reliability-validation.csv")), error = function(e) NULL)
if (!is.null(rec)) {
  rmap <- data.table(role = rep(c("hitter", "starter"), each = 3), metric = rep(c("k", "ubb", "hr"), 2),
                     component = rep(c("hitters", "starters"), each = 3),
                     rate = c("K per PA", "BB+HBP per PA", "HR per PA", "K per BF", "BB+HBP per BF", "HR per BF"))
  rmap <- merge(rmap, rec[, .(component, rate, rk = implied_k)], by = c("component", "rate"))
  est[rmap, on = .(role, metric), recency_k := i.rk]
}
est[, `:=`(ratio_kr = model_k / k_kr21, ratio_re = model_k / k_re, n70_kr = 7 / 3 * k_kr21, n70_re = 7 / 3 * k_re)]
verdict <- function(mk, r1, r2, role, metric) {
  if (role != "hitter" && metric %in% BIP5) return("model shrinks the x version instead")
  if (is.na(mk)) return("not a model rate")
  if (!is.finite(r1) || !is.finite(r2)) return("not estimable")
  hi <- c(r1, r2) >= 2; lo <- c(r1, r2) <= 0.5
  if (all(hi)) return("TOO MUCH shrink: model k 2x+ both estimates")
  if (all(lo)) return("TOO LITTLE shrink: model k under half of both")
  if (hi[1]) return("too much vs KR-21 only")
  if (hi[2]) return("too much vs beta-binomial only")
  if (lo[1]) return("too little vs KR-21 only")
  if (lo[2]) return("too little vs beta-binomial only")
  "consistent (within 2x of both)"
}
est[, verdict := mapply(verdict, model_k, ratio_kr, ratio_re, role, metric)]
ord <- c(OUTCOMES, paste0("x_", BIP5), "babip", "gb", "fb", "ld", "pu")
est[, `:=`(ro = match(role, ROLES), mo = match(metric, ord))]
setorder(est, scope, ro, mo); est[, c("ro", "mo", "model_key") := NULL]
fwrite(est, file.path(OUT, "estimates.csv"))
fwrite(grid[, .(role, scope, metric, N, units, kr21_sim, kr21_mcse, kr21_exact, implied_k, units_2N, split_sim)],
       file.path(OUT, "alpha-grid.csv"))

# --- markdown tables -------------------------------------------------------------------------------------
fk <- function(x) ifelse(!is.finite(x), "n/a", ifelse(x >= 0.99 * KMAX, "> 100,000",
                         formatC(signif(x, 3), format = "d", big.mark = ",")))
fci <- function(lo, hi) ifelse(is.finite(lo), sprintf("[%s, %s]", fk(lo), fk(hi)), "")
f2 <- function(x) ifelse(is.finite(x), sprintf("%.2f", x), "n/a")
md <- c("# Reliability tables (generated by reliability.R)", "",
        "The information used here was obtained free of charge from and is copyrighted by Retrosheet.", "",
        sprintf("Draws per grid point: %d. Bootstrap replicates: %d (2015-2022), %d (2023-2025).", D, B, B_ERA), "")
unit_word <- c(hitter = "PA", starter = "BF", reliever = "BF")
for (r in ROLES) {
  x <- est[scope == "2015-2022" & role == r]
  md <- c(md, sprintf("## %ss, 2015-2022 (k in %s; BABIP-like in balls in play, batted-ball shares in batted balls)",
                      tools::toTitleCase(r), unit_word[[r]]), "",
          "| Outcome | Rate | Units | k KR-21+SB [95% CI] | k random effects [95% CI] | N at 0.7 (KR / RE) | Model k | Recency study | Verdict |",
          "|---|---|---|---|---|---|---|---|---|",
          sprintf("| %s | %.3f | %s | %s %s | %s %s | %s / %s | %s | %s | %s |", x$label, x$mean_rate,
                  formatC(x$units, format = "d", big.mark = ","), fk(x$k_kr21), fci(x$kr_lo, x$kr_hi),
                  fk(x$k_re), fci(x$re_lo, x$re_hi), fk(x$n70_kr), fk(x$n70_re), fk(x$model_k),
                  ifelse(is.na(x$recency_k), "", fk(x$recency_k)), x$verdict), "")
}
md <- c(md, "## Cross-checks, 2015-2022", "",
        "| Role | Outcome | KR-21 sim | KR-21 exact | Split-half | RE all units | RE on units with N* or more | KR-21 implied at N* | N* | ANOVA moments | Drop 2020: KR / RE | ANOVA park-neutral |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|")
x <- est[scope == "2015-2022"]
md <- c(md, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %d | %s | %s / %s | %s |", x$role, x$label, fk(x$k_kr21),
                    fk(x$k_kr21_exact), fk(x$k_split), fk(x$k_re), fk(x$k_re_surv), fk(x$k_kr21_at_nstar), x$nstar,
                    fk(x$k_mom), fk(x$k_kr21_no2020), fk(x$k_re_no2020), fk(x$k_mom_park)), "")
e2 <- merge(est[scope == "2015-2022", .(role, metric, label, kk = k_kr21, kr = k_re)],
            est[scope == "2023-2025", .(role, metric, ek = k_kr21, ekl = kr_lo, ekh = kr_hi, er = k_re, erl = re_lo, erh = re_hi)],
            by = c("role", "metric"))
e2[, `:=`(ro = match(role, ROLES), mo = match(metric, ord))]; setorder(e2, ro, mo)
md <- c(md, "## Era check, 2023-2025 (not used for any choice)", "",
        "| Role | Outcome | KR-21+SB 2015-22 | KR-21+SB 2023-25 [95% CI] | RE 2015-22 | RE 2023-25 [95% CI] |",
        "|---|---|---|---|---|---|",
        sprintf("| %s | %s | %s | %s %s | %s | %s %s |", e2$role, e2$label, fk(e2$kk), fk(e2$ek), fci(e2$ekl, e2$ekh),
                fk(e2$kr), fk(e2$er), fci(e2$erl, e2$erh)), "")
cross[, `:=`(ro = match(role, ROLES), mo = match(metric, ord))]; setorder(cross, ro, mo); cross[, c("ro", "mo") := NULL]
fwrite(cross, file.path(OUT, "cross-season.csv"))
md <- c(md, "## Year t to t+1 (pairs 2015-16 to 2018-19 and 2021-22)", "",
        "| Role | Outcome | Pairs | Min events | r [95% CI] | r if talent were stable | Persistence [95% CI] |",
        "|---|---|---|---|---|---|---|",
        sprintf("| %s | %s | %d | %d | %s [%s, %s] | %s | %s [%s, %s] |", cross$role, cross$label, cross$pairs, cross$min_events,
                f2(cross$r), f2(cross$r_lo), f2(cross$r_hi), f2(cross$r_stable), f2(cross$persistence),
                f2(cross$pers_lo), f2(cross$pers_hi)), "")
writeLines(md, file.path(OUT, "tables.md"))

# --- plot: alpha vs N --------------------------------------------------------------------------------------
PLOT_M <- c(k = "K", ubb = "BB", hr = "HR", babip = "BABIP", gb = "GB share")
COLS <- c(K = "#2a78d6", BB = "#eb6834", HR = "#1baf7a", BABIP = "#eda100", `GB share` = "#e87ba4")
FACET <- c(hitter = "Hitters (N = PA)", starter = "Starters (N = BF)", reliever = "Relievers (N = BF)")
FIT <- c("KR-21 + Spearman-Brown fit", "Beta-binomial, all player-seasons")
pts <- grid[scope == "2015-2022" & metric %in% names(PLOT_M) & is.finite(kr21_sim)]
pe <- est[scope == "2015-2022" & metric %in% names(PLOT_M)]
nx <- seq(5, 800, by = 5)
cur <- rbindlist(lapply(seq_len(nrow(pe)), function(i) data.table(role = pe$role[i], metric = pe$metric[i],
  N = rep(nx, 2), method = rep(FIT, each = length(nx)),
  alpha = c(nx / (nx + pe$k_kr21[i]), nx / (nx + pe$k_re[i])))))
cur[, method := factor(method, FIT)]
lab <- cur[N == 800 & method == FIT[1]]
pts[, `:=`(stat = factor(PLOT_M[metric], PLOT_M), panel = factor(FACET[role], FACET))]
cur[, `:=`(stat = factor(PLOT_M[metric], PLOT_M), panel = factor(FACET[role], FACET))]
lab[, `:=`(stat = factor(PLOT_M[metric], PLOT_M), panel = factor(FACET[role], FACET))]
setorder(lab, panel, -alpha)
lab[, ylab := { y <- alpha; if (length(y) > 1) for (i in 2:length(y)) y[i] <- min(y[i], y[i - 1] - 0.055); y }, by = panel]
p <- ggplot() +
  geom_hline(yintercept = c(0.5, 0.7), colour = "#b5b3ad", linewidth = 0.4, linetype = "dotted") +
  geom_line(data = cur, aes(N, alpha, colour = stat, linetype = method), linewidth = 0.7) +
  geom_point(data = pts, aes(N, kr21_sim, colour = stat), size = 1.6) +
  geom_text(data = lab, aes(x = 815, y = ylab, label = stat, colour = stat), hjust = 0, size = 3, show.legend = FALSE) +
  facet_wrap(~panel, nrow = 1) +
  scale_colour_manual(values = COLS, name = NULL) +
  scale_linetype_manual(values = setNames(c("solid", "22"), FIT), name = NULL) +
  scale_x_continuous(limits = c(0, 930), breaks = seq(0, 800, 200)) +
  scale_y_continuous(limits = c(-0.05, 1), breaks = c(0, 0.25, 0.5, 0.7, 1)) +
  labs(x = "Events in the sample (BABIP counts balls in play; GB share counts batted balls)",
       y = "Reliability (alpha)", title = "How fast MLB per-PA rates become reliable, 2015-2022",
       caption = paste0("Points: KR-21 alpha on N random events per player-season, mean of ", D,
                        " draws, season-centred. Lines: alpha(N) = N / (N + k). Dotted: 0.5 (N = k) and 0.7 (N = 2.33k).",
                        "\nThe information used here was obtained free of charge from and is copyrighted by Retrosheet.")) +
  theme_minimal(base_size = 10) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA), panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = "#e8e7e3", linewidth = 0.3), legend.position = "bottom",
        legend.box = "horizontal", text = element_text(colour = "#0b0b0b"),
        axis.text = element_text(colour = "#52514e"), plot.caption = element_text(colour = "#52514e", hjust = 0),
        strip.text = element_text(face = "bold", hjust = 0))
ggsave(file.path(RES, "reliability-alpha-vs-n.png"), p, width = 12, height = 5.2, dpi = 150, bg = "#fcfcfb")
say("done: ", OUT)
