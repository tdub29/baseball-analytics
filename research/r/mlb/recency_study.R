#!/usr/bin/env Rscript
# Recency study, validation stage (RECENCY-PLAN.md tests 1-4 and 6). Loads 2015-2019 only, so no
# test-season row can reach a choice; scores 2017-2019.
#
#   Rscript research/r/mlb/recency_study.R
#
# Writes research/r/mlb/results/recency/ (grid, lambda, reliability CSVs) and
# results/recency-validation.md.

suppressPackageStartupMessages({ library(dplyr); library(purrr) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("ingest.R", "gamelogs.R", "windows.R", "recency_data.R")) source(file.path(SRC, f))

VALID <- 2017:2019
H     <- c(7, 14, 30, 60, 120, 240, Inf)
CARRY <- c(0, 0.25, 0.5, 0.75, 1)
LAMBDA <- expand.grid(lambda = c(0.5, 1, 2), r = c(7, 14))
SESOI <- 0.001          # skill units: 0.1% of the outcome's variance around the league target
OUT   <- file.path(SRC, "results", "recency")
SMOKE <- Sys.getenv("SMOKE") == "1"          # tiny grid, for catching wiring bugs fast
if (SMOKE) { H <- c(30, Inf); CARRY <- 0.5; LAMBDA <- LAMBDA[1, ]; OUT <- file.path(OUT, "smoke") }

# --- one rate: grid, league target, scoring -------------------------------------------------

league_target <- function(events, queries, num, den) {
  lg <- stats::aggregate(events[c(num, den)], events[c("Date", "season", "t")], sum)
  lg$entity <- "lg"
  q <- data.frame(entity = "lg", Date = queries$Date, season = queries$season, t = queries$t)
  s <- asof_decay(lg, q, c(num, den), h = 30, c = 1)
  s[, 1] / pmax(s[, 2], 1e-9)
}

#' Squared-error sums by season for every (h, c, k), lambda = 0.
grid_rate <- function(events, queries, num, den, kbase, league) {
  y <- queries[[paste0("y_", num)]] / queries[[paste0("y_", den)]]
  w <- queries[[paste0("y_", den)]]
  K <- kbase * 2^(0:7)
  base <- tapply(w * (y - league)^2, queries$season, sum)
  rows <- list()
  for (h in H) for (cc in CARRY) {
    S <- asof_decay(events, queries, c(num, den), h, cc)
    for (k in K) {
      e <- tapply(w * (y - shrink_rate(S[, 1], S[, 2], k, league))^2, queries$season, sum)
      rows[[length(rows) + 1]] <- data.frame(h = h, c = cc, k = k, season = as.integer(names(e)),
                                             sse = as.numeric(e), sse0 = as.numeric(base[names(e)]))
    }
  }
  dplyr::bind_rows(rows)
}

skill <- function(g) 1 - sum(g$sse) / sum(g$sse0)

#' Pick (h, c, k) on some seasons; leave-one-season-out shows how stable the pick is.
pick <- function(grid, seasons) {
  s <- grid[grid$season %in% seasons, ] |> dplyr::group_by(h, c, k) |>
    dplyr::summarise(skill = 1 - sum(sse) / sum(sse0), .groups = "drop")
  s[which.max(s$skill), ]
}

loso <- function(grid) dplyr::bind_rows(lapply(VALID, function(s) {
  p <- pick(grid, setdiff(VALID, s))
  held <- grid[grid$season == s & grid$h == p$h & grid$c == p$c & grid$k == p$k, ]
  data.frame(held_out = s, ho_h = p$h, ho_c = p$c, ho_k = p$k, held_out_skill = skill(held))
}))

#' Lambda: does weight on the last r days add beyond the smooth decay? Held out by season: for
#' each validation season, (h, c, k) and then (lambda, r, k) are picked on the other two, and both
#' errors are taken on the held-out season. Cluster bootstrap of the pooled held-out gain.
lambda_rate <- function(events, queries, num, den, grid, league, cluster, B = 1000) {
  y  <- queries[[paste0("y_", num)]] / queries[[paste0("y_", den)]]
  w  <- queries[[paste0("y_", den)]]
  b0 <- w * (y - league)^2
  e0 <- e1 <- rep(NA_real_, nrow(queries)); chosen <- list()
  for (s in VALID) {
    p  <- pick(grid, setdiff(VALID, s))
    tr <- queries$season != s; ho <- !tr
    S0 <- asof_decay(events, queries, c(num, den), p$h, p$c)
    e0[ho] <- (w * (y - shrink_rate(S0[, 1], S0[, 2], p$k, league))^2)[ho]
    best <- NULL
    for (i in seq_len(nrow(LAMBDA))) {
      l  <- LAMBDA[i, ]
      S1 <- asof_decay(events, queries, c(num, den), p$h, p$c, l$lambda, l$r)
      for (k in p$k * 2^(-2:2)) {    # lambda adds weight, so k is re-picked on the new scale
        err <- w * (y - shrink_rate(S1[, 1], S1[, 2], k, league))^2
        if (is.null(best) || sum(err[tr]) < best$sse) best <- list(lambda = l$lambda, r = l$r, k = k, sse = sum(err[tr]), err = err)
      }
    }
    e1[ho] <- best$err[ho]
    chosen[[as.character(s)]] <- sprintf("%d: lambda %.1f, r %d, k %.0f", s, best$lambda, best$r, best$k)
  }
  by <- rowsum(cbind(e0, e1, b0), cluster)
  gain <- function(m) (sum(m[, 1]) - sum(m[, 2])) / sum(m[, 3])
  set.seed(20261003)
  boot <- replicate(if (SMOKE) 20 else B, gain(by[sample(nrow(by), replace = TRUE), , drop = FALSE]))
  ci <- stats::quantile(boot, c(0.05, 0.95))
  verdict <- if (ci[1] > SESOI) "matters" else if (ci[1] > -SESOI && ci[2] < SESOI) "equivalent to zero" else "inconclusive"
  data.frame(held_out_gain = gain(by), lo90 = ci[1], hi90 = ci[2], verdict = verdict,
             clusters = nrow(by), picks = paste(unlist(chosen), collapse = "; "), row.names = NULL)
}

#' Split-half reliability per entity-season (odd vs even appearances), Spearman-Brown.
reliability <- function(events, num, den, seasons = VALID) {
  e <- events[events$season %in% seasons, ]
  e <- e[order(e$entity, e$Date), ]
  e$half <- stats::ave(seq_len(nrow(e)), e$entity, e$season, FUN = function(i) seq_along(i) %% 2)
  a <- stats::aggregate(e[c(num, den)], e[c("entity", "season", "half")], sum)
  w <- stats::reshape(a, idvar = c("entity", "season"), timevar = "half", direction = "wide")
  d0 <- w[[paste0(den, ".0")]]; d1 <- w[[paste0(den, ".1")]]
  keep <- !is.na(d0) & !is.na(d1) & pmin(d0, d1) >= stats::quantile(pmin(d0, d1), 0.5, na.rm = TRUE)
  r <- stats::cor(w[[paste0(num, ".0")]][keep] / d0[keep], w[[paste0(num, ".1")]][keep] / d1[keep],
                  use = "complete.obs")
  n <- mean(d0[keep] + d1[keep])
  R <- 2 * r / (1 + r)
  data.frame(entities = sum(keep), n_per_season = n, r_half = r, r_full = R, implied_k = n * (1 - R) / R)
}

# --- assemble components --------------------------------------------------------------------

L      <- load_seasons(2015:2019)
bounds <- dplyr::bind_rows(lapply(L, `[[`, "bounds"))
sched  <- schedule_rows(L)
venue  <- sched[c("game_pk", "venue_id")]
add_t  <- function(d) { d$t <- season_day(d$Date, d$season, bounds); d }

hit <- merge(hitter_rows(L), venue, by = "game_pk")
for (p in list(c("woba", "woba_den"), c("so", "pa"), c("bbhbp", "pa"), c("hr", "pa")))
  hit <- park_adjust(hit, park_factors(hit, p[1], p[2]), p[1])
hit <- add_t(hit)

pit <- merge(pitcher_rows(L), venue, by = "game_pk")
for (n in c("so", "bbhbp", "hr", "runs", "kbb", "fip", "resp_runs"))
  pit <- park_adjust(pit, park_factors(pit, n, "bf"), n)
pit <- add_t(pit)

team <- team_rows(L, hitter_rows(L))
team <- park_adjust(team, park_factors(team[!is.na(team$woba), ], "woba", "woba_den"), "woba")
team <- add_t(team)

# queries: the starting lineup's hitters; starts; relief appearances; team-games, validation only
slots <- dplyr::bind_rows(lapply(c(paste0("home_bat", 1:9), paste0("away_bat", 1:9)), function(b)
  data.frame(entity = sched[[b]], game_pk = sched$game_pk, Date = sched$Date, season = sched$season)))
slots <- slots[!is.na(slots$entity) & slots$season %in% VALID, ]
outcome <- function(q, ev, cols) {
  y <- ev[c("entity", "game_pk", cols)]; names(y)[-(1:2)] <- paste0("y_", cols)
  merge(q, y, by = c("entity", "game_pk"))
}
q_hit  <- add_t(outcome(slots, hit, c("woba", "woba_den", "so", "bbhbp", "hr", "pa")))
q_hit$cluster <- paste(hit$team_id[match(paste(q_hit$entity, q_hit$game_pk), paste(hit$entity, hit$game_pk))], q_hit$season)
q_start <- pit[pit$role == "start" & pit$season %in% VALID, c("entity", "game_pk", "Date", "season", "t")]
q_start <- outcome(q_start, pit, c("so", "bbhbp", "hr", "runs", "bf")); q_start$cluster <- paste(q_start$entity, q_start$season)
q_rel <- pit[pit$role != "start" & pit$season %in% VALID, c("entity", "game_pk", "Date", "season", "t")]
q_rel <- outcome(q_rel, pit, c("kbb", "fip", "resp_runs", "bf")); q_rel$cluster <- paste(q_rel$entity, q_rel$season)
q_team <- team[team$season %in% VALID, c("entity", "game_pk", "Date", "season", "t")]
q_team <- outcome(q_team, team, c("margin", "games", "woba", "woba_den")); q_team$cluster <- paste(q_team$entity, q_team$season)

PLAN <- list(
  list("hitters", "wOBA per PA", hit, q_hit, "woba", "woba_den", 25),
  list("hitters", "K per PA", hit, q_hit, "so", "pa", 25),
  list("hitters", "BB+HBP per PA", hit, q_hit, "bbhbp", "pa", 25),
  list("hitters", "HR per PA", hit, q_hit, "hr", "pa", 25),
  list("starters", "K per BF", pit, q_start, "so", "bf", 25),
  list("starters", "BB+HBP per BF", pit, q_start, "bbhbp", "bf", 25),
  list("starters", "HR per BF", pit, q_start, "hr", "bf", 25),
  list("starters", "runs per BF", pit, q_start, "runs", "bf", 25),
  list("relievers", "K-BB per BF", pit, q_rel, "kbb", "bf", 25),
  list("relievers", "FIP-style per BF", pit, q_rel, "fip", "bf", 25),
  list("relievers", "runs incl. inherited per BF", pit, q_rel, "resp_runs", "bf", 25),
  list("team", "run margin per game", team, q_team, "margin", "games", 2.5),
  list("team", "offense wOBA per PA", team[!is.na(team$woba), ], q_team[!is.na(q_team$y_woba), ], "woba", "woba_den", 200)
)

dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
grids <- list(); picks <- list(); lams <- list(); rels <- list(); curves <- list()
for (p in PLAN) {
  comp <- p[[1]]; rate <- p[[2]]; ev <- p[[3]]; q <- p[[4]]; num <- p[[5]]; den <- p[[6]]
  q <- q[!is.na(q[[paste0("y_", den)]]) & q[[paste0("y_", den)]] > 0, ]   # a 0-PA line has no rate
  message(comp, " / ", rate, ": ", nrow(q), " predictions")
  lg   <- league_target(ev, q, num, den)
  g    <- grid_rate(ev, q, num, den, p[[7]], lg)
  best <- pick(g, VALID)
  grids[[rate]]  <- cbind(component = comp, rate = rate, g)
  picks[[rate]]  <- cbind(component = comp, rate = rate, best, loso(g))
  curves[[rate]] <- g |> dplyr::group_by(h, c, k) |>
    dplyr::summarise(skill = 1 - sum(sse) / sum(sse0), .groups = "drop") |>
    dplyr::group_by(h) |> dplyr::slice_max(skill, n = 1, with_ties = FALSE) |>
    dplyr::mutate(component = comp, rate = rate)
  lams[[rate]]   <- cbind(component = comp, rate = rate, lambda_rate(ev, q, num, den, g, lg, q$cluster))
  own <- if (comp == "starters") ev[ev$role == "start", ] else if (comp == "relievers") ev[ev$role != "start", ] else ev
  rels[[rate]]   <- cbind(component = comp, rate = rate, reliability(own, num, den))
}
utils::write.csv(dplyr::bind_rows(grids), file.path(OUT, "grid-validation.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(picks), file.path(OUT, "picks-validation.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(curves), file.path(OUT, "decay-curves-validation.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(lams), file.path(OUT, "lambda-validation.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(rels), file.path(OUT, "reliability-validation.csv"), row.names = FALSE)
message("wrote ", OUT)
