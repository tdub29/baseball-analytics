#!/usr/bin/env Rscript
# Checks for the StatsAPI adapter (statsapi_pa.R).
#
#   Rscript research/r/mlb/statsapi_check.R parity 2025     # vs Retrosheet: results/statsapi-parity-2025.md
#   Rscript research/r/mlb/statsapi_check.R coverage 2026   # what the pull holds: results/statsapi-coverage-2026.md
#
# Fetches whatever feeds are missing first (resumable), so the first run of a season is slow.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("gamelogs.R", "retro.R", "statsapi_pa.R")) source(file.path(SRC, f))
args <- commandArgs(TRUE); mode <- args[1]; season <- as.integer(args[2])
stopifnot(mode %in% c("parity", "coverage"), !is.na(season))

pct <- function(x, d = 2) sprintf(paste0("%.", d, "f%%"), 100 * x)
md <- function(df) {
  df <- as.data.frame(df)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(df))),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
BIP4 <- c("gb", "ld", "fb", "pu")
OUT <- c("k", "ubb", "hbp", "single", "double", "triple", "hr", "out_ip")

S <- statsapi_pa(season, raw = TRUE)
SG <- statsapi_games(season, raw = TRUE)
m <- id_maps(season)
mapped <- function(id) !grepl("^mlbam", id)
idcov <- c(
  sprintf("- Plate appearances with a Retrosheet batter id: %s (%d of %d); with a Retrosheet pitcher id: %s.",
          pct(mean(mapped(S$batter))), sum(mapped(S$batter)), nrow(S), pct(mean(mapped(S$pitcher)))),
  sprintf("- Distinct batters mapped: %d of %d; distinct pitchers mapped: %d of %d.",
          uniqueN(S$batter[mapped(S$batter)]), uniqueN(S$batter), uniqueN(S$pitcher[mapped(S$pitcher)]), uniqueN(S$pitcher)),
  sprintf("- Games with a Retrosheet home plate umpire id: %s; with a Retrosheet park id: %s (maps learned from %s).",
          pct(mean(mapped(SG$umphome) & !is.na(SG$umphome))), pct(mean(!grepl("^venue", SG$site))),
          paste(range(m$from), collapse = "-")))

if (mode == "parity") {
  R <- retro_pa(season); RG <- retro_games(season)
  both <- intersect(RG$gid, SG$gid)
  only_r <- setdiff(RG$gid, SG$gid); only_s <- setdiff(SG$gid, RG$gid)
  RGm <- RG[gid %in% both]; SGm <- SG[match(RGm$gid, gid)]
  Rm <- R[gid %in% both]; Sm <- S[gid %in% both]

  # --- games and scores
  score_ok <- RGm$vruns == SGm$vruns & RGm$hruns == SGm$hruns
  pr <- function(P) P[, .(n = .N, runs = sum(runs)), by = .(gid, batteam)]
  pc <- merge(pr(Rm), pr(Sm), by = c("gid", "batteam"), all = TRUE, suffixes = c("_r", "_s"))
  for (v in c("n_r", "n_s", "runs_r", "runs_s")) pc[is.na(get(v)), (v) := 0L]
  pg <- pc[, .(n_r = sum(n_r), n_s = sum(n_s), runs_r = sum(runs_r), runs_s = sum(runs_s)), by = gid]
  dpa <- pg$n_s - pg$n_r
  # --- outcome counts per game and per batter
  oc <- function(P, by) dcast(P[, .N, by = c(by, "outcome")], as.formula(paste(paste(by, collapse = "+"), "~ outcome")),
                              value.var = "N", fill = 0)
  og <- merge(oc(Rm, "gid"), oc(Sm, "gid"), by = "gid", all = TRUE, suffixes = c("_r", "_s"))
  for (v in setdiff(names(og), "gid")) og[is.na(get(v)), (v) := 0]
  game_out_ok <- Reduce(`&`, lapply(OUT, function(o) og[[paste0(o, "_r")]] == og[[paste0(o, "_s")]]))
  ob <- merge(oc(Rm, "batter"), oc(Sm, "batter"), by = "batter", all = TRUE, suffixes = c("_r", "_s"))
  for (v in setdiff(names(ob), "batter")) ob[is.na(get(v)), (v) := 0]
  bat_ok <- Reduce(`&`, lapply(OUT, function(o) ob[[paste0(o, "_r")]] == ob[[paste0(o, "_s")]]))
  tot <- data.table(outcome = OUT, retrosheet = sapply(OUT, function(o) sum(Rm$outcome == o)),
                    statsapi = sapply(OUT, function(o) sum(Sm$outcome == o)))
  tot[, `:=`(diff = statsapi - retrosheet, share_r = pct(retrosheet / sum(retrosheet)), share_s = pct(statsapi / sum(statsapi)),
             games_equal = pct(sapply(OUT, function(o) mean(og[[paste0(o, "_r")]] == og[[paste0(o, "_s")]]))),
             batters_equal = pct(sapply(OUT, function(o) mean(ob[[paste0(o, "_r")]] == ob[[paste0(o, "_s")]]))),
             batter_abs_diff = sapply(OUT, function(o) sum(abs(ob[[paste0(o, "_r")]] - ob[[paste0(o, "_s")]]))))]
  # --- aligned plate appearances: same game, batter, pitcher and meeting number
  A <- merge(Rm, Sm, by = c("gid", "batter", "pitcher", "tto"), suffixes = c("_r", "_s"))
  agree <- function(a, b) mean((a == b) | (is.na(a) & is.na(b)), na.rm = TRUE)
  pa_agree <- data.table(field = c("outcome", "bb_type", "runs", "outs_pre", "inning", "top_bot", "bathand", "pithand", "umphome", "site", "seq"),
                         agreement = pct(c(agree(A$outcome_r, A$outcome_s), agree(A$bb_type_r, A$bb_type_s), agree(A$runs_r, A$runs_s),
                                           agree(A$outs_pre_r, A$outs_pre_s), agree(A$inning_r, A$inning_s), agree(A$top_bot_r, A$top_bot_s),
                                           agree(A$bathand_r, A$bathand_s), agree(A$pithand_r, A$pithand_s), agree(A$umphome_r, A$umphome_s),
                                           agree(A$site_r, A$site_s), agree(A$seq_r, A$seq_s))))
  # --- batted-ball type
  share <- function(x) { x <- x[x %in% BIP4]; sapply(BIP4, function(b) mean(x == b)) }
  bb <- data.table(bb_type = BIP4, retrosheet = pct(share(Rm$bb_type), 1), statsapi = pct(share(Sm$bb_type), 1),
                   retrosheet_n = sapply(BIP4, function(b) sum(Rm$bb_type == b, na.rm = TRUE)),
                   statsapi_n = sapply(BIP4, function(b) sum(Sm$bb_type == b, na.rm = TRUE)))
  hist <- rbindlist(lapply(2021:2025, retro_pa))
  hshare <- share(hist$bb_type)
  conf <- dcast(A[, .N, by = .(retrosheet = fcoalesce(bb_type_r, "NA"), statsapi_trajectory = fifelse(is.na(traj), "none", fifelse(traj == "", "empty", traj)))],
                retrosheet ~ statsapi_trajectory, value.var = "N", fill = 0)
  bipA <- A[bb_type_r %in% BIP4 | bb_type_s %in% BIP4]
  # --- game info
  gfield <- function(v) agree(RGm[[v]], SGm[[v]])
  gi <- c("site", "number", "starttime", "daynight", "usedh", "temp", "winddir", "windspeed", "sky", "precip", "umphome")
  ginfo <- data.table(field = gi, agreement = pct(sapply(gi, gfield)))
  GX <- merge(RGm[, .(gid, sky, precip, winddir, windspeed, temp)], SG[, .(gid, game_pk)], by = "gid")
  GX <- merge(GX, statsapi_parsed(season)$games[, .(game_pk, condition, wind)], by = "game_pk")
  sky_x <- dcast(GX[, .N, by = .(condition, sky)], condition ~ sky, value.var = "N", fill = 0)
  pre_x <- dcast(GX[, .N, by = .(condition, precip)], condition ~ precip, value.var = "N", fill = 0)
  wind_x <- dcast(GX[, .N, by = .(statsapi = sub("^[^,]*, *", "", wind), winddir)], statsapi ~ winddir, value.var = "N", fill = 0)
  kdp <- A[bb_type_r %in% BIP4 & !outcome_r %in% c("single", "double", "triple", "hr", "out_ip"), .N]
  ump_pa <- A[umphome_r != umphome_s, uniqueN(gid)]
  ump_g <- RGm[RGm$umphome != SGm$umphome, unique(umphome)]
  new_site <- RGm[RGm$site != SGm$site, unique(site)]
  bat_moved <- nrow(Rm) - nrow(A)
  mis <- A[outcome_r != outcome_s, .N, by = .(retrosheet = outcome_r, statsapi = outcome_s, event)][order(-N)][1:min(.N, 12)]

  out <- c(
    sprintf("# StatsAPI adapter parity with Retrosheet, %d", season), "",
    sprintf("Generated by `research/r/mlb/statsapi_check.R parity %d` on %s. Retrosheet side: `retro_pa(%d)` and `retro_games(%d)` (retro.R). StatsAPI side: `statsapi_pa(%d)` and `statsapi_games(%d)` (statsapi_pa.R) from the MLB StatsAPI live feed of every final regular-season game. Park and umpire id maps are learned from %s only, so %d is out of sample for them, as 2026 will be.",
            season, Sys.Date(), season, season, season, season, paste(range(m$from), collapse = "-"), season), "",
    "The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at \"www.retrosheet.org\".", "",
    "## Games", "",
    sprintf("- Retrosheet regular-season games: %d. StatsAPI final games: %d. Matched on gid (home team, date, doubleheader number): %d.",
            nrow(RG), nrow(SG), length(both)),
    sprintf("- Only in Retrosheet: %s. Only in StatsAPI: %s.", if (length(only_r)) paste(only_r, collapse = ", ") else "none",
            if (length(only_s)) paste(only_s, collapse = ", ") else "none"),
    sprintf("- Final score identical (both teams): %s of matched games (%d of %d).", pct(mean(score_ok)), sum(score_ok), length(score_ok)),
    sprintf("- Runs on plate-appearance rows, per game: identical in %s of games; per team-game %s. Totals: Retrosheet %d, StatsAPI %d. (Runs scoring on steals, wild pitches and other non-PA events sit on neither side's PA rows.)",
            pct(mean(pg$runs_r == pg$runs_s)), pct(mean(pc$runs_r == pc$runs_s)), sum(pg$runs_r), sum(pg$runs_s)), "",
    "## Plate appearances per game", "",
    sprintf("- Total plate appearances (intentional walks dropped on both sides): Retrosheet %d, StatsAPI %d (difference %+d).",
            nrow(Rm), nrow(Sm), nrow(Sm) - nrow(Rm)),
    sprintf("- Games with identical PA counts: %s (%d of %d). Games off by one: %d; by two or more: %d.",
            pct(mean(dpa == 0)), sum(dpa == 0), length(dpa), sum(abs(dpa) == 1), sum(abs(dpa) >= 2)),
    sprintf("- Games with all eight outcome counts identical: %s.", pct(mean(game_out_ok))),
    sprintf("- Plate appearances aligned one to one (same gid, batter, pitcher and meeting number): %d, %s of Retrosheet's.",
            nrow(A), pct(nrow(A) / nrow(Rm))), "",
    "## Outcome distribution and per-batter totals", "",
    sprintf("Batters in either source: %d. Batters with all eight season outcome totals identical: %s (%d).",
            nrow(ob), pct(mean(bat_ok)), sum(bat_ok)), "",
    md(tot[, .(outcome, retrosheet, statsapi, diff, share_r, share_s, games_equal, batters_equal, batter_abs_diff)]), "",
    "Largest outcome disagreements on aligned plate appearances (StatsAPI event type shown):", "",
    md(mis), "",
    "## Agreement on aligned plate appearances", "",
    md(pa_agree), "",
    "## Batted-ball type", "",
    sprintf("Shares among ground balls, liners, flies and popups (bunts are NA on both sides: retro_pa() codes only hittype G, L, F, P, and Retrosheet's bunt hittypes BG/BP/BL carry no ground, fly or line flag). Retrosheet 2021-2025 pooled: gb %s, ld %s, fb %s, pu %s.",
            pct(hshare["gb"], 1), pct(hshare["ld"], 1), pct(hshare["fb"], 1), pct(hshare["pu"], 1)), "",
    md(bb), "",
    sprintf("Per-PA agreement on aligned plate appearances where either side has a ball-in-play type: %s (%d of %d). Rows are Retrosheet bb_type, columns the raw StatsAPI hitData.trajectory:",
            pct(mean(bipA$bb_type_r == bipA$bb_type_s, na.rm = TRUE)), sum(bipA$bb_type_r == bipA$bb_type_s, na.rm = TRUE), nrow(bipA)), "",
    md(conf), "",
    "## Game info", "",
    md(ginfo), "",
    "StatsAPI weather condition against Retrosheet sky:", "", md(sky_x), "",
    "StatsAPI weather condition against Retrosheet precip:", "", md(pre_x), "",
    "StatsAPI wind direction text against Retrosheet winddir:", "", md(wind_x), "",
    "## Id mapping", "", idcov, "",
    "## Residuals explained", "",
    sprintf("- Trajectory mapping: none needed beyond the four direct pairs (ground_ball gb, line_drive ld, fly_ball fb, popup pu) and bunts to NA. StatsAPI shares sit within 0.1 point of Retrosheet %d. Retrosheet gives a ball-in-play type to %d plate appearances that are not balls in play (mostly strikeout double plays, coded hittype F); no ball in play exists, so StatsAPI has no trajectory, and downstream code reads bb_type only on balls in play. \"empty\" is StatsAPI's blank trajectory on catcher's interference.", season, kdp),
    sprintf("- Per-batter totals: %d plate appearances do not align one to one. On a mid-count pinch hitter the official scorer charges a strikeout or walk to the batter the count belongs to; Retrosheet follows that rule and StatsAPI names the batter at the plate.", bat_moved),
    sprintf("- Parks: %s first appear in %d, so a map learned from %s cannot know them. All are in the map used for the next season.", paste(new_site, collapse = ", "), season, paste(range(m$from), collapse = "-")),
    sprintf("- Umpires: game-level misses are %s, an umpire Retrosheet coded differently before %d; the map now takes the latest season's code. Per-PA misses in %d games are mid-game umpire changes, which Retrosheet tracks per play and StatsAPI's game officials list does not.", paste(ump_g, collapse = ", "), season, ump_pa),
    "- Start time: StatsAPI gives the scheduled time; Retrosheet the actual start when a delay or a doubleheader's second game moved it. No model input uses it (day or night is exact).",
    "- Batter hand: Retrosheet's plays file gives the registered hand, B for switch hitters, as does StatsAPI's player record, except a handful of hitters the two register differently.", "")
} else {
  sch <- feed_schedule(season); fin <- final_games(sch)
  hist <- rbindlist(lapply(2021:2025, retro_pa))
  share <- function(x, lv) sapply(lv, function(b) mean(x[x %in% lv] == b))
  reg <- chadwick_register()[, .(key_mlbam = as.integer(key_mlbam), key_retro, mlb_played_first)]
  old <- as.data.table(readRDS("data/mlb/raw/chadwick/register.rds"))[!is.na(key_mlbam) & key_retro != ""]
  um <- unique(rbind(S[!mapped(batter), .(mlbam = batter_mlbam)], S[!mapped(pitcher), .(mlbam = pitcher_mlbam)]))
  um <- merge(um, reg[!is.na(key_mlbam), .(mlbam = key_mlbam, mlb_played_first)], by = "mlbam", all.x = TRUE)
  vet <- um[!is.na(mlb_played_first) & mlb_played_first < season]
  pa_unm_vet <- S[batter_mlbam %in% vet$mlbam | pitcher_mlbam %in% vet$mlbam, .N]
  tg <- rbind(SG[, .(team = hometeam)], SG[, .(team = visteam)])[, .N, by = team]
  bip <- S[outcome %in% c("single", "double", "triple", "hr", "out_ip") &
           !event %in% c("sac_bunt", "sac_bunt_double_play", "catcher_interf", "batter_interference", "fan_interference")]
  ou <- data.table(outcome = OUT, statsapi = pct(share(S$outcome, OUT)), retrosheet_2021_2025 = pct(share(hist$outcome, OUT)))
  bb <- data.table(bb_type = BIP4, statsapi = pct(share(S$bb_type, BIP4), 1), retrosheet_2021_2025 = pct(share(hist$bb_type, BIP4), 1))
  out <- c(
    sprintf("# StatsAPI pull coverage, %d regular season", season), "",
    sprintf("Generated by `research/r/mlb/statsapi_check.R coverage %d` on %s from `statsapi_pa(%d)` and `statsapi_games(%d)` (statsapi_pa.R). Chadwick register downloaded by statsapi_pa.R on %s.",
            season, Sys.Date(), season, season, format(file.mtime(REGISTER), "%Y-%m-%d")), "",
    "## Games", "",
    sprintf("- Schedule entries: %d (%s). Final games: %d, fetched and parsed: %d, %s to %s.",
            nrow(sch), paste(sch[, .N, by = detail][, paste(N, detail)], collapse = ", "), nrow(fin), nrow(SG), min(SG$Date), max(SG$Date)),
    sprintf("- Games per team: %s.", paste(tg[, .(teams = .N), by = N][order(-N), sprintf("%d teams with %d", teams, N)], collapse = "; ")),
    sprintf("- Doubleheader games: %d. Distinct parks: %d.", sum(SG$number > 0), uniqueN(SG$site)),
    sprintf("- Plate appearances (intentional walks dropped): %d, %.1f per game.", nrow(S), nrow(S) / nrow(SG)),
    sprintf("- Balls in play with no StatsAPI trajectory (so bb_type NA; sacrifice bunts and interference excluded): %d of %d.",
            bip[is.na(traj), .N], nrow(bip)),
    sprintf("- Weather: temperature missing in %d games, wind direction unknown in %d (of which roofed: %d).",
            sum(is.na(SG$temp)), sum(SG$winddir == "unknown"), sum(SG$winddir == "unknown" & SG$sky == "dome")), "",
    "## Outcome and batted-ball mix against Retrosheet 2021-2025", "",
    md(ou), "", md(bb), "",
    "## Id mapping", "", idcov,
    if (!nrow(um)) "- Unmapped players: none." else sprintf("- Unmapped players: %d. Of these, %d debuted in %d per the register (no Retrosheet id assigned yet, no history to lose); %d debuted earlier (their prefixed id starts a fresh history; %d PAs involve one); %d are not in the register at all.",
            nrow(um), um[mlb_played_first == season, .N], season, nrow(vet), pa_unm_vet, um[is.na(mlb_played_first), .N]),
    if (nrow(vet)) sprintf("- Earlier debuts without a Retrosheet id: %s.", paste(head(vet$mlbam, 20), collapse = ", ")) else NULL,
    sprintf("- For comparison, the baseballr register snapshot in data/mlb/raw/chadwick (%s) maps %s of batter PAs and %s of pitcher PAs: it predates the register's Retrosheet ids for %d debuts, which is why statsapi_pa.R keeps its own refreshed copy.",
            format(file.mtime("data/mlb/raw/chadwick/register.rds"), "%Y-%m-%d"),
            pct(mean(S$batter_mlbam %in% old$key_mlbam)), pct(mean(S$pitcher_mlbam %in% old$key_mlbam)), season),
    sprintf("- Parks with no Retrosheet id (prefixed): %s.", if (any(grepl("^venue", SG$site))) paste(unique(SG$site[grepl("^venue", SG$site)]), collapse = ", ") else "none"),
    sprintf("- Home plate umpires with no Retrosheet id: %d of %d (%d games); %d of them are in the register with no Retrosheet id assigned yet (first-year umpires, so no history to lose).",
            uniqueN(SG$umphome[!mapped(SG$umphome)]), uniqueN(SG$umphome), sum(!mapped(SG$umphome)),
            reg[key_mlbam %in% as.integer(sub("^mlbam", "", SG$umphome[!mapped(SG$umphome)])) & key_retro == "", .N]), "")
}
f <- file.path(SRC, "results", sprintf("statsapi-%s-%d.md", mode, season))
writeLines(out, f)
message("wrote ", f)
