# Tables for the recency study (RECENCY-PLAN.md), built from the StatsAPI game-log cache.
#
# One row per appearance (hitter-game, pitcher-game, team-game) with event counts and the
# opportunities they are rates of, plus season, venue and in-season day t. Park adjustment
# divides every count by its venue's factor for that rate, from the three prior seasons only.

load_seasons <- function(seasons, src = gamelog_sources("data/mlb/raw"),
                         seasons_src = cached_sources("data/mlb/raw")) {
  out <- lapply(seasons, function(s) {
    win <- season_window(s, fetch = seasons_src$seasons)
    g   <- season_gamelogs(s, win, src)
    g$season <- s; g$bounds <- data.frame(season = s, start = as.Date(win$start), end = as.Date(win$end))
    g
  })
  stats::setNames(out, seasons)
}

#' Hitter appearances: one row per hitter-game (non-pitchers), wOBA and component counts.
hitter_rows <- function(L) {
  dplyr::bind_rows(lapply(L, function(g) {
    h <- g$hitters
    h <- h[h$plateAppearances > 0, ]
    data.frame(entity = h$person_id, team_id = h$team_id, game_pk = h$game_pk, Date = h$Date,
               season = g$season, pa = h$plateAppearances, woba_den = woba_den(h),
               woba = woba_num(h), so = h$strikeOuts, bbhbp = h$baseOnBalls + h$hitByPitch,
               hr = h$homeRuns, runs = h$runs)
  }))
}

#' Pitcher appearances, with starts (7+ outs) told apart from openers and relief.
pitcher_rows <- function(L) {
  dplyr::bind_rows(lapply(L, function(g) {
    p <- g$pitchers
    p <- p[p$battersFaced > 0, ]
    gs <- p$gamesStarted %in% 1
    data.frame(entity = p$person_id, team_id = p$team_id, game_pk = p$game_pk, Date = p$Date,
               season = g$season, bf = p$battersFaced, outs = p$outs, so = p$strikeOuts,
               bbhbp = p$baseOnBalls + p$hitByPitch, hr = p$homeRuns, runs = p$runs,
               kbb = p$strikeOuts - p$baseOnBalls,
               fip = 13 * p$homeRuns + 3 * (p$baseOnBalls + p$hitByPitch) - 2 * p$strikeOuts,
               # a reliever answers for his own runs plus inherited runners he let score
               resp_runs = p$runs + ifelse(gs, 0, dplyr::coalesce(p$inheritedRunnersScored, 0)),
               pitches = p$numberOfPitches, saves = p$saves, holds = p$holds,
               role = ifelse(gs & p$outs >= 7, "start", ifelse(gs, "opener", "relief")))
  }))
}

#' Team-game rows: run margin, and offense from non-pitcher hitter lines only (universal DH).
team_rows <- function(L, hitters) {
  sched <- dplyr::bind_rows(lapply(L, function(g) transform(g$schedule, season = g$season)))
  side <- function(team, opp, rs, ra, home) data.frame(
    entity = sched[[team]], opp = sched[[opp]], game_pk = sched$game_pk, Date = sched$Date,
    season = sched$season, venue_id = sched$venue_id, home = home,
    margin = sched[[rs]] - sched[[ra]], games = 1)
  t <- rbind(side("home_id", "away_id", "home_score", "away_score", TRUE),
             side("away_id", "home_id", "away_score", "home_score", FALSE))
  off <- stats::aggregate(cbind(woba, woba_den) ~ team_id + game_pk, hitters, sum)
  names(off)[1] <- "entity"
  merge(t, off, by = c("entity", "game_pk"), all.x = TRUE)
}

schedule_rows <- function(L) dplyr::bind_rows(lapply(L, function(g) transform(g$schedule, season = g$season)))

#' Venue factor per rate and season from the three prior seasons, shrunk toward 1.
#'
#' `rows` has venue_id, season and the numerator and denominator columns. `m` opportunities of
#' league-average play are added to each venue, so a park with one series of history sits at 1.
park_factors <- function(rows, num, den, m = 3000) {
  by <- stats::aggregate(rows[c(num, den)], rows[c("venue_id", "season")], sum)
  lg <- stats::aggregate(rows[c(num, den)], rows["season"], sum)
  seasons <- sort(unique(rows$season))
  dplyr::bind_rows(lapply(seasons, function(S) {
    prior <- by[by$season %in% (S - 3):(S - 1), ]
    lgp   <- lg[lg$season %in% (S - 3):(S - 1), ]
    if (!nrow(prior)) return(NULL)
    v <- stats::aggregate(prior[c(num, den)], prior["venue_id"], sum)
    lr <- sum(lgp[[num]]) / sum(lgp[[den]])
    data.frame(venue_id = v$venue_id, season = S,
               pf = ((v[[num]] + m * lr) / (v[[den]] + m)) / lr)
  }))
}

#' Divide `cols` by the venue factor of each row's game (1 where a venue has no history).
park_adjust <- function(rows, pf, cols) {
  rows <- merge(rows, pf, by = c("venue_id", "season"), all.x = TRUE, sort = FALSE)
  rows$pf[is.na(rows$pf)] <- 1
  for (c in cols) rows[[c]] <- rows[[c]] / rows$pf
  rows$pf <- NULL
  rows
}
