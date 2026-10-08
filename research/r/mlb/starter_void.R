# Closing-line value of the day-ahead bets under the listed-pitcher rule. MLB moneylines are usually
# voided when a listed starter does not start, so a bet's real outcome depends on whether both
# probables took the mound. Scores the 2023-2025 bets at the frozen tau of 6 points three ways: all
# bets, bets on games where both starters came from the archived probables, and bets on games where
# both listed probables started (the bets that would stand). Exploratory: the 2023-2025 test is spent.
#
#   FEAT_TAG=-explore-prob Rscript research/r/mlb/starter_void.R
#
# Reads data/mlb/matchup/predictions{TAG}-test.csv (matchup_model.R test), features{TAG}-starters.csv
# (matchup_build.R STARTER_MODE=probable) and the odds join; writes results/starter-void{TAG}.md.
suppressPackageStartupMessages(library(data.table))
TAG <- Sys.getenv("FEAT_TAG", "-explore-prob"); TAU <- 0.06
out_md <- sprintf("research/r/mlb/results/starter-void%s.md", TAG)
md <- readLines(sprintf("research/r/mlb/results/matchup-model%s-test.md", TAG))
best <- sub(".*: (.*)[.]$", "\\1", grep("^Best matchup variant", md, value = TRUE))
pr <- fread(sprintf("data/mlb/matchup/predictions%s-test.csv", TAG))[season %in% 2023:2025]
mk <- fread("data/mlb/raw/odds/market-joined.csv")
pr <- merge(pr, mk[, .(game_pk, p_open, med_home_open, med_away_open)], by = "game_pk")
pr <- pr[!is.na(p_open) & !is.na(p_close) & !is.na(get(best))]
st <- fread(sub("predictions", "features", sprintf("data/mlb/matchup/predictions%s-starters.csv", TAG)))
g <- st[, .(listed = all(src == "probable") && .N == 2, stood = all(src == "probable" & sp == sp_act) && .N == 2), by = gid]
pr <- merge(pr, g, by = "gid", all.x = TRUE)[is.na(listed), `:=`(listed = FALSE, stood = FALSE)]
# Games whose listed starters both equal the two-day rotation guess (the starter a bettor could
# expect at the open without the announcement): from the rotation build's slot checkpoint.
rot <- unique(as.data.table(readRDS("data/mlb/matchup/features-v2-dayahead-rot-slots.rds")$L)[, .(gid, pitteam = opp, rot = sp)])
gr <- merge(st, rot, by = c("gid", "pitteam"), all.x = TRUE)[, .(as_rot = .N == 2 && all(src == "probable") && all(sp == rot, na.rm = FALSE)), by = gid]
pr <- merge(pr, gr, by = "gid", all.x = TRUE)[is.na(as_rot), as_rot := FALSE]
# How long before first pitch the probables snapshot was taken, test seasons
pp <- fread("data/mlb/raw/statsapi/pregame-probables.csv")[status %in% c("Pre-Game", "Scheduled", "Warmup", "Delayed Start") & !is.na(first_pitch)]
pp[, lead := as.numeric(difftime(as.POSIXct(first_pitch, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), as.POSIXct(snapshot, "%Y%m%d_%H%M%S", tz = "UTC"), units = "mins"))]
lead <- pp[lead > 0 & season %in% 2023:2025, .(med = median(lead)), by = season][order(season)]

clv_bets <- function(x) {   # as matchup_model.R
  eh <- x[[best]] - x$p_open; side <- ifelse(eh >= TAU, "h", ifelse(-eh >= TAU, "a", NA))
  b <- x[!is.na(side)]; side <- side[!is.na(side)]
  open_p <- ifelse(side == "h", b$p_open, 1 - b$p_open); close_p <- ifelse(side == "h", b$p_close, 1 - b$p_close)
  price <- ifelse(side == "h", b$med_home_open, b$med_away_open); won <- ifelse(side == "h", b$y == 1, b$y == 0)
  data.table(Date = as.Date(b$Date), season = b$season, clv = close_p - open_p, profit = ifelse(won, price - 1, -1))
}
week_ci <- function(v, d) { w <- as.Date(cut(d, "week")); by <- tapply(v, w, sum); n <- tapply(v, w, length); set.seed(20261004)
  stats::quantile(replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }), c(.025, .975)) }
fmt <- function(x, d = 2) formatC(as.numeric(x), format = "f", digits = d)
row <- function(lab, x) { b <- clv_bets(x); ci <- week_ci(b$clv, b$Date); ri <- week_ci(b$profit, b$Date)
  sprintf("| %s | %d | %d | %s [%s, %s] | %s [%s, %s] |", lab, nrow(x), nrow(b), fmt(100 * mean(b$clv)), fmt(100 * ci[1]), fmt(100 * ci[2]),
          fmt(mean(b$profit), 3), fmt(ri[1], 3), fmt(ri[2], 3)) }
writeLines(c(sprintf("# Day-ahead bets under the listed-pitcher rule (%s)", sub("^-", "", TAG)), "",
  sprintf("Generated %s by starter_void.R. Exploratory: the 2023-2025 test is spent and tau is frozen at %s (chosen on 2021-2022 for v2), not re-tuned. Model column: %s.",
          format(Sys.Date()), TAU, best), "",
  "| games | with odds | bets | mean CLV at the open (prob. points), week-block 95% | ROI at median open price, 95% |", "| --- | --- | --- | --- | --- |",
  row("all 2023-2025", pr), row("both starters from archived probables", pr[listed == TRUE]),
  row("both listed probables started (bets that stand)", pr[stood == TRUE]),
  row("both listed probables equal the two-day rotation guess", pr[as_rot == TRUE]),
  row("at least one listed probable differs from the rotation guess", pr[as_rot == FALSE]), "",
  "The two rotation rows differ in which games they hold, so they indicate where the edge sits; neither is a bound.", "",
  sprintf("Share of games with both probables listed: %s; of those, both started: %s.", fmt(mean(pr$listed), 3), fmt(mean(pr$stood[pr$listed]), 3)),
  sprintf("Median minutes from the probables snapshot to first pitch: %s. The opening price has no timestamp.",
          paste(sprintf("%d %.0f", lead$season, lead$med), collapse = ", ")), "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.",
  "2017-2025 probable starters: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research."), out_md)
message("wrote ", out_md)
