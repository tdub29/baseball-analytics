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
REL_CFG <- PIT_CFG                                  # relievers' bullpen rates; v2 uses the pitcher constants

#' Shrink constants centred on the random-effects k of the reliability study (results/reliability.md),
#' one multiplier per group: pitchers' batted-ball expected outcomes (starter centres in PIT, reliever
#' centres in REL), hitters' singles, triples and outs in play, and relievers' walks. Windows and
#' every other constant stay as in v2.
k_cfg <- function(m_pit = 1, m_bat = 1, m_rel_bb = 1) {
  set <- function(cfg, k) { for (o in names(k)) cfg[[o]][3] <- k[[o]]; cfg }
  list(BAT = set(BAT_CFG, m_bat * c(single = 195, triple = 534, out_ip = 75)),
       PIT = set(PIT_CFG, m_pit * c(single = 157, double = 210, triple = 129, hr = 106, out_ip = 121)),
       REL = set(PIT_CFG, c(m_pit * c(single = 89, double = 152, triple = 97, hr = 79, out_ip = 69), ubb = m_rel_bb * 134)))
}
# K_SET=v4: multipliers chosen by walk-forward log loss on 2017-2019 outcomes (matchup_tune.R,
# MATCHUP-PLAN.md it 8, 2026-10-06). The default, v2, keeps the constants above.
# Tuned 2026-10-06 (results/matchup-k-tune-v4-base.md, -v4-base2.md): 0.5 to 4 all lost to v2; the
# extended grid peaked inside at 8 / 8, about v2 scale. Relievers' walk multiplier was flat.
M_PIT_V4 <- 8; M_BAT_V4 <- 8; M_REL_BB_V4 <- 1
K_SET <- Sys.getenv("K_SET", "v2")
stopifnot(K_SET %in% c("v2", "v4"))
if (K_SET == "v4") { ks <- k_cfg(M_PIT_V4, M_BAT_V4, M_REL_BB_V4); BAT_CFG <- ks$BAT; PIT_CFG <- ks$PIT; REL_CFG <- ks$REL }

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

#' Rotation guess for every team-game: the starter predicted from the starts known `known` days
#' before the game's date (games dated d - known or earlier). Starts after that and before the game
#' (the day before, doubleheader game 1) are unknown, so they are predicted in order with the same
#' rule and count as made. Rule: among pitchers who started one of the team's last `pool` games this
#' season, the one with the longest rest, if he has `min_rest` or more days of rest (days between
#' starts, so 4 = every fifth day). Fallback: the team's previous-season starters by number of
#' starts who have not started in the last `min_rest` days, then the longest-rested pool pitcher.
#' pool = 6 was chosen by how often the guess equals the actual starter on 2017-2022 (match rate
#' 0.626; 5 games 0.624, 7 games 0.569, 10 games 0.437: a long pool lets a pitcher who started once
#' and left the rotation win on rest).
#' `st` has one row per team-game: gid, team, Date, season, sp, sp_hand (the actual starters, read
#' only once known). Returns gid, team, sp, sp_hand of the guess.
rotation_starters <- function(st, known = 2, pool = 6, min_rest = 4) {
  st <- data.table::as.data.table(st)[order(team, Date, gid)]
  st[, {
    d <- as.numeric(Date); n <- .N
    prev <- lapply(split(seq_len(n), season), function(i) {         # each season's starters, most starts first
      p <- sp[i]; cnt <- table(p); lst <- tapply(d[i], p, max)[names(cnt)]
      p <- names(cnt)[order(-cnt, -lst)]
      list(p = p, h = sp_hand[i][length(i) + 1L - match(p, rev(sp[i]))])
    })
    first <- match(season, season)                                   # first row of each row's season
    gp <- gh <- rep(NA_character_, n)
    pick <- function(hp, hh, hd, dd, s) {
      m <- length(hp)
      if (m) {
        tk <- max(1L, m - pool + 1L):m
        u <- tk[!duplicated(hp[tk], fromLast = TRUE)]                # each pool pitcher's latest start
        rest <- dd - hd[u] - 1
        ok <- rest >= min_rest
        if (any(ok)) { j <- u[ok][which.max(rest[ok])]; return(c(hp[j], hh[j])) }
      }
      pv <- prev[[as.character(s - 1)]]
      if (!is.null(pv)) {
        j <- which(!pv$p %in% hp[dd - hd - 1 < min_rest])[1]
        if (!is.na(j)) return(c(pv$p[j], pv$h[j]))
      }
      if (m) { j <- u[which.max(rest)]; return(c(hp[j], hh[j])) }
      c(NA_character_, NA_character_)
    }
    for (i in seq_len(n)) {
      k <- findInterval(d[i] - known, d)                             # last row dated d - known or earlier
      f <- first[i]
      idx <- if (k >= f) f:k else integer(0)
      hp <- sp[idx]; hh <- sp_hand[idx]; hd <- d[idx]
      lo <- max(k + 1L, f)
      if (lo < i) for (j in lo:(i - 1L)) {                          # unknown starts before the game
        g <- pick(hp, hh, hd, d[j], season[i])
        hp <- c(hp, g[1]); hh <- c(hh, g[2]); hd <- c(hd, d[j])
      }
      g <- pick(hp, hh, hd, d[i], season[i]); gp[i] <- g[1]; gh[i] <- g[2]
    }
    .(gid = gid, sp = gp, sp_hand = gh)
  }, by = team]
}

#' Retrosheet gid to StatsAPI game_pk: games matched on date and final score, then on the team-id
#' maps those matches imply (each Retrosheet code to its most frequent StatsAPI id), one pk per gid.
#' The same join as matchup_model.R (left inline there: frozen). `G`: gid, Date, hometeam, visteam,
#' hruns, vruns. `S`: game_pk, Date, home_id, away_id, home_score, away_score.
pk_crosswalk <- function(G, S) {
  cand <- merge(G[, .(gid, Date, hometeam, visteam, hruns, vruns)], S, by.x = c("Date", "hruns", "vruns"),
                by.y = c("Date", "home_score", "away_score"))
  hmap <- cand[, .N, by = .(hometeam, home_id)][order(-N)][!duplicated(hometeam)]
  amap <- cand[, .N, by = .(visteam, away_id)][order(-N)][!duplicated(visteam)]
  cand <- merge(merge(cand, hmap[, .(hometeam, hid = home_id)], by = "hometeam"), amap[, .(visteam, aid = away_id)], by = "visteam")
  cand <- cand[home_id == hid & away_id == aid]
  cand[!duplicated(gid) & !duplicated(game_pk), .(gid, game_pk)]
}

#' Odds-ratio combination of batter, pitcher and league rates for each outcome, renormalised.
log5 <- function(b, p, l) {
  odds <- function(x) x / (1 - x)
  o <- odds(pmin(b, 0.999)) * odds(pmin(p, 0.999)) / odds(pmin(l, 0.999))
  m <- o / (1 + o)
  m / rowSums(m)
}

#' Team defensive efficiency gap, home minus away in points of ball-in-play out rate, as of `lag`
#' days before each game's date (inputs dated date - lag - 1 or earlier). The definition of dder in
#' context_features.R: outs on balls in play (homers out, reached-on-error not an out), park-
#' neutralised by the site's three prior seasons, decayed h = 120, carry 0.75, shrunk to the
#' trailing-year league rate with 3000 balls. lag = 0 reproduces context.rds. forward = TRUE adds the
#' 2026 StatsAPI season (statsapi_pa.R must be sourced), with its field_error events as reached on error.
der_gap <- function(games, lag = 0, forward = FALSE) {
  G <- data.table::rbindlist(c(lapply(2015:2025, retro_games), if (forward) list(statsapi_games(2026))))
  BND <- as.data.frame(G[, .(start = min(Date), end = max(Date)), by = season])
  P <- data.table::rbindlist(lapply(2015:2025, retro_pa))
  if (forward) { P26 <- statsapi_pa(2026, raw = TRUE); P <- rbind(P, P26[, names(P), with = FALSE]) }
  TD <- Sys.getenv("TAMPER_FROM")                      # leakage test only (tamper.R, sourced by matchup_model.R)
  if (nzchar(TD)) P <- tamper_pg(P, NULL, as.Date(TD))$P
  TR <- Sys.getenv("TRUNCATE_FROM")                    # participation test only (leakage_tamper.R)
  if (nzchar(TR)) { P <- P[Date < as.Date(TR)]; G <- G[Date < as.Date(TR)] }
  BIPO <- c("single", "double", "triple", "out_ip")
  der <- P[outcome %in% BIPO, .(bip = .N, outs = sum(outcome == "out_ip")), by = .(gid, Date, season, site, team = pitteam)]
  rm(P)
  roe <- data.table::rbindlist(lapply(2015:2025, function(s)
    data.table::fread(retro_file(s, "plays"), select = c("gid", "gametype", "pa", "pitteam", "roe"), showProgress = FALSE)[
      gametype == "regular" & pa == 1, .(roe = sum(roe)), by = .(gid, team = pitteam)]))
  if (forward) roe <- rbind(roe, P26[, .(roe = sum(event == "field_error")), by = .(gid, team = pitteam)])
  if (nzchar(TD)) roe <- tamper_roe(roe, G, as.Date(TD))
  if (nzchar(TR)) roe <- roe[gid %in% G$gid]
  der <- merge(der, roe, by = c("gid", "team"), all.x = TRUE)
  der[is.na(roe), roe := 0][, outs := outs - roe]
  pf <- data.table::rbindlist(lapply(2015:(if (forward) 2026 else 2025), function(S) {
    x <- der[season %in% (S - 3):(S - 1)]
    if (!nrow(x)) return(NULL)
    lg <- sum(x$outs) / sum(x$bip)
    x[, .(season = S, pf = ((sum(outs) + 4000 * lg) / (sum(bip) + 4000)) / lg), by = site]
  }))
  der <- merge(der, pf, by = c("season", "site"), all.x = TRUE)
  der[is.na(pf), pf := 1][, outs_n := outs / pf][, t := season_day(Date, season, BND)]
  qd <- games$Date - lag
  lg_der <- league_rate(der[, .(outs_n = sum(outs_n), bip = sum(bip)), by = Date], "outs_n", "bip", qd, 365)
  de <- as.data.frame(der[, .(entity = team, Date, season, t, outs_n, bip)])
  q <- function(team) data.frame(entity = team, Date = qd, season = games$season, t = season_day(qd, games$season, BND))
  derx <- function(team) { s <- asof_decay(de, q(team), c("outs_n", "bip"), h = 120, c = 0.75); (s[, 1] + 3000 * lg_der) / (s[, 2] + 3000) }
  data.table::data.table(gid = games$gid, dder = 100 * (derx(games$hometeam) - derx(games$visteam)))
}
