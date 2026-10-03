# StatsAPI game logs: every team's hitting and pitching line per game, and every player's line
# per appearance. One call per team-season-group and one per 50 players, so a season costs about
# a hundred calls instead of one per game. Cached through cache_fetch() like the other pulls.
#
# These replace the Baseball-Reference 15-day windows for the recency study: a fixed 15-day
# window cannot answer "which window is best", per-game lines can.

API <- "https://statsapi.mlb.com/api/v1"

num <- function(x) suppressWarnings(as.numeric(x))

#' The 30 clubs in a season.
mlb_teams <- function(season) {
  t <- jsonlite::fromJSON(sprintf("%s/teams?sportId=1&season=%d", API, season), flatten = TRUE)$teams
  data.frame(team_id = t$id, team = t$name)
}

#' Everyone who appeared for a club that season, with position type.
team_roster <- function(team_id, season) {
  url <- sprintf("%s/teams/%d/roster?season=%d&rosterType=fullSeason", API, team_id, season)
  r <- jsonlite::fromJSON(url, flatten = TRUE)$roster
  data.frame(person_id = r$person.id, pos = r$position.abbreviation, team_id = team_id)
}

#' One club's per-game line for a season, `group` = "hitting" or "pitching".
team_game_log <- function(team_id, season, group) {
  url <- sprintf("%s/teams/%d/stats?stats=gameLog&group=%s&season=%d&gameType=R",
                 API, team_id, group, season)
  s <- jsonlite::fromJSON(url, flatten = TRUE)$stats$splits[[1]]
  out <- data.frame(team_id = team_id, game_pk = s$game.gamePk, Date = as.Date(s$date),
                    is_home = s$isHome, opp_id = s$opponent.id)
  cbind(out, stat_cols(s))
}

#' Per-appearance lines for up to 50 players in one call.
player_game_logs <- function(ids, season, group) {
  url <- sprintf("%s/people?personIds=%s&hydrate=stats(group=[%s],type=[gameLog],season=%d,gameType=[R])",
                 API, paste(ids, collapse = ","), group, season)
  p <- jsonlite::fromJSON(url, flatten = TRUE)$people
  rows <- lapply(seq_len(nrow(p)), function(i) {
    s <- p$stats[[i]]$splits[[1]]
    if (is.null(s) || !NROW(s)) return(NULL)
    cbind(data.frame(person_id = p$id[i], game_pk = s$game.gamePk, Date = as.Date(s$date),
                     team_id = s$team.id, is_home = s$isHome), stat_cols(s))
  })
  out <- dplyr::bind_rows(rows)
  if (!nrow(out)) out <- data.frame(person_id = integer(0))   # a data frame, so it caches
  out
}

STATS <- c("plateAppearances", "atBats", "hits", "doubles", "triples", "homeRuns", "baseOnBalls",
           "intentionalWalks", "hitByPitch", "sacFlies", "strikeOuts", "runs", "earnedRuns",
           "outs", "battersFaced", "gamesStarted", "numberOfPitches", "saves", "holds",
           "gamesFinished")

stat_cols <- function(s) {
  cols <- intersect(paste0("stat.", STATS), names(s))
  out  <- as.data.frame(lapply(s[cols], num))
  names(out) <- sub("^stat\\.", "", cols)
  out
}

#' Cached StatsAPI sources under `dir`, paced lightly; StatsAPI is not Baseball-Reference.
gamelog_sources <- function(dir = "data/mlb/raw", pause = 0.3) {
  list(
    teams    = cache_fetch(mlb_teams, file.path(dir, "statsapi_teams"), pause),
    roster   = cache_fetch(team_roster, file.path(dir, "statsapi_roster"), pause),
    team_log = cache_fetch(team_game_log, file.path(dir, "statsapi_team_log"), pause),
    # keyed by season, group and batch number; the ids come from the cached rosters
    player   = function(ids, season, group, batch) {
      cache_fetch(function(season, group, batch) player_game_logs(ids, season, group),
                  file.path(dir, "statsapi_player_log"), pause)(season, group, batch)
    }
  )
}

#' Every table the recency study needs for one season, from the cache (fetching misses).
season_gamelogs <- function(season, src = gamelog_sources()) {
  teams  <- src$teams(season)
  roster <- dplyr::bind_rows(lapply(teams$team_id, src$roster, season = season))
  logs   <- function(group) dplyr::bind_rows(lapply(teams$team_id, src$team_log,
                                                    season = season, group = group))
  people <- function(group, keep) {
    ids <- sort(unique(roster$person_id[keep]))
    batches <- split(ids, ceiling(seq_along(ids) / 50))
    dplyr::bind_rows(lapply(seq_along(batches), function(b)
      src$player(batches[[b]], season, group, b)))
  }
  list(
    team_hitting  = logs("hitting"),
    team_pitching = logs("pitching"),
    pitchers      = people("pitching", roster$pos %in% c("P", "TWP")),
    hitters       = people("hitting", !roster$pos %in% "P"),
    teams         = teams
  )
}
