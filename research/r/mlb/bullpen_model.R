#!/usr/bin/env Rscript
# Bullpen usage, starter hook and simulator inputs (SIM-PLAN.md), validation seasons only.
#
#   Rscript research/r/mlb/bullpen_model.R      # writes data/mlb/sim/inputs-<season>.rds, 2016-2022
#
# Reads Retrosheet 2015-2022 and nothing later: 2023-2025 is the scored-once test. Per-game inputs
# are as of the start of the game's date; every fitted piece for season S (transitions, LI table,
# hook, exit and choice models, factors) uses seasons max(2015, S - 3) to S - 1. matchup.R is
# sourced read-only at a pinned commit, the frozen v2 engine (another agent edits the working copy).
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table); library(survival) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R")) source(file.path(SRC, f))
MATCHUP_REV <- "4e47746"
local({ tmp <- tempfile(fileext = ".R")
  writeLines(system2("git", c("-C", SRC, "show", paste0(MATCHUP_REV, ":./matchup.R")), stdout = TRUE), tmp)
  source(tmp) })
SEAS <- 2015:2022; TARGET <- 2016:2022
stopifnot(max(SEAS) <= 2022)                        # never a test-season row
K_SPLIT_BAT <- 600; K_SPLIT_PIT <- 600              # as matchup_build.R
WIN_G <- 18; KMAX <- 22                             # bullpen window (team games) and cap
OUT <- "data/mlb/sim"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
win <- function(S) if (S == 2015) 2015L else max(2015L, S - 3L):(S - 1L)
bin <- function(x, br) findInterval(x, br, left.open = TRUE)   # (a, b] bins, shared with simulate.R
PB_BR <- c(39, 49, 59, 69, 79, 84, 89, 94, 99, 104, 109, 114, 119)   # starter pitches
BB_BR <- c(3, 6, 9, 12, 15, 18, 21, 24, 27, 30)                      # starter batters faced
AB_BR <- c(1, 2, 3, 4, 5, 6, 9)                                      # reliever batters faced
RP_BR <- c(9, 19, 29, 39)                                            # reliever pitches

# --- plays: base-out states, runs between plate appearances, pitches -----------------------------
G <- rbindlist(lapply(SEAS, function(s) {
  g <- fread(retro_file(s, "gameinfo"), select = c("gid", "date", "gametype", "innings", "site", "visteam", "hometeam", "vruns", "hruns"), showProgress = FALSE)
  g[gametype == "regular"][, `:=`(Date = as.Date(as.character(date), "%Y%m%d"), season = s, gametype = NULL, date = NULL)]
}))
G[is.na(innings), innings := 9L]
bounds <- G[, .(start = min(Date), end = max(Date)), by = season]
cols <- c("gid", "gametype", "inning", "top_bot", "pa", "batteam", "pitteam", "batter", "pitcher", "bathand", "pithand",
          "nump", "outs_pre", "outs_post", "br1_pre", "br2_pre", "br3_pre", "br1_post", "br2_post", "br3_post",
          "runs", "score_v", "score_h", "walk", "iw", "k", "hbp", "single", "double", "triple", "hr")
R <- rbindlist(lapply(SEAS, function(s) fread(retro_file(s, "plays"), select = cols, showProgress = FALSE)[gametype == "regular"][, season := s]))
R[, gametype := NULL]
occ <- function(x) as.integer(!is.na(x) & x != "")
R[, `:=`(row = seq_len(.N), half = rleid(inning, top_bot)), by = gid]
R[, s_pre := outs_pre * 8L + occ(br1_pre) + 2L * occ(br2_pre) + 4L * occ(br3_pre)]
R[, s_post := fifelse(outs_post >= 3, 24L, outs_post * 8L + occ(br1_post) + 2L * occ(br2_post) + 4L * occ(br3_post))]
R[, c("br1_pre", "br2_pre", "br3_pre", "br1_post", "br2_post", "br3_post") := NULL]
R[is.na(nump), nump := 0L][is.na(runs), runs := 0L]
R[, cp := cumsum(nump), by = .(gid, pitcher)]                 # pitches so far today, this row included
R[, cumr0 := cumsum(runs) - runs, by = gid]                   # game runs before this row
H <- R[, .(end_cumr = cumr0[.N] + runs[.N], end_s = s_post[.N]), by = .(gid, half)]
X <- R[pa == 1]
X[, outcome := fcase(k == 1, "k", walk == 1 & iw == 1, "ibb", walk == 1, "ubb", hbp == 1, "hbp", single == 1, "single",
                     double == 1, "double", triple == 1, "triple", hr == 1, "hr", default = "out_ip")]
X[, c("walk", "iw", "k", "hbp", "single", "double", "triple", "hr") := NULL]
O9 <- c(OUT8, "ibb")
X[, o := match(outcome, O9)]
X[, `:=`(nxt_row = shift(row, -1), nxt_s = shift(s_pre, -1), nxt_cumr0 = shift(cumr0, -1)), by = .(gid, half)]
X <- merge(X, H, by = c("gid", "half"), sort = FALSE)
X[, ie := as.integer(is.na(nxt_row))]                         # last plate appearance of the half
X[, r_tr := fifelse(ie == 1L, end_cumr - cumr0, nxt_cumr0 - cumr0)]
X[, s_nxt := fifelse(ie == 1L, end_s, nxt_s)]
X[, c("nxt_row", "nxt_s", "nxt_cumr0", "end_cumr", "end_s") := NULL]
stopifnot(all(X$r_tr >= 0 & X$r_tr <= 4), all(X$s_nxt %in% 0:24))
setorder(X, gid, row)
X[, dp := cp - shift(cp, fill = 0), by = .(gid, pitcher)]     # pitches attributed to this plate appearance
X <- merge(X, G[, .(gid, Date, sched = innings, hwin = as.integer(hruns > vruns), tie = hruns == vruns)], by = "gid", sort = FALSE)
X[, t := season_day(Date, season, as.data.frame(bounds))]
setorder(X, gid, row)
X[, inn_c := pmin(pmax(inning - sched + 9L, 1L), 10L)]        # inning relative to scheduled length, 10 = extras
X[, mg := pmax(pmin(score_h - score_v, 7L), -7L)]
message("plate appearances 2015-2022: ", nrow(X))

# --- win expectancy and LI per season (prior seasons) ---------------------------------------------
li_table <- function(S) {
  x <- X[season %in% win(S) & !tie]
  c3 <- x[, .(w3 = mean(hwin)), by = .(top_bot, mg)]
  c2 <- merge(x[, .(w2 = sum(hwin), n2 = .N), by = .(inn_c, top_bot, mg)], c3, by = c("top_bot", "mg"))
  c2[, w2 := (w2 + 50 * w3) / (n2 + 50)]
  grid <- CJ(inn_c = 1:10, top_bot = 0:1, s_pre = 0:23, mg = -7:7)
  grid <- merge(grid, x[, .(w1 = sum(hwin), n1 = .N), by = .(inn_c, top_bot, s_pre, mg)], by = c("inn_c", "top_bot", "s_pre", "mg"), all.x = TRUE)
  grid <- merge(grid, c2[, .(inn_c, top_bot, mg, w2)], by = c("inn_c", "top_bot", "mg"), all.x = TRUE)
  grid <- merge(grid, c3, by = c("top_bot", "mg"), all.x = TRUE)
  grid[is.na(w2), w2 := fifelse(is.na(w3), 0.5, w3)][is.na(n1), `:=`(n1 = 0L, w1 = 0L)]
  grid[, we := (w1 + 20 * w2) / (n1 + 20)]
  key <- function(i, h, s, m) ((i - 1L) * 2L + h) * 24L * 15L + s * 15L + (m + 7L) + 1L
  setorder(grid, inn_c, top_bot, s_pre, mg)
  we <- grid$we
  x[, we0 := we[key(inn_c, top_bot, s_pre, mg)]]
  x[, we1 := shift(we0, -1), by = gid]
  x[is.na(we1), we1 := hwin]                                   # last plate appearance: the result
  x[, d := abs(we1 - we0)]
  l2 <- x[, .(d2 = sum(d), n2 = .N), by = .(inn_c, top_bot, mg)][, d2 := d2 / n2]
  g2 <- merge(CJ(inn_c = 1:10, top_bot = 0:1, s_pre = 0:23, mg = -7:7),
              x[, .(d1 = sum(d), n1 = .N), by = .(inn_c, top_bot, s_pre, mg)], by = c("inn_c", "top_bot", "s_pre", "mg"), all.x = TRUE)
  g2 <- merge(g2, l2[, .(inn_c, top_bot, mg, d2)], by = c("inn_c", "top_bot", "mg"), all.x = TRUE)
  g2[is.na(d2), d2 := mean(x$d)][is.na(n1), `:=`(n1 = 0L, d1 = 0)]
  setorder(g2, inn_c, top_bot, s_pre, mg)
  li <- pmax(((g2$d1 + 20 * g2$d2) / (g2$n1 + 20)) / mean(x$d), 0.01)   # decided games have zero swing
  list(we = we, li = li)
}
li_key <- function(inn_c, top_bot, s, mg) ((inn_c - 1L) * 2L + top_bot) * 360L + s * 15L + (mg + 7L) + 1L
LIT <- setNames(lapply(SEAS, li_table), SEAS)
message("LI tables done")

# --- appearances ------------------------------------------------------------------------------------
st <- R[R[, .I[1], by = .(gid, pitteam)]$V1, .(gid, pitteam, sp = pitcher, sp_hand = pithand)]
tl <- R[, .(team_last = max(row)), by = .(gid, pitteam)]
APP <- R[, .(first_row = row[1], last_row = row[.N], bf = sum(pa), pitches = cp[.N], hand = pithand[1], inning = inning[1],
             top_bot = top_bot[1], s_pre = s_pre[1], score_v = score_v[1], score_h = score_h[1]), by = .(gid, season, pitteam, pitcher)]
APP <- merge(APP, st[, .(gid, pitteam, sp)], by = c("gid", "pitteam"))
APP[, starter := pitcher == sp][, sp := NULL]
APP <- merge(APP, tl, by = c("gid", "pitteam"))
APP[, fin := as.integer(last_row == team_last)][, team_last := NULL]
APP <- merge(APP, G[, .(gid, adate = Date, sched = innings)], by = "gid")
APP[, md := fifelse(top_bot == 0L, score_h - score_v, score_v - score_h)]     # fielding team's lead at entry
APP[, inn_c := pmin(pmax(inning - sched + 9L, 1L), 10L)]
APP[, li := NA_real_]
for (s in SEAS) APP[season == s, li := LIT[[as.character(s)]]$li[li_key(inn_c, top_bot, s_pre, pmax(pmin(score_h - score_v, 7L), -7L))]]
APP[, t := season_day(adate, season, as.data.frame(bounds))]
APP[, hand := ifelse(hand %in% c("L", "R"), hand, "R")]
message("appearances: ", nrow(APP), " (relief ", sum(!APP$starter), ")")

# --- team games and bullpen candidates (as of the game's date) -----------------------------------
TG <- rbind(G[, .(gid, Date, season, team = hometeam, home = 1L)], G[, .(gid, Date, season, team = visteam, home = 0L)])
setorder(TG, team, Date, gid)
TG[, tg := seq_len(.N), by = team]
TG[, kprev := findInterval(as.numeric(Date) - 1, as.numeric(Date)), by = team]   # team games dated before this date
APP <- merge(APP, TG[, .(gid, pitteam = team, tg)], by = c("gid", "pitteam"))
Q <- TG[, .(gid, team, Date, season, lo = kprev - WIN_G + 1L, hi = kprev)]
C <- APP[, .(pitteam, tg2 = tg, pitcher, adate, starter, hand)][Q, on = .(pitteam = team, tg2 >= lo, tg2 <= hi), allow.cartesian = TRUE, nomatch = NULL]
C <- C[, .(n_app = .N, n_rel = sum(!starter), n_start = sum(starter), last = max(adate), n14 = sum(!starter & adate >= Date - 14),
           hand = hand[which.max(adate)]), by = .(gid, team = pitteam, Date, season, pitcher)]
C <- merge(C, st[, .(gid, team = pitteam, sp)], by = c("gid", "team"))[pitcher != sp][, sp := NULL]
ap_all <- APP[, .(pitcher, adate, ateam = pitteam)][order(pitcher, adate)]
ap_all <- ap_all[, .(ateam = ateam[.N]), by = .(pitcher, adate)]
setkey(ap_all, pitcher, adate)
lastany <- ap_all[, .(pitcher, adate, ateam, last_any = adate)][C[, .(pitcher, adate = Date - 1)], roll = Inf, on = .(pitcher, adate)]
C[, `:=`(ateam = lastany$ateam, last_any = lastany$last_any)]     # most recent appearance before the date, any team
C <- C[ateam == team][, ateam := NULL]
setorder(C, gid, team, -n_rel, -last)
C[, k := seq_len(.N), by = .(gid, team)]
C <- C[k <= KMAX]
DP <- APP[, .(p = sum(pitches)), by = .(pitcher, adate)]
for (j in 1:3) { d <- DP[, .(pitcher, Date = adate + j, v = p)]; setnames(d, "v", paste0("p", j)); C <- merge(C, d, by = c("pitcher", "Date"), all.x = TRUE) }
for (j in paste0("p", 1:3)) set(C, which(is.na(C[[j]])), j, 0)
C[, `:=`(b2b = as.integer(p1 > 0 & p2 > 0), lds = log(pmin(as.numeric(Date - last_any), 30)), ss = n_start / n_app)]
C[, t := season_day(Date, season, as.data.frame(bounds))]
# role, as of the date, from relief appearances (decayed h = 60 in-season days, carry 0.5, shrunk with 4)
rel_ev <- APP[starter == FALSE & bf >= 1, .(entity = pitcher, Date = adate, season, t, li, fin, bf, n = 1)]
lg0 <- rel_ev[season == 2015, .(li = mean(li), fin = mean(fin), bf = mean(bf))]
rs <- asof_decay(as.data.frame(rel_ev), data.frame(entity = C$pitcher, Date = C$Date, season = C$season, t = C$t), c("li", "fin", "bf", "n"), h = 60, c = 0.5)
C[, `:=`(gm = (rs[, "li"] + 4 * lg0$li) / (rs[, "n"] + 4), fin = (rs[, "fin"] + 4 * lg0$fin) / (rs[, "n"] + 4),
         lmbf = log((rs[, "bf"] + 4 * lg0$bf) / (rs[, "n"] + 4)))]
# pitches per batter (all appearances) relative to the league, as of the date
all_ev <- APP[bf >= 1, .(entity = pitcher, Date = adate, season, t, pitches, bf)]
lg_ppa <- function(q) { s <- asof_decay(transform(as.data.frame(all_ev), entity = "lg"), transform(q, entity = "lg"), c("pitches", "bf"), h = 30, c = 1); s[, 1] / pmax(s[, 2], 1) }
eff_of <- function(q) { s <- asof_decay(as.data.frame(all_ev), q, c("pitches", "bf"), h = 60, c = 0.5); l <- lg_ppa(q)
  ((s[, 1] + 100 * l) / (s[, 2] + 100)) / l }
C[, eff := eff_of(data.frame(entity = pitcher, Date = Date, season = season, t = t))]
message("candidates: ", nrow(C), "; per team-game ", round(nrow(C) / uniqueN(C[, .(gid, team)]), 1))

# --- starters: leash (mean pitches and batters per start) and efficiency, as of the date ----------
starts <- APP[starter == TRUE, .(entity = pitcher, Date = adate, season, t, pitches, bf, n = 1)]
leash_of <- function(q) {
  s <- asof_decay(as.data.frame(starts), q, c("pitches", "bf", "n"), h = 60, c = 0.5)
  l <- asof_decay(transform(as.data.frame(starts), entity = "lg"), transform(q, entity = "lg"), c("pitches", "bf", "n"), h = 30, c = 1)
  cbind(leash = (s[, 1] + 3 * l[, 1] / pmax(l[, 3], 1e-9)) / (s[, 3] + 3), exp_bf = (s[, 2] + 3 * l[, 2] / pmax(l[, 3], 1e-9)) / (s[, 3] + 3))
}
SP <- APP[starter == TRUE, .(gid, team = pitteam, pitcher, hand, Date = adate, season, t, bf, pitches)]
lq <- data.frame(entity = SP$pitcher, Date = SP$Date, season = SP$season, t = SP$t)
SP[, c("leash", "exp_bf") := as.data.table(leash_of(lq))][, eff := eff_of(lq)]

# --- hook and exit hazard training rows ---------------------------------------------------------------
X <- merge(X, APP[, .(gid, pitcher, starter, app_first = first_row)], by = c("gid", "pitcher"), sort = FALSE)
setorder(X, gid, row)
X[, `:=`(app_bf = seq_len(.N), app_r = cumsum(r_tr)), by = .(gid, pitcher)]
X[, last_pa := app_bf == max(app_bf), by = .(gid, pitcher)]
tf <- X[, .(tf_last = max(row)), by = .(gid, pitteam)]             # last plate appearance the team fielded
X <- merge(X, tf, by = c("gid", "pitteam"), sort = FALSE)
X[, removed := as.integer(last_pa & row < tf_last)]
X[, cens := last_pa & row == tf_last]                               # still in when the game ended
setorder(X, gid, row)
HS <- merge(X[starter == TRUE & !cens, .(gid, pitcher, season, removed, ie, bf = app_bf, pitches = cp, runs = app_r)],
            SP[, .(gid, pitcher, leash)], by = c("gid", "pitcher"))
HS[, `:=`(pb = bin(pitches, PB_BR), bb = bin(bf, BB_BR), rb = pmin(runs, 8L), dev = pmax(pitches - leash, 0))]
HR <- merge(X[starter == FALSE & !cens, .(gid, pitcher, season, Date, removed, ie, bf = app_bf, pitches = cp, runs = app_r, late9 = as.integer(inning >= sched))],
            C[, .(pitcher, Date, lmbf)][!duplicated(C[, .(pitcher, Date)])], by = c("pitcher", "Date"), all.x = TRUE)
HR[is.na(lmbf), lmbf := log(lg0$bf)]
HR[, `:=`(ab = bin(bf, AB_BR), rb = pmin(runs, 4L), pbr = bin(pitches, RP_BR))]
fit_hook <- function(S) {
  d <- HS[season %in% win(S)]; if (S >= 2020) d <- d[bf >= 3 | ie == 1]
  m <- glm(removed ~ factor(pb) * ie + factor(bb) + factor(rb) + leash + dev, binomial, d)
  grid <- CJ(pb = 0:length(PB_BR), ie = 0:1, bb = 0:length(BB_BR), rb = 0:8)
  grid[, eta := predict(m, transform(grid, leash = 0, dev = 0), type = "link")]
  list(eta = array(grid[order(rb, bb, ie, pb)]$eta, c(length(PB_BR) + 1, 2, length(BB_BR) + 1, 9)),
       b_leash = coef(m)[["leash"]], b_dev = coef(m)[["dev"]], n = nrow(d), dev_expl = 1 - m$deviance / m$null.deviance)
}
fit_exit <- function(S) {
  d <- HR[season %in% win(S)]; if (S >= 2020) d <- d[bf >= 3 | ie == 1]
  m <- glm(removed ~ factor(ab) * ie + factor(rb) + factor(pbr) + late9 * ie + lmbf * ie, binomial, d)
  grid <- CJ(ab = 0:length(AB_BR), ie = 0:1, rb = 0:4, pbr = 0:length(RP_BR), late9 = 0:1)
  grid[, eta := predict(m, transform(grid, lmbf = 0), type = "link")]
  list(eta = array(grid[order(late9, pbr, rb, ie, ab)]$eta, c(length(AB_BR) + 1, 2, 5, length(RP_BR) + 1, 2)),
       b_lmbf = coef(m)[["lmbf"]], b_lmbf_ie = coef(m)[grepl("lmbf", names(coef(m))) & grepl(":", names(coef(m)))][[1]],
       n = nrow(d), dev_expl = 1 - m$deviance / m$null.deviance)
}

# --- choice events: who enters, among the available candidates ---------------------------------------
EV <- APP[starter == FALSE & bf >= 1, .(gid, team = pitteam, pitcher, season, Date = adate, first_row, li, inning, sched, md)]
fpa <- X[, .(gid, pitcher, row, batteam, batter, bathand)][order(gid, row)]
fpa[, pa_i := seq_len(.N), by = .(gid, batteam)]
ent <- fpa[fpa[, .I[1], by = .(gid, pitcher)]$V1, .(gid, pitcher, batteam, pa_i)]
nb <- rbindlist(lapply(0:2, function(j) merge(ent[, .(gid, pitcher, batteam, pa_i = pa_i + j, j)], fpa[, .(gid, batteam, pa_i, batter, bathand)],
                                               by = c("gid", "batteam", "pa_i"))))
EV <- merge(EV, ent[, .(gid, pitcher)], by = c("gid", "pitcher"))
used <- APP[, .(gid, team = pitteam, used = pitcher, ufr = first_row)]
choice_rows <- function(S) {
  ev <- EV[season %in% win(S)][, ev := .I]
  cs <- merge(ev, C[, .(gid, team, cand = pitcher, chand = hand, gm, fin, lmbf, ss, p1, p2, p3, b2b, lds, n14)], by = c("gid", "team"), allow.cartesian = TRUE)
  u <- merge(cs[, .(ev, gid, team, cand, first_row)], used, by.x = c("gid", "team", "cand"), by.y = c("gid", "team", "used"))[ufr < first_row]
  cs <- cs[!u, on = .(ev, cand)]
  cs[, chosen := as.integer(cand == pitcher)]
  cs <- cs[ev %in% cs[chosen == 1L]$ev]
  nbx <- merge(nb[, .(gid, pitcher, j, bathand)], ev[, .(gid, pitcher, ev)], by = c("gid", "pitcher"))
  sm <- merge(cs[, .(ev, cand, chand)], nbx[, .(ev, j, bathand)], by = "ev", allow.cartesian = TRUE)
  sm[, same := as.integer(bathand == chand)]                       # registered "B" (switch) never matches
  sm <- sm[, .(same = as.integer(any(same[j == 0] == 1L)), share3 = mean(same)), by = .(ev, cand)]
  cs <- merge(cs, sm, by = c("ev", "cand"), all.x = TRUE)
  cs[is.na(same), `:=`(same = 0L, share3 = 0)]
  cs[, `:=`(lLI = log(li), save9 = as.integer(inning >= sched & md >= 1 & md <= 3), early = as.integer(inning <= 5),
            blow = as.integer(abs(md) >= 5), late = as.integer(inning >= sched - 1L))]
  list(rows = cs, events = nrow(ev), kept = uniqueN(cs$ev))
}
CHOICE_F <- chosen ~ gm + fin + lmbf + ss + p1 + p2 + p3 + b2b + lds + n14 + gm:lLI + fin:save9 + lmbf:early + lmbf:blow +
  ss:early + gm:blow + same + share3:late + strata(ev)
fit_choice <- function(S) {
  cr <- choice_rows(S); d <- cr$rows
  d[, `:=`(p1 = p1 / 10, p2 = p2 / 10, p3 = p3 / 10)]
  m <- clogit(CHOICE_F, data = d, method = "approximate")
  list(coef = coef(m), se = sqrt(diag(vcov(m))), events = cr$events, kept = cr$kept, rows = nrow(d))
}

# --- per-season tables: transitions, intentional walks, pitches, TTO and home factors -----------------
season_tables <- function(S) {
  x <- X[season %in% win(S)]
  tr <- x[, .N, by = .(s_pre, o, s_nxt, r_tr)]
  pool <- X[season < S, .N, by = .(s_pre, o, s_nxt, r_tr)]          # fallback for thin cells: every earlier season
  if (S == 2015) pool <- tr
  tr <- merge(CJ(s_pre = 0:23, o = 1:9), tr, by = c("s_pre", "o"), all.x = TRUE)
  nn <- tr[, .(n = sum(N, na.rm = TRUE)), by = .(s_pre, o)]
  thin <- nn[n < 30]
  if (nrow(thin)) {                                                  # ibb borrows ubb; others their pooled cell
    fb <- rbindlist(lapply(seq_len(nrow(thin)), function(i) {
      s <- thin$s_pre[i]; oo <- thin$o[i]; src <- if (oo == 9L) 2L else oo
      p <- pool[s_pre == s & o == src]
      if (!nrow(p) || sum(p$N) < 30) p <- tr[s_pre == s & o == 2L & !is.na(N)]
      p[, .(s_pre = s, o = oo, s_nxt, r_tr, N = 30 * N / sum(N))]
    }))
    tr <- rbind(tr[!is.na(N)], fb)[, .(N = sum(N)), by = .(s_pre, o, s_nxt, r_tr)]
  } else tr <- tr[!is.na(N)]
  tr[, p := N / sum(N), by = .(s_pre, o)]
  setorder(tr, s_pre, o, -p)
  ibb <- x[, .(p = mean(o == 9L)), by = s_pre][order(s_pre)]
  pt <- x[o <= 9, .N, by = .(o, dp = pmin(pmax(dp, 1L), 15L))][order(o, dp)][, p := N / sum(N), by = o]
  P8 <- x[o <= 8]
  rate <- function(d) tabulate(d$o, 8) / nrow(d)
  base <- rate(P8)
  hf <- rate(P8[top_bot == 1L]) / base; af <- rate(P8[top_bot == 0L]) / base
  sx <- P8[starter == TRUE]
  sx <- merge(sx, PA_TTO[, .(gid, row, tto)], by = c("gid", "row"))
  f12 <- rate(sx[tto <= 2]) / rate(sx); f3 <- rate(sx[tto >= 3]) / rate(sx)
  list(trans = tr[, .(s_pre, o, s_nxt, r_tr, p)], ibb = ibb$p, pitch = pt[, .(o, dp, p)], hf = hf, af = af, f12 = f12, f3 = f3)
}
setorder(X, gid, row)
PA_TTO <- X[o <= 8, .(gid, pitcher, batter, row)][, tto := seq_len(.N), by = .(gid, pitcher, batter)]

# --- matchup rates (the v2 engine, read-only) --------------------------------------------------------
P <- rbindlist(lapply(SEAS, retro_pa))
P[, t := season_day(Date, season, as.data.frame(bounds))]
P <- outcome_matrix(P)
P[, bathand := ifelse(bathand %in% c("L", "R"), bathand, "R")]
P[, pithand := ifelse(pithand %in% c("L", "R"), pithand, "R")]
PF <- park_table(P)
Pn <- park_neutral(P, PF)
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
Pxn <- park_neutral(Px, PF)
EVB <- as.data.frame(Pn[, c("Date", "season", "t", OUT8, "n"), with = FALSE])
EVP <- as.data.frame(Pxn[, c("Date", "season", "t", OUT8, "n"), with = FALSE])
evb <- function(entity) { EVB$entity <- entity; EVB }
evp <- function(entity) { EVP$entity <- entity; EVP }
lgr <- function(q, key, by) league_rates(Pn, transform(q, lg_key = key), by = by)
rm(Px); invisible(gc())

# lineups: the first nine batters each team sent up (as matchup_build.R), from the cached PA rows
lineup <- P[order(gid, seq)][, .SD[!duplicated(batter)][1:9], by = .(gid, batteam), .SDcols = c("batter", "bathand")]
lineup[, slot := seq_len(.N), by = .(gid, batteam)]

game_rates <- function(S) {
  gs <- G[season == S, .(gid, Date, season, site, hometeam, visteam, sched = innings)]
  gs[, t := season_day(Date, season, as.data.frame(bounds))]
  L <- merge(lineup, gs, by = "gid")
  L[, b := as.integer(batteam == hometeam)]                         # batting team: 0 away, 1 home
  L <- L[!is.na(batter)]
  # pitchers each lineup can face: the opposing starter (col 0) and candidates (cols 1..K)
  sp_g <- st[, .(gid, f = pitteam, sp, sp_hand = ifelse(sp_hand %in% c("L", "R"), sp_hand, "R"))]
  L[, f := ifelse(b == 1L, visteam, hometeam)]
  L <- merge(L, sp_g, by = c("gid", "f"))
  pit <- rbind(L[!duplicated(L[, .(gid, f)]), .(gid, f, col = 0L, pitcher = sp, hand = sp_hand)],
               C[season == S, .(gid, f = team, col = k, pitcher, hand)])
  PR <- merge(L[, .(gid, f, b, slot, batter, bathand, Date, season, t, site)], pit, by = c("gid", "f"), allow.cartesian = TRUE)
  # batter rates vs each pitcher hand, per (batter, date)
  bq <- unique(L[, .(batter, bathand, Date, season, t)])
  q <- function(e, d) data.frame(entity = e, Date = d$Date, season = d$season, t = d$t)
  lgq <- data.frame(Date = bq$Date, season = bq$season, t = bq$t)
  ba <- asof_outcomes(evb(Pn$batter), q(bq$batter, bq), BAT_CFG)
  bk <- evb(paste(Pn$batter, Pn$pithand))
  lgs <- lgr(lgq, bq$bathand, "bathand")
  bvL <- shrunk_rates(ba, asof_outcomes(bk, q(paste(bq$batter, "L"), bq), BAT_CFG), BAT_CFG, lgs, lgr(lgq, paste(bq$bathand, "L"), c("bathand", "pithand")), K_SPLIT_BAT)
  bvR <- shrunk_rates(ba, asof_outcomes(bk, q(paste(bq$batter, "R"), bq), BAT_CFG), BAT_CFG, lgs, lgr(lgq, paste(bq$bathand, "R"), c("bathand", "pithand")), K_SPLIT_BAT)
  # pitcher rates vs each batter side, per (pitcher, hand, side, date)
  pq <- unique(PR[, .(pitcher, hand, bathand, Date, season, t)])
  lpq <- data.frame(Date = pq$Date, season = pq$season, t = pq$t)
  pa_ <- asof_outcomes(evp(Pxn$pitcher), q(pq$pitcher, pq), PIT_CFG)
  pv <- shrunk_rates(pa_, asof_outcomes(evp(paste(Pxn$pitcher, Pxn$bathand)), q(paste(pq$pitcher, pq$bathand), pq), PIT_CFG), PIT_CFG,
                     lgr(lpq, pq$hand, "pithand"), lgr(lpq, paste(pq$bathand, pq$hand), c("bathand", "pithand")), K_SPLIT_PIT)
  lpair <- lgr(lpq, paste(pq$bathand, pq$hand), c("bathand", "pithand"))
  ib <- match(paste(PR$batter, PR$Date), paste(bq$batter, bq$Date))
  ip <- match(paste(PR$pitcher, PR$hand, PR$bathand, PR$Date), paste(pq$pitcher, pq$hand, pq$bathand, pq$Date))
  bv <- bvL[ib, ] * (PR$hand == "L") + bvR[ib, ] * (PR$hand == "R")
  m <- log5(bv, pv[ip, ], as.matrix(lpair)[ip, ])
  f <- merge(data.frame(i = seq_len(nrow(PR)), season = PR$season, site = PR$site, bathand = PR$bathand), as.data.frame(PF),
             by = c("season", "site", "bathand"), all.x = TRUE)
  f <- as.matrix(f[order(f$i), paste0("pf_", OUT8)]); f[is.na(f)] <- 1
  m <- m * f; m <- m / rowSums(m)
  list(PR = PR, m = m)
}

# --- assemble one season's simulator inputs -------------------------------------------------------
build_season <- function(S) {
  t0 <- Sys.time()
  ST <- season_tables(S)
  gr <- game_rates(S)
  PR <- gr$PR; m <- gr$m
  gs <- G[season == S][order(Date, gid)]
  gs <- gs[gid %in% PR$gid]
  gs[, gi := seq_len(.N)]
  PR <- merge(PR[, i := .I], gs[, .(gid, gi)], by = "gid")
  hfac <- rbind(ST$af, ST$hf)
  # rates[g, b, slot, col, o]: col 1 starter first two passes, 2 starter third pass, 2 + k candidate k
  PM <- KMAX + 2L
  rates <- array(NA_real_, c(nrow(gs), 2, 9, PM, 8))
  put <- function(rows, colx, fac) {
    x <- m[rows$i, , drop = FALSE] * hfac[rows$b + 1L, ] * fac
    x <- x / rowSums(x)
    idx <- cbind(rep(rows$gi, 8), rep(rows$b + 1L, 8), rep(rows$slot, 8), rep(colx, 8), rep(1:8, each = nrow(rows)))
    rates[idx] <<- as.vector(x)
  }
  s0 <- PR[col == 0L]
  put(s0, 1L, matrix(ST$f12, nrow(s0), 8, byrow = TRUE))
  put(s0, 2L, matrix(ST$f3, nrow(s0), 8, byrow = TRUE))
  ck <- PR[col > 0L]
  put(ck, ck$col + 2L, 1)
  # missing slots (fewer than nine batters) and missing candidates: league-average rows, never reached
  lgm <- colMeans(m[s0$i, ])
  miss <- which(is.na(rates[, , , , 1]), arr.ind = TRUE)
  for (o in 1:8) rates[cbind(miss, o)] <- lgm[o] / sum(lgm)
  # candidates per fielding team: f index 0 = away team's pitchers, 1 = home team's
  cs <- merge(C[season == S], gs[, .(gid, gi, hometeam)], by = "gid")
  cs[, f := as.integer(team == hometeam)]
  fill <- function(v, def = 0) { a <- array(def, c(nrow(gs), 2, KMAX)); a[cbind(cs$gi, cs$f + 1L, cs$k)] <- v; a }
  cand <- list(n = { a <- matrix(0L, nrow(gs), 2); x <- cs[, .(n = max(k)), by = .(gi, f)]; a[cbind(x$gi, x$f + 1L)] <- x$n; a },
               pitcher = fill(cs$pitcher, NA_character_), handL = fill(as.integer(cs$hand == "L")),
               gm = fill(cs$gm), fin = fill(cs$fin), lmbf = fill(cs$lmbf), ss = fill(cs$ss), p1 = fill(cs$p1 / 10), p2 = fill(cs$p2 / 10),
               p3 = fill(cs$p3 / 10), b2b = fill(cs$b2b), lds = fill(cs$lds), n14 = fill(cs$n14), eff = fill(cs$eff, 1))
  sp <- merge(SP[season == S], gs[, .(gid, gi, hometeam)], by = "gid")
  sp[, f := as.integer(team == hometeam)]
  spa <- function(v) { a <- matrix(NA_real_, nrow(gs), 2); a[cbind(sp$gi, sp$f + 1L)] <- v; a }
  starter <- list(pitcher = { a <- matrix(NA_character_, nrow(gs), 2); a[cbind(sp$gi, sp$f + 1L)] <- sp$pitcher; a },
                  leash = spa(sp$leash), exp_bf = spa(sp$exp_bf), eff = spa(sp$eff))
  # batters: same side as each candidate (switch hitters never), for the choice model
  L9 <- unique(PR[col == 0L, .(gid, gi, b, slot, batter, bathand)])
  swg <- unique(X[season == S & bathand == "B", paste(gid, batter)])  # registered switch hitters (lineup-card fact)
  bs <- array(0L, c(nrow(gs), 2, 9)); bs[cbind(L9$gi, L9$b + 1L, L9$slot)] <- ifelse(paste(L9$gid, L9$batter) %in% swg, 2L, as.integer(L9$bathand == "L"))
  batter <- array(NA_character_, c(nrow(gs), 2, 9)); batter[cbind(L9$gi, L9$b + 1L, L9$slot)] <- L9$batter
  li <- LIT[[as.character(S)]]
  ans <- list(season = S, games = gs[, .(gi, gid, Date, season, site, visteam, hometeam, sched = innings, vruns, hruns)],
              rates = rates, cand = cand, starter = starter, batside = bs, batter = batter,
              tables = ST, li = li$li, we = li$we, hook = fit_hook(S), exit = fit_exit(S), choice = fit_choice(S),
              br = list(PB = PB_BR, BB = BB_BR, AB = AB_BR, RP = RP_BR), kmax = KMAX)
  saveRDS(ans, file.path(OUT, sprintf("inputs-%d.rds", S)))
  message(S, ": ", nrow(gs), " games, ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")
  invisible(NULL)
}

# actual appearances, for scoring the bullpen and hook forecasts (2016-2022 only)
saveRDS(list(app = APP[season >= 2016, .(gid, season, team = pitteam, pitcher, starter, bf, pitches)],
             cand = C[season >= 2016, .(gid, team, pitcher, k, n_app, n_rel, n_start)],
             team_games = TG[season >= 2016, .(gid, team, kprev)],
             starters = SP[season >= 2016, .(gid, team, pitcher, bf, exp_bf, leash)]),
        file.path(OUT, "actual.rds"))
args <- commandArgs(TRUE)
todo <- if (length(args)) as.integer(args) else TARGET
stopifnot(all(todo %in% TARGET))
for (S in todo) build_season(S)
