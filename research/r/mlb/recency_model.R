#!/usr/bin/env Rscript
# Recency study, win-model stage (RECENCY-PLAN.md "Win model and baselines").
#
#   Rscript research/r/mlb/recency_model.R validation        # 2017-2019, from 2015-2019 data
#   Rscript research/r/mlb/recency_model.R test              # 2021-2025, scored once
#   Rscript research/r/mlb/recency_model.R forward           # + 2026, exploratory, csv only
#
# Windows come from results/recency/picks-validation.csv and grid-validation.csv, frozen before
# any test row is loaded. One row per game, home side; weekly walk-forward logistic refits.

suppressPackageStartupMessages({ library(dplyr); library(purrr) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("ingest.R", "gamelogs.R", "windows.R", "recency_data.R")) source(file.path(SRC, f))
RES <- file.path(SRC, "results", "recency")

mode <- commandArgs(TRUE)[1]
stopifnot(mode %in% c("validation", "test", "forward"))
# forward: exploratory, post hoc 2026 predictions from the frozen spec (2021-2025 rerun alongside as
# the reproduction check); writes the csv only, never a scored md. RECENCY_OUT (unset by default)
# sends the csv and md to another directory so a rerun cannot overwrite committed results.
PRED  <- switch(mode, test = 2021:2025, forward = 2021:2026, 2017:2019)
LOAD  <- switch(mode, test = 2015:2025, forward = 2015:2026, 2015:2019)
OUT   <- Sys.getenv("RECENCY_OUT")
out_md <- file.path(if (nzchar(OUT)) OUT else file.path(SRC, "results"), sprintf("recency-model-%s.md", mode))
if (mode == "test" && file.exists(out_md) && !"--force" %in% commandArgs(TRUE))
  stop(out_md, " exists: the test is scored once. --force only if 2021-2025 are to become validation.")

picks <- utils::read.csv(file.path(RES, "picks-validation.csv"))
grid  <- utils::read.csv(file.path(RES, "grid-validation.csv"))
win_for <- function(rate, no_decay = FALSE) {
  if (!no_decay) { p <- picks[picks$rate == rate, ][1, ]; return(list(h = p[[3]], c = p[[4]], k = p[[5]])) }
  g <- grid[grid$rate == rate & is.infinite(grid$h) & grid$c == 1, ] |>
    dplyr::group_by(k) |> dplyr::summarise(s = 1 - sum(sse) / sum(sse0), .groups = "drop")
  list(h = Inf, c = 1, k = g$k[which.max(g$s)])
}

# --- data -----------------------------------------------------------------------------------

L      <- load_seasons(LOAD)
bounds <- dplyr::bind_rows(lapply(L, `[[`, "bounds"))
sched  <- schedule_rows(L)
venue  <- sched[c("game_pk", "venue_id")]
add_t  <- function(d) { d$t <- season_day(d$Date, d$season, bounds); d }

hit <- merge(hitter_rows(L), venue, by = "game_pk")
hit <- add_t(park_adjust(hit, park_factors(hit, "woba", "woba_den"), "woba"))
pit <- merge(pitcher_rows(L), venue, by = "game_pk")
for (n in c("so", "bbhbp", "hr", "fip")) pit <- park_adjust(pit, park_factors(pit, n, "bf"), n)
pit <- add_t(pit)
team <- add_t(team_rows(L, hitter_rows(L)))
games <- add_t(sched[sched$season >= 2016, ])

est <- function(events, q, num, den, w) {
  lgq <- data.frame(entity = "lg", Date = q$Date, season = q$season, t = q$t)
  lge <- stats::aggregate(events[c(num, den)], events[c("Date", "season", "t")], sum); lge$entity <- "lg"
  lg  <- asof_decay(lge, lgq, c(num, den), h = 30, c = 1)
  S   <- asof_decay(events, q, c(num, den), w$h, w$c)
  shrink_rate(S[, 1], S[, 2], w$k, lg[, 1] / pmax(lg[, 2], 1e-9))
}

#' Every input gap, home minus away, with each component at its chosen (or no-decay) window.
features <- function(no_decay = FALSE) {
  W <- function(r) win_for(r, no_decay)
  f <- data.frame(game_pk = games$game_pk)
  # lineup: mean shrunk wOBA of the nine posted starters
  side_lineup <- function(side) {
    q <- dplyr::bind_rows(lapply(1:9, function(i) data.frame(row = seq_len(nrow(games)),
      entity = games[[paste0(side, "_bat", i)]], Date = games$Date, season = games$season, t = games$t)))
    v <- est(hit, q, "woba", "woba_den", W("wOBA per PA"))
    v[is.na(q$entity)] <- NA
    tapply(v, q$row, mean, na.rm = TRUE)
  }
  f$lineup <- side_lineup("home") - side_lineup("away")
  # probable starter: FIP-style from his K, BB+HBP and HR rates, each at its own window
  side_sp <- function(side) {
    q <- data.frame(entity = games[[paste0(side, "_sp")]], Date = games$Date, season = games$season, t = games$t)
    q$entity[is.na(q$entity)] <- -1                                   # unknown starter: league rates
    13 * est(pit, q, "hr", "bf", W("HR per BF")) + 3 * est(pit, q, "bbhbp", "bf", W("BB+HBP per BF")) -
      2 * est(pit, q, "so", "bf", W("K per BF"))
  }
  f$starter <- side_sp("home") - side_sp("away")
  # bullpen: pitchers who relieved for the team in the last 21 days, weighted by relief BF there
  rel <- pit[pit$role != "start", ]
  side_pen <- function(side) {
    tid <- games[[paste0(side, "_id")]]
    key <- unique(data.frame(team_id = tid, Date = games$Date, season = games$season, t = games$t))
    by_team <- split(rel[order(rel$Date), ], rel$team_id[order(rel$Date)])
    members <- dplyr::bind_rows(lapply(split(seq_len(nrow(key)), key$team_id), function(ii) {
      r <- by_team[[as.character(key$team_id[ii[1]])]]
      if (is.null(r)) return(NULL)
      dn <- as.numeric(r$Date); qd <- as.numeric(key$Date[ii])
      hi <- findInterval(qd - 1, dn); lo <- findInterval(qd - 22, dn)       # rows in [d - 21, d - 1]
      dplyr::bind_rows(lapply(which(hi > lo), function(j) {
        s <- r[(lo[j] + 1):hi[j], ]
        a <- rowsum(s$bf, s$entity)
        data.frame(key = ii[j], entity = as.numeric(rownames(a)), w = a[, 1])
      }))
    }))
    q <- data.frame(entity = members$entity, Date = key$Date[members$key], season = key$season[members$key],
                    t = key$t[members$key])
    members$fip <- est(pit, q, "fip", "bf", W("FIP-style per BF"))
    pen <- tapply(members$fip * members$w, members$key, sum) / tapply(members$w, members$key, sum)
    v <- rep(NA_real_, nrow(key)); v[as.integer(names(pen))] <- pen
    # fatigue: relief pitches thrown the previous day and previous three days
    tq <- data.frame(entity = key$team_id, Date = key$Date)
    te <- data.frame(entity = rel$team_id, Date = rel$Date, p = dplyr::coalesce(rel$pitches, 0))
    p1 <- asof_sums(te, tq, "p", trailing_sum, 1)[, 1]; p3 <- asof_sums(te, tq, "p", trailing_sum, 3)[, 1]
    m <- match(paste(tid, games$Date), paste(key$team_id, key$Date))
    data.frame(pen = v[m], p1 = p1[m], p3 = p3[m])
  }
  hp <- side_pen("home"); ap <- side_pen("away")
  f$bullpen <- hp$pen - ap$pen; f$fatigue1 <- hp$p1 - ap$p1; f$fatigue3 <- hp$p3 - ap$p3
  # run differential per game
  side_rd <- function(side) {
    q <- data.frame(entity = games[[paste0(side, "_id")]], Date = games$Date, season = games$season, t = games$t)
    est(team, q, "margin", "games", W("run margin per game"))
  }
  f$rd <- side_rd("home") - side_rd("away")
  f
}

#' The incumbent's carrying part: season-to-date run differential per game shrunk by 20 games
#' (commit b15a7af). Its Baseball-Reference pitching term does not exist past 2019 and tied
#' home field when it did, so C is scored as home field + this gap.
incumbent_rd <- function() {
  q <- function(side) data.frame(entity = games[[paste0(side, "_id")]], Date = games$Date,
                                 season = games$season, t = games$t)
  S <- function(side) asof_decay(team, q(side), c("margin", "games"), h = Inf, c = 0)
  h <- S("home"); a <- S("away")
  h[, 1] / (h[, 2] + 20) - a[, 1] / (a[, 2] + 20)
}

#' Elo with margin of victory, as of each date (a day's games are rated after all are predicted).
elo <- function(K, carry, hfa = 24) {
  r <- list(); out <- numeric(nrow(games)); last_season <- NA
  ord <- order(games$Date, games$game_pk)
  for (d in sort(unique(games$Date))) {
    i <- ord[games$Date[ord] == d]
    s <- games$season[i[1]]
    if (!identical(s, last_season)) { r <- lapply(r, function(x) 1500 + carry * (x - 1500)); last_season <- s }
    get <- function(id) { v <- r[[as.character(id)]]; if (is.null(v)) 1500 else v }
    rh <- vapply(games$home_id[i], get, 0); ra <- vapply(games$away_id[i], get, 0)
    out[i] <- rh + hfa - ra
    m  <- games$home_score[i] - games$away_score[i]
    ex <- 1 / (1 + 10^(-(rh + hfa - ra) / 400))
    mov <- log(abs(m) + 1) * 2.2 / (0.001 * ifelse(m > 0, 1, -1) * (rh + hfa - ra) + 2.2)
    delta <- K * mov * ((m > 0) - ex)
    for (j in seq_along(i)) {
      r[[as.character(games$home_id[i[j]])]] <- rh[j] + delta[j]
      r[[as.character(games$away_id[i[j]])]] <- ra[j] - delta[j]
    }
  }
  out
}

# --- walk-forward scoring -------------------------------------------------------------------

walk <- function(df, formula) {
  df$block <- as.Date(cut(df$Date, "week"))
  p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% PRED]))) {
    i <- which(df$block == b & df$season %in% PRED)
    tr <- df[df$Date < b, ]
    m <- stats::glm(formula, stats::binomial, tr)
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}

ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))

base <- data.frame(game_pk = games$game_pk, Date = games$Date, season = games$season,
                   home_team = games$home_id, y = as.integer(games$home_score > games$away_score))
E  <- merge(base, features(FALSE), by = "game_pk")
E0 <- merge(base, features(TRUE), by = "game_pk")
E  <- E[order(E$Date, E$game_pk), ]; E0 <- E0[match(E$game_pk, E0$game_pk), ]
for (v in c("lineup", "starter", "bullpen", "fatigue1", "fatigue3", "rd")) {
  E[[v]][is.na(E[[v]])] <- 0; E0[[v]][is.na(E0[[v]])] <- 0
}
E$c_rd <- incumbent_rd()[match(E$game_pk, games$game_pk)]

# Elo: K and carry chosen on validation games only (in test mode the validation seasons are
# re-scored from the same loaded data, before any test prediction is made)
VAL <- 2017:2019
elo_grid <- expand.grid(K = c(4, 6, 8, 12), carry = c(0.5, 0.67, 0.8))
elo_ll <- apply(elo_grid, 1, function(g) {
  E$elo <- elo(g[["K"]], g[["carry"]])[match(E$game_pk, games$game_pk)]
  v <- E$season %in% VAL
  m <- stats::glm(y ~ elo, stats::binomial, E[E$season < 2017 | v, ])   # in-sample fit, ranking only
  mean(ll(stats::predict(m, E[v, ], type = "response"), E$y[v]))
})
eg <- elo_grid[which.min(elo_ll), ]
E$elo <- elo(eg$K, eg$carry)[match(E$game_pk, games$game_pk)]

P <- data.frame(game_pk = E$game_pk, Date = E$Date, season = E$season, home_team = E$home_team, y = E$y)
P$A  <- NA; P$B <- walk(E, y ~ 1)
P$A  <- P$B      # constant and home-only coincide in a home-side frame: the intercept IS home field
P$C  <- walk(E, y ~ c_rd)
P$D  <- walk(E, y ~ elo)
P$E0 <- walk(transform(E0, Date = E$Date, season = E$season), y ~ lineup + starter + bullpen + fatigue1 + fatigue3 + rd)
P$E  <- walk(E, y ~ lineup + starter + bullpen + fatigue1 + fatigue3 + rd)
P <- P[P$season %in% PRED, ]

csv_dir <- if (nzchar(OUT)) OUT else RES
dir.create(csv_dir, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(P, file.path(csv_dir, sprintf("model-predictions-%s.csv", mode)), row.names = FALSE)
message("Elo pick: K ", eg$K, ", carry ", eg$carry)
message("wrote predictions for ", nrow(P), " games")
if (mode == "forward") quit(save = "no")   # exploratory: no scoring, no verdict

# --- score ------------------------------------------------------------------------------------

tiers <- c("B", "C", "D", "E0", "E")
P$cluster <- paste(P$home_team, P$season)
brier <- function(p, y) (p - y)^2
per_season <- dplyr::bind_rows(lapply(c(sort(unique(P$season)), 0L), function(s) {
  x <- if (s == 0) P else P[P$season == s, ]
  data.frame(season = if (s == 0) "pooled" else as.character(s), games = nrow(x),
             t(vapply(tiers, function(m) mean(ll(x[[m]], x$y)), 0)),
             acc_E = mean((x$E > 0.5) == x$y), acc_C = mean((x$C > 0.5) == x$y), check.names = FALSE)
}))
paired <- function(a, b, B = 1000) {      # positive = b better than a on log loss
  d  <- ll(P[[a]], P$y) - ll(P[[b]], P$y)
  by <- tapply(d, P$cluster, sum); n <- tapply(d, P$cluster, length)
  set.seed(20261003)
  boot <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  c(gain = mean(d), stats::quantile(boot, c(0.025, 0.975)))
}
calib <- function(m) {
  z <- stats::qlogis(pmin(pmax(P[[m]], 1e-6), 1 - 1e-6))
  s <- summary(stats::glm(P$y ~ z, stats::binomial))$coefficients
  i <- summary(stats::glm(P$y ~ 1 + offset(z), stats::binomial))$coefficients
  c(intercept = i[1, 1], int_lo = i[1, 1] - 1.96 * i[1, 2], int_hi = i[1, 1] + 1.96 * i[1, 2],
    slope = s[2, 1], slope_lo = s[2, 1] - 1.96 * s[2, 2], slope_hi = s[2, 1] + 1.96 * s[2, 2])
}
fmt <- function(x, d = 4) formatC(x, format = "f", digits = d)
EvC <- paired("C", "E"); EvE0 <- paired("E0", "E"); EvD <- paired("D", "E"); CvB <- paired("B", "C")
cal <- calib("E")
seasons_won <- sum(per_season$E[per_season$season != "pooled"] < per_season$C[per_season$season != "pooled"])
gate <- EvC[2] > 0 && seasons_won >= ceiling(0.8 * (nrow(per_season) - 1)) &&
  cal["int_lo"] < 0 && cal["int_hi"] > 0 && cal["slope_lo"] < 1 && cal["slope_hi"] > 1
lines <- c(sprintf("# Recency study: win model, %s", mode), "",
  sprintf("Generated %s by `Rscript research/r/mlb/recency_model.R %s`. %d games, one row per game, home side, weekly walk-forward refits.",
          format(Sys.Date()), mode, nrow(P)), "",
  "Tiers: B home field (equals the constant model in a home-side frame); C incumbent run differential",
  sprintf("(season to date, shrunk 20 games); D Elo with margin (K %s, carry %s, picked on 2017-2019); E0 E's inputs with no", eg$K, eg$carry),
  "decay (all history, carry 1, no recency term); E lineup, probable starter, bullpen, fatigue and run differential at the chosen windows.", "",
  "## Log loss by season (lower is better)", "",
  paste0("| season | games | ", paste(tiers, collapse = " | "), " | accuracy E | accuracy C |"),
  paste0("|", strrep(" --- |", length(tiers) + 4)),
  apply(per_season, 1, function(r) paste0("| ", r[["season"]], " | ", r[["games"]], " | ",
        paste(fmt(as.numeric(r[tiers])), collapse = " | "), " | ", fmt(100 * as.numeric(r[["acc_E"]]), 1), "% | ",
        fmt(100 * as.numeric(r[["acc_C"]]), 1), "% |")), "",
  "## Paired log-loss gains, team-season cluster bootstrap (positive = second model better)", "",
  "| contrast | gain | 95% interval |", "| --- | --- | --- |",
  sprintf("| C over B (incumbent vs home field) | %s | [%s, %s] |", fmt(CvB[1], 5), fmt(CvB[2], 5), fmt(CvB[3], 5)),
  sprintf("| E over C (slide decision) | %s | [%s, %s] |", fmt(EvC[1], 5), fmt(EvC[2], 5), fmt(EvC[3], 5)),
  sprintf("| E over E0 (recency at win level) | %s | [%s, %s] |", fmt(EvE0[1], 5), fmt(EvE0[2], 5), fmt(EvE0[3], 5)),
  sprintf("| E over D (vs Elo) | %s | [%s, %s] |", fmt(EvD[1], 5), fmt(EvD[2], 5), fmt(EvD[3], 5)), "",
  sprintf("Calibration of E: intercept %s [%s, %s], slope %s [%s, %s].", fmt(cal[1], 3), fmt(cal[2], 3), fmt(cal[3], 3),
          fmt(cal[4], 3), fmt(cal[5], 3), fmt(cal[6], 3)), "",
  sprintf("E beats C in %d of %d seasons. Ship rule (test only): E over C interval above zero, 4 of 5 seasons, calibration intervals cover 0 and 1: **%s**.",
          seasons_won, nrow(per_season) - 1, if (mode == "test") (if (gate) "PASS" else "FAIL") else "not applied on validation"), "",
  "Not evidence of betting profit: there is no market baseline.")
writeLines(lines, out_md)
message("wrote ", out_md)
