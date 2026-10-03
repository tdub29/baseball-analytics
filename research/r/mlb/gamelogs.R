# StatsAPI game logs: every team's hitting and pitching line per game, and every player's line
# per appearance. One call per team-season-group and one per 50 players, so a season costs about
# a hundred calls instead of one per game. Cached through cache_fetch() like the other pulls.
#
# These replace the Baseball-Reference 15-day windows for the recency study: a fixed 15-day
# window cannot answer "which window is best", per-game lines can.

API <- "https://statsapi.mlb.com/api/v1"

as_num <- function(x) suppressWarnings(as.numeric(x))

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
           "gamesFinished", "inheritedRunners", "inheritedRunnersScored")

stat_cols <- function(s) {
  cols <- intersect(paste0("stat.", STATS), names(s))
  out  <- as.data.frame(lapply(s[cols], as_num))
  names(out) <- sub("^stat\\.", "", cols)
  out
}

#' Every regular-season game in a date range with venue, probable starters and the posted
#' starting lineups in batting order (one call per season; lineups post before first pitch).
schedule_lineups <- function(start, end) {
  url <- sprintf("%s/schedule?sportId=1&gameType=R&startDate=%s&endDate=%s&hydrate=lineups,probablePitcher",
                 API, start, end)
  g <- dplyr::bind_rows(jsonlite::fromJSON(url, flatten = TRUE)$dates$games)
  g <- g[g$status.abstractGameState == "Final" & !is.na(g$teams.home.score), ]
  g <- g[!duplicated(g$gamePk), ]
  ids <- function(col, i) vapply(g[[col]], function(p) if (NROW(p) >= i) p$id[i] else NA_integer_, integer(1))
  out <- data.frame(game_pk = g$gamePk, Date = as.Date(g$officialDate), venue_id = g$venue.id,
                    home_id = g$teams.home.team.id, away_id = g$teams.away.team.id,
                    home_score = g$teams.home.score, away_score = g$teams.away.score,
                    home_sp = g$teams.home.probablePitcher.id, away_sp = g$teams.away.probablePitcher.id)
  for (i in 1:9) {
    out[[paste0("home_bat", i)]] <- if ("lineups.homePlayers" %in% names(g)) ids("lineups.homePlayers", i) else NA_integer_
    out[[paste0("away_bat", i)]] <- if ("lineups.awayPlayers" %in% names(g)) ids("lineups.awayPlayers", i) else NA_integer_
  }
  out
}

#' Retry a flaky call a few times before letting the error through (a dropped connection
#' should cost a pause, not a rerun of the season).
retry <- function(f, attempts = 4) function(...) {
  for (i in seq_len(attempts)) {
    out <- tryCatch(f(...), error = function(e) e)
    if (!inherits(out, "error")) return(out)
    Sys.sleep(2 * i)
  }
  stop(out)
}

#' Cached StatsAPI sources under `dir`, paced lightly; StatsAPI is not Baseball-Reference.
gamelog_sources <- function(dir = "data/mlb/raw", pause = 0.3) {
  mlb_teams <- retry(mlb_teams); team_roster <- retry(team_roster)
  team_game_log <- retry(team_game_log); schedule_lineups <- retry(schedule_lineups)
  player_game_logs <- retry(player_game_logs)
  list(
    teams    = cache_fetch(mlb_teams, file.path(dir, "statsapi_teams"), pause),
    roster   = cache_fetch(team_roster, file.path(dir, "statsapi_roster"), pause),
    team_log = cache_fetch(team_game_log, file.path(dir, "statsapi_team_log"), pause),
    schedule = cache_fetch(schedule_lineups, file.path(dir, "statsapi_lineups"), pause),
    # keyed by season, group and batch number; the ids come from the cached rosters
    player   = function(ids, season, group, batch) {
      cache_fetch(function(season, group, batch) player_game_logs(ids, season, group),
                  file.path(dir, "statsapi_player_log"), pause)(season, group, batch)
    }
  )
}

#' Every table the recency study needs for one season, from the cache (fetching misses).
#' `win` is the season's regular-season window (start, end).
season_gamelogs <- function(season, win, src = gamelog_sources()) {
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
    teams         = teams,
    schedule      = src$schedule(as.character(win$start), as.character(win$end))
  )
}
