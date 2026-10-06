#!/usr/bin/env Rscript
# Scores the 2026 forward test once, under the rules fixed in FORWARD-PLAN.md.
#
#   Rscript research/r/mlb/forward_score.R            # as-run: writes results/forward-test-2026.md, once
#   FORCE=1 OUT=forward-test-2026-corrected.md Rscript research/r/mlb/forward_score.R
#                                                     # a corrected run, next to the as-run report
#
# Reads the walk-forward 2026 predictions written by `matchup_model.R forward` (OUT_TAG -v2,
# -v2-dayahead, -v4) and `FORWARD=1 sabr_baseline.R`, all under data/mlb/matchup/ (local only).
# Each matchup file carries its frozen best variant (chosen on 2017-2022) in the `best` column.
# All four files must match the sha256 recorded in FORWARD-PLAN.md, and the model code must be
# committed, so the scored files are tied to frozen code. Differences are baseline minus model per
# game, so positive means the model is better; 95% intervals resample home teams (1,000 draws,
# seed 20261005).

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
asrun <- file.path(SRC, "results", "forward-test-2026.md")
if (Sys.getenv("FORCE") != "1") {
  if (Sys.getenv("OUT") != "") stop("OUT is only for a corrected run (FORCE=1); the as-run report is always ", asrun)
  if (file.exists(asrun)) stop(asrun, " exists: the forward test is scored once")
  out_md <- asrun
} else {
  out_md <- file.path(SRC, "results", Sys.getenv("OUT"))
  if (!file.exists(asrun)) stop("FORCE=1 publishes a corrected run next to the as-run report, and ", asrun, " does not exist")
  if (Sys.getenv("OUT") == "" || normalizePath(out_md, mustWork = FALSE) == normalizePath(asrun)) stop("FORCE=1 needs OUT set to a new file name")
  if (file.exists(out_md)) stop(out_md, " exists")
}
git <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE), error = function(e) "unknown")
dirty <- git("status", "--porcelain", "--", file.path(SRC, "*.R"), file.path(SRC, "FORWARD-PLAN.md"))
if (length(dirty) || !is.null(attr(dirty, "status"))) stop("commit the model code and FORWARD-PLAN.md before scoring: ", paste(trimws(dirty), collapse = "; "))
plan <- readLines(file.path(SRC, "FORWARD-PLAN.md"), warn = FALSE)
hashes <- vapply(c("predictions-v2-forward.csv", "predictions-v2-dayahead-forward.csv", "predictions-v4-forward.csv",
                   "sabr-predictions-forward.csv"), function(f) {
  h <- as.character(openssl::sha256(file(file.path("data/mlb/matchup", f))))
  rec <- regmatches(plan, regexpr("[0-9a-f]{64}", plan))[grepl(paste0("`", f, "` sha256"), plan[grepl("[0-9a-f]{64}", plan)], fixed = TRUE)]
  if (length(rec) != 1 || rec != h) stop(f, " sha256 ", h, " does not match the one recorded in FORWARD-PLAN.md")
  h }, "")
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lgt <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261005)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }

rd <- function(f) { x <- fread(file.path("data/mlb/matchup", f)); stopifnot(all(x$season == 2026), !anyDuplicated(x$gid)); x }
mm <- function(tag) {
  f <- sprintf("predictions%s-forward.csv", tag)
  x <- rd(f); b <- unique(x$best); stopifnot(length(b) == 1)
  list(x = x, best = b, file = f)
}
v2 <- mm("-v2"); da <- mm("-v2-dayahead"); v4 <- mm("-v4"); s4 <- rd("sabr-predictions-forward.csv")
P <- v2$x[, .(gid, y, B_home, C_team_only, v2 = get(v2$best))]
P <- merge(P, da$x[, .(gid, y_da = y, v2_dayahead = get(da$best))], by = "gid")
P <- merge(P, v4$x[, .(gid, y_v4 = y, v4 = get(v4$best))], by = "gid")
P <- merge(P, s4[, .(gid, y_s4 = y, S4 = S4_plus_team)], by = "gid")
stopifnot(P$y == P$y_da, P$y == P$y_s4, P$y == P$y_v4)
models <- c("v2", "v2_dayahead", "v4"); bases <- c("B_home", "C_team_only", "S4")
n_all <- c(v2 = nrow(v2$x), v2_dayahead = nrow(da$x), v4 = nrow(v4$x), S4 = nrow(s4))
P <- P[complete.cases(P[, c(models, bases), with = FALSE])]
cl <- substr(P$gid, 1, 3)                                  # home team (one season)

met <- rbindlist(lapply(c(models, bases), function(m) {
  p <- P[[m]]; sl <- stats::coef(stats::glm(P$y ~ lgt(p), stats::binomial))[2]
  data.table(model = m, log_loss = fmt(mean(ll(p, P$y))), brier = fmt(mean((p - P$y)^2)), accuracy = fmt(mean((p > 0.5) == (P$y == 1)), 3), slope = fmt(sl, 3))
}))
cmp <- rbindlist(c(
  lapply(models, function(m) rbindlist(lapply(bases, function(b) { g <- paired(ll(P[[b]], P$y) - ll(P[[m]], P$y), cl)
    data.table(model = m, baseline = b, d = g[1], lo = g[2], hi = g[3]) }))),
  list({ g <- paired(ll(P$v2, P$y) - ll(P$v4, P$y), cl); data.table(model = "v4", baseline = "v2", d = g[1], lo = g[2], hi = g[3]) })))
cmp[, verdict := fifelse(lo > 0, "model better", fifelse(hi < 0, "baseline better", "no detectable difference"))]

sha <- git("rev-parse", "--short", "HEAD")
lines <- c("# 2026 forward test: scored once", "",
  sprintf("Scored %s at commit %s under FORWARD-PLAN.md. %s", format(Sys.time(), "%Y-%m-%d %H:%M"), sha,
          if (out_md == asrun) "As-run report." else "Corrected run; the as-run report is forward-test-2026.md."), "",
  "Prediction files (sha256, as recorded in FORWARD-PLAN.md before scoring):", "",
  sprintf("- `%s` `%s`", names(hashes), hashes), "",
  sprintf("Games scored: %d of 2026 with a prediction from every model (files: v2 %s, v2 day-ahead %s, v4 %s, S4 %s).", nrow(P),
          n_all[["v2"]], n_all[["v2_dayahead"]], n_all[["v4"]], n_all[["S4"]]),
  sprintf("Frozen best variants: v2 %s, v2 day-ahead %s, v4 %s.", v2$best, da$best, v4$best), "",
  "## Outcomes (lower log loss and Brier are better; slope 1 = calibrated)", "",
  "| model | log loss | Brier | accuracy at 50% | calibration slope |", "| --- | --- | --- | --- | --- |",
  met[, sprintf("| %s | %s | %s | %s | %s |", model, log_loss, brier, accuracy, slope)], "",
  "## Paired comparisons (baseline minus model per game; positive = model better)", "",
  "| model | vs | difference | 95% interval | verdict |", "| --- | --- | --- | --- | --- |",
  cmp[, sprintf("| %s | %s | %s | [%s, %s] | %s |", model, baseline, fmt(d, 5), fmt(lo, 5), fmt(hi, 5), verdict)], "",
  "Intervals resample the 30 home teams (1,000 draws, seed 20261005). No odds: the 2026 test is scored on outcomes only.",
  "v4 replaces v2 as the default only if the v4 vs v2 interval lies above zero.", "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.",
  "2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.")
writeLines(lines, out_md)
message(paste(lines, collapse = "\n"))
