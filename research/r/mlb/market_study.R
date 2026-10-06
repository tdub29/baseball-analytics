#!/usr/bin/env Rscript
# Market study (MARKET-PLAN.md): the frozen recency model against the no-vig closing moneyline.
#
#   Rscript research/r/mlb/market_study.R
#   OUT=market-study-joinfix.md Rscript research/r/mlb/market_study.R   # corrected run beside the as-run md
#
# Odds: data/mlb/raw/odds/mlb_odds_dataset.json (SportsBookReview scrape, private research only).
# Model: results/recency/model-predictions-test.csv (E, frozen before any odds were loaded).

suppressPackageStartupMessages({ library(dplyr); library(purrr) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("ingest.R", "gamelogs.R")) source(file.path(SRC, f))
RES  <- file.path(SRC, "results")
OUT  <- Sys.getenv("OUT", "market-study.md")
VALM <- 2021:2022
TESTM <- 2023:2025

`%||%` <- function(a, b) if (is.null(a)) b else a
decimal <- function(a) ifelse(a > 0, 1 + a / 100, 1 + 100 / abs(a))

# --- odds: one row per game, consensus no-vig close and best closing prices -------------------

raw <- jsonlite::fromJSON("data/mlb/raw/odds/mlb_odds_dataset.json", simplifyVector = FALSE)
odds <- dplyr::bind_rows(lapply(names(raw), function(d) dplyr::bind_rows(lapply(raw[[d]], function(g) {
  v  <- g$gameView
  ml <- g$odds$moneyline
  if (is.null(ml) || !length(ml) || is.null(v$homeTeamScore)) return(NULL)
  pick <- function(b, line, side) { x <- b[[line]][[side]]; if (is.null(x)) NA_real_ else as.numeric(x) }
  books <- data.frame(
    book = vapply(ml, function(b) b$sportsbook %||% NA_character_, ""),
    ch = vapply(ml, pick, 0, "currentLine", "homeOdds"), ca = vapply(ml, pick, 0, "currentLine", "awayOdds"),
    oh = vapply(ml, pick, 0, "openingLine", "homeOdds"), oa = vapply(ml, pick, 0, "openingLine", "awayOdds"))
  books <- books[!is.na(books$ch) & !is.na(books$ca) & books$ch != 0 & books$ca != 0, ]
  if (!nrow(books)) return(NULL)
  dh <- decimal(books$ch); da <- decimal(books$ca)
  nv <- (1 / dh) / (1 / dh + 1 / da)
  op <- !is.na(books$oh) & !is.na(books$oa) & books$oh != 0 & books$oa != 0
  ov <- if (any(op)) mean((1 / decimal(books$oh[op])) / (1 / decimal(books$oh[op]) + 1 / decimal(books$oa[op]))) else NA_real_
  data.frame(odds_date = as.Date(d), start = v$startDate, home = v$homeTeam$fullName, away = v$awayTeam$fullName,
             hs = as.numeric(v$homeTeamScore), as = as.numeric(v$awayTeamScore), status = v$gameStatusText %||% "",
             books = nrow(books), p_close = mean(nv), p_open = ov, overround = mean(1 / dh + 1 / da),
             best_home = max(dh), best_away = max(da), med_home = stats::median(dh), med_away = stats::median(da),
             med_home_open = if (any(op)) stats::median(decimal(books$oh[op])) else NA_real_,
             med_away_open = if (any(op)) stats::median(decimal(books$oa[op])) else NA_real_)
}))))

# --- join to StatsAPI games by date, team names and final score ----------------------------

gl <- gamelog_sources("data/mlb/raw"); cs <- cached_sources("data/mlb/raw")
sched <- dplyr::bind_rows(lapply(2021:2025, function(s) {
  win <- season_window(s, fetch = cs$seasons)
  sc <- gl$schedule(as.character(win$start), as.character(win$end))
  tm <- gl$teams(s)
  data.frame(game_pk = sc$game_pk, Date = sc$Date, season = s, home = tm$team[match(sc$home_id, tm$team_id)],
             away = tm$team[match(sc$away_id, tm$team_id)], hs = sc$home_score, as = sc$away_score)
}))
norm <- function(x) {                       # odds names: 2021 Cleveland already "Guardians",
  x <- gsub("[^a-z]", "", tolower(sub("^Oakland ", "", x)))   # 2025 A's "Athletics Athletics"
  x[x == "clevelandindians"] <- "clevelandguardians"; x[x == "athleticsathletics"] <- "athletics"; x
}
key  <- function(d, h, a, hs, as) paste(d, norm(h), norm(a), hs, as)
sk <- key(sched$Date, sched$home, sched$away, sched$hs, sched$as)
ok <- key(odds$odds_date, odds$home, odds$away, odds$hs, odds$as)
amb <- sk %in% sk[duplicated(sk)] | sk %in% ok[duplicated(ok)]               # same teams, same day, same score
m <- match(sk, ok); m[amb] <- NA
sched$odds_row <- m

pred <- utils::read.csv(file.path(RES, "recency", "model-predictions-test.csv"))
G <- merge(pred, sched[c("game_pk", "odds_row")], by = "game_pk")
G <- G[!is.na(G$odds_row), ]
G <- cbind(G, odds[G$odds_row, c("p_close", "p_open", "books", "overround", "best_home", "best_away", "med_home", "med_away", "med_home_open", "med_away_open", "status")])
G$Date <- as.Date(G$Date)
# Sept-Oct 2021 "current" lines were scraped after first pitch (36% moved over 15 points from the
# open, closing log loss 0.52 and 0.40): in-game prices, not closing lines. Found by the charter's
# sanity check after the first run; that run is kept as results/market-study-v1-asrun.md.
bad_window <- G$Date >= as.Date("2021-09-01") & G$Date <= as.Date("2021-12-31")
excluded <- sum(bad_window)
G <- G[!bad_window, ]
match_rate <- nrow(G) / sum(pred$Date >= "2021-03-20" & pred$Date <= "2025-08-16")

# --- Q1: forecast --------------------------------------------------------------------------

ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
G$cluster <- paste(G$home_team, G$season)
paired <- function(da, B = 1000) {          # positive = E better
  by <- tapply(da, G$cluster[seq_along(da)], sum); n <- tapply(da, G$cluster[seq_along(da)], length)
  set.seed(20261004)
  boot <- replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  c(mean(da), stats::quantile(boot, c(0.025, 0.975)))
}
q1 <- dplyr::bind_rows(lapply(c(sort(unique(G$season)), 0L), function(s) {
  x <- if (s == 0) G else G[G$season == s, ]
  data.frame(season = if (s == 0) "pooled" else as.character(s), games = nrow(x),
             ll_market = mean(ll(x$p_close, x$y)), ll_E = mean(ll(x$E, x$y)), ll_C = mean(ll(x$C, x$y)),
             acc_market = mean((x$p_close > 0.5) == x$y), acc_E = mean((x$E > 0.5) == x$y))
}))
q1_gain <- paired(ll(G$p_close, G$y) - ll(G$E, G$y))

# --- Q2: does E add information to the line? fit 2021-2022, score 2023-2025 -----------------

lg <- function(p) stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
G$lm <- lg(G$p_close); G$le <- lg(G$E)
tr <- G$season %in% VALM; te <- G$season %in% TESTM
blend <- stats::glm(y ~ lm + le, stats::binomial, G[tr, ])
G$p_blend <- stats::predict(blend, G, type = "response")
q2 <- {
  d <- ll(G$p_close[te], G$y[te]) - ll(G$p_blend[te], G$y[te])
  by <- tapply(d, G$cluster[te], sum); n <- tapply(d, G$cluster[te], length)
  set.seed(20261004)
  boot <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) })
  c(gain = mean(d), stats::quantile(boot, c(0.025, 0.975)))
}

# --- Q3: betting at the best closing price; threshold from 2021-2022 only --------------------

bets <- function(x, tau) {
  eh <- x$E - x$p_close; ea <- (1 - x$E) - (1 - x$p_close)
  side <- ifelse(eh >= tau, "home", ifelse(ea >= tau, "away", NA))
  b <- x[!is.na(side), ]; side <- side[!is.na(side)]
  price <- ifelse(side == "home", b$best_home, b$best_away)
  won <- ifelse(side == "home", b$y == 1, b$y == 0)
  data.frame(Date = b$Date, season = b$season, side = side, price = price, won = won,
             profit = ifelse(won, price - 1, -1), p_model = ifelse(side == "home", b$E, 1 - b$E))
}
TAUS <- c(0.01, 0.02, 0.03, 0.04, 0.05, 0.06)
val <- dplyr::bind_rows(lapply(TAUS, function(t) { b <- bets(G[tr, ], t)
  data.frame(tau = t, bets = nrow(b), roi = if (nrow(b)) mean(b$profit) else NA) }))
cand <- val[val$bets >= 200, ]
tau <- if (nrow(cand)) cand$tau[which.max(cand$roi)] else NA
week_boot <- function(b, B = 1000) {
  w <- as.Date(cut(b$Date, "week")); by <- tapply(b$profit, w, sum); n <- tapply(b$profit, w, length)
  set.seed(20261004)
  stats::quantile(replicate(B, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }), c(0.025, 0.975))
}
tb <- if (!is.na(tau)) bets(G[te, ], tau) else bets(G[0, ], 1)
q3 <- if (nrow(tb)) c(bets = nrow(tb), wins = sum(tb$won), units = sum(tb$profit), roi = mean(tb$profit), week_boot(tb)) else NULL
q3_season <- if (nrow(tb)) tb |> dplyr::group_by(season) |> dplyr::summarise(bets = dplyr::n(), units = sum(profit), roi = mean(profit), .groups = "drop") else NULL
# quarter Kelly alongside, same threshold, bankroll-free: stake fraction f = 0.25 * (p*price - 1)/(price - 1)
kelly <- if (nrow(tb)) { f <- pmax(0, 0.25 * (tb$p_model * tb$price - 1) / (tb$price - 1)); sum(f * tb$profit) / sum(f) } else NA

# --- report ---------------------------------------------------------------------------------

fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
out <- c("# Market study: frozen recency model vs the closing line", "",
  sprintf("Generated %s by `Rscript research/r/mlb/market_study.R`. Charter: MARKET-PLAN.md.", format(Sys.Date())), "",
  sprintf("Matched %d games (%.1f%% of model games 2021-03-20 to 2025-08-16), %d more excluded (Sept-Oct 2021 lines scraped after first pitch). Mean closing overround %.3f; books per game %.1f.",
          nrow(G), 100 * match_rate, excluded, mean(G$overround), mean(G$books)),
  "Post-hoc correction: the pre-registered run (`market-study-v1-asrun.md`) included those games; its validation choices are superseded here, so 2023-2025 results in this file are exploratory where they depend on Q2's blend or Q3's threshold.", "",
  "## Q1: forecast, no tuning (log loss, lower is better)", "",
  "| season | games | no-vig close | E | incumbent C | accuracy close | accuracy E |", "| --- | --- | --- | --- | --- | --- | --- |",
  apply(q1, 1, function(r) sprintf("| %s | %s | %s | %s | %s | %s%% | %s%% |", r[["season"]], r[["games"]], fmt(r[["ll_market"]]),
        fmt(r[["ll_E"]]), fmt(r[["ll_C"]]), fmt(100 * as.numeric(r[["acc_market"]]), 1), fmt(100 * as.numeric(r[["acc_E"]]), 1))), "",
  sprintf("E minus close, per-game log loss (positive = E better): %s [%s, %s].", fmt(q1_gain[1], 5), fmt(q1_gain[2], 5), fmt(q1_gain[3], 5)), "",
  "## Q2: does E add information? (blend fit 2021-2022, scored 2023-2025)", "",
  sprintf("Blend: logit p = %s + %s logit(close) + %s logit(E). Test gain over the close alone: %s [%s, %s].",
          fmt(coef(blend)[1], 3), fmt(coef(blend)[2], 3), fmt(coef(blend)[3], 3), fmt(q2[1], 5), fmt(q2[2], 5), fmt(q2[3], 5)), "",
  "## Q3: betting at the best closing price", "",
  "Thresholds on 2021-2022:", "", "| tau | bets | ROI |", "| --- | --- | --- |",
  apply(val, 1, function(r) sprintf("| %s | %s | %s |", r[["tau"]], r[["bets"]], fmt(r[["roi"]], 3))), "",
  if (is.na(tau)) "No threshold reached 200 bets on 2021-2022." else
    sprintf("Chosen tau %s. Test 2023-2025: %d bets, %d won, %s units, ROI %s, week-block 95%% [%s, %s]. Quarter Kelly ROI on stake %s.",
            tau, q3[["bets"]], q3[["wins"]], fmt(q3[["units"]], 1), fmt(q3[["roi"]], 3), fmt(q3[[5]], 3), fmt(q3[[6]], 3), fmt(kelly, 3)), "",
  if (!is.null(q3_season)) c("| season | bets | units | ROI |", "| --- | --- | --- | --- |",
    apply(q3_season, 1, function(r) sprintf("| %s | %s | %s | %s |", r[["season"]], r[["bets"]], fmt(r[["units"]], 1), fmt(r[["roi"]], 3)))) else "", "",
  "Private research on scraped odds; not betting advice.")
writeLines(out, file.path(RES, OUT))
utils::write.csv(G[c("game_pk", "Date", "season", "y", "E", "C", "p_close", "p_open", "p_blend", "best_home", "best_away", "med_home", "med_away", "med_home_open", "med_away_open")],
                 "data/mlb/raw/odds/market-joined.csv", row.names = FALSE)   # odds-derived: stays local
message("wrote ", file.path(RES, OUT))
