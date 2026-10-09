#!/usr/bin/env Rscript
# Leakage tamper test for the matchup model (MODEL-CARD.md, section 5). For a cutoff D every outcome
# dated on or after D is shuffled among the rows dated on or after D (tamper.R: each plate
# appearance's outcome, batted-ball type, runs and outs before the play; each game's final score;
# reached-on-error counts per fielding team-game), then the features are rebuilt and the model rerun.
# Inputs that are as of the game leave every game dated up to D bit-identical; games after D move.
#
#   Rscript research/r/mlb/leakage_tamper.R          # runs every missing step in order, then compares
#   Rscript research/r/mlb/leakage_tamper.R <step>   # one step (to run the three builds side by side)
#
# Steps: build-none, build-2019, build-2024 (matchup_build.R); model-none, model-base-validation,
# model-base-test, model-2019, model-2024 (matchup_model.R). "none" leaves TAMPER_FROM unset and must
# reproduce features.rds and predictions-v2-validation.csv. "base" sets TAMPER_FROM past the data:
# nothing is shuffled, but dder is recomputed by der_gap() exactly as in the tampered runs, so base
# against a cutoff isolates the scramble. Every output stays in data/mlb/matchup (gitignored),
# including the model's own md files; the summary is research/r/mlb/results/leakage-tamper.md
# (aggregates only, no odds).
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
DIR <- "data/mlb/matchup"
CUTS <- c(`2019` = "2019-07-01", `2024` = "2024-07-01")   # mid-validation, mid-test; Mondays, so D opens a walk-forward week
MODE <- c(`2019` = "validation", `2024` = "test")
NEVER <- "2099-12-31"
fp <- function(...) file.path(DIR, sprintf(...))
st <- function(script, arg, out, ...) list(script = script, arg = arg, out = out, env = c(...))

STEPS <- list(
  `build-none` = st("matchup_build.R", character(0), fp("features-tamper-none.rds"), TAMPER_FROM = "", FEAT_OUT = fp("features-tamper-none.rds")),
  `model-none` = st("matchup_model.R", "validation", fp("predictions-tamper-none-validation.csv"), TAMPER_FROM = "",
                    FEAT_IN = fp("features-tamper-none.rds"), OUT_TAG = "-tamper-none"))
for (m in c("validation", "test"))
  STEPS[[paste0("model-base-", m)]] <- st("matchup_model.R", m, fp("predictions-tamper-base-%s.rds", m), TAMPER_FROM = NEVER,
                                          FEAT_IN = fp("features-tamper-none.rds"), OUT_TAG = "-tamper-base")
for (k in names(CUTS)) {
  STEPS[[paste0("build-", k)]] <- st("matchup_build.R", character(0), fp("features-tamper-%s.rds", k), TAMPER_FROM = CUTS[[k]],
                                     FEAT_OUT = fp("features-tamper-%s.rds", k))
  STEPS[[paste0("model-", k)]] <- st("matchup_model.R", MODE[[k]], fp("predictions-tamper-%s-%s.rds", k, MODE[[k]]), TAMPER_FROM = CUTS[[k]],
                                     FEAT_IN = fp("features-tamper-%s.rds", k), OUT_TAG = paste0("-tamper-", k))
}
# Participation test: every play and game dated on or after D removed (TRUNCATE_FROM), so who played after D,
# not just how it went, is gone; games before D must still be bit-identical.
for (k in names(CUTS)) {
  STEPS[[paste0("trunc-build-", k)]] <- st("matchup_build.R", character(0), fp("features-trunc-%s.rds", k), TAMPER_FROM = "", TRUNCATE_FROM = CUTS[[k]],
                                           FEAT_OUT = fp("features-trunc-%s.rds", k))
  STEPS[[paste0("trunc-model-", k)]] <- st("matchup_model.R", MODE[[k]], fp("predictions-trunc-%s-%s.rds", k, MODE[[k]]), TAMPER_FROM = "", TRUNCATE_FROM = CUTS[[k]],
                                           FEAT_IN = fp("features-trunc-%s.rds", k), OUT_TAG = paste0("-trunc-", k))
}
ORDER <- c("build-none", "build-2019", "build-2024", "model-none", "model-base-validation", "model-base-test", "model-2019", "model-2024",
           "trunc-build-2019", "trunc-build-2024", "trunc-model-2019", "trunc-model-2024")

run <- function(nm) {
  s <- STEPS[[nm]]; t0 <- Sys.time()
  old <- Sys.getenv(names(s$env), unset = NA, names = TRUE)
  do.call(Sys.setenv, as.list(s$env))
  on.exit(for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])))
  rc <- system2(file.path(R.home("bin"), "Rscript"), c(file.path(SRC, s$script), s$arg))
  if (rc != 0 || !file.exists(s$out)) stop(nm, " failed (exit ", rc, ")")
  if ("OUT_TAG" %in% names(s$env)) {                 # the model writes an md to results/; keep it local
    md <- file.path(SRC, "results", sprintf("matchup-model%s-%s.md", s$env[["OUT_TAG"]], s$arg))
    if (file.exists(md)) file.rename(md, file.path(DIR, basename(md)))
  }
  fwrite(data.table(step = nm, start = t0, end = Sys.time()), fp("tamper-steps.csv"), append = TRUE)
}

a <- commandArgs(TRUE)
if (length(a)) { if (!a[1] %in% names(STEPS)) stop("unknown step ", a[1]); run(a[1]); quit(save = "no") }
for (nm in ORDER) if (!file.exists(STEPS[[nm]]$out)) run(nm)

# --- compare -----------------------------------------------------------------------------------
rowdiff <- function(a, b) {                          # per row, largest absolute difference over columns; Inf if NA-ness or a label differs
  m <- numeric(nrow(a))
  for (c in names(a)) {
    x <- a[[c]]; y <- b[[c]]
    d <- if (is.numeric(x)) abs(as.numeric(x) - as.numeric(y)) else ifelse(x == y, 0, Inf)
    na <- is.na(x) | is.na(y); d[na] <- ifelse(is.na(x) & is.na(y), 0, Inf)[na]
    m <- pmax(m, d)
  }
  m
}
coldiff <- function(a, b, rows) vapply(names(a), function(c) max(rowdiff(a[rows, c, with = FALSE], b[rows, c, with = FALSE]), 0), 0)
fmt <- function(x) ifelse(x == 0, "0", formatC(x, format = "e", digits = 1))
pct <- function(x) sprintf("%.1f%%", 100 * x)
mdval <- function(f, pat) { x <- grep(pat, readLines(f), value = TRUE); if (length(x)) sub(paste0(".*", pat, " *"), "", sub("[.]$", "", x[1])) else "n/a" }

# no-op: TAMPER_FROM unset reproduces the frozen files
orig <- readRDS(file.path(DIR, "features.rds")); none <- readRDS(fp("features-tamper-none.rds"))
stopifnot(identical(names(orig), names(none)), nrow(orig) == nrow(none))
none_o <- none[match(orig$gid, none$gid)]
feat_eq <- vapply(names(orig), function(c) isTRUE(all.equal(orig[[c]], none_o[[c]])), TRUE)
feat_id <- identical(orig, none)
pref <- fread(file.path(DIR, "predictions-v2-validation.csv")); pnew <- fread(fp("predictions-tamper-none-validation.csv"))
stopifnot(identical(names(pref), names(pnew)), nrow(pref) == nrow(pnew))
pnew_o <- pnew[match(pref$gid, pnew$gid)]
pred_eq <- vapply(setdiff(names(pref), "p_close"), function(c) isTRUE(all.equal(pref[[c]], pnew_o[[c]])), TRUE)   # p_close: evaluation only, below
close_gain <- sum(is.na(pref$p_close)) - sum(is.na(pnew_o$p_close)); close_same <- max(abs(pref$p_close - pnew_o$p_close), 0, na.rm = TRUE)
pred_id <- identical(pref, pnew)
PC <- c("M1_runs_ratio", "M2_components", "M3_plus_team", "M4_plus_rest", "M5_plus_defense", "B_home", "C_team_only", "E_recency", "C_incumbent", "ENS")
base_v <- readRDS(fp("predictions-tamper-base-validation.rds"))
der_pred <- max(coldiff(pnew_o[match(base_v$gid, gid), PC, with = FALSE], base_v[, PC, with = FALSE], seq_len(nrow(base_v))))   # CSV 15 digits
ctx <- readRDS(file.path(DIR, "context.rds"))[, .(gid, dder)]
bi <- readRDS(fp("model-inputs-tamper-base-validation.rds"))
der_ctx <- max(abs(bi$dder - ctx$dder[match(bi$gid, ctx$gid)]))

# per cutoff: base (nothing shuffled) against the tampered run
IN <- c("d12", "d3", "dpen", "drd", "dder", "drest", "dmoved")
MW <- c("M1_runs_ratio", "M2_components", "M3_plus_team", "M4_plus_rest", "M5_plus_defense", "B_home", "C_team_only")
res <- lapply(names(CUTS), function(k) {
  D <- as.Date(CUTS[[k]]); m <- MODE[[k]]
  ft <- readRDS(fp("features-tamper-%s.rds", k)); stopifnot(setequal(ft$gid, none$gid), identical(names(ft), names(none)))
  ft <- ft[match(none$gid, gid)]
  fc <- setdiff(names(none), c("vruns", "hruns"))
  fd <- rowdiff(none[, ..fc], ft[, ..fc]); ld <- rowdiff(none[, .(vruns, hruns)], ft[, .(vruns, hruns)])
  a <- readRDS(fp("model-inputs-tamper-base-%s.rds", m)); b <- readRDS(fp("model-inputs-tamper-%s-%s.rds", k, m))
  j <- merge(a, b, by = c("gid", "Date"), suffixes = c("", ".t"))
  ina <- j[, c(IN, "y"), with = FALSE]; inb <- setnames(j[, paste0(c(IN, "y"), ".t"), with = FALSE], c(IN, "y"))
  pa <- readRDS(fp("predictions-tamper-base-%s.rds", m)); pb <- readRDS(fp("predictions-tamper-%s-%s.rds", k, m))
  jp <- merge(pa, pb, by = c("gid", "Date"), suffixes = c("", ".t"))
  ppa <- jp[, PC, with = FALSE]; ppb <- setnames(jp[, paste0(PC, ".t"), with = FALSE], PC)
  pre_p <- jp$Date <= D
  list(k = k, D = D, mode = m,
       f_pre = sum(none$Date <= D), f_pre_max = max(fd[none$Date <= D]), f_lab_max = max(ld[none$Date < D]),
       f_post = sum(none$Date > D), f_post_chg = mean(fd[none$Date > D] > 0),
       i_pre = sum(j$Date <= D), i_pre_max = coldiff(ina[, ..IN], inb[, ..IN], j$Date <= D), i_y_max = max(rowdiff(ina[j$Date < D, "y"], inb[j$Date < D, "y"])),
       i_post_chg = sapply(c("drd", "dder"), function(c) mean(rowdiff(ina[j$Date > D, c, with = FALSE], inb[j$Date > D, c, with = FALSE]) > 0)),
       p_pre = sum(pre_p), p_pre_max = coldiff(ppa, ppb, pre_p), p_strict_max = coldiff(ppa, ppb, jp$Date < D), p_onD = sum(jp$Date == D), p_post = sum(jp$Date > D),
       p_post_chg = mean(rowdiff(ppa[jp$Date > D, "M5_plus_defense"], ppb[jp$Date > D, "M5_plus_defense"]) > 0),
       p_post_max = max(rowdiff(ppa[jp$Date > D, "M5_plus_defense"], ppb[jp$Date > D, "M5_plus_defense"])),
       ens_w = c(base = mdval(fp("matchup-model-tamper-base-%s.md", m), "chosen on 2017-2019\\):"),
                 tamper = mdval(fp("matchup-model-tamper-%s-%s.md", k, m), "chosen on 2017-2019\\):")),
       best = c(base = mdval(fp("matchup-model-tamper-base-%s.md", m), "on 2017-2022 \\(validation\\):"),
                tamper = mdval(fp("matchup-model-tamper-%s-%s.md", k, m), "on 2017-2022 \\(validation\\):")))
})
names(res) <- names(CUTS)
verdict <- function(r) r$f_pre_max == 0 && r$f_lab_max == 0 && all(r$i_pre_max == 0) && r$i_y_max == 0 &&
  all(r$p_pre_max[MW] == 0) && r$f_post_chg > 0 && r$p_post_chg > 0
noop_ok <- all(feat_eq) && all(pred_eq)

# suspended games: Retrosheet dates each play on the day it was played and the game row on the day it started
for (f in c("windows.R", "retro.R")) source(file.path(SRC, f))
GG <- rbindlist(lapply(2015:2025, retro_games))
PS <- rbindlist(lapply(2015:2025, function(s) retro_pa(s)[, .(gid, Date, seq, batteam, batter)]))
SUS <- PS[, .(d0 = min(Date), d1 = max(Date), n_dates = uniqueN(Date)), by = gid][n_dates > 1]
# How many suspended-game lineups (first nine batters, as matchup_build.R reads them) take a batter whose
# first plate appearance came on the completion day.
sus_lu <- local({
  p <- PS[gid %in% SUS$gid][order(gid, seq)]
  lu <- function(x) x[, .SD[!duplicated(batter)][1:9], by = .(gid, batteam)][!is.na(batter), .(gid, batteam, batter)]
  full <- lu(p); early <- lu(p[SUS[, .(gid, d0)], on = "gid"][Date == d0])
  late <- full[!early, on = c("gid", "batteam", "batter")]
  list(n_lu = uniqueN(full[, .(gid, batteam)]), lu = uniqueN(late[, .(gid, batteam)]), games = uniqueN(late$gid))
})
rm(PS)
# The run margin drd counts each final score from the day the game started (matchup_model.R). Re-dating a suspended
# game's score to its completion day measures how far that reaches; v2 is frozen, so this is measured, not changed.
rd_gap <- local({
  F0 <- GG[!gid %in% SUS$gid & season >= 2017]
  rd <- function(G) {
    tm <- rbind(G[, .(team = hometeam, Date, season, margin = hruns - vruns)], G[, .(team = visteam, Date, season, margin = vruns - hruns)])
    b <- as.data.frame(tm[, .(start = min(Date), end = max(Date)), by = season]); tm[, t := season_day(Date, season, b)][, n := 1]
    x <- function(team) { q <- data.frame(entity = team, Date = F0$Date, season = F0$season, t = season_day(F0$Date, F0$season, b))
      s <- asof_decay(transform(as.data.frame(tm), entity = team), q, c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
    x(F0$hometeam) - x(F0$visteam)
  }
  G1 <- copy(GG); G1[SUS, on = "gid", Date := i.d1]
  d <- abs(rd(GG) - rd(G1)); te <- F0$season >= 2023
  list(n = nrow(F0), chg = sum(d > 1e-12), max = max(d), mean = mean(d), test_max = max(d[te]), test_mean = mean(d[te]))
})

# participation: truncated build and model against the untampered base, games strictly before D. A game suspended
# before D and finished on or after D loses its own later plays, so its lineup (the first nine batters in its plays)
# and everything built on it can differ; such games are reported apart, not hidden.
tr <- lapply(names(CUTS), function(k) {
  D <- as.Date(CUTS[[k]]); m <- MODE[[k]]; str <- SUS[d0 < D & d1 >= D]
  ft <- readRDS(fp("features-trunc-%s.rds", k)); pre <- none[Date < D]
  stopifnot(setequal(ft$gid, pre$gid), identical(names(ft), names(none)))
  ft <- ft[match(pre$gid, gid)]
  a <- readRDS(fp("model-inputs-tamper-base-%s.rds", m)); b <- readRDS(fp("model-inputs-trunc-%s-%s.rds", k, m))
  j <- merge(a[Date < D], b, by = c("gid", "Date"), suffixes = c("", ".t")); stopifnot(nrow(j) == nrow(b), nrow(j) == nrow(a[Date < D]))
  pa <- readRDS(fp("predictions-tamper-base-%s.rds", m)); pb <- readRDS(fp("predictions-trunc-%s-%s.rds", k, m))
  jp <- merge(pa[Date < D], pb, by = c("gid", "Date"), suffixes = c("", ".t")); jp <- jp[!is.na(M5_plus_defense)]
  fr <- rowdiff(pre, ft)
  ir <- rowdiff(j[, c(IN, "y"), with = FALSE], setnames(j[, paste0(c(IN, "y"), ".t"), with = FALSE], c(IN, "y")))
  pr <- rowdiff(jp[, MW, with = FALSE], setnames(jp[, paste0(MW, ".t"), with = FALSE], MW))
  ok <- function(g) !g %in% str$gid
  list(k = k, D = D, mode = m, str = str, f_n = nrow(pre), f_max = max(fr), f_max_x = max(fr[ok(pre$gid)]),
       i_n = nrow(j), i_max = max(ir), i_max_x = max(ir[ok(j$gid)]),
       p_n = nrow(jp), p_max = max(pr), p_max_x = max(pr[ok(jp$gid)]),
       bad = union(union(pre$gid[fr > 0], j$gid[ir > 0]), jp$gid[pr > 0]),
       p_str = jp[gid %in% str$gid, .(gid, base = M5_plus_defense, trunc = M5_plus_defense.t)])
})
tr_ok <- vapply(tr, function(r) r$f_max_x == 0 && r$i_max_x == 0 && r$p_max_x == 0, TRUE)
tr_exc <- unlist(lapply(tr, `[[`, "bad"))

tl <- if (file.exists(fp("tamper-steps.csv"))) fread(fp("tamper-steps.csv"))[, .SD[.N], by = step] else NULL
row <- function(...) paste0("| ", paste(..., sep = " | "), " |")
L <- c("# Leakage tamper test: matchup model M5 v2, 2017-2025 features", "",
  sprintf("Generated %s by `research/r/mlb/leakage_tamper.R`. Overall verdict: **%s**.", format(Sys.Date()),
          if (!(noop_ok && all(vapply(res, verdict, TRUE)) && all(tr_ok))) "FAIL"
          else if (length(tr_exc)) sprintf("PASS, with %d documented exception(s): suspended games straddling a truncation cutoff, see Participation test", length(tr_exc))
          else "PASS"), "",
  "## Method", "",
  "For a cutoff D, every outcome dated on or after D is shuffled among the rows dated on or after D, with fixed seeds",
  "(`tamper.R`): each plate appearance's outcome, batted-ball type, runs on the play and outs before it, jointly; each",
  "game's final score (away and home runs together); and the reached-on-error count of each fielding team-game, which",
  "`der_gap()` reads from the plays file for defensive efficiency. Game id, date, sequence, batter, pitcher, hands,",
  "teams, park, umpire and lineup stay. The features are rebuilt (`matchup_build.R`) and the model rerun",
  "(`matchup_model.R`), whose own inputs are tampered the same way: the team run margin `drd` from the shuffled",
  "scores and `dder` recomputed by `der_gap()` from the shuffled plays.",
  "Inputs that are as of the game must leave every game dated on or before D bit-identical to an untampered run;",
  "games after D must change, or the scramble did nothing. Both cutoffs are Mondays, so D's walk-forward week is",
  "fit on games before D and every prediction dated on or before D must also be identical.", "",
  "The untampered reference for a cutoff is the base run: `TAMPER_FROM` past the data, so nothing is shuffled but",
  "`dder` comes from `der_gap()` exactly as in the tampered runs. Differences are exact (absolute value of the",
  "difference of the stored doubles; 0 means bit-identical).", "",
  "## No-op proof (TAMPER_FROM unset)", "",
  sprintf("- Rebuilt features against `features.rds`: %d games, %d of %d columns equal under `all.equal`, `identical()` %s.",
          nrow(orig), sum(feat_eq), length(feat_eq), if (feat_id) "TRUE" else "FALSE"),
  sprintf("- Validation predictions against `predictions-v2-validation.csv`: %d games, %d of %d prediction and label columns equal under `all.equal`. The evaluation column `p_close` is not a model output: the frozen CSV predates the 2026-10-06 odds team-name fix (commit 6d2503c), so %d more games now carry a closing line, and every game priced in both agrees to %s.",
          nrow(pref), sum(pred_eq), length(pred_eq), close_gain, fmt(close_same)),
  sprintf("- `der_gap()` against `context.rds` (the frozen `dder`): max absolute difference %s on %d games; base predictions against the none run, every model column: %s (the CSV keeps 15 significant digits).",
          fmt(der_ctx), nrow(bi), fmt(der_pred)), "",
  "## Results by cutoff", "",
  row("cutoff D", "mode", "features: games on or before D", "max abs feature diff", "model inputs: max abs diff (d12 ... dder)",
      "predictions on or before D", "max abs diff M1-M5", "games after D: features changed", "after D: M5 changed", "verdict"),
  paste0("|", strrep(" --- |", 10)),
  vapply(res, function(r) row(r$D, r$mode, format(r$f_pre, big.mark = ","), fmt(r$f_pre_max), fmt(max(r$i_pre_max)),
                              format(r$p_pre, big.mark = ","), fmt(max(r$p_pre_max[MW])), pct(r$f_post_chg), pct(r$p_post_chg),
                              if (verdict(r)) "PASS" else "FAIL"), ""), "",
  "Detail:", "")
L <- c(L, "As first run (same outputs), the verdict read FAIL from two comparison errors, not leaks: the model-input check included the label y for games dated D, which the scramble shuffles by design, and the no-op check included `p_close`. Both are fixed in the comparison; no model, feature or tamper output changed.", "")
for (r in res) L <- c(L,
  sprintf("- D = %s (%s mode, base vs tampered): outcome labels (vruns, hruns) identical before D: max diff %s; model inputs on %d games on or before D, per column %s; outcome y before D: %s.",
          r$D, r$mode, fmt(r$f_lab_max), r$i_pre, paste(sprintf("%s %s", names(r$i_pre_max), fmt(r$i_pre_max)), collapse = ", "), fmt(r$i_y_max)),
  sprintf("  Predictions on or before D, per column: %s.", paste(sprintf("%s %s", names(r$p_pre_max), fmt(r$p_pre_max)), collapse = ", ")),
  sprintf("  Strictly before D: %s. The %d games dated D itself have shuffled final scores, which the E and C join key reads.", paste(sprintf("%s %s", names(r$p_strict_max), fmt(r$p_strict_max)), collapse = ", "), r$p_onD),
  sprintf("  After D: %s of %d games' features changed; drd changed for %s and dder for %s of model rows; M5 changed for %s of %d predictions (max abs %s).",
          pct(r$f_post_chg), r$f_post, pct(r$i_post_chg[["drd"]]), pct(r$i_post_chg[["dder"]]), pct(r$p_post_chg), r$p_post, fmt(r$p_post_max)),
  sprintf("  Ensemble weight on the best variant (chosen on 2017-2019): base %s, tampered %s. Best variant (chosen on 2017-2022): base %s, tampered %s.",
          r$ens_w[["base"]], r$ens_w[["tamper"]], r$best[["base"]], r$best[["tamper"]]))
L <- c(L, "",
  "## Participation test (truncation)", "",
  "The scramble keeps who played. This test removes it: every play and every game dated on or after D is dropped",
  "(`TRUNCATE_FROM`) before the build, before the model's own inputs (team run margin, rest and travel, `der_gap()`),",
  "and before the walk-forward. Starter length, bullpen usage, lineups and the schedule after D are then gone, not",
  "shuffled. Every game dated before D must match the untampered base run exactly. Games dated D are dropped too,",
  "because the actual-starter build reads the day's own starter from that game's plays.", "",
  "A suspended game is the one place the cut falls inside a game: Retrosheet dates the game row on the day it started",
  "and each play on the day it was played, so a game suspended before D and finished on or after D keeps its row but",
  "loses its own later plays. Its lineup (the first nine batters in its plays) and everything built on it can then",
  "differ. Those games are reported apart below, with both the all-games and the excluding-straddlers maxima.", "",
  row("cutoff D", "mode", "games before D", "straddling games", "max abs feature diff: all / excl.", "model inputs (d12 ... dder, y): all / excl.",
      "predictions", "max abs diff M1-M5: all / excl.", "verdict"),
  paste0("|", strrep(" --- |", 9)),
  vapply(seq_along(tr), function(i) { r <- tr[[i]]; row(r$D, r$mode, format(r$f_n, big.mark = ","), nrow(r$str),
                                                         paste(fmt(r$f_max), "/", fmt(r$f_max_x)), paste(fmt(r$i_max), "/", fmt(r$i_max_x)),
                                                         format(r$p_n, big.mark = ","), paste(fmt(r$p_max), "/", fmt(r$p_max_x)),
                                                         if (!tr_ok[i]) "FAIL" else if (length(r$bad)) "PASS excl. straddler" else "PASS") }, ""), "")
for (r in tr) if (nrow(r$str)) L <- c(L, sprintf("- D = %s: straddling %s; differing %s.%s", r$D,
  paste(sprintf("%s (started %s, finished %s)", r$str$gid, r$str$d0, r$str$d1), collapse = ", "),
  if (length(r$bad)) paste(r$bad, collapse = ", ") else "none",
  if (nrow(r$p_str)) paste0(" M5 home win probability, base against truncated: ", paste(sprintf("%s %.3f vs %.3f", r$p_str$gid, r$p_str$base, r$p_str$trunc), collapse = ", "), ".") else ""))
L <- c(L, "",
  "As first run, this comparison counted every game before D and read FAIL at 2024-07-01 on that one game. No other",
  "game moved by any amount, so no play-dated input leaked across D; the difference is the straddling game's own",
  "lineup read from its completion-day plays. That is an actual-lineup oracle property of the frozen v2 build,",
  "recorded under Limits, and the comparison now shows such games apart instead of hiding them. The truncated",
  "probability reflects a partial lineup (only the batters who came up on the start day), so it does not measure",
  "how much the oracle is worth. Truncation drops rows by their own date, so it cannot see facts stored on a game",
  "row dated at the start (the final score, the reached-on-error count); those are covered under Limits.", "",
  "## Every other input matchup_model.R reads", "",
  "- `context.rds` (`dder`): built from plate-appearance outcomes and reached-on-error counts, so it is not used under tamper; `der_gap()` recomputes it from the shuffled data (no-op proof above shows it reproduces the frozen file).",
  "- Team run margin `drd`: from Retrosheet final scores, shuffled with the game scores and decayed as of the day before each game.",
  "- Rest and travel (`drest`, `dmoved`): days since each team's previous game and whether the park changed. Schedule facts read backward only (`shift()` over each team's games in date order); no outcome enters.",
  "- Run values (`rv_fit`): fit on 2015-2016 team-games, before both cutoffs; fixed.",
  "- Recency model `E_recency` and incumbent `C_incumbent`: read from the frozen `results/recency/model-predictions-*.csv`, not regenerated here. They enter only the ensemble column `ENS` and the complete-case filter of the score tables, never M1-M5. E is a weekly walk-forward model with its own independent real-data tamper test (`RECENCY-PLAN.md`, iteration 8). Under tamper their join key, which matches StatsAPI games on date and final score, fails for most shuffled games after D, so after D the tampered run has fewer E rows; before D it is unchanged.",
  "- Odds (`market-joined.csv`): evaluation only, never a model input; joined after the predictions are made.",
  "- Inside the build: park factors and the batted-ball outcome mix use the three prior seasons, and every hitter, pitcher, league, starter-length and bullpen input is an as-of window; the tamper result above is the end-to-end check on all of them.", "",
  "## Limits", "",
  "- The scramble moves outcomes, not participation; the truncation test above covers participation by removing everything dated on or after D. Both tests run on the frozen v2 build (actual starters and lineups). The exploratory day-ahead, rotation and probable-starter builds share its as-of windows but were not rerun under either test.",
  "- `E_recency`, `C_incumbent` and `ENS` are outside both tests: E and C are frozen CSVs, and ENS blends them.",
  "- `ENS` is not part of M5. Its weight is chosen in sample on 2017-2019 and the best variant on 2017-2022 by design (`MATCHUP-PLAN.md`, iteration 5), so when D falls inside those seasons a tampered run may pick a different weight and `ENS` before D moves. That is a model-selection property recorded above, not a feature leak, but it makes validation-season scores for the best variant and ENS optimistic; only 2023-2025 is free of that selection.",
  sprintf("- Suspended games (%d in 2015-2025 have plays on two dates). The v2 lineup for such a game is its first nine batters across all its plays, so it can include a batter whose first plate appearance came on the completion day: %d of %d team-lineups in %d games do (some may be original starters who had not yet batted). v2 already reads actual lineups, so this extends a known oracle within the game. Separately, `drd` counts a suspended game's final score from the day it started: re-dating those scores to the completion day changes `drd` for %s of %s games in 2017-2025 by at most %.3f runs (mean over all games %.1e), and in the 2023-2025 test seasons by at most %.3f (mean %.1e). That look-ahead reaches other games, and the truncation test cannot see it, because the final score sits on the game row dated at the start.",
          nrow(SUS), sus_lu$lu, sus_lu$n_lu, sus_lu$games, format(rd_gap$chg, big.mark = ","), format(rd_gap$n, big.mark = ","), rd_gap$max, rd_gap$mean, rd_gap$test_max, rd_gap$test_mean),
  "- For the same reason, `der_gap()` (matchup.R) joins a game's whole reached-on-error count by game id onto each of its dated rows, so a suspended game's start-date row carries completion-day errors and the count is taken off both dates. BOS202406260 had none, so the truncation test does not exercise this path. Unmeasured beyond that game.",
  "- The day-ahead lineup build (matchup_build.R, `LINEUP_MODE = \"projected\"`) picks each source game by its start date and copies that game's full lineup, so completion-day batters of a suspended game can enter later games' projected lineups. Not tested and not measured; v2 itself uses actual lineups.",
  "- v2 is frozen, so all of the above are recorded, not fixed. The next pre-registered version should date suspended scores and errors on completion and take lineups from the start-day lineup card.",
  "- Two cutoffs and one seed per cutoff.",
  "- Independent review (2026-10-07) checked the comparison fixes above and the as-of boundaries: every window reads rows dated before the game (decayed sums on the day before, bullpen and lineup windows on earlier dates, weekly fits on earlier weeks).", "")
if (!is.null(tl)) L <- c(L, "## Runtime", "",
  sprintf("Logged steps, minutes each (steps in a group ran side by side, on different days per group): %s.",
          paste(sprintf("%s %.0f", tl$step, as.numeric(difftime(tl$end, tl$start, units = "mins"))), collapse = ", ")), "")
L <- c(L, "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(L, file.path(SRC, "results", "leakage-tamper.md"))
message("wrote ", file.path(SRC, "results", "leakage-tamper.md"))
