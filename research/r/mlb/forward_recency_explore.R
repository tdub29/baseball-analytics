#!/usr/bin/env Rscript
# Exploratory, post hoc: scores the recency model E and the M5 + E ensemble on the 2026 games that
# the forward test (forward_score.R, FORWARD-PLAN.md) scored without them. Changes no model,
# threshold, recipe or verdict; the forward test and its report stay as run.
#
#   Rscript research/r/mlb/recency_model.R forward      # writes results/recency/model-predictions-forward.csv
#   Rscript research/r/mlb/forward_recency_explore.R    # writes results/forward-2026-recency-explore.md
#
# Same loss, same per-game difference (baseline minus model, positive = model better) and the same
# home-team bootstrap (1,000 draws, seed 20261005) as forward_score.R. The ensemble weight is
# re-derived on 2017-2019 exactly as matchup_model.R does and must equal the frozen 0.55.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
MD  <- "data/mlb/matchup"
out_md <- file.path(SRC, "results", "forward-2026-recency-explore.md")

ll  <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lgt <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261005)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
sha <- function(p) as.character(openssl::sha256(file(p)))

# the forward-test inputs, checked against the hashes recorded before scoring
plan <- readLines(file.path(SRC, "FORWARD-PLAN.md"), warn = FALSE)
for (f in c("predictions-v2-forward.csv", "sabr-predictions-forward.csv")) {
  rec <- regmatches(plan, regexpr("[0-9a-f]{64}", plan))[grepl(paste0("`", f, "` sha256"), plan[grepl("[0-9a-f]{64}", plan)], fixed = TRUE)]
  if (length(rec) != 1 || rec != sha(file.path(MD, f))) stop(f, " does not match the sha256 in FORWARD-PLAN.md")
}
v2 <- fread(file.path(MD, "predictions-v2-forward.csv")); bv <- unique(v2$best); stopifnot(length(bv) == 1)
s4 <- fread(file.path(MD, "sabr-predictions-forward.csv"))
rec_path <- file.path(SRC, "results", "recency", "model-predictions-forward.csv")
rec <- fread(rec_path)

# ensemble weight: same grid, same 2017-2019 games, same rule as matchup_model.R
val <- fread(file.path(MD, "predictions-v2-validation.csv"))[season %in% 2017:2019 & !is.na(E_recency) & !is.na(get(bv))]
wgrid <- seq(0, 1, 0.05)
ens_w <- wgrid[which.min(vapply(wgrid, function(w) mean(ll(stats::plogis(w * lgt(val[[bv]]) + (1 - w) * lgt(val$E_recency)), val$y)), 0))]
stopifnot(isTRUE(all.equal(ens_w, 0.55)))                       # MODEL-CARD.md: weight 0.55 on M5

# reproduction: the forward run's 2021-2025 rows against the committed test predictions
old <- fread(file.path(SRC, "results", "recency", "model-predictions-test.csv"))
new <- rec[season %in% 2021:2025][match(old$game_pk, game_pk)]
stopifnot(nrow(new) == nrow(old), !anyNA(new$game_pk), all(new$y == old$y))
tiers <- c("B", "C", "D", "E0", "E")
repro <- rbindlist(lapply(tiers, function(m) data.table(tier = m, exact = sum(new[[m]] == old[[m]]),
  max_abs = max(abs(new[[m]] - old[[m]])), ll_new = mean(ll(new[[m]], new$y)), ll_old = mean(ll(old[[m]], old$y)))))

# 2026: one row per game, joined on game_pk
P <- v2[, .(gid, game_pk, y, B_home, C_team_only, v2 = get(bv))]
P <- merge(P, rec[season == 2026, .(game_pk, y_e = y, E)], by = "game_pk")
P <- merge(P, s4[, .(gid, y_s4 = y, S4 = S4_plus_team)], by = "gid")
stopifnot(P$y == P$y_e, P$y == P$y_s4, !anyNA(P$E))
P[, ENS := stats::plogis(ens_w * lgt(v2) + (1 - ens_w) * lgt(E))]
models <- c("v2", "E", "ENS"); bases <- c("B_home", "C_team_only", "S4")
P <- P[complete.cases(P[, c(models, bases), with = FALSE])]
cl <- substr(P$gid, 1, 3)                                         # home team (one season)

met <- rbindlist(lapply(c(models, bases), function(m) {
  p <- P[[m]]; sl <- stats::coef(stats::glm(P$y ~ lgt(p), stats::binomial))[2]
  data.table(model = m, log_loss = fmt(mean(ll(p, P$y))), brier = fmt(mean((p - P$y)^2)), accuracy = fmt(mean((p > 0.5) == (P$y == 1)), 3), slope = fmt(sl, 3))
}))
pair <- function(m, b) { g <- paired(ll(P[[b]], P$y) - ll(P[[m]], P$y), cl); data.table(model = m, baseline = b, d = g[1], lo = g[2], hi = g[3]) }
cmp <- rbindlist(c(list(pair("v2", "E"), pair("ENS", "v2"), pair("ENS", "E")),
                   lapply(c("E", "ENS"), function(m) rbindlist(lapply(bases, function(b) pair(m, b))))))
cmp[, reading := fifelse(lo > 0, "model better", fifelse(hi < 0, "baseline better", "no detectable difference"))]
lv2 <- mean(ll(P$v2, P$y)); lE <- mean(ll(P$E, P$y))

lines <- c("# 2026: recency model E and the M5 + E ensemble (exploratory, post hoc)", "",
  "**Exploratory and post hoc.** E and the ensemble were not in FORWARD-PLAN.md, and this file was produced after",
  "the forward test was scored (forward-test-2026.md). No result here changes any model, threshold, recipe or",
  "verdict, and it does not settle the MODEL-CARD.md trigger \"M5 fails to beat E's log loss in the next held-out",
  "season\": that check stays unchecked for 2026 and carries to 2027 as the card says.", "",
  sprintf("Generated %s by `Rscript research/r/mlb/forward_recency_explore.R`, after `Rscript research/r/mlb/recency_model.R forward`.",
          format(Sys.Date())), "",
  "## How E and the ensemble were produced", "",
  "- E is the frozen recency spec, unchanged: windows from `results/recency/picks-validation.csv` and",
  "  `grid-validation.csv`, the same six home-minus-away gaps (lineup, starter, bullpen, fatigue over 1 and 3 days,",
  "  run margin per game), and the same weekly walk-forward refit on every game from 2016 dated before each Monday.",
  "  The only change is the data range: 2015-2026 loaded, 2021-2026 predicted, 2026 StatsAPI game logs fetched",
  "  key-free into the existing cache.",
  sprintf("- The ensemble is the logit blend `plogis(w * logit(M5) + (1 - w) * logit(E))` with w = %s, re-derived on", ens_w),
  "  2017-2019 by the matchup_model.R rule and equal to the frozen weight in MODEL-CARD.md.",
  sprintf("- M5 is the forward test's v2 file (`%s`, sha256 matches FORWARD-PLAN.md), best variant %s.", "predictions-v2-forward.csv", bv),
  sprintf("- E predictions: `results/recency/model-predictions-forward.csv` (sha256 `%s`).", sha(rec_path)), "",
  "## Reproduction check (2021-2025 rows of the forward run vs the committed test predictions)", "",
  "| tier | games | exactly equal | max abs difference | log loss, forward run | log loss, committed |", "| --- | --- | --- | --- | --- | --- |",
  repro[, sprintf("| %s | %d | %d | %.1e | %s | %s |", tier, nrow(old), exact, max_abs, fmt(ll_new, 6), fmt(ll_old, 6))], "",
  "The committed test predictions (commit 2b4b366) predate the asof_decay precision fix (a0ac7df). A rerun of the",
  "test spec with the pre-fix windows.R reproduces the committed file exactly, and a rerun with the current code",
  "matches the forward run's 2021-2025 rows exactly, so adding 2026 rows changes no earlier prediction and the",
  "differences above are the precision fix alone.", "",
  sprintf("## 2026 outcomes (%d games; lower log loss and Brier are better; slope 1 = calibrated)", nrow(P)), "",
  "| model | log loss | Brier | accuracy at 50% | calibration slope |", "| --- | --- | --- | --- | --- |",
  met[, sprintf("| %s | %s | %s | %s | %s |", model, log_loss, brier, accuracy, slope)], "",
  "v2 is M5 (the matchup model), E the recency model, ENS the ensemble; B_home, C_team_only and S4 are the forward",
  "test's baselines, as scored there.", "",
  "## Paired comparisons (baseline minus model per game; positive = model better)", "",
  "| model | vs | difference | 95% interval | reading |", "| --- | --- | --- | --- | --- |",
  cmp[, sprintf("| %s | %s | %s | [%s, %s] | %s |", model, baseline, fmt(d, 5), fmt(lo, 5), fmt(hi, 5), reading)], "",
  "Intervals resample the 30 home teams (1,000 draws, seed 20261005), as in forward_score.R. No odds are used.", "",
  sprintf("Descriptively, M5's 2026 log loss was %s E's (%s vs %s). One post hoc season; not a verdict.",
          if (lv2 < lE) "below" else if (lv2 > lE) "above" else "equal to", fmt(lv2), fmt(lE)), "",
  "## Caveats", "",
  "- Decision time is first pitch, as in the 2021-2025 test and v2: the starter is StatsAPI's probable pitcher,",
  "  which in history is the man who started, and the lineup is the posted starting nine.",
  "- Every E input uses only games dated before the game's date (as-of rule in windows.R); park factors for 2026",
  "  come from 2023-2025, and a venue with no prior history gets a factor of 1. Same-day doubleheader games do",
  "  not see each other. A suspended game keeps its official (original) date, so innings played on resumption",
  "  count from that date, as in the 2021-2025 test.",
  "- The 2026 schedule has 2,429 final games, all with both posted lineups; 2 are missing a probable starter",
  "  and use league rates for it, the frozen rule for an unknown starter.",
  "- The bullpen term weights relievers by relief batters faced in the last 21 days only, as frozen.", "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.",
  "2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.")
writeLines(lines, out_md)
message(paste(lines, collapse = "\n"))
