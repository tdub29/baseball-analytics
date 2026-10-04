# Retrosheet plate appearances and game info for the matchup model (MATCHUP-PLAN.md).
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.
# Interested parties may contact Retrosheet at "www.retrosheet.org".
#
# One compact row per regular-season plate appearance: who batted and pitched, both hands,
# the outcome as one category, batted-ball type, the order position, and how many times this
# batter has already faced this pitcher in the game (for the times-through-the-order penalty).

RETRO <- "data/mlb/raw/retrosheet"

OUTCOMES <- c("k", "ubb", "hbp", "single", "double", "triple", "hr", "out_ip")

retro_file <- function(season, what) {
  zip <- file.path(RETRO, sprintf("%dcsvs.zip", season))
  f <- sprintf("%d%s.csv", season, what)
  dir <- file.path(RETRO, season)
  if (!file.exists(file.path(dir, f))) utils::unzip(zip, files = f, exdir = dir)
  file.path(dir, f)
}

#' Plate appearances for one season, cached as rds.
retro_pa <- function(season) {
  out <- file.path(RETRO, sprintf("pa_%d.rds", season))
  if (file.exists(out)) return(readRDS(out))
  cols <- c("gid", "date", "gametype", "inning", "top_bot", "site", "batteam", "pitteam", "batter",
            "pitcher", "bathand", "pithand", "pa", "single", "double", "triple", "hr", "hbp", "walk",
            "iw", "k", "bip", "ground", "fly", "line", "bunt", "sh", "hittype", "runs", "outs_pre",
            "umphome")
  p <- data.table::fread(retro_file(season, "plays"), select = cols, showProgress = FALSE)
  p <- p[gametype == "regular" & pa == 1]
  p[, outcome := data.table::fcase(k == 1, "k", walk == 1 & iw == 0, "ubb", hbp == 1, "hbp",
                                    single == 1, "single", double == 1, "double", triple == 1, "triple",
                                    hr == 1, "hr", default = "out_ip")]
  p <- p[!(walk == 1 & iw == 1)]                         # intentional walks are a manager's choice
  p[, bb_type := data.table::fcase(hittype == "G" | (bip == 1 & ground == 1), "gb",
                                   hittype == "L" | (bip == 1 & line == 1), "ld",
                                   hittype == "P", "pu",
                                   hittype == "F" | (bip == 1 & fly == 1), "fb", default = NA_character_)]
  p[, Date := as.Date(as.character(date), "%Y%m%d")]
  p[, seq := seq_len(.N), by = gid]
  p[, tto := seq_len(.N), by = .(gid, pitcher, batter)]   # 1 = first time this batter faces him today
  p[, season := season]
  keep <- c("gid", "Date", "season", "inning", "top_bot", "site", "batteam", "pitteam", "batter",
            "pitcher", "bathand", "pithand", "outcome", "bb_type", "runs", "outs_pre", "umphome", "seq", "tto")
  p <- p[, ..keep]
  saveRDS(p, out)
  p
}

#' Game info: teams, date, doubleheader number, start time, weather, umpire, DH, final score.
retro_games <- function(season) {
  g <- data.table::fread(retro_file(season, "gameinfo"), showProgress = FALSE)
  g <- g[gametype == "regular"]
  g[, `:=`(Date = as.Date(as.character(date), "%Y%m%d"), season = season)]
  g[, .(gid, Date, season, visteam, hometeam, site, number, starttime, daynight, usedh, temp,
        winddir, windspeed, sky, precip, umphome, vruns, hruns)]
}
