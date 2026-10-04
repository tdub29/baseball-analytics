# Statcast expected outcomes per batted ball, joined to Retrosheet plate appearances.
#
# Each ball in play gets the league outcome mix (single, double, triple, home run, out) of balls hit
# at a similar exit velocity and launch angle over the prior three seasons. Rates built from these
# carry quality of contact without the luck of where the ball landed (Savant data, key-free).

SC_DIR <- "data/mlb/raw/statcast"
BIP5 <- c("single", "double", "triple", "hr", "out_ip")

statcast_bip <- function() {
  out <- file.path(SC_DIR, "bip_all.rds")
  if (file.exists(out)) return(readRDS(out))
  cols <- c("game_pk", "game_date", "batter", "pitcher", "stand", "p_throws", "events", "bb_type",
            "launch_speed", "launch_angle", "at_bat_number", "home_team")
  files <- list.files(SC_DIR, "^bip_\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE)
  x <- data.table::rbindlist(lapply(files, function(f) {
    d <- tryCatch(data.table::fread(f, select = cols, showProgress = FALSE), error = function(e) NULL)
    if (is.null(d) || !nrow(d)) NULL else d
  }), fill = TRUE)
  x <- unique(x, by = c("game_pk", "at_bat_number"))
  x[, Date := as.Date(game_date)][, season := as.integer(format(Date, "%Y"))]
  x[, outcome := data.table::fcase(events == "single", "single", events == "double", "double",
                                   events == "triple", "triple", events == "home_run", "hr", default = "out_ip")]
  saveRDS(x, out)
  x
}

#' Outcome mix by exit-velocity and launch-angle bin from the three prior seasons (2015 uses itself).
ev_la_mix <- function(x) {
  x <- x[!is.na(launch_speed) & !is.na(launch_angle)]
  x[, `:=`(evb = pmin(pmax(floor(launch_speed / 3), 10), 39), lab = pmin(pmax(floor(launch_angle / 4), -12), 18))]
  cnt <- x[, .N, by = .(season, evb, lab, outcome)]
  data.table::rbindlist(lapply(sort(unique(x$season)), function(S) {
    src <- cnt[season %in% if (S == min(x$season)) S else (S - 3):(S - 1)]
    m <- data.table::dcast(src[, .(N = sum(N)), by = .(evb, lab, outcome)], evb + lab ~ outcome, value.var = "N", fill = 0)
    for (o in setdiff(BIP5, names(m))) m[[o]] <- 0
    m[, tot := rowSums(.SD), .SDcols = BIP5]
    m <- m[tot >= 20]                                      # thin bins fall back to the batted-ball-type mix
    for (o in BIP5) m[[paste0("sx_", o)]] <- m[[o]] / m$tot
    cbind(season = S, m[, c("evb", "lab", paste0("sx_", BIP5)), with = FALSE])
  }))
}

#' Expected outcome probabilities for Retrosheet balls in play, keyed by (gid, seq).
#' Matched on date, batter and pitcher (Chadwick ids) and the order of their meetings that day.
statcast_expected <- function(P, register) {
  x <- statcast_bip()
  mix <- ev_la_mix(x)
  x[, `:=`(evb = pmin(pmax(floor(launch_speed / 3), 10), 39), lab = pmin(pmax(floor(launch_angle / 4), -12), 18))]
  x <- merge(x, mix, by = c("season", "evb", "lab"), all.x = TRUE)
  idmap <- register[!is.na(key_mlbam) & key_retro != "", .(mlbam = as.integer(key_mlbam), retro = key_retro)]
  x[, batter_r := idmap$retro[match(batter, idmap$mlbam)]][, pitcher_r := idmap$retro[match(pitcher, idmap$mlbam)]]
  data.table::setorder(x, Date, batter_r, pitcher_r, at_bat_number)
  x[, k := seq_len(.N), by = .(Date, batter_r, pitcher_r)]
  r <- P[outcome %in% BIP5 & !is.na(bb_type), .(gid, seq, Date, batter, pitcher)]
  data.table::setorder(r, Date, batter, pitcher, seq)
  r[, k := seq_len(.N), by = .(Date, batter, pitcher)]
  j <- merge(r, x[!is.na(sx_single), c("Date", "batter_r", "pitcher_r", "k", paste0("sx_", BIP5)), with = FALSE],
             by.x = c("Date", "batter", "pitcher", "k"), by.y = c("Date", "batter_r", "pitcher_r", "k"))
  j[, c("gid", "seq", paste0("sx_", BIP5)), with = FALSE]
}
