#!/usr/bin/env Rscript
# Recomputes the independent post-scoring review checks of the 2026 forward test (FORWARD-PLAN.md,
# 2026-10-06 review entry; REPORT.md section 9; MODEL-CARD.md) from committed code.
#
#   Rscript research/r/mlb/review_checks.R            # writes results/review-checks-2026.md, nothing else
#
# Exploratory: computed after scoring. It changes no number, threshold or verdict; the as-run report
# (results/forward-test-2026.md) and the pre-registered home-team intervals decide. Read-only on every
# other file: it reads the four scored 2026 prediction files (sha256 checked against FORWARD-PLAN.md,
# as forward_score.R), predictions-v2-test.csv, predictions-v2-validation.csv and
# sabr-predictions-validation.csv, all under data/mlb/matchup/ (local only). No odds are read.
# Conventions as forward_score.R: baseline minus model per game, positive = model better; every
# resample is 1,000 draws at seed 20261005. Published values below are copied from the docs named.
# The notes section diagnoses each DIFFER row; it reruns some resamples at five other seeds (SEEDS),
# for diagnosis only.

suppressPackageStartupMessages({ library(data.table) })
t0 <- Sys.time()
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
out_md <- file.path(SRC, "results", "review-checks-2026.md")
git <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE), error = function(e) "unknown")
plan <- readLines(file.path(SRC, "FORWARD-PLAN.md"), warn = FALSE)
for (f in c("predictions-v2-forward.csv", "predictions-v2-dayahead-forward.csv", "predictions-v4-forward.csv",
            "sabr-predictions-forward.csv")) {
  h <- as.character(openssl::sha256(file(file.path("data/mlb/matchup", f))))
  rec <- regmatches(plan, regexpr("[0-9a-f]{64}", plan))[grepl(paste0("`", f, "` sha256"), plan[grepl("[0-9a-f]{64}", plan)], fixed = TRUE)]
  if (length(rec) != 1 || rec != h) stop(f, " sha256 ", h, " does not match the one recorded in FORWARD-PLAN.md")
}
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
lgt <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
sg <- function(x, d = 4) sprintf(paste0("%+.", d, "f"), x)
ci <- function(lo, hi, f = sg) sprintf("[%s, %s]", f(lo), f(hi))
boot <- function(d, cl, seed = 20261005) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(seed)   # forward_score.R's draws
  replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }) }
qn <- function(b) as.numeric(stats::quantile(b, c(.025, .975)))
SEEDS <- c(1, 42, 2026, 20261004, 20261006)                # seed sensitivity beside 20261005, notes only
rng <- function(m, i, f = sg) sprintf("%s to %s", f(min(m[i, ])), f(max(m[i, ])))
inside <- function(m, lo, hi, d = 4) round(min(m[1, ]), d) <= lo & lo <= round(max(m[1, ]), d) & round(min(m[2, ]), d) <= hi & hi <= round(max(m[2, ]), d)
verdict <- function(lo, hi) fifelse(lo > 0, "model better", fifelse(hi < 0, "baseline better", "no detectable difference"))
mt <- function(ok) fifelse(ok, "MATCH", "DIFFER")

# --- the scored 2026 table, loaded exactly as forward_score.R (plus Date) ---------------------------
rd <- function(f) { x <- fread(file.path("data/mlb/matchup", f)); stopifnot(all(x$season == 2026), !anyDuplicated(x$gid)); x }
mm <- function(tag) { x <- rd(sprintf("predictions%s-forward.csv", tag)); b <- unique(x$best); stopifnot(length(b) == 1); list(x = x, best = b) }
v2 <- mm("-v2"); da <- mm("-v2-dayahead"); v4 <- mm("-v4"); s4 <- rd("sabr-predictions-forward.csv")
P <- v2$x[, .(gid, Date = as.Date(Date), y, B_home, C_team_only, v2 = get(v2$best))]
P <- merge(P, da$x[, .(gid, y_da = y, v2_dayahead = get(da$best))], by = "gid")
P <- merge(P, v4$x[, .(gid, y_v4 = y, v4 = get(v4$best))], by = "gid")
P <- merge(P, s4[, .(gid, y_s4 = y, S4 = S4_plus_team)], by = "gid")
stopifnot(P$y == P$y_da, P$y == P$y_s4, P$y == P$y_v4)
models <- c("v2", "v2_dayahead", "v4"); bases <- c("B_home", "C_team_only", "S4")
P <- P[complete.cases(P[, c(models, bases), with = FALSE])]
cl <- substr(P$gid, 1, 3)                                  # home team (one season), the pre-registered cluster
wk <- as.Date(cut(P$Date, "week"))                         # Monday weeks, the refit and ROI-block week of matchup_model.R
G <- length(unique(cl)); stopifnot(nrow(P) == 2429, G == 30)

# --- the ten comparisons under three resamples ------------------------------------------------------
cmp <- data.table(model = c(rep(models, each = 3), "v4"), baseline = c(rep(bases, 3), "v2"))
z <- stats::qnorm(.975); tq <- stats::qt(.975, G - 1)
cmp <- cmp[, {
  d <- ll(P[[baseline]], P$y) - ll(P[[model]], P$y); h <- boot(d, cl); g <- boot(d, P$gid); w <- boot(d, wk)
  q <- function(b) as.numeric(stats::quantile(b, c(.025, .975)))
  .(est = mean(d), se = stats::sd(h), h_lo = q(h)[1], h_hi = q(h)[2], g_lo = q(g)[1], g_hi = q(g)[2], w_lo = q(w)[1], w_hi = q(w)[2])
}, by = .(model, baseline)]
cmp[, `:=`(v_h = verdict(h_lo, h_hi), t_lo = est - tq * se, t_hi = est + tq * se,
           p = 2 * stats::pnorm(-abs(est / se)))]
cmp[, `:=`(v_t = verdict(t_lo, t_hi), v_g = verdict(g_lo, g_hi), v_w = verdict(w_lo, w_hi), holm = stats::p.adjust(p, "holm"))]
ft <- readLines(file.path(SRC, "results", "forward-test-2026.md"), warn = FALSE)            # as-run intervals, read only
pub <- rbindlist(lapply(strsplit(grep("^\\| (v2|v2_dayahead|v4) \\| (B_home|C_team_only|S4|v2) \\|", ft, value = TRUE), " *\\| *"),
  function(x) data.table(model = x[2], baseline = x[3], pub_d = x[4], pub_ci = x[5], pub_v = x[6])))
cmp <- merge(cmp, pub, by = c("model", "baseline"), sort = FALSE)
cmp[, rec_ci := ci(h_lo, h_hi, function(x) fmt(x, 5))]
stopifnot(nrow(cmp) == 10)
row <- function(m, b) cmp[model == m & baseline == b]

# --- 1. power to detect the earlier edges (two-sided 5% z test, SE = SD of the home-team draws) -----
TV <- fread("data/mlb/matchup/predictions-v2-test.csv")     # 2023-2025, the frozen test table's complete cases
TV <- TV[complete.cases(TV[, setdiff(names(TV), c("gid", "game_pk", "Date", "season", "y", "p_close")), with = FALSE])]
e_c <- mean(ll(TV$C_team_only, TV$y)) - mean(ll(TV$M5_plus_defense, TV$y))
VV <- fread("data/mlb/matchup/predictions-v2-validation.csv")[season %in% 2017:2022]    # as sabr_baseline.R
VV <- VV[complete.cases(VV[, setdiff(names(VV), c("gid", "game_pk", "Date", "season", "y", "p_close")), with = FALSE])]
VV <- merge(VV, fread("data/mlb/matchup/sabr-predictions-validation.csv")[, .(gid, y_s = y, S4_plus_team)], by = "gid")
stopifnot(nrow(TV) == 7288, nrow(VV) == 12142, VV$y == VV$y_s)
e_s <- mean(ll(VV$S4_plus_team, VV$y)) - mean(ll(VV$M5_plus_defense, VV$y))
pw <- function(delta, se) stats::pnorm(delta / se - z) + stats::pnorm(-delta / se - z)
mde <- function(se) (z + stats::qnorm(.8)) * se
rs <- row("v2", "S4"); rc <- row("v2", "C_team_only")
pow_s <- pw(e_s, rs$se); pow_c <- pw(e_c, rc$se)
c1 <- data.table(q = c("cluster SE, v2 vs S4", "cluster SE, v2 vs team run margin",
                       "80%-power detectable edge vs S4", "80%-power detectable edge vs team run margin",
                       "earlier edge over S4 (2017-2022, 12,142 games)", "earlier edge over team run margin (2023-2025, 7,288 games)",
                       "power for the earlier edge over team run margin", "power for the earlier edge over S4",
                       "2026 interval contains the earlier edge (both)"),
  pub = c("0.0013", "0.0023", "0.0036", "0.0063", "0.0011", "0.0021", "about 15%", "about 15%", "yes"),
  rec = c(fmt(rs$se), fmt(rc$se), fmt(mde(rs$se)), fmt(mde(rc$se)), fmt(e_s), fmt(e_c),
          sprintf("%.1f%%", 100 * pow_c), sprintf("%.1f%%", 100 * pow_s),
          fifelse(rs$h_lo < e_s & e_s < rs$h_hi & rc$h_lo < e_c & e_c < rc$h_hi, "yes", "no")))
c1[, match := mt(c(pub[1:6] == rec[1:6], round(100 * pow_c) == 15, round(100 * pow_s) == 15, rec[9] == "yes"))]
se_w <- (rc$h_hi - rc$h_lo) / (2 * z)                      # SE implied by the interval width
FIX <- "Corrected in REPORT.md on 2026-10-06"
c1[, note := c(NA,
  sprintf("0.0023 is the interval width / 3.92 (%s); the SD of the draws is %s. The published detectable edge 0.0063 fits %s (it would be %s with %s), so the published SE and detectable edge came from two different SE estimates. %s to 0.0022.",
          fmt(se_w, 5), fmt(rc$se, 5), fmt(rc$se, 5), fmt(mde(se_w)), fmt(se_w, 5), FIX),
  NA, NA, NA, NA,
  sprintf("%.1f%% with the SD of the draws; %.1f%% with the interval-width SE %s, which rounds to the published 15%%. %s to 16%%.",
          100 * pow_c, 100 * pw(e_c, se_w), fmt(se_w, 5), FIX),
  sprintf("%.1f%% (%.1f%% with the rounded SE 0.0013): about 14%%, so \"about 15%%\" for both earlier edges was loose for S4. %s to 14%%.",
          100 * pow_s, 100 * pw(e_s, 0.0013), FIX),
  NA)]

# --- 2. Holm over the ten comparisons (two-sided normal p from the estimate and its home-team SE) ---
hf <- cmp[baseline == "B_home"]; ot <- cmp[baseline != "B_home"]
c2 <- data.table(q = c("home-field wins significant after Holm (of 3)", "largest Holm-adjusted p among them",
                       "other comparisons significant after Holm (of 7)"),
  pub = c("3", "at most 0.006", "0 (nothing else comes close)"),
  rec = c(sum(hf$holm < .05), fmt(max(hf$holm)), sprintf("%d (smallest adjusted p %s)", sum(ot$holm < .05), fmt(min(ot$holm), 3))))
c2[, match := mt(c(rec[1] == "3", max(hf$holm) <= 0.006, sum(ot$holm < .05) == 0))][, note := NA_character_]

# --- 3. t(29) for 30 clusters: estimate +/- qt(.975, 29) x home-team SE ------------------------------
nf_t <- sum(cmp$v_t != cmp$v_h)
c3 <- data.table(q = c("interval widening, t(29) over normal", "verdicts flipped (of 10)"),
  pub = c("about 4%", "0"), rec = c(sprintf("%.1f%%", 100 * (tq / z - 1)), as.character(nf_t)))
c3[, match := mt(c(round(100 * (tq / z - 1)) == 4, nf_t == 0))][, note := NA_character_]

# --- 4. game-level and week-block resamples beside the home-team one ---------------------------------
dc <- row("v2_dayahead", "C_team_only"); fl <- cmp[v_g != v_h | v_w != v_h]
c4 <- data.table(q = c("home-team intervals equal to forward-test-2026.md (5 decimals)", "v2_dayahead vs team run margin, game resample",
                       "v2_dayahead vs team run margin, week resample", "comparisons whose verdict changes under game or week resampling"),
  pub = c("10 of 10", "[+0.0001, +0.0066]", "[+0.0004, +0.0063]", "1: v2_dayahead vs C_team_only"),
  rec = c(sprintf("%d of 10", sum(cmp$rec_ci == cmp$pub_ci & fmt(cmp$est, 5) == cmp$pub_d)), ci(dc$g_lo, dc$g_hi), ci(dc$w_lo, dc$w_hi),
          sprintf("%d: %s", nrow(fl), paste(fl$model, "vs", fl$baseline, collapse = "; "))))
c4[, match := mt(pub == rec)]
d_dc <- ll(P$C_team_only, P$y) - ll(P$v2_dayahead, P$y)
sd_g <- sapply(SEEDS, function(s) qn(boot(d_dc, P$gid, s))); sd_w <- sapply(SEEDS, function(s) qn(boot(d_dc, wk, s)))
wk_sun <- as.Date(cut(P$Date, "week", start.on.monday = FALSE))
noise <- function(m, lo, hi, what, f = sg, d = 4, why = "Monte Carlo noise") sprintf("%s, no correction needed: the same %s at seed 20261005 and at seeds %s gives lower bounds %s and upper bounds %s; the published interval lies %s that range.",
  why, what, paste(SEEDS, collapse = ", "), rng(m, 1, f), rng(m, 2, f), fifelse(inside(m, lo, hi, d), "inside", "outside"))
c4[, note := c(NA,
  paste(noise(sd_g <- cbind(c(dc$g_lo, dc$g_hi), sd_g), 0.0001, 0.0066, "game resample"),
        fifelse(any(sd_g[1, ] < 0), "At some seeds the lower bound is below zero, so whether this comparison clears zero under game resampling is itself seed-dependent.", "")),
  paste(noise(cbind(c(dc$w_lo, dc$w_hi), sd_w), 0.0004, 0.0063, "week resample", why = "Monte Carlo noise or the week definition"),
        sprintf("Sunday-start weeks (%d) at seed 20261005 give %s%s.", length(unique(wk_sun)), w_sun <- do.call(ci, as.list(qn(boot(d_dc, wk_sun)))),
                fifelse(w_sun == "[+0.0004, +0.0063]", ", the published interval exactly, so the review may have used Sunday weeks", ""))),
  NA)]

# --- 5. calibration slope of v2, home-team cluster bootstrap of the refit slope ----------------------
x5 <- cbind(1, lgt(P$v2))                                  # glm.fit: the same fit as glm(y ~ lgt(v2)), faster
slope <- function(i) stats::glm.fit(x5[i, ], P$y[i], family = stats::binomial())$coefficients[2]
gi <- split(seq_len(nrow(P)), cl)
sbs <- function(seed) { set.seed(seed); replicate(1000, slope(unlist(gi[sample(length(gi), replace = TRUE)], use.names = FALSE))) }
sq <- stats::quantile(sbs(20261005), c(.025, .975))
sd_c <- sapply(SEEDS, function(s) qn(sbs(s)))
c5 <- data.table(q = c("calibration slope, v2", "home-team cluster 95% interval", "maintenance trigger (interval excludes 1)"),
  pub = c("0.933", "[0.705, 1.151]", "not triggered"),
  rec = c(fmt(slope(seq_len(nrow(P))), 3), ci(sq[1], sq[2], function(x) fmt(x, 3)), fifelse(sq[1] > 1 | sq[2] < 1, "triggered", "not triggered")))
c5[, match := mt(pub == rec)]
c5[, note := c(NA,
  paste(noise(sd_c <- cbind(as.numeric(sq), sd_c), 0.705, 1.151, "cluster bootstrap", function(x) fmt(x, 3), 3),
        fifelse(any(sd_c[1, ] > 1 | sd_c[2, ] < 1), "The trigger fires at some of those seeds.", "The trigger fires at none of those seeds.")),
  NA)]

# --- 6. also in REPORT.md as a review check: projected-lineup edge over v2 (positive = v2_dayahead better)
d6 <- ll(P$v2, P$y) - ll(P$v2_dayahead, P$y); se6 <- stats::sd(boot(d6, cl)); mar <- sum(d6[month(P$Date) == 3]) / sum(d6)
c6 <- data.table(q = c("v2_dayahead minus v2 log loss saved per game", "standard error (home-team draws)", "share of the edge from March games"),
  pub = c("0.0007", "0.0005", "most of it"), rec = c(fmt(mean(d6)), fmt(se6), sprintf("%.0f%%", 100 * mar)))
c6[, match := mt(c(rec[1:2] == pub[1:2], mar > 0.5))]
im <- month(P$Date) == 3
c6[, note := c(NA, NA,
  sprintf("March holds %d of %s games (%.0f%%) and supplies %.3f of the %.3f total log loss saved (%.0f%%). The March per-game edge is %s against %s in the other months: concentrated in March per game, but not most of the total. %s to \"40%% of it from the %d March games\".",
          sum(im), format(nrow(P), big.mark = ","), 100 * mean(im), sum(d6[im]), sum(d6), 100 * mar, fmt(mean(d6[im])), fmt(mean(d6[!im])), FIX, sum(im)))]

# --- write ------------------------------------------------------------------------------------------
tb <- function(x) c("| quantity | published | recomputed | match |", "| --- | --- | --- | --- |", x[, sprintf("| %s | %s | %s | %s |", q, pub, rec, match)], "")
all_c <- rbind(c1, c2, c3, c4, c5, c6)
lines <- c("# 2026 forward test: review checks, recomputed", "",
  sprintf("Computed %s at commit %s by `review_checks.R`. **Exploratory: computed after scoring; changes no number, threshold or verdict.** The pre-registered home-team intervals in `forward-test-2026.md` decide; this file only makes the independent post-scoring review's ad hoc checks (FORWARD-PLAN.md, 2026-10-06; REPORT.md section 9; MODEL-CARD.md) reproducible. %d of %d rows match.",
          format(Sys.time(), "%Y-%m-%d %H:%M"), git("rev-parse", "--short", "HEAD"), sum(all_c$match == "MATCH"), nrow(all_c)), "",
  sprintf("Inputs: the four scored 2026 files (sha256 matched FORWARD-PLAN.md), %d games, %d home-team clusters, %d Monday weeks; earlier edges from `predictions-v2-test.csv` and `predictions-v2-validation.csv` with `sabr-predictions-validation.csv`. Every resample: 1,000 draws, seed 20261005, ratio of summed differences as `forward_score.R`. Baseline minus model per game; positive = model better.",
          nrow(P), G, length(unique(wk))), "",
  "## The ten comparisons", "",
  "| model | vs | estimate | home-team 95%, as run | recomputed | SE | t(29) 95% | game 95% | week 95% | Holm p |",
  "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  cmp[, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", model, baseline, fmt(est, 5), pub_ci, rec_ci, fmt(se, 5),
                ci(t_lo, t_hi), ci(g_lo, g_hi), ci(w_lo, w_hi), fmt(holm, 4))], "",
  "SE: standard deviation of the 1,000 home-team draws. t(29): estimate plus or minus qt(0.975, 29) times SE. Game: each game resampled. Week: Monday weeks resampled. Holm p: two-sided normal p from estimate / SE, Holm-adjusted over the ten.", "",
  "## 1. Power of the 2026 test to detect the earlier edges (v2)", "",
  "Two-sided 5% z test with the home-team SE; detectable edge = (1.96 + 0.84) x SE. Earlier edges: S4 minus M5 on the 2017-2022 validation games, team run margin minus M5 on the 2023-2025 test games. \"About 15%\" matches when the power rounds to 15%.", "",
  tb(c1),
  "## 2. Holm adjustment over the ten comparisons", "", tb(c2),
  "## 3. t(29) widening for 30 home-team clusters", "", tb(c3),
  "## 4. Game-level and week-block resampling beside the home-team clusters", "", tb(c4),
  "## 5. Calibration slope of v2", "",
  "Slope of logit(p) in a logistic refit of outcomes; interval: 1,000 home-team cluster draws, refit each time, 2.5% and 97.5% quantiles.", "",
  tb(c5),
  "## 6. Projected-lineup edge over v2 (also a review check in REPORT.md section 9)", "", tb(c6),
  "## Notes on the differences", "",
  "One line per DIFFER row, computed by this script. The published column keeps the values as originally published; seeds other than 20261005 appear only here.", "",
  all_c[match == "DIFFER", sprintf("- %s: %s", q, fifelse(is.na(note), "no diagnosis recorded.", trimws(note)))], "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.",
  "2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.")
writeLines(lines, out_md)
message(paste(lines, collapse = "\n"))
message(sprintf("runtime %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
