#!/usr/bin/env Rscript
# Data audit for the MLB research pipeline (DATA.md): row counts by season, cross-source
# reconciliation, duplicate keys and missingness, read from the local raw cache only (no network).
#
#   Rscript research/r/mlb/data_audit.R        # from the repo root; writes results/data-audit.md
#
# Aggregates only. The odds dataset has no license (private research): no odds row and no per-game
# odds value is written anywhere by this script. Game-level lists below carry scores, never prices.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("retro.R", "statcast.R")) source(file.path(SRC, f))
RAW <- "data/mlb/raw"
SEASONS <- 2015:2025
OUT <- file.path(SRC, "results", "data-audit.md")
EXCL <- as.Date(c("2021-09-01", "2021-12-31"))       # in-game "current" lines (MARKET-PLAN.md it 2)

pct <- function(a, b) ifelse(b > 0, sprintf("%.2f%%", 100 * a / b), "-")
md <- function(d) {
  d <- as.data.frame(d)
  d[] <- lapply(d, function(x) ifelse(is.na(x), "-", as.character(x)))
  c(paste("|", paste(names(d), collapse = " | "), "|"), paste("|", paste(rep("---", ncol(d)), collapse = " | "), "|"),
    vapply(seq_len(nrow(d)), function(i) paste("|", paste(unlist(d[i, ]), collapse = " | "), "|"), ""))
}
files <- function(dir, pattern = "\\.rds$") sort(list.files(file.path(RAW, dir), pattern, full.names = TRUE))
read_dir <- function(dir) rbindlist(lapply(files(dir), function(f) {
  d <- as.data.table(readRDS(f)); if (nrow(d)) d[, file := basename(f)]; d }), fill = TRUE)
yr <- function(d) as.integer(format(d, "%Y"))
L <- character(0)                                   # report lines
add <- function(...) L <<- c(L, ...)

# --- load ----------------------------------------------------------------------------------------

message(format(Sys.time(), "%H:%M:%S "), "loading Retrosheet")
G  <- rbindlist(lapply(SEASONS, retro_games))                         # regular-season games
P  <- rbindlist(lapply(SEASONS, retro_pa))                            # PAs, intentional walks removed
GI <- rbindlist(lapply(SEASONS, function(s) fread(retro_file(s, "gameinfo"), select = c("gid", "gametype"), showProgress = FALSE)))
message(format(Sys.time(), "%H:%M:%S "), "loading StatsAPI")
S  <- read_dir("statsapi_lineups"); S[, season := yr(Date)]
TM <- rbindlist(lapply(SEASONS, function(s) cbind(season = s, as.data.table(readRDS(file.path(RAW, "statsapi_teams", paste0(s, ".rds")))))))
TL <- read_dir("statsapi_team_log")[, group := sub(".*_(hitting|pitching)\\.rds$", "\\1", file)][, season := yr(Date)]
PL <- read_dir("statsapi_player_log")[, `:=`(group = sub("^\\d{4}_(hitting|pitching)_.*", "\\1", file), season = as.integer(substr(file, 1, 4)))]
RO <- read_dir("statsapi_roster")[, season := as.integer(sub("^\\d+_(\\d{4})\\.rds$", "\\1", file))]
SC <- read_dir("statsapi_schedule")                                   # ingest.R schedule, backtest 2016-2019
message(format(Sys.time(), "%H:%M:%S "), "loading Statcast, Chadwick, Baseball-Reference")
X   <- statcast_bip()                                                 # cached union of the weekly CSVs
REG <- as.data.table(readRDS(file.path(RAW, "chadwick", "register.rds")))
BREF <- rbindlist(lapply(c("bref_batter", "bref_pitcher"), function(d) data.table(
  source = d, season = as.integer(substr(basename(files(d)), 1, 4)), rows = vapply(files(d), function(f) NROW(readRDS(f)), 0))))

message(format(Sys.time(), "%H:%M:%S "), "parsing odds")
dec <- function(a) ifelse(a > 0, 1 + a / 100, 1 + 100 / abs(a))
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
nv  <- function(h, a) { ok <- !is.na(h) & !is.na(a) & h != 0 & a != 0
  if (!any(ok)) return(NA_real_); dh <- dec(h[ok]); da <- dec(a[ok]); mean((1 / dh) / (1 / dh + 1 / da)) }
raw <- jsonlite::fromJSON(file.path(RAW, "odds", "mlb_odds_dataset.json"), simplifyVector = FALSE)
line_fields <- character(0); books_seen <- character(0)
O <- rbindlist(lapply(names(raw), function(d) rbindlist(lapply(raw[[d]], function(g) {
  v <- g$gameView; ml <- g$odds$moneyline; tt <- g$odds$totals
  line_fields <<- union(line_fields, unlist(lapply(ml, function(b) c(names(b), paste0("openingLine.", names(b$openingLine)),
                                                                     paste0("currentLine.", names(b$currentLine))))))
  books_seen <<- union(books_seen, unlist(lapply(c(ml, tt), function(b) b$sportsbook)))
  side <- function(line, s) vapply(ml, function(b) num(b[[line]][[s]]), 0)
  ch <- side("currentLine", "homeOdds"); ca <- side("currentLine", "awayOdds")
  oh <- side("openingLine", "homeOdds"); oa <- side("openingLine", "awayOdds")
  list(odds_date = as.Date(d), start = v$startDate %||% NA_character_, home = v$homeTeam$fullName %||% NA_character_,
       away = v$awayTeam$fullName %||% NA_character_, hs = num(v$homeTeamScore), as = num(v$awayTeamScore),
       status = v$gameStatusText %||% "", gtype = v$gameType %||% NA_character_, n_ml = length(ml),
       n_cur = sum(!is.na(ch) & !is.na(ca) & ch != 0 & ca != 0), n_open = sum(!is.na(oh) & !is.na(oa) & oh != 0 & oa != 0),
       n_tot = length(tt), p_close = nv(ch, ca), p_open = nv(oh, oa))
}))))
rm(raw); O[, season := yr(odds_date)]

# --- 0. raw input fingerprints -------------------------------------------------------------------
message(format(Sys.time(), "%H:%M:%S "), "fingerprints")

fingerprint <- function(label, paths) {
  h <- tools::md5sum(paths)
  combo <- if (length(paths) == 1) unname(h) else {
    tf <- tempfile(); writeLines(paste(basename(paths), h), tf); unname(tools::md5sum(tf)) }
  m <- file.mtime(paths)
  data.table(source = label, files = length(paths), MB = sprintf("%.1f", sum(file.size(paths)) / 2^20),
             modified = paste(unique(format(range(m), "%Y-%m-%d")), collapse = " to "), md5 = combo)
}
FP <- rbind(
  fingerprint("Retrosheet season zips", files("retrosheet", "csvs\\.zip$")),
  fingerprint("StatsAPI lineups (schedule, scores, probables, lineups)", files("statsapi_lineups")),
  fingerprint("StatsAPI team game logs", files("statsapi_team_log")),
  fingerprint("StatsAPI player game logs", files("statsapi_player_log")),
  fingerprint("StatsAPI rosters", files("statsapi_roster")),
  fingerprint("StatsAPI teams", files("statsapi_teams")),
  fingerprint("StatsAPI schedule (ingest.R, backtest)", files("statsapi_schedule")),
  fingerprint("StatsAPI season dates", files("seasons")),
  fingerprint("Savant batted balls (weekly CSVs)", files("statcast", "^bip_\\d{4}-\\d{2}-\\d{2}\\.csv$")),
  fingerprint("Chadwick register", files("chadwick")),
  fingerprint("Baseball-Reference daily batting windows", files("bref_batter")),
  fingerprint("Baseball-Reference daily pitching windows", files("bref_pitcher")),
  fingerprint("Odds dataset (SportsBookReview scrape)", file.path(RAW, "odds", "mlb_odds_dataset.json")))

# --- 1. row counts by season ---------------------------------------------------------------------

sc_final <- SC[status.abstractGameState == "Final" & !is.na(teams.home.score)][!duplicated(gamePk)][, .N, by = .(season = yr(as.Date(officialDate)))]
cnt <- function(d, by = "season") d[, .N, by = by]
counts <- list()
put <- function(name, d) counts[[name]] <<- d$N[match(SEASONS, d$season)]
put("Retrosheet games", cnt(G))
put("Retrosheet PAs", cnt(P))
put("Retrosheet balls in play", cnt(P[outcome %in% BIP5 & !is.na(bb_type)]))
put("StatsAPI games", cnt(S))
put("StatsAPI team-log rows", cnt(TL))
put("StatsAPI hitter lines", cnt(PL[group == "hitting"]))
put("StatsAPI pitcher lines", cnt(PL[group == "pitching"]))
put("StatsAPI roster rows", cnt(RO))
put("StatsAPI schedule (backtest)", sc_final)
put("Statcast balls in play", cnt(X))
put("bref batting rows", BREF[source == "bref_batter", .(N = sum(rows)), by = season])
put("bref pitching rows", BREF[source == "bref_pitcher", .(N = sum(rows)), by = season])
put("Odds games (all)", cnt(O))
put("Odds games final, scored", cnt(O[startsWith(status, "Final") & !is.na(hs)]))
RCt <- data.table(source = names(counts), do.call(rbind, counts))
setnames(RCt, c("source", as.character(SEASONS)))

# --- 2. Retrosheet vs StatsAPI: games and final scores -------------------------------------------

message(format(Sys.time(), "%H:%M:%S "), "reconciling Retrosheet and StatsAPI")
cand <- merge(G[, .(Date, season, hometeam, visteam, hruns, vruns)], S[, .(Date, home_id, away_id, home_score, away_score)],
              by.x = c("Date", "hruns", "vruns"), by.y = c("Date", "home_score", "away_score"), allow.cartesian = TRUE)
vote <- rbind(cand[, .(season, code = hometeam, id = home_id)], cand[, .(season, code = visteam, id = away_id)])[
  , .N, by = .(season, code, id)][order(-N)][!duplicated(paste(season, code))]
map_check <- vote[, .(codes = .N, ids = uniqueN(id)), by = season]
R <- merge(G, vote[, .(season, hometeam = code, hid = id)], by = c("season", "hometeam"), all.x = TRUE)
R <- merge(R, vote[, .(season, visteam = code, aid = id)], by = c("season", "visteam"), all.x = TRUE)
setorder(R, gid); R[, ia := .I]
A <- S[, .(game_pk, Date, season, hid = home_id, aid = away_id, hs = home_score, as = away_score)]
setorder(A, game_pk); A[, ib := .I]
R[, `:=`(hs = hruns, as = vruns)]

pair <- function(r, a, keys) {            # one-to-one on keys; the k-th copy of a key pairs with the k-th
  r <- copy(r)[, key := do.call(paste, .SD), .SDcols = keys][, k := seq_len(.N), by = key]
  a <- copy(a)[, key := do.call(paste, .SD), .SDcols = keys][, k := seq_len(.N), by = key]
  merge(r[, .(ia, key, k)], a[, .(ib, key, k)], by = c("key", "k"))[, .(ia, ib)]
}
K5 <- c("Date", "hid", "aid", "hs", "as")
p1 <- pair(R, A, K5)
rkey <- do.call(paste, R[, ..K5]); amb_ra <- sum(duplicated(rkey) | duplicated(rkey, fromLast = TRUE))
R2 <- R[!ia %in% p1$ia]; A2 <- A[!ib %in% p1$ib]
p2 <- pair(R2, A2, c("Date", "hid", "aid"))
R3 <- R2[!ia %in% p2$ia]; A3 <- A2[!ib %in% p2$ib]
m3 <- merge(R3[, .(ia, Dr = Date, hid, aid, hs, as)], A3[, .(ib, Da = Date, hid, aid, hs, as)], by = c("hid", "aid", "hs", "as"))
m3 <- m3[abs(as.numeric(Dr - Da)) <= 3][order(abs(as.numeric(Dr - Da)))]
used_a <- integer(0); used_r <- integer(0); keep <- logical(nrow(m3))
for (i in seq_len(nrow(m3))) if (!m3$ia[i] %in% used_r && !m3$ib[i] %in% used_a) {
  keep[i] <- TRUE; used_r <- c(used_r, m3$ia[i]); used_a <- c(used_a, m3$ib[i]) }
p3 <- m3[keep, .(ia, ib)]
R4 <- R3[!ia %in% p3$ia]; A4 <- A3[!ib %in% p3$ib]
p4 <- pair(R4[, .(ia, Date, hid = aid, aid = hid, hs = as, as = hs)], A4, K5)
R5 <- R4[!ia %in% p4$ia]; A5 <- A4[!ib %in% p4$ib]
R[, cat := "retrosheet only"]; R[ia %in% p1$ia, cat := "exact"]; R[ia %in% p2$ia, cat := "score differs"]
R[ia %in% p3$ia, cat := "date differs"]; R[ia %in% p4$ia, cat := "home/away swapped"]
by_s <- function(x) table(factor(x, levels = SEASONS))
RS <- data.table(season = SEASONS, retrosheet = as.integer(by_s(R$season)), statsapi = as.integer(by_s(A$season)),
                 exact = as.integer(by_s(R[cat == "exact"]$season)),
                 `score differs` = as.integer(by_s(R[cat == "score differs"]$season)),
                 `date differs` = as.integer(by_s(R[cat == "date differs"]$season)),
                 `home/away swapped` = as.integer(by_s(R[cat == "home/away swapped"]$season)),
                 `retrosheet only` = as.integer(by_s(R5$season)), `statsapi only` = as.integer(by_s(A5$season)))
RS[, `match rate` := pct(exact, retrosheet)]
RS[, `score agreement` := pct(exact, exact + `score differs`)]
pairs_all <- rbind(p2[, cat := "score differs"], p3[, cat := "date differs"], p4[, cat := "home/away swapped"])
EXC <- rbind(
  merge(pairs_all, R[, .(ia, gid, season, rdate = Date, teams = paste(visteam, "at", hometeam), r_score = paste0(vruns, "-", hruns))], by = "ia")[
    A[, .(ib, game_pk, adate = Date, a_score = paste0(as, "-", hs))], on = "ib", nomatch = 0],
  R5[, .(cat = "retrosheet only", gid, season, rdate = Date, teams = paste(visteam, "at", hometeam), r_score = paste0(vruns, "-", hruns))],
  A5[, .(cat = "statsapi only", season, game_pk, adate = Date, a_score = paste0(as, "-", hs),
         teams = paste(TM$team[match(paste(season, aid), paste(TM$season, TM$team_id))], "at",
                       TM$team[match(paste(season, hid), paste(TM$season, TM$team_id))]))],
  fill = TRUE)[order(season, cat)]
EXC <- EXC[, .(category = cat, season, gid, game_pk, `Retrosheet date` = rdate, `StatsAPI date` = adate, teams,
               `Retrosheet score (away-home)` = r_score, `StatsAPI score (away-home)` = a_score)]

# ambiguity that matters downstream: same teams, same day, same score (the model joins drop or guess these)
amb_api <- A[, .N, by = K5][N > 1, sum(N)]

# --- 3. Statcast balls in play to Retrosheet ------------------------------------------------------

message(format(Sys.time(), "%H:%M:%S "), "matching Statcast to Retrosheet")
idmap <- REG[!is.na(key_mlbam) & key_retro != "", .(mlbam = as.integer(key_mlbam), retro = key_retro)][!duplicated(mlbam)]
x <- X[, .(season, Date, game_pk, at_bat_number, batter, pitcher, out_s = outcome, bb_s = bb_type, launch_speed, launch_angle)]
x[, `:=`(batter_r = idmap$retro[match(batter, idmap$mlbam)], pitcher_r = idmap$retro[match(pitcher, idmap$mlbam)])]
setorder(x, Date, batter_r, pitcher_r, at_bat_number); x[, k := seq_len(.N), by = .(Date, batter_r, pitcher_r)]
r <- P[outcome %in% BIP5 & !is.na(bb_type), .(gid, seq, season, Date, batter, pitcher, out_r = outcome, bb_r = bb_type)]
setorder(r, Date, batter, pitcher, seq); r[, k := seq_len(.N), by = .(Date, batter, pitcher)]
J <- merge(r, x[!is.na(batter_r) & !is.na(pitcher_r), !c("season", "batter", "pitcher")], by.x = c("Date", "batter", "pitcher", "k"),
           by.y = c("Date", "batter_r", "pitcher_r", "k"))
BBMAP <- c(ground_ball = "gb", line_drive = "ld", fly_ball = "fb", popup = "pu")
rdates <- unique(G[, .(season, Date)]); xdates <- unique(X[, .(season, Date)])
nodates <- rdates[!xdates, on = c("season", "Date")][, .N, by = season]
SCM <- J[, .(matched = .N, `matched, EV and LA present` = sum(!is.na(launch_speed) & !is.na(launch_angle)),
             `outcome agrees` = pct(sum(out_r == out_s), .N), `batted-ball type agrees` = pct(sum(bb_r == BBMAP[bb_s], na.rm = TRUE), .N)), by = season]
SCM <- merge(merge(r[, .(`Retrosheet BIP` = .N), by = season], SCM, by = "season", all.x = TRUE),
             x[, .(`Statcast BIP` = .N, `Statcast rows without a Retrosheet id` = sum(is.na(batter_r) | is.na(pitcher_r))), by = season], by = "season")
SCM[, `Retrosheet BIP matched` := pct(matched, `Retrosheet BIP`)]
SCM[, `Statcast BIP matched` := pct(matched, `Statcast BIP`)]
SCM[, `usable (EV and LA)` := pct(`matched, EV and LA present`, `Retrosheet BIP`)]
SCM[, `Retrosheet dates with no Statcast rows` := nodates$N[match(season, nodates$season)]]
SCM[is.na(`Retrosheet dates with no Statcast rows`), `Retrosheet dates with no Statcast rows` := 0L]
SCM <- SCM[, .(season, `Retrosheet BIP`, `Statcast BIP`, matched, `Retrosheet BIP matched`, `Statcast BIP matched`,
               `usable (EV and LA)`, `outcome agrees`, `batted-ball type agrees`, `Statcast rows without a Retrosheet id`,
               `Retrosheet dates with no Statcast rows`)]
usable_all <- J[, sum(!is.na(launch_speed) & !is.na(launch_angle))]
nodate_list <- rdates[!xdates, on = c("season", "Date")][order(Date), paste(format(Date), collapse = ", ")]
# batted-ball type shares by season in each source: a jump in one source and not the other is a definition change
mix <- function(d, col, map = identity) { m <- d[, .N, by = .(season, t = map(get(col)))][!is.na(t)]
  m[, s := sprintf("%.1f", 100 * N / sum(N)), by = season]; dcast(m, season ~ t, value.var = "s") }
BBM <- merge(setnames(mix(r, "bb_r"), c("gb", "ld", "fb", "pu"), paste("Retrosheet", c("gb", "ld", "fb", "pu")), skip_absent = TRUE),
             setnames(mix(x, "bb_s", function(v) unname(BBMAP[v])), c("gb", "ld", "fb", "pu"), paste("Statcast", c("gb", "ld", "fb", "pu")), skip_absent = TRUE),
             by = "season")
y <- rbindlist(lapply(files("statcast", "^bip_\\d{4}-\\d{2}-\\d{2}\\.csv$"), function(f)
  tryCatch(fread(f, select = c("game_pk", "at_bat_number"), showProgress = FALSE), error = function(e) NULL)))
csv_rows <- nrow(y); csv_dup <- sum(duplicated(y)); rm(y)

# --- 4. odds to StatsAPI games --------------------------------------------------------------------

message(format(Sys.time(), "%H:%M:%S "), "matching odds to StatsAPI")
norm <- function(x) {                       # odds names: 2021 Cleveland already "Guardians",
  x <- gsub("[^a-z]", "", tolower(sub("^Oakland ", "", x)))   # 2025 A's "Athletics Athletics"
  x[x == "clevelandindians"] <- "clevelandguardians"; x[x == "athleticsathletics"] <- "athletics"; x
}   # market_study.R's key
S[, `:=`(home = TM$team[match(paste(season, home_id), paste(TM$season, TM$team_id))],
         away = TM$team[match(paste(season, away_id), paste(TM$season, TM$team_id))])]
key <- function(d, h, a, hs, as) paste(d, norm(h), norm(a), hs, as)
O[, final := startsWith(status, "Final") & !is.na(hs) & !is.na(as)]
SW <- as.data.table(readRDS(files("seasons")[1]))[, .(season = as.integer(season_id), rs = as.Date(regular_season_start_date),
                                                      re = as.Date(regular_season_end_date))]
iw <- match(O$season, SW$season)
# inside the season window and not typed spring, All-Star or postseason (spring games run on past an
# overseas opener, e.g. Seoul 2024 and Tokyo 2025); "Unknown" is kept, it carries regular-season games
O[, regular := odds_date >= SW$rs[iw] & odds_date <= SW$re[iw] & gtype %in% c("R", "Unknown")]
OF <- O[final == TRUE]
sk <- key(S$Date, S$home, S$away, S$home_score, S$away_score)
ok <- key(OF$odds_date, OF$home, OF$away, OF$hs, OF$as)
OF[, amb := ok %in% ok[duplicated(ok)] | ok %in% sk[duplicated(sk)]]
OF[, row := match(ok, sk)]
OF[amb == TRUE, row := NA]
OF[, reason := fifelse(!is.na(row), "matched", fifelse(amb, "ambiguous (same teams, day, score)", "unmatched"))]
d1 <- key(OF$odds_date - 1, OF$home, OF$away, OF$hs, OF$as) %in% sk | key(OF$odds_date + 1, OF$home, OF$away, OF$hs, OF$as) %in% sk
dn <- paste(OF$odds_date, norm(OF$home), norm(OF$away)) %in% paste(S$Date, norm(S$home), norm(S$away))
snames <- unique(paste(c(S$season, S$season), norm(c(S$home, S$away))))            # StatsAPI names per season
known <- paste(OF$season, norm(OF$home)) %in% snames & paste(OF$season, norm(OF$away)) %in% snames
u <- OF$reason == "unmatched"          # index outside the table: inside j, reason is already the subset
OF$reason[u] <- fifelse(!OF$regular[u], "outside regular season", fifelse(d1[u], "date off by one day",
                        fifelse(dn[u], "score differs", fifelse(!known[u], "team name not in StatsAPI", "no StatsAPI game that day"))))
# odds names that never match a StatsAPI name that season, and the regular-season games they carry
bad_names <- OF[regular == TRUE, .(nm = c(home, away)), by = season][, .(rows = .N), by = .(season, nm)]
bad_names <- bad_names[!paste(season, norm(nm)) %in% snames]
first <- min(O$odds_date); last <- max(O$odds_date)
inwin <- S[Date >= first & Date <= last]
OM <- OF[, .(`odds final games` = .N, `outside regular season` = sum(reason == "outside regular season"),
             matched = sum(reason == "matched"), ambiguous = sum(reason == "ambiguous (same teams, day, score)"),
             `date off by one` = sum(reason == "date off by one day"), `score differs` = sum(reason == "score differs"),
             `name not in StatsAPI` = sum(reason == "team name not in StatsAPI"),
             `no game that day` = sum(reason == "no StatsAPI game that day"),
             `in excluded window` = sum(reason == "matched" & odds_date >= EXCL[1] & odds_date <= EXCL[2])), by = season]
OM <- merge(OM, inwin[, .(`StatsAPI games in odds range` = .N), by = season], by = "season")
OM <- merge(O[, .(`odds entries` = .N, `not final or no score` = sum(!final)), by = season], OM, by = "season")
OM[, `regular-season odds matched` := pct(matched, `odds final games` - `outside regular season`)]
OM[, `StatsAPI games covered` := pct(matched, `StatsAPI games in odds range`)]
matched_pk <- S$game_pk[OF$row[!is.na(OF$row)]]
dup_pk <- sum(duplicated(matched_pk))
# StatsAPI games in the odds range with no matched odds row, by team (top 3 per season)
nod <- inwin[!game_pk %in% matched_pk, .(team = c(home, away)), by = .(game_pk, season)][, .N, by = .(season, team)][order(season, -N)]
NOD <- nod[, .(`games without odds` = inwin[season == .BY$season & !game_pk %in% matched_pk, .N],
               `teams most affected (games)` = paste0(head(team, 3), " (", head(N, 3), ")", collapse = ", ")), by = season]
# which date the odds file keys a game on: the local (Eastern) date or the UTC date of first pitch
st <- as.POSIXct(sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", O$start), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
tz_et <- mean(as.Date(format(st, tz = "America/New_York")) == O$odds_date, na.rm = TRUE)
tz_utc <- mean(as.Date(format(st, tz = "UTC")) == O$odds_date, na.rm = TRUE)
# line-move sanity per season-month (the check that found the in-game Sept-Oct 2021 scrape)
MV <- OF[!is.na(row) & !is.na(p_close) & !is.na(p_open)]
MV[, y := as.integer(hs > as)]
MV <- MV[hs != as, .(games = .N, `moved 15+ points from open` = pct(sum(abs(p_close - p_open) > 0.15), .N),
                     `closing log loss` = sprintf("%.4f", mean(-(y * log(p_close) + (1 - y) * log(1 - p_close))))),
         by = .(month = format(odds_date, "%Y-%m"))][order(month)]
MV[, flag := fifelse(month >= "2021-09" & month <= "2021-12", "excluded window", "")]

# --- 5. duplicate keys ----------------------------------------------------------------------------
message(format(Sys.time(), "%H:%M:%S "), "duplicates")

dups <- function(src, keyname, d, cols) data.table(source = src, `key columns` = keyname, rows = nrow(d),
                                                   `duplicate rows` = sum(duplicated(d[, ..cols])))
nonblank <- function(v) !is.na(v) & v != ""
DU <- rbind(
  dups("Retrosheet gameinfo (regular)", "gid", G, "gid"),
  dups("Retrosheet gameinfo (all game types)", "gid", GI, "gid"),
  dups("Retrosheet plate appearances", "gid, seq", P, c("gid", "seq")),
  dups("StatsAPI lineups", "game_pk", S, "game_pk"),
  dups("StatsAPI lineups", "date, home, away, score", S, c("Date", "home_id", "away_id", "home_score", "away_score")),
  dups("StatsAPI team game logs", "team_id, game_pk, group", TL, c("team_id", "game_pk", "group")),
  dups("StatsAPI player game logs", "person_id, game_pk, group", PL, c("person_id", "game_pk", "group")),
  dups("StatsAPI rosters", "person_id, team_id, season", RO, c("person_id", "team_id", "season")),
  data.table(source = "Savant weekly CSVs (before dedupe)", `key columns` = "game_pk, at_bat_number", rows = csv_rows, `duplicate rows` = csv_dup),
  dups("Statcast cache bip_all.rds", "game_pk, at_bat_number", X, c("game_pk", "at_bat_number")),
  dups("Chadwick register", "key_mlbam", REG[!is.na(key_mlbam)], "key_mlbam"),
  dups("Chadwick register", "key_retro", REG[nonblank(key_retro)], "key_retro"),
  dups("Chadwick register", "key_bbref", REG[nonblank(key_bbref)], "key_bbref"),
  dups("Odds", "date, home, away, start", O, c("odds_date", "home", "away", "start")),
  dups("Odds (final)", "date, home, away, score", OF, c("odds_date", "home", "away", "hs", "as")))
cache_note <- if (csv_rows - csv_dup == nrow(X)) "matches" else sprintf("does NOT match (cache %d rows, CSVs %d after dedupe): rebuild bip_all.rds", nrow(X), csv_rows - csv_dup)

# --- 6. missingness of key fields -----------------------------------------------------------------
message(format(Sys.time(), "%H:%M:%S "), "missingness")

# player game logs against the team game logs they should add up to. Player logs are fetched only for
# players on the cached fullSeason rosters (gamelogs.R), so anyone missing from a roster loses a season.
tsum <- function(g, v) TL[group == g, .(t = sum(get(v), na.rm = TRUE)), by = .(game_pk, team_id, season)]
psum <- function(g, v) PL[group == g, .(p = sum(get(v), na.rm = TRUE)), by = .(game_pk, team_id)]
cmp <- function(g, v) { m <- merge(tsum(g, v), psum(g, v), by = c("game_pk", "team_id"), all.x = TRUE)[is.na(p), p := 0]
  m[, .(miss = sum(pmax(t - p, 0)), tot = sum(t)), by = season] }
bfc <- cmp("pitching", "battersFaced"); pac <- cmp("hitting", "plateAppearances")
sp_all <- S[, .(season, sp = c(home_sp, away_sp)), by = game_pk][!is.na(sp)]
off_roster <- sp_all[!paste(season, sp) %in% RO[, paste(season, person_id)], .(starts = .N, pitchers = uniqueN(sp)), by = season]
nostart <- merge(rbind(S[, .(game_pk, team_id = home_id, season)], S[, .(game_pk, team_id = away_id, season)]),
                 PL[group == "pitching" & gamesStarted == 1, .(game_pk, team_id, gs = 1)], by = c("game_pk", "team_id"), all.x = TRUE)[
  is.na(gs), .N, by = season]
PLC <- data.table(season = SEASONS)
PLC[, `pitcher BF missing vs team logs` := pct(bfc$miss[match(season, bfc$season)], bfc$tot[match(season, bfc$season)])]
PLC[, `team-games with no starter line` := nostart$N[match(season, nostart$season)]]
PLC[, `starts by pitchers absent from the rosters` := off_roster$starts[match(season, off_roster$season)]]
PLC[, `such pitchers` := off_roster$pitchers[match(season, off_roster$season)]]
PLC[, `hitter PA missing vs team logs` := pct(pac$miss[match(season, pac$season)], pac$tot[match(season, pac$season)])]
for (j in names(PLC)[-1]) set(PLC, which(is.na(PLC[[j]])), j, if (is.character(PLC[[j]])) "0.00%" else 0L)
starters <- PL[group == "pitching" & gamesStarted == 1, .(n = .N, sp = person_id[1]), by = .(game_pk, team_id)]
S <- merge(S, starters[, .(game_pk, home_id = team_id, h_act = sp, h_n = n)], by = c("game_pk", "home_id"), all.x = TRUE)
S <- merge(S, starters[, .(game_pk, away_id = team_id, a_act = sp, a_n = n)], by = c("game_pk", "away_id"), all.x = TRUE)
bat <- c(paste0("home_bat", 1:9), paste0("away_bat", 1:9))
S[, lineup_gap := rowSums(is.na(.SD)) > 0, .SDcols = bat]
miss <- function(field, d, flag) { t <- d[, .(v = pct(sum(flag[.I]), .N)), by = season]
  out <- data.table(field = field); for (s in SEASONS) out[[as.character(s)]] <- t$v[match(s, t$season)]; out }
Pb <- P[outcome %in% BIP5]
MS <- rbind(
  miss("Retrosheet PA: batter or pitcher id blank", P, !nonblank(P$batter) | !nonblank(P$pitcher)),
  miss("Retrosheet PA: batter hand B (switch hitter, side not recorded)", P, P$bathand == "B"),
  miss("Retrosheet PA: batter hand not L, R or B", P, !P$bathand %in% c("L", "R", "B")),
  miss("Retrosheet PA: pitcher hand not L/R", P, !P$pithand %in% c("L", "R")),
  miss("Retrosheet PA: hit or out in play without batted-ball type", Pb, is.na(Pb$bb_type)),
  miss("Retrosheet game: temperature 0 or missing", G, is.na(G$temp) | G$temp <= 0),
  miss("Retrosheet game: home-plate umpire blank", G, !nonblank(G$umphome)),
  miss("StatsAPI game: a probable starter missing", S, is.na(S$home_sp) | is.na(S$away_sp)),
  miss("StatsAPI game: probable is not the actual starter", S[!is.na(home_sp) & !is.na(h_act) & !is.na(away_sp) & !is.na(a_act)],
       with(S[!is.na(home_sp) & !is.na(h_act) & !is.na(away_sp) & !is.na(a_act)], home_sp != h_act | away_sp != a_act)),
  miss("StatsAPI game: no starter in the player logs (either side)", S, is.na(S$h_act) | is.na(S$a_act)),
  miss("StatsAPI game: a lineup slot missing", S, S$lineup_gap),
  miss("StatsAPI game: venue missing", S, is.na(S$venue_id)),
  miss("Statcast BIP: exit velocity missing", X, is.na(X$launch_speed)),
  miss("Statcast BIP: launch angle missing", X, is.na(X$launch_angle)),
  miss("Statcast BIP: batter or pitcher has no Retrosheet id", x, is.na(x$batter_r) | is.na(x$pitcher_r)),
  miss("Odds game: no moneyline", O, O$n_ml == 0),
  miss("Odds game: no current moneyline", O, O$n_cur == 0),
  miss("Odds game: no opening moneyline", O, O$n_open == 0),
  miss("Odds game: no totals", O, O$n_tot == 0))
reg_cov <- data.table(
  check = c("Statcast batters and pitchers with a Retrosheet id", "Retrosheet batters and pitchers in the register",
            "StatsAPI probable starters with a Baseball-Reference id"),
  value = c(pct(sum(unique(c(X$batter, X$pitcher)) %in% idmap$mlbam), uniqueN(c(X$batter, X$pitcher))),
            pct(sum(unique(c(P$batter, P$pitcher)) %in% REG$key_retro), uniqueN(c(P$batter, P$pitcher))),
            { ids <- unique(c(SC$teams.home.probablePitcher.id, SC$teams.away.probablePitcher.id)); ids <- ids[!is.na(ids)]
              pct(sum(ids %in% REG[nonblank(key_bbref)]$key_mlbam), length(ids)) }))

# --- report ---------------------------------------------------------------------------------------

add("# Data audit: MLB research pipeline", "",
    sprintf("Generated %s by `Rscript research/r/mlb/data_audit.R` from the local raw cache (no network). Source descriptions, terms and known gaps: [DATA.md](../DATA.md). Aggregates only: no odds row or per-game price appears here.", format(Sys.Date())), "",
    "Method (McGilvray assessment baseline): each check has a population, a pass rule and a reason. Reconciliation pairs records one to one, exact first, then each looser rule on what is left, so every record lands in exactly one category.", "",
    "## Headline", "",
    sprintf("- Retrosheet vs StatsAPI: %d of %d Retrosheet regular-season games (%s) match a StatsAPI game on date, both teams and final score; %d score disagreements, %d date disagreements, %d home/away swaps, %d Retrosheet-only and %d StatsAPI-only games.",
            sum(RS$exact), sum(RS$retrosheet), pct(sum(RS$exact), sum(RS$retrosheet)), sum(RS$`score differs`), sum(RS$`date differs`),
            sum(RS$`home/away swapped`), sum(RS$`retrosheet only`), sum(RS$`statsapi only`)),
    sprintf("- Statcast to Retrosheet balls in play: %s of Retrosheet balls in play matched (range %s to %s by season); %s usable with exit velocity and launch angle.",
            pct(sum(SCM$matched, na.rm = TRUE), sum(SCM$`Retrosheet BIP`)), pct(min(SCM$matched / SCM$`Retrosheet BIP`), 1), pct(max(SCM$matched / SCM$`Retrosheet BIP`), 1),
            pct(usable_all, sum(SCM$`Retrosheet BIP`))),
    sprintf("- Odds to StatsAPI games: %d of %d final regular-season odds games matched (%s; the file also holds %d spring, All-Star and postseason rows); %s of StatsAPI games between %s and %s have a matched odds row; %d matched games fall in the excluded window. %d StatsAPI games matched by two odds rows.",
            sum(OM$matched), sum(OM$`odds final games` - OM$`outside regular season`),
            pct(sum(OM$matched), sum(OM$`odds final games` - OM$`outside regular season`)), sum(OM$`outside regular season`),
            pct(sum(OM$matched), sum(OM$`StatsAPI games in odds range`)), first, last, sum(OM$`in excluded window`), dup_pk),
    sprintf("- Duplicate keys: %d source keys checked, %d with duplicates (table 5). The Statcast cache %s the weekly CSVs.",
            nrow(DU), sum(DU$`duplicate rows` > 0), cache_note), "",
    "## Prioritized findings", "",
    "Ranked by how much each could move a committed result. Severity is a judgement on reach and size; none of these has been rerun to measure its effect.", "",
    sprintf("1. **High: switch hitters entered as right-handed (matchup model, totals).** %s of Retrosheet PAs carry batter hand B; `matchup_build.R` maps them to R, so platoon splits, the platoon prior and park factors by batter hand treat a switch hitter as right-handed even against right-handed pitchers. Reaches `features.rds`, the frozen matchup v2 test and the totals study. Fix: side = opposite of the pitcher's hand for B (table 6).",
            pct(sum(P$bathand == "B"), nrow(P))),
    "2. **Medium: Retrosheet batted-ball types change definition in 2020 (matchup model, totals).** Pitchers are rated on the outcome mix of their batted-ball types over the prior three seasons, so 2020-2022 balls get mixes fit partly on the pre-2020 definition (table 3). Touches validation seasons 2021-2022 directly and the 2023-2025 test through decayed history.",
    if (nrow(bad_names)) sprintf("3. **Medium: odds team names that never match (market study, matchup market tests).** %s. Those games are silently missing from `market-joined.csv`. `totals_study.R` maps names by majority vote and keeps them (table 4).",
            paste(bad_names[, sprintf("%d: \"%s\" (%d rows)", season, nm, rows)], collapse = "; "))
    else "3. **Resolved 2026-10-06: odds team names that never matched.** 2021 \"Cleveland Guardians\" and 2025 \"Athletics Athletics\" are now mapped in `market_study.R` and here; every regular-season odds name matches a StatsAPI team (table 4). Corrected market results: `market-study-joinfix.md` and the `*-joinfix-test.md` files.",
    sprintf("4. **Low to medium: StatsAPI player logs miss pitchers absent from the cached rosters (recency model E and everything built on it).** Up to %s of pitcher batters faced missing in a season; %d starts by %d such pitchers across 2015-2025 (table 6).",
            PLC[, `pitcher BF missing vs team logs`][which.max(bfc$miss[match(PLC$season, bfc$season)] / bfc$tot[match(PLC$season, bfc$season)])],
            sum(off_roster$starts), sum(off_roster$pitchers)),
    sprintf("5. **Low: %d games with home and away swapped between Retrosheet and StatsAPI** (relocated series, mostly 2020; table 2). The Retrosheet-to-StatsAPI join in `matchup_model.R` drops them, so they carry no recency or market row. The 2018 tiebreakers are StatsAPI-only.", sum(RS$`home/away swapped`)),
    sprintf("6. **Low: Statcast gaps (%s Retrosheet dates without Statcast rows).** Statcast feeds only the dropped v3 ablations, not a frozen model.", sum(SCM$`Retrosheet dates with no Statcast rows`)), "",
    "## 0. Raw inputs (fingerprints)", "",
    "md5 of the single file, or of the sorted list of per-file md5s for a directory. `modified` is the local file time, i.e. the retrieval date.", "",
    md(FP), "",
    "## 1. Row counts by season", "",
    "Retrosheet PAs exclude intentional walks (retro.R). Balls in play: hits and outs in play with a batted-ball type. StatsAPI games are final regular-season games in the season window. Baseball-Reference windows were pulled for 2016-2019 only (the 2019 backtest).", "",
    md(RCt), "",
    "## 2. Retrosheet vs StatsAPI: games and final scores", "",
    sprintf("Retrosheet team codes are mapped to StatsAPI team ids per season by majority vote over games that agree on date and score (codes per season: %s; ids per season: %s).",
            paste(unique(map_check$codes), collapse = "/"), paste(unique(map_check$ids), collapse = "/")),
    "Rules in order: exact (date, home, away, both scores); same date and teams, score differs; same teams and score within 3 days; home and away swapped, same date and score; the rest are unmatched.", "",
    md(RS), "",
    sprintf("Same teams, same day, same score (doubleheaders that cannot be told apart by score): %d Retrosheet games and %d StatsAPI games. `matchup_model.R` keeps the first pairing of such games and `market_study.R` and `totals_study.R` drop them.", amb_ra, amb_api), "",
    if (nrow(EXC)) c("Every game outside the exact category:", "", md(EXC), "") else c("Every game is in the exact category.", ""),
    "## 3. Statcast balls in play to Retrosheet", "",
    "Matched as `statcast.R` does: date, batter and pitcher (MLBAM to Retrosheet ids through the Chadwick register) and the order of their balls in play that day. `usable` needs exit velocity and launch angle, which the expected-outcome mix requires. Agreement columns compare the two sources' scoring of the same ball.", "",
    md(SCM), "",
    sprintf("Retrosheet game dates with no Statcast rows: %s.", if (nchar(nodate_list)) nodate_list else "none"), "",
    "Batted-ball type shares by season (percent of balls in play). Retrosheet's types change definition in 2020: popups go from about 1% to 7% and fly balls from about 35% to 26%, and agreement with Statcast's types rises from about 85% to 99.8%, so Retrosheet types from 2020 on follow Statcast's classification while earlier seasons do not. Anything that pools types across that boundary (for example a mix fit on 2017-2019 and applied to 2020-2022 balls) mixes two definitions.", "",
    md(BBM), "",
    "## 4. Odds to StatsAPI games", "",
    sprintf("Joined as `market_study.R` does: odds file date, both team names (normalised, \"Oakland\" dropped) and the final score; a key that repeats on either side is dropped as ambiguous. Unmatched rows are classified by the first looser rule that finds a StatsAPI game. The odds file keys a game on the Eastern date of first pitch for %s of rows and on the UTC date for %s.",
            pct(tz_et, 1), pct(tz_utc, 1)), "",
    md(OM), "",
    "Regular-season odds names that never match a StatsAPI team name that season (rows, home or away). Each one drops that team's games from the moneyline join:", "",
    if (nrow(bad_names)) md(bad_names[, .(season, `odds name` = nm, rows)]) else "none", "",
    "StatsAPI games inside the odds date range with no matched odds row (the excluded window counts as matched here), and the teams most affected:", "",
    md(NOD), "",
    sprintf("Sportsbooks named in the moneyline and totals entries: %s.", paste(sort(books_seen), collapse = ", ")), "",
    sprintf("Fields present on a book's moneyline entry: %s. There is no timestamp on the opening or current line; `currentLine` on a finished game is the last scraped price, taken as the close.", paste(sort(line_fields), collapse = ", ")), "",
    "Line-move sanity per month (matched games, no ties): share of games whose consensus no-vig home probability moved more than 15 points from the open, and the closing log loss. In-game scrapes show as a jump in moves and a drop in log loss.", "",
    md(MV), "",
    "## 5. Duplicate keys", "",
    md(DU), "",
    "Notes: a doubleheader with the same final score in both games repeats the (date, home, away, score) key by design; Chadwick ids are many-to-one only where a row lacks the id (blank rows are excluded).", "",
    "## 6. Missingness of key fields", "",
    "Share of rows failing each rule, by season. `-` means the source has no rows that season. \"Probable is not the actual starter\" compares StatsAPI's historical probable with the pitcher credited with the start in StatsAPI's own game logs: a near-zero rate means the stored probable is the actual starter, written after the game, not a pre-game probable.", "",
    md(MS), "",
    "\"Batter hand B\" is a switch hitter: Retrosheet's plays file gives the registered hand, not the side he batted from. `matchup_build.R` maps every non-L/R hand to R, so these PAs enter the platoon splits and park factors as right-handed, although a switch hitter bats left against right-handed pitchers.", "",
    md(reg_cov), "",
    "StatsAPI player game logs against the team game logs they should sum to. Player logs are pulled only for players on the cached fullSeason rosters (`gamelogs.R`), so a pitcher missing from those rosters loses his whole season. Pitchers batting before the universal DH (2015-2019, 2021) explain most of the hitter gap in those years, because hitter logs skip roster pitchers by design.", "",
    md(PLC), "",
    "The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at \"www.retrosheet.org\".")
writeLines(L, OUT)
message("wrote ", OUT)
