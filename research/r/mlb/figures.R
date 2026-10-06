#!/usr/bin/env Rscript
# Figures for REPORT.md: the matchup model against the betting market.
#
#   Rscript research/r/mlb/figures.R          # from the repo root; writes results/figures/*.png
#
# Reads the committed walk-forward predictions (data/mlb/matchup/predictions-*.csv) and the local,
# unlicensed odds join (data/mlb/raw/odds/market-joined.csv, totals-validation.csv). Odds leave
# this script only as aggregates: season means, bins of 20+ games, weekly cumulative sums and
# bootstrap distributions. No per-game odds row is written or plotted.
# Before drawing, it reproduces the committed headline numbers and stops if any has drifted.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales); library(grid) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
OUT <- file.path(SRC, "results", "figures"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
SEED <- 20261004

# --- palette and theme: one accent for the model, one for the market, gray for everything else ---
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#8a8984"; GRID <- "#e6e5e1"; SURF <- "#fcfcfb"; BAND <- "#f0efec"
MODEL <- "#2a78d6"; MARKET <- "#eb6834"; BASE <- "#a3a29c"
RETRO <- "The information used here was obtained free of charge from and is copyrighted by Retrosheet."
SRC_NOTE <- "Source: walk-forward predictions from research/r/mlb (Retrosheet plate appearances, MLB StatsAPI); odds: SportsBookReview scrape, unlicensed, aggregates only."
theme_report <- function() {
  theme_minimal(base_size = 13) + theme(
    text = element_text(colour = INK), plot.background = element_rect(fill = SURF, colour = NA),
    panel.background = element_rect(fill = SURF, colour = NA),
    plot.title = element_text(face = "bold", size = 17, margin = margin(b = 4)),
    plot.subtitle = element_text(colour = INK2, size = 12, margin = margin(b = 10), lineheight = 1.1),
    plot.caption = element_text(colour = MUTED, size = 8.5, hjust = 0, lineheight = 1.15, margin = margin(t = 10)),
    plot.title.position = "plot", plot.caption.position = "plot",
    axis.text = element_text(colour = INK2), axis.title = element_text(colour = INK2, size = 11),
    panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
    strip.text = element_text(face = "bold", hjust = 0, size = 12), legend.position = "none",
    plot.margin = margin(16, 20, 12, 16))
}
save_png <- function(p, name, w = 10, h = 6.25) {          # 2x: 10 x 6.25 in at 200 dpi = 2000 x 1250 px
  ggsave(file.path(OUT, name), p, width = w, height = h, dpi = 200, device = "png", type = "cairo", bg = SURF)
  message("wrote ", file.path(OUT, name))
}
cap <- function(...) paste(c(...), collapse = "\n")
f4 <- function(x) formatC(x, format = "f", digits = 4)
f2 <- function(x) formatC(x, format = "f", digits = 2)
pct <- function(x, d = 1) paste0(ifelse(x > 0, "+", ""), formatC(100 * x, format = "f", digits = d), "%")
comma0 <- function(x) format(x, big.mark = ",", trim = TRUE)
near <- function(a, b, tol) isTRUE(all(abs(a - b) <= tol))

# --- scoring and bootstrap helpers (same definitions as matchup_model.R) ---------------------------
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
cboot <- function(d, cl, B = 1000) {        # ratio-of-sums bootstrap over clusters; returns draws too
  by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(SEED)
  b <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  list(est = mean(d), lo = unname(quantile(b, 0.025)), hi = unname(quantile(b, 0.975)), draws = b)
}
week <- function(d) as.Date(cut(as.Date(d), "week"))
wilson <- function(k, n, z = 1.96) { p <- k / n; c0 <- p + z^2 / (2 * n); s <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  cbind(lo = (c0 - s) / (1 + z^2 / n), hi = (c0 + s) / (1 + z^2 / n)) }

# --- data --------------------------------------------------------------------------------------------
rd <- function(f) { x <- fread(file.path("data/mlb/matchup", f)); x[, hometeam := substr(gid, 1, 3)]; x[] }
val <- rd("predictions-v2-validation.csv"); tst <- rd("predictions-v2-test.csv")
dat <- rd("predictions-v2-dayahead-test.csv")
mk <- fread("data/mlb/raw/odds/market-joined.csv")
mk <- mk[!(as.Date(Date) >= as.Date("2021-09-01") & as.Date(Date) <= as.Date("2021-12-31"))]   # in-game scrapes (MARKET-PLAN.md it 2)
MODELS <- c("B_home", "C_team_only", "C_incumbent", "E_recency", "M1_runs_ratio", "M2_components",
            "M3_plus_team", "M4_plus_rest", "M5_plus_defense", "ENS")
LABS <- c(B_home = "Home field only", C_team_only = "Team run margin only", C_incumbent = "Incumbent: season-to-date run margin",
          E_recency = "Recency model E", M1_runs_ratio = "M1 matchup: expected runs ratio", M2_components = "M2 matchup: run components",
          M3_plus_team = "M3 = M2 + team run margin", M4_plus_rest = "M4 = M3 + rest and travel",
          M5_plus_defense = "M5 = M3 + team defense (frozen pick)", ENS = "Ensemble of M5 and E")
BEST <- "M5_plus_defense"
summary_lines <- character()
say <- function(...) { s <- sprintf(...); summary_lines <<- c(summary_lines, s); message(s) }

# =====================================================================================================
# Figure 1. Model ladder
# =====================================================================================================
lad <- rbindlist(lapply(list(list("Validation 2017-2022", val[season %in% 2017:2022]), list("Test 2023-2025, scored once", tst)), function(z) {
  x <- z[[2]][complete.cases(z[[2]][, MODELS, with = FALSE])]
  rbindlist(lapply(MODELS, function(m) { b <- cboot(ll(x[[m]], x$y), paste(x$hometeam, x$season))
    data.table(period = z[[1]], model = m, n = nrow(x), ll = b$est, lo = b$lo, hi = b$hi) }))
}))
# committed: matchup-model-v2-validation.md and -v2-test.md pooled rows
stopifnot(near(lad[period %like% "Valid" & model == BEST, ll], 0.6703, 6e-5), near(lad[period %like% "Test" & model == BEST, ll], 0.6776, 6e-5),
          near(lad[period %like% "Valid" & model == "ENS", ll], 0.6699, 6e-5), near(lad[period %like% "Test" & model == "B_home", ll], 0.6916, 6e-5),
          lad[period %like% "Valid", n[1]] == 12142, lad[period %like% "Test", n[1]] == 7288)
close_ref <- rbindlist(lapply(list(list("Validation 2017-2022", val[season %in% 2017:2022]), list("Test 2023-2025, scored once", tst)), function(z) {
  x <- z[[2]][!is.na(p_close) & !is.na(get(BEST))]; cl <- paste(x$hometeam, x$season)
  bc <- cboot(ll(x$p_close, x$y), cl); bm <- cboot(ll(x[[BEST]], x$y), cl)
  data.table(period = z[[1]], n = nrow(x), seasons = paste(range(x$season), collapse = "-"),
             close = bc$est, close_lo = bc$lo, close_hi = bc$hi, m5 = bm$est, m5_lo = bm$lo, m5_hi = bm$hi)
}))
stopifnot(close_ref$n == c(4130, 6451), near(close_ref$close[1], 0.6689, 6e-5))
for (i in seq_len(nrow(close_ref))) say("Fig 1 %s: no-vig close %s vs M5 %s on the %s games with odds (%s)", close_ref$period[i],
  f4(close_ref$close[i]), f4(close_ref$m5[i]), comma0(close_ref$n[i]), close_ref$seasons[i])
for (p in unique(lad$period)) { h <- lad[period == p & model == "B_home", ll]; t <- lad[period == p & model == "C_team_only", ll]; e <- lad[period == p & model == "ENS", ll]
  say("Fig 1 %s: home %s, team-only %s, ensemble %s; team-only carries %.0f%% of the gain from home to ensemble", p, f4(h), f4(t), f4(e), 100 * (h - t) / (h - e)) }

ODDS_ROW <- "Games with odds only:\nM5 (hollow) vs no-vig close"
YL <- unname(c(ODDS_ROW, rev(LABS[MODELS])))
lad[, model := factor(LABS[model], levels = YL)]
lad[, period := factor(period, levels = c("Validation 2017-2022", "Test 2023-2025, scored once"))]
close_ref[, period := factor(period, levels = levels(lad$period))]
lad[, hl := ifelse(as.character(model) %in% LABS[c(BEST, "ENS")], "m", "b")]
odd <- rbind(close_ref[, .(period, who = "close", ll = close, lo = close_lo, hi = close_hi)], close_ref[, .(period, who = "m5", ll = m5, lo = m5_lo, hi = m5_hi)])
odd[, model := factor(ODDS_ROW, levels = YL)]
close_ref[, lab := sprintf("No-vig close %s
%s games with odds, %s", f4(close), comma0(n), seasons)]
p1 <- ggplot(lad, aes(ll, model)) +
  geom_hline(yintercept = 1.5, colour = GRID, linewidth = 0.6) +
  geom_vline(data = close_ref, aes(xintercept = close), colour = MARKET, linewidth = 0.7, alpha = 0.8) +
  geom_text(data = close_ref, aes(x = close, y = length(YL) + 0.55, label = lab), colour = MARKET, hjust = 0, vjust = 0, nudge_x = 0.0004, size = 3.3, lineheight = 0.95) +
  geom_errorbar(aes(xmin = lo, xmax = hi, colour = hl), width = 0, linewidth = 0.5, alpha = 0.55, orientation = "y") +
  geom_point(aes(colour = hl), size = 2.8) +
  geom_text(aes(x = hi, label = f4(ll), colour = hl), hjust = 0, nudge_x = 0.0003, size = 3.1) +
  geom_errorbar(data = odd, aes(xmin = lo, xmax = hi, colour = who), width = 0, linewidth = 0.5, alpha = 0.55, orientation = "y", position = position_nudge(y = c(-0.12, -0.12, 0.12, 0.12))) +
  geom_point(data = odd[who == "close"], colour = MARKET, size = 2.8, position = position_nudge(y = -0.12)) +
  geom_point(data = odd[who == "m5"], shape = 21, fill = SURF, colour = MODEL, size = 2.8, stroke = 1, position = position_nudge(y = 0.12)) +
  geom_text(data = odd, aes(x = hi, label = f4(ll), colour = who), hjust = 0, nudge_x = 0.0003, size = 3.1, position = position_nudge(x = 0.0003, y = c(-0.12, -0.12, 0.12, 0.12))) +
  scale_colour_manual(values = c(m = MODEL, b = MUTED, close = MARKET, m5 = MODEL)) +
  scale_x_continuous(labels = label_number(accuracy = 0.001), expand = expansion(mult = c(0.04, 0.12))) +
  scale_y_discrete(limits = YL, expand = expansion(add = c(0.7, 1.5))) +
  facet_wrap(~period, scales = "free_x") +
  labs(title = "Team strength does most of the work, and no model reaches the closing line",
       subtitle = sprintf("Pooled log loss per game, lower is better. The ladder scores every game (%s validation, %s test). The close exists only where odds do,\nso the bottom row re-scores M5 on exactly those games: it sits right of the close in both periods.",
                          comma0(lad[period %like% "Valid", n[1]]), comma0(lad[period %like% "Test", n[1]])),
       x = "Log loss per game", y = NULL,
       caption = cap("Bars: 95% interval of each mean log loss, home team-season cluster bootstrap (1,000 draws). They mostly carry season-level luck shared by every forecast; the paired gap to the close is tighter (see the gap figure).",
                     "2020 has no recency-model predictions and is outside the validation pool. Values match results/matchup-model-v2-validation.md and -v2-test.md.", SRC_NOTE, RETRO)) +
  theme_report() + theme(panel.spacing = unit(2.2, "lines"))
save_png(p1, "fig1-model-ladder.png", w = 12.5, h = 7.5)

# =====================================================================================================
# Figure 2. Gap to the close by season, paired
# =====================================================================================================
G <- rbind(val[season %in% 2021:2022], tst)[!is.na(p_close) & !is.na(get(BEST))]
G[, d := ll(p_close, y) - ll(get(BEST), y)]                      # close minus model: positive = model better
gap <- rbindlist(c(
  lapply(2021:2025, function(s) { x <- G[season == s]; b <- cboot(x$d, paste(x$hometeam, x$season))
    data.table(grp = as.character(s), n = nrow(x), est = b$est, lo = b$lo, hi = b$hi, close = mean(ll(x$p_close, x$y)), model = mean(ll(x[[BEST]], x$y))) }),
  lapply(list(c(2021, 2022), c(2023, 2025)), function(r) { x <- G[season %between% r]; b <- cboot(x$d, paste(x$hometeam, x$season))
    data.table(grp = sprintf("%d-%02d\npooled", r[1], r[2] %% 100), n = nrow(x), est = b$est, lo = b$lo, hi = b$hi, close = mean(ll(x$p_close, x$y)), model = mean(ll(x[[BEST]], x$y))) })))
stopifnot(near(unlist(gap[grp == "2023-25\npooled", .(est, lo, hi)]), c(-0.00356, -0.00543, -0.00164), 6e-6),
          near(unlist(gap[grp == "2021-22\npooled", .(est, lo, hi)]), c(-0.00207, -0.00415, 0.00007), 6e-6))
for (i in seq_len(nrow(gap))) say("Fig 2 %s: n %s, close %s, M5 %s, close minus M5 %s [%s, %s]", sub("\n", " ", gap$grp[i]), comma0(gap$n[i]),
  f4(gap$close[i]), f4(gap$model[i]), formatC(gap$est[i], format = "f", digits = 5), formatC(gap$lo[i], format = "f", digits = 5), formatC(gap$hi[i], format = "f", digits = 5))
gap[, grp := factor(grp, levels = grp)][, x := c(1:5, 6.6, 7.6)]
gap[, test := grp %in% c("2023", "2024", "2025", "2023-25\npooled")]
gap[, xl := sprintf("%s\n%s games", grp, comma0(n))]
p2 <- ggplot(gap, aes(x, est)) +
  annotate("rect", xmin = 2.5, xmax = 5.5, ymin = -Inf, ymax = Inf, fill = BAND) +
  annotate("rect", xmin = 7.1, xmax = 8.1, ymin = -Inf, ymax = Inf, fill = BAND) +
  annotate("text", x = 4, y = 0.0047, label = "Test seasons: frozen model, scored once", colour = INK2, size = 3.6, fontface = "bold") +
  annotate("text", x = 1.5, y = 0.0047, label = "Validation: choices\nmade here", colour = MUTED, size = 3.6, lineheight = 0.95) +
  geom_hline(yintercept = 0, colour = MARKET, linewidth = 0.8) +
  annotate("text", x = 0.12, y = -0.0003, label = "Model equals\nthe close", colour = MARKET, hjust = 0, size = 3.3, vjust = 1, lineheight = 0.95) +
  geom_vline(xintercept = 6.05, colour = GRID, linewidth = 0.6) +
  geom_errorbar(aes(ymin = lo, ymax = hi, colour = test), width = 0, linewidth = 0.8) +
  geom_point(aes(colour = test, shape = grepl("pooled", grp)), size = 3.2) +
  geom_text(aes(y = hi, label = ifelse(abs(est) < 5e-5, "0.0000", sprintf("%+.4f", est))), vjust = -0.7, size = 3.2, colour = INK2) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 18)) +
  scale_colour_manual(values = c(`FALSE` = MUTED, `TRUE` = MODEL)) +
  scale_x_continuous(breaks = gap$x, labels = gap$xl, expand = expansion(add = c(0.9, 0.5))) +
  scale_y_continuous(labels = label_number(accuracy = 0.001, style_positive = "plus"), limits = c(-0.0105, 0.0052)) +
  labs(title = "The model trailed the closing line in four of five seasons; 2025 was a draw",
       subtitle = "Close minus model, mean log loss per game on the same games (above zero = model better). M5, first-pitch inputs.\nThe validation interval just reaches zero; the frozen test interval excludes it.",
       x = NULL, y = "Close minus model, log loss per game",
       caption = cap("Bars: 95% paired interval, home team-season cluster bootstrap (1,000 draws, seed 20261004). Games with odds only; Sept-Oct 2021 excluded (closing lines scraped after first pitch).",
                     "Pooled values reproduce results/matchup-model-v2-validation.md and -v2-test.md. Season intervals are computed by this script. 2025 odds end 2025-08-16.", SRC_NOTE, RETRO)) +
  theme_report() + theme(panel.grid.major.x = element_blank())
save_png(p2, "fig2-gap-to-close.png", w = 11, h = 6.5)

# =====================================================================================================
# Figure 3. Calibration on 2023-2025 (games with odds)
# =====================================================================================================
C3 <- tst[!is.na(p_close) & !is.na(get(BEST))]
BRK <- c(0, seq(0.30, 0.70, 0.05), 1)
cal <- rbindlist(lapply(list(c(BEST, "Model M5 (first pitch)"), c("p_close", "No-vig closing line")), function(z) {
  p <- C3[[z[1]]]; brk <- BRK
  repeat {                                                        # fold a thin end bin into its neighbour until every bin has 20+ games
    n <- table(cut(p, brk, include.lowest = TRUE)); if (all(n >= 20)) break
    brk <- if (n[1] < 20) brk[-2] else brk[-(length(brk) - 1)]
  }
  bin <- cut(p, brk, include.lowest = TRUE)
  d <- data.table(p, y = C3$y, bin)[, .(n = .N, pred = mean(p), obs = mean(y), k = sum(y)), by = bin][order(bin)]
  d[, c("lo", "hi") := as.data.table(wilson(k, n))][, who := z[2]]
  fit <- glm(C3$y ~ qlogis(p), family = binomial); se <- sqrt(diag(vcov(fit)))[2]
  d[, slope := coef(fit)[2]][, slope_lo := coef(fit)[2] - 1.96 * se][, slope_hi := coef(fit)[2] + 1.96 * se][, sdp := sd(p)]
  d
}))
stopifnot(all(cal$n >= 20))                                       # odds aggregates: 20+ games per bin
for (w in unique(cal$who)) { z <- cal[who == w][1]; say("Fig 3 %s: calibration slope %s [%s, %s], SD of probabilities %s, %d games, bins %s",
  w, f2(z$slope), f2(z$slope_lo), f2(z$slope_hi), formatC(z$sdp, format = "f", digits = 3), sum(cal[who == w, n]), paste(cal[who == w, n], collapse = "/")) }
cal[, strip := sprintf("%s: slope %s [%s, %s]", who, f2(slope), f2(slope_lo), f2(slope_hi))]
cal[, strip := factor(strip, levels = unique(strip))]
p3 <- ggplot(cal, aes(pred, obs)) +
  geom_abline(slope = 1, intercept = 0, colour = MUTED, linewidth = 0.5) +
  geom_errorbar(aes(ymin = lo, ymax = hi, colour = who), width = 0, linewidth = 0.7) +
  geom_point(aes(colour = who), size = 2.8) +
  geom_text(aes(y = ifelse(seq_along(n) %% 2 == 1, 0.15, 0.11), label = comma0(n)), size = 2.8, colour = MUTED) +
  annotate("text", x = 0.2, y = 0.19, label = "games per bin", size = 2.8, colour = MUTED, hjust = 0) +
  annotate("text", x = 0.80, y = 0.83, label = "perfect calibration", size = 3, colour = MUTED, angle = 0, hjust = 1, vjust = -0.6) +
  scale_colour_manual(values = setNames(c(MODEL, MARKET), c("Model M5 (first pitch)", "No-vig closing line"))) +
  scale_x_continuous(labels = label_percent(accuracy = 1), limits = c(0.2, 0.82), breaks = seq(0.2, 0.8, 0.1)) +
  scale_y_continuous(labels = label_percent(accuracy = 1), limits = c(0.09, 0.86), breaks = seq(0.2, 0.8, 0.1)) +
  coord_equal() + facet_wrap(~strip) +
  labs(title = "Both forecasts track the observed rates; the model leans slightly overconfident",
       subtitle = sprintf("Predicted vs observed home win rate, %s test games with odds, 2023-2025.\nBins 5 points wide; the end bins hold everything below 30%% or above 70%%, widened until each has 20+ games.", comma0(nrow(C3))),
       x = "Predicted home win probability (bin mean)", y = "Observed home win rate",
       caption = cap("Bars: Wilson 95% interval for the observed rate. Slope: logistic recalibration of the outcome on the logit of the forecast (1 = calibrated spread), Wald 95% interval.",
                     "Exploratory description of the test seasons, computed by this script; not a pre-registered test.", SRC_NOTE, RETRO)) +
  theme_report() + theme(panel.spacing = unit(2, "lines"))
save_png(p3, "fig3-calibration.png", w = 10.8, h = 7.6)

# =====================================================================================================
# Figure 4. Bets at the open, day-ahead lineups, 2023-2025: closing-line value
# =====================================================================================================
O <- merge(dat[!is.na(p_close) & !is.na(get(BEST)) & !is.na(game_pk)],
           mk[, .(game_pk, p_open, med_home_open, med_away_open)], by = "game_pk")[!is.na(p_open)]
setorder(O, Date, gid)
open_bets <- function(x, prob, tau) {             # prob = NULL bets home on every game
  if (is.null(prob)) side <- rep("h", nrow(x)) else { eh <- x[[prob]] - x$p_open; side <- ifelse(eh >= tau, "h", ifelse(-eh >= tau, "a", NA)) }
  b <- x[!is.na(side)]; side <- side[!is.na(side)]
  open_p <- ifelse(side == "h", b$p_open, 1 - b$p_open); close_p <- ifelse(side == "h", b$p_close, 1 - b$p_close)
  price <- ifelse(side == "h", b$med_home_open, b$med_away_open); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  data.table(Date = as.Date(b$Date), season = b$season, clv = close_p - open_p, profit = ifelse(won, price - 1, -1))
}
TAU <- 0.06                                                    # frozen on 2021-2022 by CLV (matchup-model-v2-dayahead-test.md)
strat <- list(list("model", "Model M5, day-ahead lineups", BEST), list("team", "Team run margin only", "C_team_only"), list("home", "Always bet the home team", NULL))
B4 <- lapply(strat, function(s) open_bets(O, s[[3]], TAU)); names(B4) <- vapply(strat, `[[`, "", 1)
wk_stats <- function(b) { cl <- cboot(b$clv, week(b$Date)); ro <- cboot(b$profit, week(b$Date)); list(clv = cl, roi = ro) }
S4 <- lapply(B4, wk_stats)
stopifnot(nrow(B4$model) == 561, near(100 * c(S4$model$clv$est, S4$model$clv$lo, S4$model$clv$hi), c(2.01, 1.67, 2.35), 0.006),
          near(c(S4$model$roi$est, S4$model$roi$lo, S4$model$roi$hi), c(0.047, -0.050, 0.137), 6e-4))
for (s in strat) { k <- s[[1]]; z <- S4[[k]]; say("Fig 4 %s: %s bets, mean CLV %s points [%s, %s], ROI at median open %s [%s, %s]; bets by season %s",
  s[[2]], comma0(nrow(B4[[k]])), f2(100 * z$clv$est), f2(100 * z$clv$lo), f2(100 * z$clv$hi), pct(z$roi$est), pct(z$roi$lo), pct(z$roi$hi),
  paste(B4[[k]][, .N, by = season][, sprintf("%d: %d", season, N)], collapse = ", ")) }
clv_sd <- sd(100 * B4$model$clv); clv_deff <- max(1, (sd(100 * S4$model$clv$draws) / (clv_sd / sqrt(nrow(B4$model))))^2)
clv_need <- ceiling(clv_deff * (1.96 * clv_sd / (100 * S4$model$clv$est))^2)
say("Fig 4: model CLV per-bet SD %s points, design effect %s; bets for the expected 95%% interval of mean CLV to exclude zero: %d", f2(clv_sd), f2(clv_deff), clv_need)
# weekly cumulative path (no single bet is recoverable from a weekly step), band = bets x 95% interval of mean CLV
cum <- rbindlist(lapply(strat, function(s) { k <- s[[1]]; b <- B4[[k]]; z <- S4[[k]]$clv
  w <- b[, .(n = .N, clv = sum(100 * clv)), by = .(wk = week(Date))][order(wk)][, `:=`(bets = cumsum(n), cum = cumsum(clv))]
  rbind(data.table(wk = NA, n = 0, clv = 0, bets = 0, cum = 0), w)[, `:=`(lo = bets * 100 * z$lo, hi = bets * 100 * z$hi, key = k)] }))
cum[, panel := factor(key, levels = names(B4), labels = vapply(strat, function(s) sprintf("%s\n%s bets, %s points per bet [%s, %s]", s[[2]],
  comma0(nrow(B4[[s[[1]]]])), sprintf("%+.2f", 100 * S4[[s[[1]]]]$clv$est), f2(100 * S4[[s[[1]]]]$clv$lo), f2(100 * S4[[s[[1]]]]$clv$hi)), ""))]
cum[, col := ifelse(key == "model", "m", "b")]
p4 <- ggplot(cum, aes(bets, cum)) +
  geom_blank(data = cum[, .(bets = max(bets) * c(0, 1), cum = max(bets) * c(-0.1, 2.6)), by = panel]) +   # same points-per-bet scale in every panel
  geom_hline(yintercept = 0, colour = MUTED, linewidth = 0.4) +
  geom_ribbon(aes(ymin = lo, ymax = hi, fill = col), alpha = 0.18) +
  geom_line(aes(colour = col), linewidth = 0.9) +
  scale_colour_manual(values = c(m = MODEL, b = INK2)) + scale_fill_manual(values = c(m = MODEL, b = MUTED)) +
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +
  facet_wrap(~panel, scales = "free") +
  labs(title = sprintf("Bets at the open gained %s points of closing-line value each as run; with the starter guessed, about 0.8", f2(100 * S4$model$clv$est)),
       subtitle = sprintf("Cumulative closing-line value (CLV) of bets at the opening line, 2023-2025, in time order: how far the no-vig line moved toward each side bet, summed in\nprobability points. Every panel uses the same points-per-bet scale, so steeper means more value per bet. Betting every home team also drifts upward (lines\ntend to move toward home sides), so that drift is the floor to beat. Model and team-margin bets: %d+ points off the no-vig open (frozen threshold).", round(100 * TAU)),
       x = "Bets placed (cumulative, weekly steps)", y = "Cumulative CLV, probability points",
       caption = cap("Band: bets placed times the 95% week-block bootstrap interval of mean CLV per bet (1,000 draws). Model figures reproduce results/matchup-model-v2-dayahead-test.md.",
                     "As run this is an upper bound: the day-ahead model knows the actual starter. Exploratory builds that guess the starter from the rotation gain 0.73 [0.53, 0.94]",
                     "and, with every input lagged a day, 0.81 [0.60, 1.02] points per bet (results/matchup-model-explore-rot-test.md, -explore-rotlag-test.md; MATCHUP-PLAN.md iteration 7).",
                     "The two baselines are computed by this script from the same predictions and odds and are exploratory (not in a committed result). Odds end 2025-08-16.", SRC_NOTE, RETRO)) +
  theme_report() + theme(panel.spacing = unit(2, "lines"), strip.text = element_text(face = "bold", hjust = 0, size = 10.5, lineheight = 1.05))
save_png(p4, "fig4-clv-at-open.png", w = 12.5, h = 7.2)

# =====================================================================================================
# Figure 5. ROI reality check: bootstrap ROI vs break-even, and the bets needed to prove an edge
# =====================================================================================================
roi <- S4$model$roi; prof <- B4$model$profit
p_le0 <- mean(roi$draws <= 0)
sd_bet <- sd(prof); se_iid <- sd_bet / sqrt(length(prof)); se_blk <- sd(roi$draws); deff <- max(1, (se_blk / se_iid)^2)
per_season <- B4$model[, .N, by = season]
need <- function(edge, z) deff * (z * sd_bet / edge)^2
say("Fig 5: ROI %s [%s, %s], %.0f%% of week-block draws at or below break-even; per-bet profit SD %s, design effect %s",
    pct(roi$est), pct(roi$lo), pct(roi$hi), 100 * p_le0, f2(sd_bet), f2(deff))
say("Fig 5: bets needed for the expected 95%% interval to exclude zero at a true edge of 1/2/3/4.7/6%%: %s; for 80%% power at 4.7%%: %s",
    paste(comma0(round(need(c(0.01, 0.02, 0.03, roi$est, 0.06), 1.96))), collapse = "/"), comma0(round(need(roi$est, 1.96 + qnorm(0.8)))))
h5 <- data.table(roi = roi$draws)
p5a <- ggplot(h5, aes(roi)) +
  geom_histogram(binwidth = 0.01, boundary = 0, fill = MODEL, alpha = 0.55, colour = SURF, linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = MARKET, linewidth = 0.8) +
  annotate("text", x = -0.003, y = Inf, label = sprintf("Break-even\n%.0f%% of draws at or below", 100 * p_le0), colour = MARKET, hjust = 1, vjust = 1.3, size = 3.3, lineheight = 0.95) +
  geom_vline(xintercept = roi$est, colour = INK, linewidth = 0.5) +
  annotate("text", x = roi$est + 0.003, y = Inf, label = sprintf("Observed %s", pct(roi$est)), hjust = 0, vjust = 1.3, size = 3.3) +
  annotate("segment", x = roi$lo, xend = roi$hi, y = -3, yend = -3, colour = INK, linewidth = 0.9) +
  scale_x_continuous(labels = label_percent(accuracy = 1)) +
  labs(title = "ROI at the median opening price", subtitle = sprintf("%d day-ahead bets, 2023-2025, week-block bootstrap (1,000 draws).\nBlack bar: 95%% interval, %s to %s.", length(prof), pct(roi$lo), pct(roi$hi)),
       x = "Return per unit staked", y = "Bootstrap draws") +
  theme_report() + theme(plot.title = element_text(size = 13.5), plot.subtitle = element_text(size = 10.5), plot.margin = margin(8, 14, 8, 8))
ed <- seq(0.01, 0.06, by = 0.0005)
pw <- rbind(data.table(edge = ed, n = need(ed, 1.96), k = "Expected 95% interval excludes zero"),
            data.table(edge = ed, n = need(ed, 1.96 + qnorm(0.8)), k = "80% chance it excludes zero"))
seas_n <- per_season[season %in% 2023:2024, round(mean(N))]
p5b <- ggplot(pw, aes(edge, n)) +
  geom_hline(yintercept = seas_n, colour = MUTED, linewidth = 0.5) +
  annotate("text", x = 0.06, y = seas_n, label = sprintf("One full season of bets (about %d)", seas_n), hjust = 1, vjust = -0.5, size = 3.1, colour = INK2) +
  geom_hline(yintercept = length(prof), colour = MUTED, linewidth = 0.5) +
  annotate("text", x = 0.06, y = length(prof), label = sprintf("All test bets, 2023-2025 (%d)", length(prof)), hjust = 1, vjust = -0.5, size = 3.1, colour = INK2) +
  geom_line(aes(linetype = k), colour = MODEL, linewidth = 0.9) +
  geom_vline(xintercept = roi$est, colour = INK, linewidth = 0.4) +
  annotate("text", x = roi$est - 0.0007, y = max(pw$n), label = sprintf("At the observed %s:\n%s bets, about %.0f seasons", pct(roi$est), comma0(round(need(roi$est, 1.96))), need(roi$est, 1.96) / seas_n),
           hjust = 1, vjust = 1, size = 3.1, lineheight = 0.95) +
  annotate("text", x = 0.0155, y = need(0.0155, 1.96 + qnorm(0.8)), label = "80% power", hjust = -0.15, size = 3.1, colour = MODEL) +
  annotate("text", x = 0.022, y = need(0.022, 1.96) * 0.6, label = "expected interval\nclears zero", hjust = 1, vjust = 1, size = 3.1, colour = MODEL, lineheight = 0.95) +
  scale_linetype_manual(values = c("Expected 95% interval excludes zero" = "solid", "80% chance it excludes zero" = "22")) +
  scale_x_continuous(labels = label_percent(accuracy = 1), breaks = seq(0.01, 0.06, 0.01)) +
  scale_y_log10(labels = label_comma(), breaks = c(100, 300, 1000, 3000, 10000, 30000)) +
  labs(title = "Bets needed to prove an edge", subtitle = sprintf("per-bet profit SD %s, week-clustering design effect %s", f2(sd_bet), f2(deff)),
       x = "True return per unit staked", y = "Bets (log scale)") +
  theme_report() + theme(plot.title = element_text(size = 13.5), plot.subtitle = element_text(size = 10.5), plot.margin = margin(8, 8, 8, 14))
png(file.path(OUT, "fig5-roi-reality-check.png"), width = 12.5, height = 6.5, units = "in", res = 200, type = "cairo", bg = SURF)
grid.newpage(); grid.rect(gp = gpar(fill = SURF, col = NA))
pushViewport(viewport(layout = grid.layout(3, 2, heights = unit(c(1.05, 1, 0.75), c("in", "null", "in")))))
grid.text("A positive return that three seasons cannot tell apart from zero", x = unit(16, "pt"), y = unit(1, "npc") - unit(20, "pt"), just = c("left", "top"),
          gp = gpar(fontsize = 17, fontface = "bold", col = INK), vp = viewport(layout.pos.row = 1, layout.pos.col = 1:2))
grid.text(sprintf("Bets at the open where the day-ahead model disagrees by 6+ points returned %s, but the interval spans break-even.\nAt that edge it takes about %s bets before the interval is expected to exclude zero.",
                  pct(roi$est), comma0(round(need(roi$est, 1.96)))),
          x = unit(16, "pt"), y = unit(1, "npc") - unit(46, "pt"), just = c("left", "top"), gp = gpar(fontsize = 12, col = INK2, lineheight = 1.1),
          vp = viewport(layout.pos.row = 1, layout.pos.col = 1:2))
print(p5a, vp = viewport(layout.pos.row = 2, layout.pos.col = 1)); print(p5b, vp = viewport(layout.pos.row = 2, layout.pos.col = 2))
grid.text(cap(sprintf("Bets needed n = design effect x (z x SD / edge)^2, z = 1.96 (expected interval) or 1.96 + 0.84 (80%% power); SD and design effect from the %d test bets. Bets per season: %s.",
                      length(prof), paste(per_season[, sprintf("%d: %d", season, N)], collapse = ", ")),
              "ROI reproduces results/matchup-model-v2-dayahead-test.md; the power curve is computed by this script. 2025 odds end 2025-08-16.", SRC_NOTE, RETRO),
          x = unit(16, "pt"), y = unit(1, "npc") - unit(8, "pt"), just = c("left", "top"), gp = gpar(fontsize = 8.5, col = MUTED, lineheight = 1.15),
          vp = viewport(layout.pos.row = 3, layout.pos.col = 1:2))
invisible(dev.off()); message("wrote ", file.path(OUT, "fig5-roi-reality-check.png"))

# =====================================================================================================
# Figure 6. Totals: model vs the closing over/under
# =====================================================================================================
tot_runs <- list(list("validation", "data/mlb/raw/odds/totals-validation.csv", 2021:2022))
if (file.exists(file.path(SRC, "results", "totals-test.md")) && file.exists("data/mlb/raw/odds/totals-test.csv"))
  tot_runs <- c(tot_runs, list(list("test", "data/mlb/raw/odds/totals-test.csv", 2023:2025)))
tot <- rbindlist(lapply(tot_runs, function(r) {
  x <- fread(r[[2]])[season %in% r[[3]] & !is.na(line) & excl == FALSE & !is.na(q_T2) & total != line]
  x[, over := as.integer(total > line)][, d := ll(p_mkt, over) - ll(q_T2, over)]
  out <- lapply(c(as.list(r[[3]]), list(r[[3]])), function(s) { z <- x[season %in% s]; b <- cboot(z$d, paste(z$hometeam, z$season), B = 2000)
    data.table(stage = r[[1]], grp = if (length(s) > 1) sprintf("%d-%02d\npooled", min(s), max(s) %% 100) else as.character(s), n = nrow(z),
               market = mean(ll(z$p_mkt, z$over)), model = mean(ll(z$q_T2, z$over)), est = b$est, lo = b$lo, hi = b$hi) })
  rbindlist(out)
}))
stopifnot(near(unlist(tot[stage == "validation" & grepl("pooled", grp), .(n, market, model)]), c(4059, 0.6919, 0.6943), c(0, 6e-5, 6e-5)),
          near(unlist(tot[stage == "validation" & grepl("pooled", grp), .(est, lo, hi)]), c(-0.00232, -0.00553, 0.00088), 6e-6))
for (i in seq_len(nrow(tot))) say("Fig 6 %s %s: n %s, market %s, T2 %s, market minus T2 %s [%s, %s]", tot$stage[i], sub("\n", " ", tot$grp[i]), comma0(tot$n[i]),
  f4(tot$market[i]), f4(tot$model[i]), formatC(tot$est[i], format = "f", digits = 5), formatC(tot$lo[i], format = "f", digits = 5), formatC(tot$hi[i], format = "f", digits = 5))
if (any(tot$stage == "test")) stopifnot(near(unlist(tot[stage == "test" & grepl("pooled", grp), .(n, est, lo, hi)]), c(6310, -0.00520, -0.00867, -0.00201), c(0, 6e-6, 6e-6, 6e-6)))
has_test <- any(tot$stage == "test")
tot[, x := seq_len(.N) + ifelse(stage == "test", 0.5, 0)][, xl := sprintf("%s\n%s games\nclose %s\nmodel %s", grp, comma0(n), f4(market), f4(model))]
tx <- range(tot[stage == "test", x])
p6 <- ggplot(tot, aes(x, est)) +
  { if (has_test) list(annotate("rect", xmin = tx[1] - 0.5, xmax = tx[2] + 0.5, ymin = -Inf, ymax = Inf, fill = BAND),
                       annotate("text", x = mean(tx), y = 0.0085, label = "Test seasons: frozen model, scored once", colour = INK2, size = 3.6, fontface = "bold")) } +
  annotate("text", x = 2, y = 0.0085, label = "Validation: candidate and threshold chosen here", colour = MUTED, size = 3.4) +
  geom_hline(yintercept = 0, colour = MARKET, linewidth = 0.8) +
  annotate("text", x = max(tot$x) + 0.45, y = 0.0003, label = "Model equals the closing total", colour = MARKET, hjust = 1, vjust = 0, size = 3.3) +
  geom_errorbar(aes(ymin = lo, ymax = hi, colour = stage), width = 0, linewidth = 0.8) +
  geom_point(aes(shape = grepl("pooled", grp), colour = stage), size = 3.2) +
  geom_text(aes(y = hi, label = sprintf("%+.4f", est)), vjust = -0.7, size = 3.2, colour = INK2) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 18)) +
  scale_colour_manual(values = c(validation = MUTED, test = MODEL)) +
  scale_x_continuous(breaks = tot$x, labels = tot$xl, expand = expansion(add = 0.5)) +
  scale_y_continuous(labels = label_number(accuracy = 0.001, style_positive = "plus"), limits = c(-0.0155, 0.0095)) +
  labs(title = if (has_test) "On totals, the model trailed the closing over/under in every test season" else "On totals the model won 2021, lost 2022, and trails the closing line overall",
       subtitle = sprintf("Market minus model, over/under log loss per game, pushes excluded (above zero = model better). Selected candidate T2 (runs per side, negative binomial).\n%s",
                          if (has_test) "The 2021 win was in the seasons used to choose the model; the frozen test interval excludes zero." else "2021-2022 only, where the candidate, blend and threshold were chosen, so this flatters the model. The 2023-2025 test has not been scored."),
       x = NULL, y = "Market minus model, log loss per game",
       caption = cap("Bars: 95% paired interval, home team-season cluster bootstrap (2,000 draws). Market: median no-vig over probability at the main closing total. Sept-Oct 2021 excluded (in-game scrapes).",
                     sprintf("Pooled values reproduce results/totals-validation.md%s; season intervals are computed by this script. 2025 odds end 2025-08-16.", if (has_test) " and results/totals-test.md" else ""), SRC_NOTE, RETRO)) +
  theme_report() + theme(panel.grid.major.x = element_blank())
save_png(p6, "fig6-totals.png", w = 11.5, h = 6.75)

# =====================================================================================================
# Figure 7. The 2026 forward season, outcomes only: each matchup model against three baselines
# (stabilization curves live in results/reliability-alpha-vs-n.png, drawn by reliability.R)
# =====================================================================================================
fw <- function(f) fread(file.path("data/mlb/matchup", f))
F2 <- fw("predictions-v2-forward.csv"); FD <- fw("predictions-v2-dayahead-forward.csv"); F4 <- fw("predictions-v4-forward.csv")
FS <- fw("sabr-predictions-forward.csv")
FP <- F2[, .(gid, y, B_home, C_team_only, v2 = get(unique(best)))]
FP <- merge(FP, FD[, .(gid, v2_dayahead = get(unique(best)))], by = "gid")
FP <- merge(FP, F4[, .(gid, v4 = get(unique(best)))], by = "gid")
FP <- merge(FP, FS[, .(gid, y_s4 = y, S4 = S4_plus_team)], by = "gid")
stopifnot(FP$y == FP$y_s4, nrow(FP) == 2429, !anyNA(FP))
fpaired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261005)   # forward_score.R's draws
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), quantile(b, c(.025, .975))) }
FMOD <- c(v2 = "v2, posted lineups", v2_dayahead = "v2, projected lineups (actual starter)", v4 = "v4, tuned shrinkage")
FBASE <- c(B_home = "vs home field only", C_team_only = "vs team run margin only", S4 = "vs SIERA, xFIP, wOBA,\nbullpen FIP and run margin (S4)")
fcl <- substr(FP$gid, 1, 3)
f7 <- rbindlist(lapply(names(FBASE), function(b) rbindlist(lapply(names(FMOD), function(m) {
  g <- fpaired(ll(FP[[b]], FP$y) - ll(FP[[m]], FP$y), fcl); data.table(base = b, model = m, est = g[1], lo = g[2], hi = g[3]) }))))
# committed: results/forward-test-2026.md (as run)
stopifnot(near(unlist(f7[base == "B_home" & model == "v2", .(est, lo, hi)]), c(0.01028, 0.00475, 0.01643), 6e-6),
          near(unlist(f7[base == "C_team_only" & model == "v2", .(est, lo, hi)]), c(0.00270, -0.00124, 0.00777), 6e-6),
          near(unlist(f7[base == "S4" & model == "v2", .(est, lo, hi)]), c(0.00048, -0.00198, 0.00298), 6e-6),
          near(mean(ll(FP$v2, FP$y)), 0.6813, 6e-5))
for (i in seq_len(nrow(f7))) say("Fig 7 %s %s: %+.5f [%+.5f, %+.5f]", f7$model[i], f7$base[i], f7$est[i], f7$lo[i], f7$hi[i])
f7[, base_f := factor(FBASE[base], levels = FBASE)][, model_f := factor(FMOD[model], levels = rev(FMOD))]
f7[, col := fifelse(lo > 0, MODEL, BASE)]
f7lev <- sapply(c("v2", "B_home", "C_team_only", "S4"), function(m) mean(ll(FP[[m]], FP$y)))
p7 <- ggplot(f7, aes(y = model_f)) +
  geom_vline(xintercept = 0, colour = INK2, linewidth = 0.5) +
  geom_errorbar(aes(xmin = lo, xmax = hi, colour = col), width = 0, linewidth = 1.1, orientation = "y") +
  geom_point(aes(x = est, colour = col), size = 3.2) +
  geom_text(aes(x = hi, label = sprintf("%+.4f", est)), hjust = -0.25, size = 3.4, colour = INK2) +
  scale_colour_identity() +
  scale_x_continuous(labels = function(x) sprintf("%+.3f", x), expand = expansion(mult = c(0.05, 0.18))) +
  facet_wrap(~base_f, ncol = 1) +
  labs(title = "2026, unseen by every model: better than home field, no detectable edge over run margin or S4",
       subtitle = sprintf(cap("Log loss saved per game by each frozen matchup model; right of zero = the model was better. 2,429 games, scored once.",
                              "Levels: v2 %s, home field %s, team run margin %s, S4 %s. One season is underpowered for edges this small.",
                              "No licensed 2026 odds, so no market comparison."),
                          f4(f7lev[["v2"]]), f4(f7lev[["B_home"]]), f4(f7lev[["C_team_only"]]), f4(f7lev[["S4"]])),
       x = "Baseline log loss minus model log loss, per game (95% interval, 30 home-team clusters)", y = NULL,
       caption = cap("Pre-registered in FORWARD-PLAN.md; as-run results in results/forward-test-2026.md. Blue: interval excludes zero.",
                     "2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.", RETRO)) +
  theme_report() + theme(panel.grid.major.y = element_blank(), strip.text = element_text(face = "bold", hjust = 0, size = 11.5, lineheight = 1.05))
save_png(p7, "fig7-forward-2026.png", w = 11.5, h = 7.6)

writeLines(summary_lines)
