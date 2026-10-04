# Matchup engine (MATCHUP-PLAN.md): per-outcome rates for batters and pitchers by handedness,
# combined by odds ratio, park-adjusted, into expected run value per plate appearance.
#
# Every estimate is as of the start of the game's date (asof_decay in windows.R). Windows and
# shrink constants start from the recency study's picks and reliability; validation may tune them.

OUT8 <- c("k", "ubb", "hbp", "single", "double", "triple", "hr", "out_ip")

# window (half-life in in-season days, carry per season) and shrink constant per outcome
BAT_CFG <- list(k = c(120, 1.0, 60), ubb = c(240, 0.75, 110), hbp = c(240, 0.75, 300),
                single = c(Inf, 0.75, 800), double = c(Inf, 0.75, 1000), triple = c(Inf, 0.75, 1500),
                hr = c(Inf, 0.5, 200), out_ip = c(Inf, 0.75, 800))
PIT_CFG <- list(k = c(120, 0.75, 90), ubb = c(240, 0.75, 300), hbp = c(240, 0.75, 500),
                single = c(Inf, 0.5, 1500), double = c(Inf, 0.5, 1500), triple = c(Inf, 0.5, 3000),
                hr = c(240, 0.75, 1300), out_ip = c(Inf, 0.5, 1500))

#' Add one 0/1 column per outcome and an opportunity count.
outcome_matrix <- function(P) {
  for (o in OUT8) P[[o]] <- as.numeric(P$outcome == o)
  P$n <- 1
  P
}

#' Park factor per (site, batter side, outcome) from the three prior seasons, shrunk toward 1.
park_table <- function(P, m = 4000) {
  seasons <- sort(unique(P$season))
  data.table::rbindlist(lapply(seasons, function(S) {
    x <- P[P$season %in% (S - 3):(S - 1), ]
    if (!nrow(x)) return(NULL)
    lg <- x[, lapply(.SD, sum), by = bathand, .SDcols = c(OUT8, "n")]
    st <- x[, lapply(.SD, sum), by = .(site, bathand), .SDcols = c(OUT8, "n")]
    st <- merge(st, lg, by = "bathand", suffixes = c("", "_lg"))
    for (o in OUT8) {
      lr <- st[[paste0(o, "_lg")]] / st$n_lg
      st[[paste0("pf_", o)]] <- ((st[[o]] + m * lr) / (st$n + m)) / lr
    }
    cbind(season = S, st[, c("site", "bathand", paste0("pf_", OUT8)), with = FALSE])
  }))
}

#' Neutralise each plate appearance's outcomes by its park (so histories are park-free).
park_neutral <- function(P, PF) {
  P <- merge(P, PF, by = c("season", "site", "bathand"), all.x = TRUE, sort = FALSE)
  for (o in OUT8) {
    f <- P[[paste0("pf_", o)]]; f[is.na(f)] <- 1
    P[[o]] <- P[[o]] / f
  }
  P[, paste0("pf_", OUT8) := NULL]
  P
}

#' As-of decayed sums of every outcome for one entity definition, each at its own window.
asof_outcomes <- function(events, queries, cfg) {
  ev <- as.data.frame(events); q <- as.data.frame(queries)
  num <- den <- matrix(0, nrow(q), length(OUT8), dimnames = list(NULL, OUT8))
  for (o in OUT8) {
    w <- cfg[[o]]
    s <- asof_decay(ev, q, c(o, "n"), h = w[1], c = w[2])
    num[, o] <- s[, 1]; den[, o] <- s[, 2]
  }
  list(num = num, den = den)
}

#' League rate per outcome as of each query, for a given (batter side, pitcher hand) pair or overall.
league_rates <- function(P, queries, by = NULL) {
  key <- if (is.null(by)) rep("lg", nrow(P)) else do.call(paste, P[, by, with = FALSE])
  lg <- P[, lapply(.SD, sum), by = .(Date, season, t, entity = key), .SDcols = c(OUT8, "n")]
  q <- data.frame(entity = if (is.null(by)) "lg" else queries$lg_key, Date = queries$Date,
                  season = queries$season, t = queries$t)
  s <- asof_decay(as.data.frame(lg), q, c(OUT8, "n"), h = 30, c = 1)
  s[, OUT8] / pmax(s[, "n"], 1e-9)
}

#' Shrunk rates: overall toward league, split toward the overall rate scaled by the league platoon
#' ratio, then renormalised to sum to one.
shrunk_rates <- function(all, split, cfg, lg_all, lg_split, k_split) {
  r <- sapply(seq_along(OUT8), function(j) {
    o <- OUT8[j]; k <- cfg[[o]][3]
    overall <- (all$num[, j] + k * lg_all[, j]) / (all$den[, j] + k)
    prior <- overall * lg_split[, j] / pmax(lg_all[, j], 1e-9)
    (split$num[, j] + k_split * prior) / (split$den[, j] + k_split)
  })
  colnames(r) <- OUT8
  r / rowSums(r)
}

#' Odds-ratio combination of batter, pitcher and league rates for each outcome, renormalised.
log5 <- function(b, p, l) {
  odds <- function(x) x / (1 - x)
  o <- odds(pmin(b, 0.999)) * odds(pmin(p, 0.999)) / odds(pmin(l, 0.999))
  m <- o / (1 + o)
  m / rowSums(m)
}
