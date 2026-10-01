# The walk-forward backtest: no prediction may see its own week's outcomes or anything later.

make_games <- function(seed = 1, days = 56) {
  set.seed(seed)
  dates <- c(seq(as.Date("2016-04-04"), by = "day", length.out = days),
             seq(as.Date("2017-04-03"), by = "day", length.out = days))
  grid  <- expand.grid(slot = 1:3, Date = dates)
  n     <- nrow(grid)
  games <- data.frame(
    game_pk = seq_len(n), Date = grid$Date, season = as.integer(format(grid$Date, "%Y")),
    HTeam = paste("Home", grid$slot), ATeam = paste("Away", grid$slot),
    teams.home.score = stats::rpois(n, 4.7), teams.away.score = stats::rpois(n, 4.4)
  )
  ranges <- list(rp_slg = c(0.30, 0.50), HR = c(2, 9), SO_perc = c(0.15, 0.30),
                 LD = c(0.18, 0.28), sp_slg = c(0.30, 0.50), slg = c(0.35, 0.48))
  for (col in SCORE_INPUTS) {
    r <- ranges[[sub("^(a_|h_|arp_|hrp_|asp_|hsp_|abat_|hbat_)", "", col)]]
    games[[col]] <- stats::runif(n, r[1], r[2])
  }
  games$arp_HR <- round(games$arp_HR)
  games$hrp_HR <- round(games$hrp_HR)
  games$a_rp_slg[sample(n, 20)] <- NA       # a few missing inputs, so imputation runs
  games
}

test_that("a block's predictions ignore its own outcomes and everything after it", {
  games <- make_games()
  base  <- walk_forward(games, predict_seasons = 2017)
  b     <- sort(unique(base$block_start))[3]
  nxt   <- min(base$block_start[base$block_start > b])

  tampered <- games
  later <- tampered$Date >= b
  tampered$teams.home.score[later] <- rev(tampered$teams.home.score[later]) + 3L
  tampered$teams.away.score[later] <- 0L
  feats <- tampered$Date >= nxt
  for (col in SCORE_INPUTS) tampered[[col]][feats] <- stats::runif(sum(feats))
  again <- walk_forward(tampered, predict_seasons = 2017)

  expect_equal(again$win_pct[again$block_start == b], base$win_pct[base$block_start == b])
  # and the tampering is not a no-op: the following block does move
  expect_false(isTRUE(all.equal(again$win_pct[again$block_start == nxt],
                                base$win_pct[base$block_start == nxt])))
})

test_that("missing inputs take the mean of earlier games only", {
  games <- make_games()
  b     <- as.Date("2017-04-17")                      # a Monday, third 2017 block
  x     <- which(games$Date == b)[1]
  games$a_rp_slg[x] <- NA
  expected <- mean(games$a_rp_slg[games$Date < b], na.rm = TRUE)

  out <- walk_forward(games, predict_seasons = 2017)
  got <- out$home_exscore[out$game_pk == x]
  row <- games[x, ]
  expect_equal(got, raw_exscore(expected, row$arp_HR, row$asp_SO_perc, row$asp_LD,
                                row$a_sp_slg, row$hbat_slg))

  # other games in the same week change nothing about that fill
  same_week <- games$Date >= b & games$Date < b + 7 & seq_len(nrow(games)) != x
  games$a_rp_slg[same_week] <- 9
  again <- walk_forward(games, predict_seasons = 2017)
  expect_equal(again$home_exscore[again$game_pk == x], got)
})

test_that("a side with no comparables falls back to the mean score of earlier games", {
  games <- make_games()
  b     <- as.Date("2017-04-17")
  x     <- which(games$Date == b)[1]
  games$arp_HR[x] <- 1000                              # an index no past game is near
  out <- walk_forward(games, predict_seasons = 2017)
  hit <- out[out$game_pk == x, ]
  prior <- games[games$Date < b, ]
  expect_equal(hit$home_n, 0L)
  expect_equal(hit$home_pred, mean(c(prior$teams.home.score, prior$teams.away.score)))
})

test_that("win_pct is a probability and only predict seasons come back", {
  out <- walk_forward(make_games(), predict_seasons = 2017)
  expect_true(all(out$win_pct >= 0 & out$win_pct <= 1))
  expect_equal(unique(out$season), 2017L)
  expect_true(all(out$home_rate > 0 & out$home_rate < 1))
})

test_that("the home score reads the AWAY bullpen", {
  g <- make_games()[1:2, ]
  g$a_rp_slg[2] <- g$a_rp_slg[1] + 0.1
  g[2, setdiff(SCORE_INPUTS, "a_rp_slg")] <- g[1, setdiff(SCORE_INPUTS, "a_rp_slg")]
  out <- add_expected_scores(g)
  expect_false(out$home_exscore[1] == out$home_exscore[2])
  expect_equal(out$away_exscore[1], out$away_exscore[2])
})

test_that("choose_threshold takes validation rows only and respects the coverage floor", {
  expect_equal(names(formals(choose_threshold)), c("validation_preds", "min_share", "grid"))
  preds <- data.frame(win_pct = c(rep(0.52, 80), 0.69, rep(0.62, 19)),
                      home_win = c(rep(c(1, 0), 40), 1, rep(1, 19)))
  t <- choose_threshold(preds)
  expect_gte(win_rate_above(favorite_frame(preds), t)$n, 10)
  expect_lt(t, 0.62)                                  # 0.69 alone is 1 game, under the floor
})

test_that("baselines score as defined", {
  preds <- data.frame(home_win = c(1, 1, 0, 1), win_pct = c(0.6, 0.4, 0.3, 0.7), home_rate = 0.54)
  s <- score_predictions(preds)
  coin <- s[s$predictor == "coin flip", ]
  expect_equal(coin$log_loss, log(2))
  expect_equal(coin$brier, 0.25)
  expect_equal(s$accuracy[s$predictor == "home team always"], 0.75)
  expect_equal(s$accuracy[s$predictor == "model"], 0.75)
})

test_that("Wilson interval matches the textbook value", {
  expect_equal(round(wilson_ci(50, 100), 4), c(0.4038, 0.5962))
  expect_true(all(is.na(wilson_ci(0, 0))))
})
