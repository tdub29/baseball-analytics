#!/usr/bin/env Rscript
# Build per-game matchup features for 2016-2025 from Retrosheet plate appearances.
#
#   Rscript research/r/mlb/matchup_build.R            # writes data/mlb/matchup/features.rds
#   FORWARD=1 FEAT_OUT=data/mlb/matchup/features-forward.rds Rscript research/r/mlb/matchup_build.R
#
# FORWARD=1 (FORWARD-PLAN.md) adds the 2026 season from MLB StatsAPI (statsapi_pa.R, parity-checked
# on 2025) after Retrosheet 2015-2025, so 2026 games get features; every input stays as of the game.
# Per side of each game: expected outcome counts against the starter (first and second time
# through the order, then third and later), against the bullpen, and the starter's expected
# batters faced. Every input is as of the start of the game's date (events through the day
# before); ASOF_LAG = 1 moves every as-of query back one day, so inputs stop two days before.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R", "statcast.R")) source(file.path(SRC, f))
HIT_X <- as.numeric(Sys.getenv("HIT_X", "0"))     # weight on Statcast expected outcomes for hitters (0 = actual)
PIT_SC <- Sys.getenv("PIT_SC", "0") == "1"        # Statcast exit velocity and launch angle for pitchers; off: lost the v3 ablation
FEAT_OUT <- Sys.getenv("FEAT_OUT", "data/mlb/matchup/features.rds")
LINEUP_MODE <- Sys.getenv("LINEUP_MODE", "posted")   # "projected": day-ahead, from the team's last game vs a same-hand starter
STARTER_MODE <- Sys.getenv("STARTER_MODE", "actual") # "rotation": starter guessed from the team's starts two days out
ASOF_LAG <- as.integer(Sys.getenv("ASOF_LAG", "0"))  # 1: every as-of input uses events through two days before the game
stopifnot(STARTER_MODE %in% c("actual", "rotation"), ASOF_LAG %in% 0:1)
SWITCH <- Sys.getenv("SWITCH", "0") == "1"         # 1: switch hitters bat opposite each pitcher's hand (v2 counts them as right-handed)
BB_REGIME <- Sys.getenv("BB_REGIME", "0") == "1"   # 1: batted-ball expected-outcome mix within one Retrosheet coding regime
FORWARD <- Sys.getenv("FORWARD", "0") == "1"      # 1: add 2026 from StatsAPI; needs its own FEAT_OUT
if (FORWARD && FEAT_OUT == "data/mlb/matchup/features.rds") stop("FORWARD=1 needs its own FEAT_OUT: features.rds is the frozen v2 file")
K_GRID <- Sys.getenv("K_GRID", "")                 # CSV of k_cfg() multipliers (id, m_pit, m_bat, m_rel_bb): one extra features file per row
K_SPLIT_BAT <- 600; K_SPLIT_PIT <- 600; TEAM_PA <- 38.3
dir.create("data/mlb/matchup", showWarnings = FALSE, recursive = TRUE)

P <- rbindlist(lapply(2015:2025, retro_pa))
G <- rbindlist(lapply(2015:2025, retro_games))
if (FORWARD) {                                     # same columns and coding as retro_pa() and retro_games()
  for (f in c("gamelogs.R", "statsapi_pa.R")) source(file.path(SRC, f))   # gamelogs.R: retry()
  P <- rbind(P, statsapi_pa(2026)); G <- rbind(G, statsapi_games(2026))
}
bounds <- P[, .(start = min(Date), end = max(Date)), by = season]
P[, t := season_day(Date, season, as.data.frame(bounds))]
P <- outcome_matrix(P)
P[, pithand := ifelse(pithand %in% c("L", "R"), pithand, "R")]
# Retrosheet's bathand is the roster hand, "B" for switch hitters (10 to 13% of plate appearances).
# SWITCH=1 gives every switch-hitter PA the side he bats from, opposite the pitcher; v2 counts "R".
P[, sw := SWITCH & bathand %in% "B"]
P[, bathand := ifelse(sw, ifelse(pithand == "L", "R", "L"), ifelse(bathand %in% c("L", "R"), bathand, "R"))]
P[, plat := bathand != pithand]                    # platoon advantage, the league prior of a switch hitter
PF <- park_table(P)
Pn <- park_neutral(P, PF)
# Pitchers are judged on expected outcomes of their batted balls (the xFIP/SIERA idea): each ball in
# play is replaced by the league outcome mix for its type (ground ball, fly, liner, popup) over the
# prior three seasons, so hit and home-run luck stays out of a pitcher's rates. Hitters keep actual.
BIP <- c("single", "double", "triple", "hr", "out_ip")
bbd <- P[!is.na(bb_type) & outcome %in% BIP, .N, by = .(season, bb_type, outcome)]
# Retrosheet's batted-ball coding changed twice: 2015-2019 (liners about 0.20 of balls in play, 1%
# of them home runs), 2020 alone (liners 0.29, 8.8% home runs, fly balls 0.21) and 2021 on (liners
# 0.24, about 1.5%, fly balls 0.26). BB_REGIME=1 builds a season's mix only from earlier seasons of
# its own regime (up to three); a regime's first season (REG0) uses its own earlier days instead, as
# of each date, with the prior three seasons' mix as a REG0_M-ball prior per type for the first days.
REG0 <- if (BB_REGIME) c(2020L, 2021L) else integer(0); REG0_M <- 100
xmix <- rbindlist(lapply(sort(unique(P$season)), function(S) {
  r0 <- max(c(min(P$season), REG0[REG0 <= S]))
  src <- bbd[season %in% if (S == min(P$season)) S else if (S %in% REG0) (S - 3):(S - 1) else max(r0, S - 3):(S - 1)]
  m <- dcast(src[, .(N = sum(N)), by = .(bb_type, outcome)], bb_type ~ outcome, value.var = "N", fill = 0)
  m[, tot := rowSums(.SD), .SDcols = BIP]
  for (o in BIP) m[[paste0("x_", o)]] <- m[[o]] / m$tot
  cbind(season = S, m[, c("bb_type", paste0("x_", BIP)), with = FALSE])
}))
Px <- merge(P, xmix, by = c("season", "bb_type"), all.x = TRUE, sort = FALSE)
if (length(REG0)) {
  day <- unique(P[season %in% REG0, .(season, Date)])[, .(bb_type = unique(bbd$bb_type)), by = .(season, Date)]
  cnt <- dcast(P[season %in% REG0 & !is.na(bb_type) & outcome %in% BIP, .N, by = .(season, Date, bb_type, outcome)],
               season + Date + bb_type ~ outcome, value.var = "N", fill = 0)
  cnt <- merge(day, cnt, by = c("season", "Date", "bb_type"), all.x = TRUE)
  for (o in BIP) cnt[is.na(get(o)), (o) := 0]
  setorder(cnt, season, bb_type, Date)
  cnt[, (BIP) := lapply(.SD, function(v) cumsum(v) - v), by = .(season, bb_type), .SDcols = BIP]   # earlier days only
  cnt <- merge(cnt, xmix, by = c("season", "bb_type"))
  tot <- rowSums(cnt[, BIP, with = FALSE])
  for (o in BIP) cnt[[paste0("x_", o)]] <- (cnt[[o]] + REG0_M * cnt[[paste0("x_", o)]]) / (tot + REG0_M)
  Px[cnt, on = .(season, Date, bb_type), (paste0("x_", BIP)) := mget(paste0("i.x_", BIP))]
  message("regime-start mixes as of each season's last day, home-run share by type:\n",
          paste(capture.output(print(cnt[, .SD[Date == max(Date)], by = season][, .(season, bb_type, x_hr = round(x_hr, 3))])), collapse = "\n"))
}
has <- !is.na(Px$x_single) & Px$outcome %in% BIP
for (o in BIP) Px[[o]][has] <- Px[[paste0("x_", o)]][has]
Px[, paste0("x_", BIP) := NULL]
# Where Statcast tracked the ball, exit velocity and launch angle replace the batted-ball type.
SX <- NULL
if ((PIT_SC || HIT_X > 0) && length(list.files(SC_DIR, "^bip_"))) {
  reg <- data.table::as.data.table(readRDS(list.files("data/mlb/raw/chadwick", full.names = TRUE)[1]))
  SX <- statcast_expected(P, reg)
  message("statcast matched balls in play: ", nrow(SX), " of ", sum(P$outcome %in% BIP & !is.na(P$bb_type)))
}
if (PIT_SC && !is.null(SX)) {
  Px <- merge(Px, SX, by = c("gid", "seq"), all.x = TRUE, sort = FALSE)
  hs <- !is.na(Px$sx_single)
  for (o in BIP) Px[[o]][hs] <- Px[[paste0("sx_", o)]][hs]
  Px[, paste0("sx_", BIP) := NULL]
}
Pxn <- park_neutral(Px, PF)
# Hitters: actual outcomes, or a blend with their own Statcast expected outcomes (HIT_X).
Ph <- P
if (HIT_X > 0 && !is.null(SX)) {
  Ph <- merge(P, SX, by = c("gid", "seq"), all.x = TRUE, sort = FALSE)
  hs <- !is.na(Ph$sx_single)
  for (o in BIP) Ph[[o]][hs] <- HIT_X * Ph[[paste0("sx_", o)]][hs] + (1 - HIT_X) * Ph[[o]][hs]
  Ph[, paste0("sx_", BIP) := NULL]
}
Phn <- park_neutral(Ph, PF)
message("plate appearances: ", nrow(P))

# --- who started: first nine batters and first pitcher for each side of each game ----------
first <- P[order(gid, seq)]
lineup <- first[, .SD[!duplicated(batter)][1:9], by = .(gid, batteam), .SDcols = c("batter", "bathand", "seq", "sw")]
lineup[, slot := seq_len(.N), by = .(gid, batteam)]
sp <- first[, .(sp = pitcher[1], sp_hand = pithand[1]), by = .(gid, pitteam)]   # who actually started each past game
# The starter each lineup faces (sp_tgt). STARTER_MODE "actual": the first pitcher in the Retrosheet
# play-by-play, i.e. who really started; that is known for sure only at first pitch, and no archived
# pre-game probables exist locally (cached StatsAPI probables were updated after the games).
# "rotation": a guess from the team's starts known two days before the game (rotation_starters() in
# matchup.R), whose rates, expected batters faced and times-through-the-order split replace the
# actual starter's everywhere below. Past games' starters (sp) stay actual: they were known then.
sp_tgt <- sp
if (STARTER_MODE == "rotation") {
  st <- merge(sp, G[, .(gid, Date, season)], by = "gid")
  st[, team := sub("^ATH$", "OAK", pitteam)]            # one franchise code across 2024-2025
  rot <- rotation_starters(st, known = 1 + max(1, ASOF_LAG))
  sp_tgt <- merge(st[, .(gid, team, pitteam)], rot, by = c("gid", "team"))[, .(gid, pitteam, sp, sp_hand)]
  hit <- merge(sp_tgt, st[, .(gid, pitteam, season, sp_act = sp)], by = c("gid", "pitteam"))
  message("rotation guess equals the actual starter:\n",
          paste(capture.output(print(hit[season >= 2016, .(team_games = .N, match = round(mean(sp == sp_act), 4)), by = season][order(season)])), collapse = "\n"))
}
if (LINEUP_MODE == "projected") {
  # Day-ahead lineup: the nine the team used in its most recent game dated before the as-of date
  # (game date minus ASOF_LAG) against a starter of the same hand as the one it faces (sp_tgt), or of
  # any hand if none yet. Past games are matched on the hand of who actually started them.
  tg <- merge(unique(lineup[, .(gid, batteam)]), G[, .(gid, Date)], by = "gid")
  tg <- merge(tg, sp[, .(gid, pitteam, opp_hand = sp_hand)], by.x = c("gid"), by.y = c("gid"), allow.cartesian = TRUE)[pitteam != batteam]
  if (STARTER_MODE == "actual") tg[, tgt_hand := opp_hand] else
    tg <- merge(tg, sp_tgt[, .(gid, pitteam, tgt_hand = sp_hand)], by = c("gid", "pitteam"))
  setorder(tg, batteam, Date, gid)
  tg[, src := {
    out <- rep(NA_character_, .N)
    for (i in seq_len(.N)) {
      prev <- which(Date < Date[i] - ASOF_LAG); same <- prev[opp_hand[prev] == tgt_hand[i]]
      j <- if (length(same)) max(same) else if (length(prev)) max(prev) else NA
      if (!is.na(j)) out[i] <- gid[j]
    }
    out
  }, by = batteam]
  lineup <- merge(tg[!is.na(src), .(gid, batteam, src)], lineup[, .(src = gid, batteam, batter, bathand, seq, slot, sw)],
                  by = c("src", "batteam"), allow.cartesian = TRUE)[, src := NULL]
  message("projected lineups for ", uniqueN(lineup[, .(gid, batteam)]), " team-games")
}
games <- G[season >= 2016, .(gid, Date, season, site, visteam, hometeam, temp, winddir, windspeed, umphome, vruns, hruns)]
games[, t := season_day(Date, season, as.data.frame(bounds))]

L <- merge(lineup, games[, .(gid, Date, season, t, site, hometeam, visteam)], by = "gid")
L[, side := ifelse(batteam == hometeam, "home", "away")]
L[, opp := ifelse(side == "home", visteam, hometeam)]
L <- merge(L, sp_tgt, by.x = c("gid", "opp"), by.y = c("gid", "pitteam"))
L <- L[!is.na(batter)]
# Side each slot bats from vs a lefty and vs a righty, and vs this starter (switch hitters: opposite).
L[, `:=`(side_vL = ifelse(sw, "R", bathand), side_vR = ifelse(sw, "L", bathand))]
L[sw == TRUE, bathand := ifelse(sp_hand %in% "L", "R", "L")]
message("lineup slots: ", nrow(L), "; switch hitters ", sum(L$sw))

# As-of query date and in-season day for every slot: asof_decay() and the bullpen window use events
# dated qd - 1 or earlier. Park factors need no shift: they come from the three prior seasons.
qd <- L$Date - ASOF_LAG
qt <- if (ASOF_LAG == 0) L$t else season_day(qd, L$season, as.data.frame(bounds))
q  <- function(entity) data.frame(entity = entity, Date = qd, season = L$season, t = qt)
ev <- function(entity) { x <- as.data.frame(Phn[, c("Date", "season", "t", OUT8, "n"), with = FALSE]); x$entity <- entity; x }
evp <- function(entity) { x <- as.data.frame(Pxn[, c("Date", "season", "t", OUT8, "n"), with = FALSE]); x$entity <- entity; x }

# --- batter, pitcher and league rates for every slot vs the starter ------------------------
lgq <- data.frame(Date = qd, season = L$season, t = qt)
lg_all  <- league_rates(Pn, lgq)
lg_hand <- function(h) league_rates(Pn, transform(lgq, lg_key = h), by = "pithand")
lg_side <- function(b) league_rates(Pn, transform(lgq, lg_key = b), by = "bathand")
lg_pair <- function(b, h) league_rates(Pn, transform(lgq, lg_key = paste(b, h)), by = c("bathand", "pithand"))
lgL <- lg_hand(rep("L", nrow(L))); lgR <- lg_hand(rep("R", nrow(L)))

# Platoon priors are side-specific: a lefty's rate vs lefties is shrunk toward his overall rate
# times (league lefty-vs-lefty / league lefty overall), and likewise for pitchers by their hand.
pair_L <- lg_pair(L$side_vL, rep("L", nrow(L))); pair_R <- lg_pair(L$side_vR, rep("R", nrow(L)))
lg_bside <- lg_side(L$bathand)
if (any(L$sw)) lg_bside[L$sw, ] <- league_rates(Pn, transform(lgq[L$sw, ], lg_key = "TRUE"), by = "plat")   # PAs with the platoon edge
# As-of decayed sums (windows only); the shrink constants act later, in counts().
bat_all <- asof_outcomes(ev(Phn$batter), q(L$batter), BAT_CFG)
bat_key <- ev(paste(Phn$batter, Phn$pithand))
bat_sL  <- asof_outcomes(bat_key, q(paste(L$batter, "L")), BAT_CFG)
bat_sR  <- asof_outcomes(bat_key, q(paste(L$batter, "R")), BAT_CFG)
isL     <- L$sp_hand == "L"
lg_phand <- lg_hand(L$sp_hand)
pit_all <- asof_outcomes(evp(Pxn$pitcher), q(L$sp), PIT_CFG)
pit_s   <- asof_outcomes(evp(paste(Pxn$pitcher, Pxn$bathand)), q(paste(L$sp, L$bathand)), PIT_CFG)
lg_sp  <- pair_L * isL + pair_R * !isL

PFd <- as.data.frame(PF)
pf_of <- function(side) {
  f <- merge(data.frame(i = seq_len(nrow(L)), season = L$season, site = L$site, bathand = side),
             PFd, by = c("season", "site", "bathand"), all.x = TRUE)
  f <- as.matrix(f[order(f$i), paste0("pf_", OUT8)]); f[is.na(f)] <- 1
  f
}
park <- function(m, f = pf_of(L$bathand)) { x <- m * f; x / rowSums(x) }
message("starter as-of sums done")

# --- starter length -----------------------------------------------------------------------
starts <- merge(P[, .(bf = .N), by = .(gid, pitcher, Date, season, t)], sp[, .(gid, sp)],
                by.x = c("gid", "pitcher"), by.y = c("gid", "sp"))
starts[, n := 1]
sq <- data.frame(entity = L$sp, Date = qd, season = L$season, t = qt)
st <- as.data.frame(starts)
sb <- asof_decay(transform(st, entity = pitcher), sq, c("bf", "n"), h = 60, c = 0.5)
lb <- asof_decay(transform(st, entity = "lg"), transform(sq, entity = "lg"), c("bf", "n"), h = 30, c = 1)
L[, exp_bf := (sb[, 1] + 3 * lb[, 1] / pmax(lb[, 2], 1e-9)) / (sb[, 2] + 3)]

# --- bullpen: who is available, how good, which hand --------------------------------------
spk <- unique(sp[, .(gid, pitcher = sp)])[, starter := TRUE]
rp <- merge(P, spk, by = c("gid", "pitcher"), all.x = TRUE)[is.na(starter)]
rel <- rp[, .(bf = .N), by = .(pitteam, pitcher, pithand, Date)]
keys <- unique(data.table(team = L$opp, Date = qd, season = L$season, t = qt))   # members and availability as of qd
mem <- rbindlist(lapply(split(keys, keys$team), function(k) {
  r <- rel[pitteam == k$team[1]]
  if (!nrow(r)) return(NULL)
  rbindlist(lapply(seq_len(nrow(k)), function(i) {
    d <- k$Date[i]
    x <- r[Date < d & Date >= d - 30]
    if (!nrow(x)) return(NULL)
    w <- x[, .(bf30 = sum(bf), last21 = any(Date >= d - 21), y1 = sum(bf[Date == d - 1]),
               y2 = any(Date == d - 2), hand = pithand[1]), by = pitcher]
    w <- w[last21 == TRUE]
    if (!nrow(w)) return(NULL)
    w[, avail := ifelse(y1 >= 9 | (y1 > 0 & y2), 0.25, 1)]
    w[, `:=`(team = k$team[1], Date = d, season = k$season[i], t = k$t[i], w = bf30 * avail)]
    w
  }))
}))
message("bullpen members: ", nrow(mem))
mq  <- function(entity) data.frame(entity = entity, Date = mem$Date, season = mem$season, t = mem$t)
mlg <- data.frame(Date = mem$Date, season = mem$season, t = mem$t)
mlg_hand <- league_rates(Pn, transform(mlg, lg_key = mem$hand), by = "pithand")
rel_all <- asof_outcomes(evp(Pxn$pitcher), mq(mem$pitcher), REL_CFG)
pit_key <- evp(paste(Pxn$pitcher, Pxn$bathand))
rel_sL <- asof_outcomes(pit_key, mq(paste(mem$pitcher, "L")), REL_CFG)
rel_sR <- asof_outcomes(pit_key, mq(paste(mem$pitcher, "R")), REL_CFG)
mlg_pL <- league_rates(Pn, transform(mlg, lg_key = paste("L", mem$hand)), by = c("bathand", "pithand"))
mlg_pR <- league_rates(Pn, transform(mlg, lg_key = paste("R", mem$hand)), by = c("bathand", "pithand"))
agg <- function(R) {
  d <- as.data.table(R * mem$w); d[, `:=`(team = mem$team, Date = mem$Date, w = mem$w)]
  d[, c(lapply(.SD, sum), list(w = sum(w))), by = .(team, Date), .SDcols = OUT8]
}
hm <- mem[, .(mixL = sum(w * (hand == "L")) / pmax(sum(w), 1e-9)), by = .(team, Date)]
pk <- paste(L$opp, qd)
mixL <- hm$mixL[match(pk, paste(hm$team, hm$Date))]
mixL[is.na(mixL)] <- 0.3
f_pen <- pf_of(L$bathand)                        # a switch hitter's park factor vs the pen: by the pen's hand mix
if (any(L$sw)) f_pen[L$sw, ] <- (mixL * pf_of(L$side_vL) + (1 - mixL) * pf_of(L$side_vR))[L$sw, ]
message("bullpen as-of sums done")

# --- shrink, combine, and expected counts per side: everything that depends on the k's ------
pos <- 1:40
slot_of <- ((pos - 1) %% 9) + 1
w_tot <- pmin(pmax(TEAM_PA - pos + 1, 0), 1)
grp <- split(seq_len(nrow(L)), paste(L$gid, L$side))
counts <- function(BAT_CFG, PIT_CFG, REL_CFG, checkpoint = NULL) {
  bat_vL <- shrunk_rates(bat_all, bat_sL, BAT_CFG, lg_bside, pair_L, K_SPLIT_BAT)
  bat_vR <- shrunk_rates(bat_all, bat_sR, BAT_CFG, lg_bside, pair_R, K_SPLIT_BAT)
  bat_sp <- bat_vL * isL + bat_vR * !isL
  pit_sp <- shrunk_rates(pit_all, pit_s, PIT_CFG, lg_phand, lg_sp, K_SPLIT_PIT)
  m_sp <- park(log5(bat_sp, pit_sp, lg_sp))
  RL <- shrunk_rates(rel_all, rel_sL, REL_CFG, mlg_hand, mlg_pL, K_SPLIT_PIT)
  RR <- shrunk_rates(rel_all, rel_sR, REL_CFG, mlg_hand, mlg_pR, K_SPLIT_PIT)
  penL <- agg(RL); penR <- agg(RR)
  iL <- match(pk, paste(penL$team, penL$Date)); iR <- match(pk, paste(penR$team, penR$Date))
  bsL <- L$bathand == "L"
  pen_vs <- as.matrix(penL[iL, OUT8, with = FALSE]) / penL$w[iL] * bsL + as.matrix(penR[iR, OUT8, with = FALSE]) / penR$w[iR] * !bsL
  if (any(L$sw)) {                               # switch hitters face each reliever from the side opposite his hand
    penS <- agg(RL * (mem$hand == "R") + RR * (mem$hand == "L")); iS <- match(pk, paste(penS$team, penS$Date))
    pen_vs[L$sw, ] <- (as.matrix(penS[iS, OUT8, with = FALSE]) / penS$w[iS])[L$sw, ]
  }
  miss <- !is.finite(rowSums(pen_vs))
  pen_vs[miss, ] <- as.matrix(lg_all)[miss, ]
  m_pen <- park(log5(mixL * bat_vL + (1 - mixL) * bat_vR, pen_vs, mixL * pair_L + (1 - mixL) * pair_R), f_pen)
  if (!is.null(checkpoint)) saveRDS(list(L = L, m_sp = m_sp, m_pen = m_pen, mixL = mixL, games = games), checkpoint)
  feat <- t(vapply(grp, function(rows) {
    b <- L$exp_bf[rows[1]]
    w_sp <- pmin(pmax(b - pos + 1, 0), 1); w_pen <- pmax(w_tot - w_sp, 0)
    o <- rows[match(slot_of, L$slot[rows])]
    ok <- !is.na(o)
    e12 <- ok & pos <= 18; e3 <- ok & pos > 18
    c(colSums(m_sp[o[e12], , drop = FALSE] * w_sp[e12]), colSums(m_sp[o[e3], , drop = FALSE] * w_sp[e3]),
      colSums(m_pen[o[ok], , drop = FALSE] * w_pen[ok]), b, mixL[rows[1]], sum(ok[1:9]))
  }, numeric(3 * length(OUT8) + 3)))
  colnames(feat) <- c(paste0("sp12_", OUT8), paste0("sp3_", OUT8), paste0("pen_", OUT8), "exp_bf", "pen_mixL", "slots")
  fd <- data.table(grp_id = names(grp), feat)      # not `key`: data.table() reads that as a sort key
  fd[, c("gid", "side") := tstrsplit(grp_id, " ")]
  wide <- dcast(fd, gid ~ side, value.var = setdiff(names(fd), c("grp_id", "gid", "side")))
  out <- merge(games, wide, by = "gid")
  if (ASOF_LAG > 0) setattr(out, "asof_lag", ASOF_LAG)             # matchup_model.R lags its own as-of inputs to match
  if (STARTER_MODE != "actual") setattr(out, "starter_mode", STARTER_MODE)
  out
}
out <- counts(BAT_CFG, PIT_CFG, REL_CFG, checkpoint = sub("[.]rds$", "-slots.rds", FEAT_OUT))   # checkpoint, one per build
saveRDS(out, FEAT_OUT)
message("wrote ", FEAT_OUT, ": ", nrow(out), " games")
if (nzchar(K_GRID)) {                            # tuning (matchup_tune.R): same as-of sums, other shrink constants
  kg <- fread(K_GRID)
  for (i in seq_len(nrow(kg))) {
    ks <- k_cfg(kg$m_pit[i], kg$m_bat[i], kg$m_rel_bb[i])
    saveRDS(counts(ks$BAT, ks$PIT, ks$REL), sub("[.]rds$", sprintf("-k%s.rds", kg$id[i]), FEAT_OUT))
  }
  message("wrote ", nrow(kg), " grid features files")
}
