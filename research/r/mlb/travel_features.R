#!/usr/bin/env Rscript
# Rest and travel v2: an exploratory second look on 2017-2022 (MATCHUP-PLAN.md, entry dated
# 2026-10-10, committed in 10a1515 before any scoring). Per-team schedule features from facts known
# before first pitch, tested against the v2 M5 base in a ridge logistic.
#
#   Rscript research/r/mlb/travel_features.R        # from the repo root
#     writes data/mlb/matchup/travel.rds (features only, no outcomes, no odds) and
#     research/r/mlb/results/travel-ablation.md
#
# Every feature uses only the team's earlier games that season, ordered by date then gid (so a
# doubleheader nightcap sees game 1 as its previous game, with 0 days and 0 miles), plus the game's
# own site and start time. No outcome enters a feature. Features are built for 2016-2025; models
# train on earlier 2016-2022 rows and are scored on 2017-2022 only. Nothing is scored on 2023-2025.
# Odds leave this script only as aggregates. No existing script or output is edited; v2 does not change.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.
# Interested parties may contact Retrosheet at "www.retrosheet.org".

suppressPackageStartupMessages({ library(data.table); library(glmnet) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R")) source(file.path(SRC, f))
PRED <- 2017:2022
OUT_RDS <- "data/mlb/matchup/travel.rds"
OUT_MD  <- file.path(SRC, "results", "travel-ablation.md")
TOL  <- 1e-9
SEED <- 20261004
PUBLISHED_OLD <- "-0.365 [-0.668, -0.090]"           # context-ablation.md, rest_travel row, 2017-2022 x 1000

F <- readRDS("data/mlb/matchup/features.rds")
G <- rbindlist(lapply(2015:2025, retro_games))
stopifnot(all(F$gid %in% G$gid))
VS <- fread("data/mlb/matchup/predictions-v2-validation.csv")   # saved v2 walk-forward predictions
message("features.rds modified ", format(file.mtime("data/mlb/matchup/features.rds")), "; games ", nrow(F))

# --- v2 base, copied from matchup_model.R (validation mode, default features, ASOF_LAG 0) -------
rv_fit <- {
  P <- outcome_matrix(rbindlist(lapply(2015:2016, retro_pa)))
  tg <- P[, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
  stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg)
}
rv <- c(stats::coef(rv_fit)[OUT8[OUT8 != "out_ip"]], out_ip = 0)
runs_of <- function(prefix, side) as.matrix(F[, paste0(prefix, "_", OUT8, "_", side), with = FALSE]) %*% rv[OUT8]
for (s in c("home", "away")) for (p in c("sp12", "sp3", "pen")) F[[paste0("r_", p, "_", s)]] <- as.numeric(runs_of(p, s))
F[, d12 := r_sp12_home - r_sp12_away][, d3 := r_sp3_home - r_sp3_away][, dpen := r_pen_home - r_pen_away]
tm <- rbind(G[, .(team = hometeam, gid, Date, season, margin = hruns - vruns, site)],
            G[, .(team = visteam, gid, Date, season, margin = vruns - hruns, site)])
bounds <- tm[, .(start = min(Date), end = max(Date)), by = season]
tm[, t := season_day(Date, season, as.data.frame(bounds))][, n := 1]
tq <- function(team) data.frame(entity = team, Date = F$Date, season = F$season, t = season_day(F$Date, F$season, as.data.frame(bounds)))
rdx <- function(team) { s <- asof_decay(transform(as.data.frame(tm), entity = team), tq(team), c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
F[, drd := rdx(hometeam) - rdx(visteam)]
# M4's two rest terms exactly as matchup_model.R builds them: by team only, across seasons
t4 <- copy(tm); setorder(t4, team, Date, gid)
t4[, `:=`(rest = pmin(as.numeric(Date - shift(Date)), 3), moved = as.numeric(site != shift(site))), by = team]
t4[is.na(rest), rest := 3][is.na(moved), moved := 0]
F <- merge(F, t4[, .(gid, hometeam = team, rest4_h = rest, moved4_h = moved)], by = c("gid", "hometeam"))
F <- merge(F, t4[, .(gid, visteam = team, rest4_a = rest, moved4_a = moved)], by = c("gid", "visteam"))
F[, drest := rest4_h - rest4_a][, dmoved := moved4_h - moved4_a]
ctx <- readRDS("data/mlb/matchup/context.rds")
F <- merge(F, ctx[, .(gid, dder)], by = "gid", all.x = TRUE); F[is.na(dder), dder := 0]

# --- site table: UTC offsets (copied from context_features.R) and coordinates -----------------
TZ <- c(ANA01 = -7, ARL02 = -5, ARL03 = -5, ATL02 = -4, ATL03 = -4, BAL12 = -4, BIR01 = -5, BOS07 = -4,
        BST01 = -4, BUF05 = -4, CHI11 = -5, CHI12 = -5, CIN09 = -4, CLE08 = -4, DEN02 = -6, DET05 = -4,
        DUN01 = -4, DYE01 = -5, FTB01 = -4, HOU03 = -5, KAN06 = -5, LON01 = 1, LOS03 = -7, MEX02 = -6,
        MIA02 = -4, MIL06 = -5, MIN04 = -5, MNT01 = -5, NYC20 = -4, NYC21 = -4, OAK01 = -7, OMA01 = -5,
        PHI13 = -4, PHO01 = -7, PIT08 = -4, SAC01 = -7, SAN02 = -7, SEA03 = -7, SEO01 = 9, SFO03 = -7,
        SJU01 = -4, STL10 = -5, STP01 = -4, TAM02 = -4, TOK01 = 9, TOR02 = -4, WAS11 = -4, WIL02 = -4)
# Sources, both fetched 2026-10-10 (no Retrosheet park list exists under data/):
#   statsapi  = MLB StatsAPI /api/v1/venues?hydrate=location, location.defaultCoordinates (venue id given)
#   wikipedia = en.wikipedia.org article coordinates (API prop=coordinates), used where StatsAPI has
#               none or puts the point outside the park (noted per row)
COORD <- fread(sep = "|", text = "site|park|city|lat|lon|src
ANA01|Angel Stadium|Anaheim CA|33.800190|-117.882400|statsapi 1
ARL02|Globe Life Park in Arlington (now Choctaw Stadium)|Arlington TX|32.751321|-97.082682|statsapi 13
ARL03|Globe Life Field|Arlington TX|32.747299|-97.081818|statsapi 5325
ATL02|Turner Field|Atlanta GA|33.735278|-84.389444|wikipedia (statsapi 16 has no coordinates)
ATL03|Truist Park (SunTrust Park)|Atlanta GA|33.890672|-84.467641|statsapi 4705
BAL12|Oriole Park at Camden Yards|Baltimore MD|39.283787|-76.621689|statsapi 2
BIR01|Rickwood Field|Birmingham AL|33.502330|-86.856356|statsapi 3949
BOS07|Fenway Park|Boston MA|42.346456|-71.097441|statsapi 3
BST01|Bristol Motor Speedway|Bristol TN|36.515600|-82.256900|wikipedia (statsapi 6130 gives 31.5156 -82.5269, in south Georgia)
BUF05|Sahlen Field|Buffalo NY|42.880772|-78.873955|statsapi 2756
CHI11|Wrigley Field|Chicago IL|41.948171|-87.655503|statsapi 17
CHI12|Guaranteed Rate Field (Rate Field)|Chicago IL|41.830000|-87.634167|statsapi 4
CIN09|Great American Ball Park|Cincinnati OH|39.097389|-84.506611|statsapi 2602
CLE08|Progressive Field|Cleveland OH|41.495861|-81.685255|statsapi 5
DEN02|Coors Field|Denver CO|39.756042|-104.994136|statsapi 19
DET05|Comerica Park|Detroit MI|42.339115|-83.048695|statsapi 2394
DUN01|TD Ballpark|Dunedin FL|28.003611|-82.786389|wikipedia (statsapi 2536 gives 27.9746 -82.7913, about 2 mi south in Clearwater)
DYE01|Field of Dreams|Dyersville IA|42.498241|-91.056486|statsapi 5445
FTB01|Fort Bragg Field|Fort Bragg NC|35.139167|-78.999167|wikipedia, Fort Bragg post centre (the field's own point not found; statsapi 5010 has none)
HOU03|Minute Maid Park (Daikin Park)|Houston TX|29.756967|-95.355509|statsapi 2392
KAN06|Kauffman Stadium|Kansas City MO|39.051567|-94.480483|statsapi 7
LON01|London Stadium|London UK|51.538600|-0.016400|wikipedia (statsapi 5381 gives the city centre 51.5085 -0.1257)
LOS03|Dodger Stadium|Los Angeles CA|34.073680|-118.240530|statsapi 22
MEX02|Estadio Alfredo Harp Helu|Mexico City MX|19.404000|-99.085500|wikipedia (statsapi 5340 has no coordinates)
MIA02|loanDepot park (Marlins Park)|Miami FL|25.777962|-80.219518|statsapi 4169
MIL06|American Family Field (Miller Park)|Milwaukee WI|43.028380|-87.970990|statsapi 32
MIN04|Target Field|Minneapolis MN|44.981829|-93.277891|statsapi 3312
MNT01|Estadio de Beisbol Monterrey (now Walmart Park)|Monterrey MX|25.718517|-100.315750|wikipedia (not in the statsapi venue list)
NYC20|Citi Field|New York NY (Queens)|40.757530|-73.845592|statsapi 3289
NYC21|Yankee Stadium|New York NY (Bronx)|40.829195|-73.926498|statsapi 3313
OAK01|Oakland Coliseum|Oakland CA|37.751511|-122.200698|statsapi 10
OMA01|TD Ameritrade Park|Omaha NE|41.258610|-95.937790|statsapi 5365
PHI13|Citizens Bank Park|Philadelphia PA|39.905391|-75.167170|statsapi 2681
PHO01|Chase Field|Phoenix AZ|33.445302|-112.066687|statsapi 15
PIT08|PNC Park|Pittsburgh PA|40.446904|-80.005753|statsapi 31
SAC01|Sutter Health Park|West Sacramento CA|38.579940|-121.512460|statsapi 2529
SAN02|Petco Park|San Diego CA|32.707861|-117.157278|statsapi 2680
SEA03|T-Mobile Park (Safeco Field)|Seattle WA|47.591333|-122.332510|statsapi 680
SEO01|Gocheok Sky Dome|Seoul KR|37.498200|126.867000|statsapi 5150
SFO03|Oracle Park (AT&T Park)|San Francisco CA|37.778383|-122.389448|statsapi 2395
SJU01|Hiram Bithorn Stadium|San Juan PR|18.416660|-66.072817|statsapi 2535
STL10|Busch Stadium|St. Louis MO|38.622567|-90.192867|statsapi 2889
STP01|Tropicana Field|St. Petersburg FL|27.767778|-82.652500|statsapi 12
TAM02|George M. Steinbrenner Field|Tampa FL|27.979970|-82.507020|statsapi 2523
TOK01|Tokyo Dome|Tokyo JP|35.705600|139.751900|statsapi 2397
TOR02|Rogers Centre|Toronto ON|43.641550|-79.389150|statsapi 14
WAS11|Nationals Park|Washington DC|38.872861|-77.007501|statsapi 3309
WIL02|Bowman Field (BB&T Ballpark, now Journey Bank Ballpark)|Williamsport PA|41.241985|-77.047510|statsapi 2735")
LAT <- setNames(COORD$lat, COORD$site); LON <- setNames(COORD$lon, COORD$site)
stopifnot(!anyDuplicated(COORD$site), setequal(COORD$site, names(TZ)), all(G$site %in% COORD$site))
hav <- function(la1, lo1, la2, lo2) { r <- pi / 180                     # great-circle miles
  a <- sin((la2 - la1) * r / 2)^2 + cos(la1 * r) * cos(la2 * r) * sin((lo2 - lo1) * r / 2)^2
  2 * 3958.8 * asin(pmin(1, sqrt(a))) }
SANITY <- data.table(a = c("NYC20", "BOS07", "NYC20", "CHI11", "ARL02", "ATL02", "OAK01", "ANA01", "STP01", "STP01", "SAC01"),
                     b = c("LOS03", "NYC21", "NYC21", "CHI12", "ARL03", "ATL03", "SFO03", "LOS03", "TAM02", "DUN01", "SFO03"),
                     lo = c(2400, 170, 0, 0, 0, 0, 0, 0, 0, 0, 50), hi = c(2500, 210, 15, 15, 2, 20, 15, 40, 30, 30, 100))
SANITY[, miles := hav(LAT[a], LON[a], LAT[b], LON[b])]
stopifnot(SANITY[, all(miles >= lo & miles <= hi)])
# longitude against the standard (non-daylight) offset: catches a sign or digit slip in either table
NODST <- c("PHO01", "SEO01", "TOK01", "SJU01", "MEX02")                 # MNT01 2018-19 and LON01 (BST) were on DST
COORD[, lon_off := lon / 15 - (TZ[site] - !(site %in% NODST))]
stopifnot(all(abs(COORD$lon_off) < 1.5))
# park names as StatsAPI's cached 2017-2019 schedule lists them for the same games (via game_pk)
sched <- rbindlist(lapply(list.files("data/mlb/raw/statsapi_schedule", full.names = TRUE),
                          function(f) as.data.table(readRDS(f))[, .(game_pk = gamePk, venue = venue.name)]), fill = TRUE)
vn <- merge(merge(G[, .(gid, site)], VS[, .(gid, game_pk)], by = "gid"), sched, by = "game_pk")[, .N, by = .(site, venue)][order(site, -N)]
COORD[, statsapi_names := vapply(site, function(s) { x <- vn[vn$site == s]; if (!nrow(x)) "" else paste(sprintf("%s (%d)", x$venue, x$N), collapse = "; ") }, "")]

# --- travel features ------------------------------------------------------------------------------
# Start hour, local clock, from Retrosheet starttime ("7:05PM"); unparseable or missing: 1:05 pm day, 7:05 pm night.
start_hour <- function(st, dn) {
  s <- toupper(gsub("[[:space:].]", "", fcoalesce(as.character(st), "")))
  m <- regmatches(s, regexec("^([0-9]{1,2}):([0-9]{2})(AM|PM|A|P)$", s))
  h <- vapply(m, function(v) { if (length(v) != 4) return(NA_real_)
    hh <- as.numeric(v[2]) %% 12 + 12 * (v[4] %in% c("PM", "P")); mm <- as.numeric(v[3])
    if (as.numeric(v[2]) > 12 || mm > 59) NA_real_ else hh + mm / 60 }, 0)
  miss <- is.na(h); h[miss] <- ifelse(dn[miss] == "day", 13 + 5 / 60, 19 + 5 / 60)
  list(h = h, n_fallback = sum(miss))
}
# Circadian lag, hours. Sign: positive = the team travelled east, so its body clock is BEHIND local
# time (Los Angeles to New York: +3, body at 4 pm for a 7 pm start); negative = travelled west, body
# AHEAD of local time. Each game day the lag first decays 1 hour per day elapsed toward zero, then adds
# the time-zone change from the previous game (Song, Severini and Allada 2017). Starts at 0 each season.
circ <- function(tzd, gap) { lag <- numeric(length(tzd))
  for (i in seq_along(tzd)[-1]) { l <- lag[i - 1]; lag[i] <- sign(l) * max(0, abs(l) - gap[i]) + tzd[i] }
  lag }
stopifnot(isTRUE(all.equal(circ(c(NA, 0, 3, 0, 0, -3), c(NA, 1, 1, 1, 0, 1)), c(0, 0, 3, 2, 2, -2))))   # west coast, east 3, decay, nightcap, back west
wrap <- function(x) x - 24 * round(x / 24)            # a clock change is at most 12 h: Tokyo to Seattle is 8 h east, not 16 h west
before <- function(d, w) findInterval(as.numeric(d) - w, as.numeric(d), left.open = TRUE)   # rows dated before d - w (d sorted)
win_sum <- function(d, x, w) { cs <- cumsum(x); cs - c(0, cs)[before(d, w) + 1] }           # this row plus earlier rows dated d - w or later
stopifnot(identical(seq_len(4) - before(as.Date(c(1, 2, 2, 10)), 7) - 1, c(0, 1, 2, 0)), win_sum(c(1, 2, 2, 10), c(5, 1, 0, 2), 7) == c(5, 6, 6, 2))
streak_of <- function(d) { u <- unique(d); r <- rep(1L, length(u))   # consecutive game days ending the day before
  for (j in seq_along(u)[-1]) if (as.numeric(u[j] - u[j - 1]) == 1) r[j] <- r[j - 1] + 1L
  k <- match(d - 1, u); fifelse(is.na(k), 0L, r[k]) }
dhprev_of <- function(d) { u <- unique(d); n <- tabulate(match(d, u)); k <- match(d - 1, u); as.numeric(!is.na(k) & n[k] >= 2) }
coors_of <- function(d, s) { cd <- as.numeric(d[s == "DEN02"])
  as.numeric(s != "DEN02" & vapply(as.numeric(d), function(x) any(cd >= x - 3 & cd < x), TRUE)) }

tr <- rbind(G[, .(team = hometeam, home = 1L, gid, Date, season, site, number, daynight, starttime)],
            G[, .(team = visteam, home = 0L, gid, Date, season, site, number, daynight, starttime)])
setorder(tr, team, Date, gid)                            # gid suffix 1 < 2 orders doubleheaders
DH_MISORDER <- tr[, .(bad = .N > 1 && is.unsorted(number)), by = .(team, Date)][, sum(bad)]
sh <- start_hour(tr$starttime, tr$daynight); tr[, hr := sh$h]
tr[, `:=`(tz = TZ[site], lat = LAT[site], lon = LON[site])]
tr[, `:=`(gap = as.numeric(Date - shift(Date)), psite = shift(site), tzd = tz - shift(tz),
          pnight = shift(daynight) == "night"), by = .(team, season)]
tr[, leg := fifelse(is.na(psite), 0, hav(LAT[psite], LON[psite], lat, lon))]
# the old five terms, exactly as context_features.R defines them (parity check only)
tr[, `:=`(o_rest = pmin(fcoalesce(gap, 3), 3), o_moved = fcoalesce(as.numeric(site != psite), 0),
          o_east = pmax(fcoalesce(tzd, 0), 0), o_west = pmax(-fcoalesce(tzd, 0), 0),
          dgan = as.numeric(daynight == "day" & fcoalesce(pnight, FALSE) & fcoalesce(gap, 0) == 1))]
tr[, `:=`(rest = o_rest, mi_prev = pmin(leg / 1000, 3))]
tr[, lag := circ(fcoalesce(wrap(tzd), 0), fcoalesce(gap, 0)), by = .(team, season)]
tr[, `:=`(lag_east = pmax(lag, 0), lag_west = pmax(-lag, 0), body = hr - lag)]   # body clock: local start minus remaining lag
tr[, `:=`(early = pmax(0, 13 - body), late = pmax(0, body - 22))]
tr[, `:=`(mi7 = pmin(win_sum(Date, leg, 7) / 1000, 6), g7 = seq_len(.N) - before(Date, 7) - 1,
          streak = streak_of(Date), dhprev = dhprev_of(Date), stand = pmin(rowid(rleid(home)), 10),
          coors = coors_of(Date, site)), by = .(team, season)]
# one known trip: the first 2017 move from Dodger Stadium to an Eastern park
ti <- tr[season == 2017 & psite == "LOS03" & tzd == 3, which = TRUE][1]
TRIP <- tr[(ti - 1):(ti + 2)][team == tr$team[ti], .(team, Date, site, tz, gap, lag, hr, body)]
stopifnot(tr$lag_east[ti] > 0, tr$lag_west[ti] == 0, tr$body[ti] < tr$hr[ti])

FAM <- list(rest = "rest", distance = c("mi_prev", "mi7"), circadian = c("lag_east", "lag_west"), start_clock = c("early", "late"),
            load = c("g7", "streak"), dgan = "dgan", dh_prev = "dhprev", stand = "stand", coors = "coors")
FEAT <- unlist(FAM, use.names = FALSE)
sides <- function(x) c(rbind(paste0(x, "_h"), paste0(x, "_a")))
TRAV <- sides(FEAT)
side <- function(sfx, col) setnames(tr[, c("gid", "team", FEAT), with = FALSE], c("team", FEAT), c(col, paste0(FEAT, sfx)))
TRV <- merge(merge(G[season >= 2016, .(gid, Date, season, hometeam, visteam, site)], side("_h", "hometeam"), by = c("gid", "hometeam")),
             side("_a", "visteam"), by = c("gid", "visteam"))
stopifnot(nrow(TRV) == nrow(G[season >= 2016]), !anyNA(TRV[, ..TRAV]), !anyDuplicated(TRV$gid))
setorder(TRV, Date, gid)
saveRDS(TRV[, c("gid", "Date", "season", "hometeam", "visteam", "site", TRAV), with = FALSE], OUT_RDS)
message("wrote ", OUT_RDS, ": ", nrow(TRV), " games")

old <- c("o_rest", "o_moved", "o_east", "o_west", "dgan")
oside <- function(sfx, col) setnames(tr[, c("gid", "team", old), with = FALSE], c("team", old), c(col, paste0(old, sfx)))
OC <- merge(merge(ctx[, .(gid, hometeam, visteam, drest, dmoved, deast, dwest, ddgan)], oside("_h", "hometeam"), by = c("gid", "hometeam")),
            oside("_a", "visteam"), by = c("gid", "visteam"))
OC[, `:=`(odrest = o_rest_h - o_rest_a, odmoved = o_moved_h - o_moved_a, odeast = o_east_h - o_east_a, odwest = o_west_h - o_west_a, oddgan = dgan_h - dgan_a)]
C1 <- OC[, max(abs(c(odrest - drest, odmoved - dmoved, odeast - deast, odwest - dwest, oddgan - ddgan)))]
if (nrow(OC) != nrow(ctx) || !(C1 < TOL)) stop("old five rest terms do not reproduce context.rds: ", nrow(OC), " of ", nrow(ctx), " games, max diff ", C1)
F <- merge(F, OC[, .(gid, odrest, odmoved, odeast, odwest, oddgan)], by = "gid")
F <- merge(F, TRV[, c("gid", TRAV), with = FALSE], by = "gid")

# --- models: 2016-2022 rows only ---------------------------------------------------------------
F[, y := as.integer(hruns > vruns)]
F <- F[season <= max(PRED) & hruns != vruns]             # 2023-2025 leave here and are never seen again
setorder(F, Date, gid)
stopifnot(max(F$Date) < as.Date("2023-01-01"))
walk <- function(df, formula, seasons) {                 # copied from matchup_model.R (ASOF_LAG 0)
  df$block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% seasons]))) {
    i <- which(df$block == b & df$season %in% seasons)
    m <- stats::glm(formula, stats::binomial, df[df$Date < b, ])
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}
foldid_of <- function(d) { wk <- as.Date(cut(d, "week")); weeks <- sort(unique(wk))     # 10 folds by calendar week
  set.seed(SEED); fw <- sample(rep_len(1:10, length(weeks))); fw[match(wk, weeks)] }
ridge_walk <- function(df, base, feats, seasons) {      # same weekly walk, ridge with the base unpenalised
  X <- as.matrix(df[, c(base, feats), with = FALSE]); pf <- c(rep(0, length(base)), rep(1, length(feats)))
  block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df)); lam <- edge <- c()
  for (b in sort(unique(block[df$season %in% seasons]))) {
    i <- which(block == b & df$season %in% seasons); k <- which(df$Date < b)
    cv <- cv.glmnet(X[k, ], df$y[k], family = "binomial", alpha = 0, penalty.factor = pf, standardize = TRUE, foldid = foldid_of(df$Date[k]))
    p[i] <- as.numeric(stats::predict(cv, X[i, , drop = FALSE], s = "lambda.min", type = "response"))
    lam <- c(lam, cv$lambda.min); edge <- c(edge, cv$lambda.min == max(cv$lambda))
  }
  list(p = p, lam = lam, edge = edge)
}
BASE4 <- c("d12", "d3", "dpen", "drd")
BASE  <- c(BASE4, "dder")
F[, p_base := walk(F, stats::reformulate(BASE, "y"), PRED)]
F[, p_m4 := walk(F, y ~ d12 + d3 + dpen + drd + drest + dmoved, PRED)]
F[, p_m3 := walk(F, stats::reformulate(BASE4, "y"), PRED)]
F[, p_m3old := walk(F, stats::reformulate(c(BASE4, "odrest", "odmoved", "odeast", "odwest", "oddgan"), "y"), PRED)]
S <- F[season %in% PRED]
stopifnot(max(S$Date) < as.Date("2023-01-01"), !anyNA(S$p_base))
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(SEED)   # copied from matchup_model.R
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
ci3 <- function(g) sprintf("%s [%s, %s]", fmt(1000 * g[1], 3), fmt(1000 * g[2], 3), fmt(1000 * g[3], 3))
CL <- paste(S$hometeam, S$season)

# --- parity: stop unless the saved v2 predictions are reproduced ---------------------------------
ref <- merge(S[, .(gid, p_base, p_m4, p_m3)], VS[, .(gid, M5_plus_defense, M4_plus_rest, M3_plus_team)], by = "gid")
PA <- ref[, max(abs(p_base - M5_plus_defense))]; PB <- ref[, max(abs(p_m4 - M4_plus_rest))]; P3 <- ref[, max(abs(p_m3 - M3_plus_team))]
if (nrow(ref) != nrow(VS) || nrow(ref) != nrow(S)) stop("row sets differ: ", nrow(S), " scored, ", nrow(VS), " saved, ", nrow(ref), " matched")
if (!(PA < TOL)) stop("rebuilt base does not reproduce M5_plus_defense: max diff ", PA)
if (!(PB < TOL)) stop("rebuilt M4 does not reproduce M4_plus_rest: max diff ", PB)
G_OLD <- paired(ll(S$p_m3, S$y) - ll(S$p_m3old, S$y), CL)
if (ci3(G_OLD) != PUBLISHED_OLD) stop("old five-term gain ", ci3(G_OLD), " does not reproduce the published ", PUBLISHED_OLD)
message(sprintf("parity: M5 %.1e, M4 %.1e on %d games; old terms %s", PA, PB, nrow(ref), ci3(G_OLD)))

# --- primary: base plus every travel feature, ridge ----------------------------------------------
R <- ridge_walk(F, BASE, TRAV, PRED)
F[, p_ridge := R$p]
# --- descriptive: unpenalised glm with every feature, and each family alone -------------------
F[, p_glm := walk(F, stats::reformulate(c(BASE, TRAV), "y"), PRED)]
for (nm in names(FAM)) F[[paste0("p_fam_", nm)]] <- walk(F, stats::reformulate(c(BASE, sides(FAM[[nm]])), "y"), PRED)
S <- F[season %in% PRED]
stopifnot(max(S$Date) < as.Date("2023-01-01"), !anyNA(S[, .(p_ridge, p_glm)]))
VARS <- c(primary_ridge = "p_ridge", glm_all = "p_glm", setNames(paste0("p_fam_", names(FAM)), paste0("glm_", names(FAM))))
GT <- rbindlist(lapply(names(VARS), function(v) {
  d <- ll(S$p_base, S$y) - ll(S[[VARS[[v]]]], S$y)       # positive = the variant is better
  c(list(variant = v), setNames(as.list(paired(d, CL)), c("d", "lo", "hi")),
    setNames(lapply(PRED, function(s) mean(d[S$season == s])), paste0("s", PRED)))
}))
PRIM <- GT[variant == "primary_ridge"]
KEEP <- PRIM$lo > 0

# --- descriptive: does the 2021-2022 close already price travel? -----------------------------------
mk <- fread("data/mlb/raw/odds/market-joined.csv")[, Date := as.Date(Date)]
dm <- mk[!is.na(p_open) & !is.na(p_close), .(games = .N, move = mean(abs(p_close - p_open))), by = .(season, Date)]
dm[, ratio := move / median(move), by = season]
BAD <- dm[games >= 5 & ratio > 3][order(Date)]$Date       # close_timing.R's registered flag rule
M <- merge(merge(S[season %in% 2021:2022, c("gid", "Date", "season", "hometeam", "y", TRAV), with = FALSE], VS[, .(gid, game_pk)], by = "gid"),
           mk[, .(game_pk, p_close)], by = "game_pk")
M <- M[!is.na(p_close)]; N_JOIN <- nrow(M)
M <- M[!(Date >= as.Date("2021-09-01") & Date <= as.Date("2021-12-31"))]; N_SEPOCT <- N_JOIN - nrow(M)
N_FLAG <- M[Date %in% BAD, .N]; M <- M[!Date %in% BAD]
M[, lc := stats::qlogis(pmin(pmax(p_close, 1e-6), 1 - 1e-6))]
XF <- rbindlist(lapply(2021:2022, function(s) {          # fit on the other season, score this one
  trn <- M[season != s]; tst <- M[season == s]
  p0 <- stats::predict(stats::glm(y ~ lc, stats::binomial, trn), tst, type = "response")
  cv <- cv.glmnet(as.matrix(trn[, c("lc", TRAV), with = FALSE]), trn$y, family = "binomial", alpha = 0,
                  penalty.factor = c(0, rep(1, length(TRAV))), standardize = TRUE, foldid = foldid_of(trn$Date))
  p1 <- as.numeric(stats::predict(cv, as.matrix(tst[, c("lc", TRAV), with = FALSE]), s = "lambda.min", type = "response"))
  data.table(season = s, hometeam = tst$hometeam, y = tst$y, p0 = as.numeric(p0), p1 = p1, edge = cv$lambda.min == max(cv$lambda))
}))
G_MKT <- paired(ll(XF$p0, XF$y) - ll(XF$p1, XF$y), paste(XF$hometeam, XF$season))
MKT_SEAS <- XF[, .(n = .N, close = mean(ll(p0, y)), plus = mean(ll(p1, y)), edge = edge[1]), by = season]

# --- glm coefficients, every feature, every 2016-2022 game (sign only) ---------------------------
CF <- summary(stats::glm(stats::reformulate(c(BASE, TRAV), "y"), stats::binomial, F))$coefficients
CF_DROP <- setdiff(TRAV, rownames(CF)); CF <- CF[intersect(TRAV, rownames(CF)), , drop = FALSE]   # aliased terms have no row

# --- report ---------------------------------------------------------------------------------------
row <- function(...) paste0("| ", paste(..., sep = " | "), " |")
FS <- rbindlist(lapply(FEAT, function(f) { x <- c(S[[paste0(f, "_h")]], S[[paste0(f, "_a")]])
  data.table(feature = f, mean = mean(x), share_nonzero = mean(x != 0), max = max(x)) }))
gline <- function(k) row(GT$variant[k], ci3(unlist(GT[k, .(d, lo, hi)])), paste(fmt(1000 * unlist(GT[k, paste0("s", PRED), with = FALSE]), 3), collapse = " | "))
L <- c("# Rest and travel v2: exploratory second look, 2017-2022", "",
  sprintf("Generated %s by research/r/mlb/travel_features.R, under the MATCHUP-PLAN.md entry of 2026-10-10 (committed in 10a1515 before any scoring).", format(Sys.Date())),
  sprintf("Features for every 2016-2025 game are in %s (features only). Models train on earlier 2016-2022 rows and are scored on 2017-2022; nothing was scored on 2023-2025.", OUT_RDS),
  "These rows already rejected the five-term rest and travel group, so a pass here is weaker evidence than a first look; a pass only makes the features a candidate for a pre-registered 2027 test. v2 does not change.", "",
  "## Method", "",
  "Base: the v2 M5 formula y ~ d12 + d3 + dpen + drd + dder, rebuilt as matchup_model.R builds it, in its weekly walk-forward (refit each Monday on every earlier game, predict that week).",
  sprintf("Primary test, the only one that can keep anything: base plus all %d travel columns (home and away separately) in a ridge logistic (glmnet %s, alpha 0, base terms unpenalised, standardize TRUE), lambda.min by 10-fold cross-validation on the earlier games only, folds assigned by calendar week, set.seed(%d) before each fold draw, refit in the same weekly walk.",
          length(TRAV), as.character(utils::packageVersion("glmnet")), SEED),
  "Paired gain = base log loss minus variant log loss per game (positive = the variant is better), pooled over 2017-2022, with a 95% interval from 1000 cluster-bootstrap draws of home team-seasons (seed 20261004).",
  "Keep rule: the primary interval must sit above zero.", "",
  "## Parity", "",
  sprintf("- Rebuilt base vs saved v2 M5_plus_defense: %d of %d games matched, max absolute difference %s (tolerance 1e-9).", nrow(ref), nrow(VS), formatC(PA, format = "e", digits = 1)),
  sprintf("- M3 plus matchup_model.R's two rest terms (drest, dmoved, built by team across seasons) vs saved M4_plus_rest: max absolute difference %s.", formatC(PB, format = "e", digits = 1)),
  sprintf("- The five old rest terms rebuilt here with context_features.R's definitions equal context.rds on all %d games (max difference %s); M3 plus those five terms gives %s x 1000 against M3, the published context-ablation figure is %s.",
          nrow(OC), formatC(C1, format = "e", digits = 1), ci3(G_OLD), PUBLISHED_OLD),
  sprintf("- (For reference, M3 vs saved M3_plus_team: max difference %s.)", formatC(P3, format = "e", digits = 1)),
  "- Deviation: the registration asks the old five rest terms to reproduce M4_plus_rest, but M4_plus_rest holds only two of them (drest, dmoved), built across seasons. The check is therefore split: M4 is reproduced with its own two terms, and the five terms are reproduced against context.rds and the published five-term result. The script stops if any of these fails.", "",
  "## Features", "",
  "Per team, from that season's earlier games (ordered by date, then gid) plus the game's own site and start time. Home and away columns enter separately.", "",
  "| family | columns (each _h and _a) | definition |", "| --- | --- | --- |",
  "| rest | rest | Days since the previous game, capped at 3; 3 at the season opener, 0 in a doubleheader nightcap. |",
  "| distance | mi_prev, mi7 | Great-circle miles from the previous game's site (0 at the opener and in a nightcap), in thousands, capped at 3; and miles summed over the legs into today's game and every earlier game dated in the previous 7 days, in thousands, capped at 6. |",
  "| circadian | lag_east, lag_west | Remaining circadian lag in hours. Each game day the previous lag shrinks 1 hour per day elapsed toward zero, then the time-zone change from the previous game's site is added (48-site UTC table). Positive = travelled east (body clock behind local time), split into east = max(lag, 0) and west = max(-lag, 0). Zero at each season opener. |",
  "| start_clock | early, late | Body-clock start hour = local start hour minus the remaining lag (an eastward-lagged team feels the game earlier). early = hours before 1 pm, late = hours after 10 pm, both on the body clock. |",
  "| load | g7, streak | Earlier games dated in the previous 7 days (a nightcap counts game 1); consecutive calendar days with a game ending the day before. |",
  "| dgan | dgan | Day game after a night game the previous day (as context_features.R). |",
  "| dh_prev | dhprev | Played a doubleheader the previous day. |",
  "| stand | stand | Games into the current home stand (home team) or road trip (away team), counting today, capped at 10, by Retrosheet's home designation. |",
  "| coors | coors | Played at Coors Field (DEN02) in the previous 3 days and not there today. |", "",
  sprintf("Start times: Retrosheet's starttime, local clock, parsed on %d team-games with %d fallbacks (1:05 pm day, 7:05 pm night). This field records actual first pitch, not the schedule: %d games began at or after 10 pm local, after delays. No schedule time exists locally for 2020-2022, so actual first pitch stands in for the scheduled start (a deviation from the registration's wording).",
          nrow(tr), sh$n_fallback, G[season %in% 2016:2022, sum(sh$h[match(gid, tr$gid)] >= 22)]),
  "Time-zone changes are wrapped to at most 12 hours, so Tokyo to Seattle counts as 8 hours east, not 16 west; inside 2017-2022 this touches only the 2019 Tokyo series (Seattle and Oakland). The old context terms keep the raw difference.",
  sprintf("Doubleheader ordering: %d same-day team pairs where gid order and Retrosheet game number disagree.", DH_MISORDER),
  sprintf("Sign check on a known trip: %s.", paste(sprintf("%s %s at %s (UTC%+d, %s day gap) lag %s, start %s local / %s body", TRIP$team, format(TRIP$Date), TRIP$site, TRIP$tz,
          ifelse(is.na(TRIP$gap), "no", as.character(TRIP$gap)), fmt(TRIP$lag, 1), fmt(TRIP$hr, 2), fmt(TRIP$body, 2)), collapse = "; ")), "",
  "Feature summary over 2017-2022 scored games (home and away pooled):", "",
  "| feature | mean | share nonzero | max |", "| --- | --- | --- | --- |",
  sprintf("| %s | %s | %s | %s |", FS$feature, fmt(FS$mean, 3), fmt(FS$share_nonzero, 3), fmt(FS$max, 3)), "",
  "## Coordinates", "",
  sprintf("%d sites (every site in the UTC table and every Retrosheet site 2015-2025): %d from MLB StatsAPI venue records, %d from Wikipedia where StatsAPI has none or misplaces the park. No Retrosheet park list exists under data/; park names were checked against StatsAPI's cached 2017-2019 schedule for the same games.",
          nrow(COORD), sum(grepl("^statsapi", COORD$src)), sum(grepl("^wikipedia", COORD$src))),
  sprintf("Checks (all pass, else the script stops): %s miles.", paste(sprintf("%s-%s %s", SANITY$a, SANITY$b, formatC(SANITY$miles, format = "f", digits = 0, big.mark = ",")), collapse = "; ")),
  sprintf("Longitude / 15 against each site's standard UTC offset: largest gap %s hours (limit 1.5).", fmt(max(abs(COORD$lon_off)), 2)),
  "Fort Bragg (FTB01, one 2016 game) uses the post's centre, so its legs may be off by a few miles. One DET05 game appears at Oakland Coliseum in StatsAPI's schedule; the Retrosheet site is kept.", "",
  "| site | park | city | lat | lon | source | StatsAPI 2017-2019 name (games) |", "| --- | --- | --- | --- | --- | --- | --- |",
  sprintf("| %s | %s | %s | %s | %s | %s | %s |", COORD$site, COORD$park, COORD$city, fmt(COORD$lat, 4), fmt(COORD$lon, 4), COORD$src, COORD$statsapi_names), "",
  "## Primary result", "",
  sprintf("Ridge (base plus all travel features) minus base, 2017-2022 pooled over %d games: %s x 1000.", nrow(S), ci3(unlist(PRIM[, .(d, lo, hi)]))),
  sprintf("By season (x 1000): %s.", paste(sprintf("%d %s", PRED, fmt(1000 * unlist(PRIM[, paste0("s", PRED), with = FALSE]), 3)), collapse = "; ")),
  sprintf("lambda.min over %d weekly fits: median %s, range %s to %s; at the largest lambda on the path (travel terms shrunk to almost nothing) in %d.",
          length(R$lam), formatC(stats::median(R$lam), format = "g", digits = 3), formatC(min(R$lam), format = "g", digits = 3), formatC(max(R$lam), format = "g", digits = 3), sum(R$edge)),
  "", sprintf("Verdict: %s", if (KEEP) "the interval sits above zero. The travel features become a candidate for a pre-registered 2027 test only; v2 does not change." else
    "the interval does not sit above zero. Nothing is kept; v2 does not change."), "",
  "## Descriptive only (never a keep)", "",
  "Paired gain against the same base, x 1000, 2017-2022 pooled with the same bootstrap, then by season.", "",
  row("variant", "2017-2022 [95% CI]", paste(PRED, collapse = " | ")), paste0("|", strrep(" --- |", length(PRED) + 2)),
  vapply(seq_len(nrow(GT)), gline, ""), "",
  "primary_ridge repeats the primary row for comparison. glm_all is every travel column in an unpenalised glm; glm_<family> is the base plus that family alone.", "",
  sprintf("Market check, 2021-2022: no-vig close (corrected odds join, as close_timing.R) recalibrated alone, y ~ logit(close), against the close logit (unpenalised) plus every travel column in a ridge with the primary's recipe; cross-fit by season (fit on one season, score the other). %d joined games, %d in Sept-Oct 2021 and %d on the %d flagged late-close dates removed, %d scored.",
          N_JOIN, N_SEPOCT, N_FLAG, length(BAD), nrow(XF)),
  sprintf("Close alone minus close plus travel: %s x 1000 (positive = travel adds to the close). By season: %s.", ci3(G_MKT),
          paste(MKT_SEAS[, sprintf("%d: %s games, log loss %s alone vs %s with travel%s", season, n, fmt(close), fmt(plus), ifelse(edge, ", lambda at the path's top", ""))], collapse = "; ")),
  "The estimator for this check (ridge with the close unpenalised, compared with a close-only logistic) is this script's reading of the registration, which names the inputs but not the model.", "",
  "## glm coefficient signs (every travel column plus the base, fit on every 2016-2022 game; descriptive)", "",
  "| term | coef | z | sign |", "| --- | --- | --- | --- |",
  sprintf("| %s | %s | %s | %s |", rownames(CF), fmt(CF[, 1]), fmt(CF[, 3], 2), ifelse(CF[, 1] > 0, "+", "-")),
  if (length(CF_DROP)) sprintf("Aliased, no coefficient: %s.", paste(CF_DROP, collapse = ", ")), "",
  "Venue coordinates: MLB StatsAPI (copyright MLB Advanced Media, L.P., private research use) and Wikipedia.",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(L, OUT_MD)
message("wrote ", OUT_MD)
