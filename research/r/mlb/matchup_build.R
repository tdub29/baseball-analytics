#!/usr/bin/env Rscript
# Build per-game matchup features for 2016-2025 from Retrosheet plate appearances.
#
#   Rscript research/r/mlb/matchup_build.R            # writes data/mlb/matchup/features.rds
#
# Per side of each game: expected outcome counts against the starter (first and second time
# through the order, then third and later), against the bullpen, and the starter's expected
# batters faced. Every input is as of the start of the game's date.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R", "statcast.R")) source(file.path(SRC, f))
HIT_X <- as.numeric(Sys.getenv("HIT_X", "0"))     # weight on Statcast expected outcomes for hitters (0 = actual)
FEAT_OUT <- Sys.getenv("FEAT_OUT", "data/mlb/matchup/features.rds")
LINEUP_MODE <- Sys.getenv("LINEUP_MODE", "posted")   # "projected": day-ahead, from the team's last game vs a same-hand starter
K_SPLIT_BAT <- 600; K_SPLIT_PIT <- 600; TEAM_PA <- 38.3
dir.create("data/mlb/matchup", showWarnings = FALSE, recursive = TRUE)

P <- rbindlist(lapply(2015:2025, retro_pa))
G <- rbindlist(lapply(2015:2025, retro_games))
bounds <- P[, .(start = min(Date), end = max(Date)), by = season]
P[, t := season_day(Date, season, as.data.frame(bounds))]
P <- outcome_matrix(P)
P[, bathand := ifelse(bathand %in% c("L", "R"), bathand, "R")]
P[, pithand := ifelse(pithand %in% c("L", "R"), pithand, "R")]
PF <- park_table(P)
Pn <- park_neutral(P, PF)
# Pitchers are judged on expected outcomes of their batted balls (the xFIP/SIERA idea): each ball in
# play is replaced by the league outcome mix for its type (ground ball, fly, liner, popup) over the
# prior three seasons, so hit and home-run luck stays out of a pitcher's rates. Hitters keep actual.
BIP <- c("single", "double", "triple", "hr", "out_ip")
bbd <- P[!is.na(bb_type) & outcome %in% BIP, .N, by = .(season, bb_type, outcome)]
xmix <- rbindlist(lapply(sort(unique(P$season)), function(S) {
  src <- bbd[season %in% if (S == min(P$season)) S else (S - 3):(S - 1)]
  m <- dcast(src[, .(N = sum(N)), by = .(bb_type, outcome)], bb_type ~ outcome, value.var = "N", fill = 0)
  m[, tot := rowSums(.SD), .SDcols = BIP]
  for (o in BIP) m[[paste0("x_", o)]] <- m[[o]] / m$tot
  cbind(season = S, m[, c("bb_type", paste0("x_", BIP)), with = FALSE])
}))
Px <- merge(P, xmix, by = c("season", "bb_type"), all.x = TRUE, sort = FALSE)
has <- !is.na(Px$x_single) & Px$outcome %in% BIP
for (o in BIP) Px[[o]][has] <- Px[[paste0("x_", o)]][has]
Px[, paste0("x_", BIP) := NULL]
# Where Statcast tracked the ball, exit velocity and launch angle replace the batted-ball type.
SX <- NULL
if (length(list.files(SC_DIR, "^bip_"))) {
  reg <- data.table::as.data.table(readRDS(list.files("data/mlb/raw/chadwick", full.names = TRUE)[1]))
  SX <- statcast_expected(P, reg)
  message("statcast matched balls in play: ", nrow(SX), " of ", sum(P$outcome %in% BIP & !is.na(P$bb_type)))
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
lineup <- first[, .SD[!duplicated(batter)][1:9], by = .(gid, batteam), .SDcols = c("batter", "bathand", "seq")]
lineup[, slot := seq_len(.N), by = .(gid, batteam)]
sp <- first[, .(sp = pitcher[1], sp_hand = pithand[1]), by = .(gid, pitteam)]
if (LINEUP_MODE == "projected") {
  # Day-ahead lineup: the nine the team used in its most recent earlier game against a starter of
  # the same hand (any hand if none yet). The starter itself is taken as announced the day before.
  tg <- merge(unique(lineup[, .(gid, batteam)]), G[, .(gid, Date)], by = "gid")
  tg <- merge(tg, sp[, .(gid, pitteam, opp_hand = sp_hand)], by.x = c("gid"), by.y = c("gid"), allow.cartesian = TRUE)[pitteam != batteam]
  setorder(tg, batteam, Date, gid)
  tg[, src := {
    out <- rep(NA_character_, .N)
    for (i in seq_len(.N)) {
      prev <- which(Date < Date[i]); same <- prev[opp_hand[prev] == opp_hand[i]]
      j <- if (length(same)) max(same) else if (length(prev)) max(prev) else NA
      if (!is.na(j)) out[i] <- gid[j]
    }
    out
  }, by = batteam]
  lineup <- merge(tg[!is.na(src), .(gid, batteam, src)], lineup[, .(src = gid, batteam, batter, bathand, seq, slot)],
                  by = c("src", "batteam"), allow.cartesian = TRUE)[, src := NULL]
  message("projected lineups for ", uniqueN(lineup[, .(gid, batteam)]), " team-games")
}
games <- G[season >= 2016, .(gid, Date, season, site, visteam, hometeam, temp, winddir, windspeed, umphome, vruns, hruns)]
games[, t := season_day(Date, season, as.data.frame(bounds))]

L <- merge(lineup, games[, .(gid, Date, season, t, site, hometeam, visteam)], by = "gid")
L[, side := ifelse(batteam == hometeam, "home", "away")]
L[, opp := ifelse(side == "home", visteam, hometeam)]
L <- merge(L, sp, by.x = c("gid", "opp"), by.y = c("gid", "pitteam"))
L <- L[!is.na(batter)]
message("lineup slots: ", nrow(L))

q  <- function(entity) data.frame(entity = entity, Date = L$Date, season = L$season, t = L$t)
ev <- function(entity) { x <- as.data.frame(Phn[, c("Date", "season", "t", OUT8, "n"), with = FALSE]); x$entity <- entity; x }
evp <- function(entity) { x <- as.data.frame(Pxn[, c("Date", "season", "t", OUT8, "n"), with = FALSE]); x$entity <- entity; x }

# --- batter, pitcher and league rates for every slot vs the starter ------------------------
lgq <- data.frame(Date = L$Date, season = L$season, t = L$t)
lg_all  <- league_rates(Pn, lgq)
lg_hand <- function(h) league_rates(Pn, transform(lgq, lg_key = h), by = "pithand")
lg_side <- function(b) league_rates(Pn, transform(lgq, lg_key = b), by = "bathand")
lg_pair <- function(b, h) league_rates(Pn, transform(lgq, lg_key = paste(b, h)), by = c("bathand", "pithand"))
lgL <- lg_hand(rep("L", nrow(L))); lgR <- lg_hand(rep("R", nrow(L)))

# Platoon priors are side-specific: a lefty's rate vs lefties is shrunk toward his overall rate
# times (league lefty-vs-lefty / league lefty overall), and likewise for pitchers by their hand.
pair_L <- lg_pair(L$bathand, rep("L", nrow(L))); pair_R <- lg_pair(L$bathand, rep("R", nrow(L)))
lg_bside <- lg_side(L$bathand)
bat_all <- asof_outcomes(ev(Phn$batter), q(L$batter), BAT_CFG)
bat_key <- ev(paste(Phn$batter, Phn$pithand))
bat_vL  <- shrunk_rates(bat_all, asof_outcomes(bat_key, q(paste(L$batter, "L")), BAT_CFG), BAT_CFG, lg_bside, pair_L, K_SPLIT_BAT)
bat_vR  <- shrunk_rates(bat_all, asof_outcomes(bat_key, q(paste(L$batter, "R")), BAT_CFG), BAT_CFG, lg_bside, pair_R, K_SPLIT_BAT)
isL     <- L$sp_hand == "L"
bat_sp  <- bat_vL * isL + bat_vR * !isL
lg_phand <- lg_hand(L$sp_hand)
pit_all <- asof_outcomes(evp(Pxn$pitcher), q(L$sp), PIT_CFG)
pit_sp  <- shrunk_rates(pit_all, asof_outcomes(evp(paste(Pxn$pitcher, Pxn$bathand)), q(paste(L$sp, L$bathand)), PIT_CFG),
                        PIT_CFG, lg_phand, pair_L * isL + pair_R * !isL, K_SPLIT_PIT)
lg_sp  <- pair_L * isL + pair_R * !isL

PFd <- as.data.frame(PF)
park <- function(m) {
  f <- merge(data.frame(i = seq_len(nrow(L)), season = L$season, site = L$site, bathand = L$bathand),
             PFd, by = c("season", "site", "bathand"), all.x = TRUE)
  f <- as.matrix(f[order(f$i), paste0("pf_", OUT8)]); f[is.na(f)] <- 1
  x <- m * f; x / rowSums(x)
}
m_sp <- park(log5(bat_sp, pit_sp, lg_sp))
message("starter matchups done")

# --- starter length -----------------------------------------------------------------------
starts <- merge(P[, .(bf = .N), by = .(gid, pitcher, Date, season, t)], sp[, .(gid, sp)],
                by.x = c("gid", "pitcher"), by.y = c("gid", "sp"))
starts[, n := 1]
sq <- data.frame(entity = L$sp, Date = L$Date, season = L$season, t = L$t)
st <- as.data.frame(starts)
sb <- asof_decay(transform(st, entity = pitcher), sq, c("bf", "n"), h = 60, c = 0.5)
lb <- asof_decay(transform(st, entity = "lg"), transform(sq, entity = "lg"), c("bf", "n"), h = 30, c = 1)
L[, exp_bf := (sb[, 1] + 3 * lb[, 1] / pmax(lb[, 2], 1e-9)) / (sb[, 2] + 3)]

# --- bullpen: who is available, how good, which hand --------------------------------------
spk <- unique(sp[, .(gid, pitcher = sp)])[, starter := TRUE]
rp <- merge(P, spk, by = c("gid", "pitcher"), all.x = TRUE)[is.na(starter)]
rel <- rp[, .(bf = .N), by = .(pitteam, pitcher, pithand, Date)]
keys <- unique(L[, .(team = opp, Date, season, t)])
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
rel_all <- asof_outcomes(evp(Pxn$pitcher), mq(mem$pitcher), PIT_CFG)
pit_key <- evp(paste(Pxn$pitcher, Pxn$bathand))
rel_vs <- function(b) shrunk_rates(rel_all, asof_outcomes(pit_key, mq(paste(mem$pitcher, b)), PIT_CFG), PIT_CFG, mlg_hand,
                                   league_rates(Pn, transform(mlg, lg_key = paste(b, mem$hand)), by = c("bathand", "pithand")), K_SPLIT_PIT)
agg <- function(R) {
  d <- as.data.table(R * mem$w); d[, `:=`(team = mem$team, Date = mem$Date, w = mem$w)]
  d[, c(lapply(.SD, sum), list(w = sum(w))), by = .(team, Date), .SDcols = OUT8]
}
penL <- agg(rel_vs("L")); penR <- agg(rel_vs("R"))
hm <- mem[, .(mixL = sum(w * (hand == "L")) / pmax(sum(w), 1e-9)), by = .(team, Date)]
message("bullpen rates done")

pk <- paste(L$opp, L$Date)
iL <- match(pk, paste(penL$team, penL$Date)); iR <- match(pk, paste(penR$team, penR$Date))
bsL <- L$bathand == "L"
pen_vs <- as.matrix(penL[iL, OUT8, with = FALSE]) / penL$w[iL] * bsL + as.matrix(penR[iR, OUT8, with = FALSE]) / penR$w[iR] * !bsL
mixL <- hm$mixL[match(pk, paste(hm$team, hm$Date))]
miss <- !is.finite(rowSums(pen_vs))
pen_vs[miss, ] <- as.matrix(lg_all)[miss, ]; mixL[is.na(mixL)] <- 0.3
m_pen <- park(log5(mixL * bat_vL + (1 - mixL) * bat_vR, pen_vs, mixL * pair_L + (1 - mixL) * pair_R))

saveRDS(list(L = L, m_sp = m_sp, m_pen = m_pen, mixL = mixL, games = games), "data/mlb/matchup/slots.rds")   # checkpoint

# --- expected counts per side -------------------------------------------------------------
pos <- 1:40
slot_of <- ((pos - 1) %% 9) + 1
w_tot <- pmin(pmax(TEAM_PA - pos + 1, 0), 1)
grp <- split(seq_len(nrow(L)), paste(L$gid, L$side))
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
saveRDS(out, FEAT_OUT)
message("wrote ", FEAT_OUT, ": ", nrow(out), " games")
