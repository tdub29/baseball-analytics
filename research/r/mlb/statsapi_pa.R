# StatsAPI plate appearances and game info in the shape of retro.R's retro_pa() and retro_games(),
# so a model frozen on Retrosheet can be scored on a season Retrosheet has not published yet.
#
# Source: the MLB StatsAPI live feed (https://statsapi.mlb.com/api/v1.1/game/{gamePk}/feed/live),
# no key. Needs retro.R (retro_games, for the id maps) and gamelogs.R (API, retry) sourced first.
#
#   statsapi_pa(season)     same 19 columns and coding as retro_pa(season)
#   statsapi_games(season)  same 18 columns and coding as retro_games(season)
#
# Raw feeds are cached gzipped under data/mlb/raw/statsapi_feed/{season}/ (gitignored with the
# rest of data/mlb/raw/); a rerun fetches only what is missing, so an interrupted pull resumes.
# The parsed feeds are cached as parsed_{season}.rds with StatsAPI's own ids and raw weather
# strings; the Retrosheet coding is applied on read, so a mapping fix never needs a re-parse.
#
# Ids: batters and pitchers map MLBAM to Retrosheet through the Chadwick register; teams through
# StatsAPI's teamCode (it is the Retrosheet code); parks and home plate umpires through the
# StatsAPI schedule joined to Retrosheet game info of the seasons before `season` (2021 on), so a
# season's maps never learn from that season's own Retrosheet file (umpires fall back to the
# register). Anything unmapped keeps its MLBAM id behind a prefix ("mlbam660271" for people,
# "venue2397" for parks): Retrosheet ids are five letters or dashes and three digits, so a
# prefixed id can never collide with one.
#
# Person ids from the Chadwick Bureau register (https://github.com/chadwickbureau/register),
# Open Data Commons Attribution License (ODC-BY).

FEED_DIR <- "data/mlb/raw/statsapi_feed"
API11 <- "https://statsapi.mlb.com/api/v1.1"
REGISTER <- file.path(FEED_DIR, "register.rds")

#' MLBAM and Retrosheet ids from the Chadwick register, downloaded once; delete REGISTER to take
#' a newer one. Its own copy, not data/mlb/raw/chadwick: other scripts read that baseballr pull,
#' and the 2026-09 snapshot there predates Retrosheet ids for 2026 debuts.
chadwick_register <- function() {
  if (file.exists(REGISTER)) return(readRDS(REGISTER))
  urls <- sprintf("https://raw.githubusercontent.com/chadwickbureau/register/master/data/people-%s.csv",
                  c(0:9, letters[1:6]))
  reg <- data.table::rbindlist(lapply(urls, function(u) retry(data.table::fread)(
    u, select = c("key_mlbam", "key_retro", "mlb_played_first", "mlb_played_last"),
    colClasses = c(key_retro = "character"), showProgress = FALSE)))
  dir.create(FEED_DIR, showWarnings = FALSE, recursive = TRUE)
  saveRDS(reg, REGISTER)
  reg
}

# Plate-appearance event types (plateAppearance = true in /api/v1/eventTypes, plus the triple-play
# grounder it leaves out). intent_walk is a plate appearance but is dropped, as retro_pa() does.
PA_EVENTS <- c("single", "double", "triple", "home_run", "double_play", "field_error", "field_out",
               "fielders_choice", "fielders_choice_out", "force_out", "grounded_into_double_play",
               "grounded_into_triple_play", "strikeout", "strike_out", "strikeout_double_play",
               "strikeout_triple_play", "triple_play", "sac_fly", "catcher_interf", "batter_interference",
               "fan_interference", "sac_fly_double_play", "sac_bunt", "sac_bunt_double_play", "walk",
               "intent_walk", "hit_by_pitch", "os_ruling_pending_primary")
K_EVENTS <- c("strikeout", "strike_out", "strikeout_double_play", "strikeout_triple_play")
# Bunts stay NA: retro_pa() codes only hittype G, L, F, P, and Retrosheet's bunt hittypes (BG, BP,
# BL) carry no ground/fly/line flag, so every Retrosheet bunt has bb_type NA.
TRAJ <- c(ground_ball = "gb", line_drive = "ld", fly_ball = "fb", popup = "pu")
WIND <- c("Out To CF" = "tocf", "Out To LF" = "tolf", "Out To RF" = "torf", "In From CF" = "fromcf",
          "In From LF" = "fromlf", "In From RF" = "fromrf", "L To R" = "ltor", "R To L" = "rtol")
SKY <- c(Dome = "dome", "Roof Closed" = "dome", Sunny = "sunny", Clear = "sunny", "Partly Cloudy" = "cloudy",
         Cloudy = "cloudy", Overcast = "overcast", Drizzle = "overcast", Rain = "overcast", Snow = "overcast")
PRECIP <- c(Drizzle = "drizzle", Rain = "rain", Snow = "snow")

#' Every regular-season game StatsAPI lists for a season, cached; refetched while any is unplayed.
feed_schedule <- function(season) {
  f <- file.path(FEED_DIR, sprintf("schedule_%d.rds", season))
  if (file.exists(f)) { s <- readRDS(f); if (!any(s$state %in% c("Preview", "Live"))) return(s) }
  url <- sprintf("%s/schedule?sportId=1&gameType=R&season=%d&hydrate=officials,team", API, season)
  days <- retry(jsonlite::fromJSON)(url, simplifyVector = FALSE)$dates
  s <- data.table::rbindlist(lapply(unlist(lapply(days, `[[`, "games"), recursive = FALSE), function(x) {
    hp <- Filter(function(o) o$officialType == "Home Plate", x$officials %||% list())
    list(game_pk = x$gamePk, Date = as.Date(x$officialDate), state = x$status$abstractGameState,
         detail = x$status$detailedState, hometeam = toupper(x$teams$home$team$teamCode),
         visteam = toupper(x$teams$away$team$teamCode), venue_id = x$venue$id,
         number = if (identical(x$doubleHeader, "N")) 0L else as.integer(x$gameNumber),
         ump_id = if (length(hp)) hp[[1]]$official$id else NA_integer_)
  }))
  dir.create(FEED_DIR, showWarnings = FALSE, recursive = TRUE)
  saveRDS(s, f)
  s
}

#' Completed games, one row each (a suspended game is listed again on the day it resumed).
final_games <- function(s) {
  s <- s[state == "Final" & grepl("^(Final|Game Over|Completed Early)", detail)]
  s[!duplicated(game_pk, fromLast = TRUE)]
}

feed_path <- function(season, pk) file.path(FEED_DIR, season, sprintf("%d.json.gz", pk))

#' Download every missing final feed for a season, paced and retried; stops if any still fail.
fetch_feeds <- function(season, pause = 0.25) {
  pks <- final_games(feed_schedule(season))$game_pk
  dir.create(file.path(FEED_DIR, season), showWarnings = FALSE, recursive = TRUE)
  todo <- pks[!file.exists(feed_path(season, pks))]
  get <- retry(function(pk) {
    txt <- readLines(url(sprintf("%s/game/%d/feed/live", API11, pk)), warn = FALSE, encoding = "UTF-8")
    tmp <- paste0(feed_path(season, pk), ".part")      # renamed only when whole, so a cut never caches
    con <- gzfile(tmp, "w"); writeLines(txt, con); close(con)
    file.rename(tmp, feed_path(season, pk))
  })
  failed <- integer(0)
  for (i in seq_along(todo)) {
    ok <- tryCatch({ get(todo[i]); TRUE }, error = function(e) FALSE)
    if (!ok) failed <- c(failed, todo[i])
    if (i %% 100 == 0) message(season, ": fetched ", i, " of ", length(todo), " missing feeds")
    Sys.sleep(pause)
  }
  if (length(failed)) stop(length(failed), " feeds failed (", paste(head(failed), collapse = ", "), "); rerun to resume")
  pks
}

#' One feed to a list of plate appearances (StatsAPI ids and codes) and one game row.
parse_feed <- function(path) {
  d <- jsonlite::fromJSON(paste(readLines(gzfile(path), warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                          simplifyVector = FALSE)
  gd <- d$gameData; ld <- d$liveData
  pa <- data.table::rbindlist(lapply(ld$plays$allPlays, function(p) {
    ev <- p$result$eventType %||% ""
    if (!ev %in% PA_EVENTS) return(NULL)                   # stolen bases, pickoffs, inning-ending outs on the bases
    b <- p$matchup$batter$id
    idx <- NA_integer_                                     # the play-ending event: where the batter's own movement is
    for (r in p$runners) if (identical(r$details$runner$id, b) && is.null(r$movement$originBase)) idx <- r$details$playIndex
    if (is.na(idx)) idx <- p$playEvents[[length(p$playEvents)]]$index
    runs <- 0L; outs <- 0L                                 # only what happened on that event, as Retrosheet's PA row has it
    for (r in p$runners) if (identical(r$details$playIndex, idx)) {
      runs <- runs + identical(r$movement$end, "score")
      outs <- outs + isTRUE(r$movement$isOut)
    }
    traj <- NA_character_
    for (e in p$playEvents) if (identical(e$index, idx) && !is.null(e$hitData$trajectory)) traj <- e$hitData$trajectory
    list(ab = p$atBatIndex, event = ev, inning = p$about$inning, top_bot = if (isTRUE(p$about$isTopInning)) 0L else 1L,
         batter = b, pitcher = p$matchup$pitcher$id, pithand = p$matchup$pitchHand$code %||% NA_character_,
         traj = traj, runs = runs, outs_pre = max(p$count$outs - outs, 0L))
  }))
  bats <- vapply(gd$players, function(x) x$batSide$code %||% NA_character_, "")
  pa[, bats := unname(bats[paste0("ID", batter)])]
  w <- gd$weather %||% list()
  hp <- Filter(function(o) o$officialType == "Home Plate", ld$boxscore$officials %||% list())
  pos <- unlist(lapply(c(ld$boxscore$teams$home$players, ld$boxscore$teams$away$players),
                       function(x) vapply(x$allPositions %||% list(), function(y) y$abbreviation, "")))
  game <- data.table::data.table(
    game_pk = gd$game$pk, Date = as.Date(gd$datetime$officialDate), visteam = toupper(gd$teams$away$teamCode),
    hometeam = toupper(gd$teams$home$teamCode), venue_id = gd$venue$id,
    number = if (identical(gd$game$doubleHeader, "N")) 0L else as.integer(gd$game$gameNumber),
    starttime = paste0(gd$datetime$time, gd$datetime$ampm), daynight = gd$datetime$dayNight %||% NA_character_,
    usedh = "DH" %in% pos, temp = suppressWarnings(as.integer(w$temp %||% NA)), wind = w$wind %||% NA_character_,
    condition = w$condition %||% NA_character_, ump_id = if (length(hp)) hp[[1]]$official$id else NA_integer_,
    vruns = as.integer(ld$linescore$teams$away$runs), hruns = as.integer(ld$linescore$teams$home$runs))
  if (nrow(pa)) pa[, game_pk := game$game_pk]
  list(pa = pa, game = game)
}

#' Parsed feeds for a season (StatsAPI ids, raw weather), cached; re-parsed when new games land.
statsapi_parsed <- function(season) {
  out <- file.path(FEED_DIR, sprintf("parsed_%d.rds", season))
  pks <- fetch_feeds(season)
  if (file.exists(out)) { x <- readRDS(out); if (setequal(x$games$game_pk, pks)) return(x) }
  parts <- lapply(seq_along(pks), function(i) {
    if (i %% 250 == 0) message(season, ": parsed ", i, " of ", length(pks))
    parse_feed(feed_path(season, pks[i]))
  })
  x <- list(pa = data.table::rbindlist(lapply(parts, `[[`, "pa")), games = data.table::rbindlist(lapply(parts, `[[`, "game")))
  saveRDS(x, out)
  x
}

#' Retrosheet game id: home team, date, doubleheader number. StatsAPI keeps "game 1 of 2" on a
#' game whose partner was postponed; Retrosheet numbers a lone game 0, so number by games played.
add_gid <- function(g) {
  g[, number := if (.N == 1L) 0L else number, by = .(hometeam, Date)]
  g[, gid := sprintf("%s%s%d", hometeam, format(Date, "%Y%m%d"), number)]
}

#' MLBAM to Retrosheet ids: players from the Chadwick register; parks and home plate umpires
#' learned from earlier seasons' schedules joined to Retrosheet game info, latest season winning
#' (Retrosheet re-coded at least one umpire in 2025); umpires fall back to the register.
id_maps <- function(season) {
  reg <- chadwick_register()[!is.na(key_mlbam) & !is.na(key_retro) & key_retro != "",
                             .(mlbam = as.integer(key_mlbam), retro = key_retro)]
  have <- as.integer(sub("csvs[.]zip$", "", list.files(RETRO, "^\\d{4}csvs[.]zip$")))
  past <- intersect(2021:(season - 1), have)
  j <- merge(add_gid(data.table::rbindlist(lapply(past, function(s) final_games(feed_schedule(s))))),
             data.table::rbindlist(lapply(past, retro_games))[, .(gid, site, umphome)], by = "gid")
  venue <- j[order(Date)][, .(site = site[.N]), by = venue_id]
  ump <- j[!is.na(ump_id)][order(Date)][, .(retro = umphome[.N]), by = .(mlbam = ump_id)]
  ump <- rbind(ump, reg[grepl("9\\d\\d$", retro) & !mlbam %in% ump$mlbam])
  list(person = reg, venue = venue, ump = ump, from = past)
}

to_retro <- function(id, map, prefix = "mlbam") {
  r <- map$retro[match(id, map$mlbam)]
  ifelse(is.na(r), paste0(prefix, id), r)
}

#' Plate appearances for one season in retro_pa()'s columns and coding.
statsapi_pa <- function(season, raw = FALSE) {
  x <- statsapi_parsed(season); m <- id_maps(season)
  g <- statsapi_games(season, raw = TRUE, x = x, m = m)
  p <- merge(x$pa[event != "intent_walk"], g[, .(game_pk, gid, Date, site, hometeam, visteam, umphome)], by = "game_pk")
  data.table::setorder(p, Date, gid, ab)
  p[, `:=`(season = as.integer(season),
           batteam = ifelse(top_bot == 0L, visteam, hometeam), pitteam = ifelse(top_bot == 0L, hometeam, visteam),
           batter_mlbam = batter, pitcher_mlbam = pitcher,
           batter = to_retro(batter, m$person), pitcher = to_retro(pitcher, m$person),
           bathand = ifelse(bats == "S", "B", bats),
           outcome = data.table::fcase(event %in% K_EVENTS, "k", event == "walk", "ubb", event == "hit_by_pitch", "hbp",
                                       event == "single", "single", event == "double", "double",
                                       event == "triple", "triple", event == "home_run", "hr", default = "out_ip"),
           bb_type = unname(TRAJ[traj]))]
  p[, seq := seq_len(.N), by = gid]
  p[, tto := seq_len(.N), by = .(gid, pitcher, batter)]
  keep <- c("gid", "Date", "season", "inning", "top_bot", "site", "batteam", "pitteam", "batter",
            "pitcher", "bathand", "pithand", "outcome", "bb_type", "runs", "outs_pre", "umphome", "seq", "tto")
  if (raw) keep <- c(keep, "game_pk", "batter_mlbam", "pitcher_mlbam", "event", "traj")   # for the parity check
  p[, ..keep]
}

#' Game info for one season in retro_games()'s columns and coding (`raw` adds game_pk).
statsapi_games <- function(season, raw = FALSE, x = statsapi_parsed(season), m = id_maps(season)) {
  g <- add_gid(data.table::copy(x$games))
  g[, `:=`(season = as.integer(season),
           site = { s <- m$venue$site[match(venue_id, m$venue$venue_id)]; ifelse(is.na(s), paste0("venue", venue_id), s) },
           winddir = { d <- unname(WIND[sub("^[^,]*, *", "", wind)]); ifelse(is.na(d), "unknown", d) },
           windspeed = suppressWarnings(as.integer(sub(" *mph.*$", "", wind))),
           sky = { s <- unname(SKY[condition]); ifelse(is.na(s), "unknown", s) },
           precip = { s <- unname(PRECIP[condition]); ifelse(is.na(s), "none", s) },
           umphome = ifelse(is.na(ump_id), NA_character_, to_retro(ump_id, m$ump)))]
  data.table::setorder(g, Date, gid)
  keep <- c("gid", "Date", "season", "visteam", "hometeam", "site", "number", "starttime", "daynight", "usedh",
            "temp", "winddir", "windspeed", "sky", "precip", "umphome", "vruns", "hruns")
  g[, c(keep, if (raw) "game_pk"), with = FALSE]
}

#' Pitcher box lines for one season in the shape sabr_baseline.R reads from Retrosheet's pitching
#' file (gid, pitcher, outs = p_ipouts, er = p_er), from the cached feeds' boxscores. The StatsAPI
#' ids are cached as pitching_{season}.rds, re-parsed when new games land; ids map on read.
statsapi_pitching <- function(season) {
  out <- file.path(FEED_DIR, sprintf("pitching_%d.rds", season))
  pks <- fetch_feeds(season)
  x <- if (file.exists(out)) readRDS(out) else NULL
  if (is.null(x) || !setequal(unique(x$game_pk), pks)) {
    x <- data.table::rbindlist(lapply(seq_along(pks), function(i) {
      if (i %% 250 == 0) message(season, ": box lines ", i, " of ", length(pks))
      d <- jsonlite::fromJSON(paste(readLines(gzfile(feed_path(season, pks[i])), warn = FALSE, encoding = "UTF-8"),
                                    collapse = "\n"), simplifyVector = FALSE)
      data.table::rbindlist(lapply(d$liveData$boxscore$teams, function(t) data.table::rbindlist(lapply(t$pitchers, function(id) {
        s <- t$players[[paste0("ID", id)]]$stats$pitching
        list(game_pk = pks[i], pitcher = as.integer(id), outs = as.integer(s$outs %||% 0L), er = as.integer(s$earnedRuns %||% 0L))
      }))))
    }))
    saveRDS(x, out)
  }
  g <- statsapi_games(season, raw = TRUE)
  x <- merge(x, g[, .(game_pk, gid)], by = "game_pk")
  x[, .(gid, pitcher = to_retro(pitcher, id_maps(season)$person), outs, er)]
}
