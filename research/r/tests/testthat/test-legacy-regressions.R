library(testthat)

# These are the defects section 5b of docs/consolidation-plan.md named, pinned as tests so
# the rebuild cannot quietly reintroduce them. Each one asserts the BROKEN behaviour of the
# legacy construct as well as the fixed behaviour, so the test proves the bug was real.

test_that("rbind(df, x, fill = TRUE) injects a garbage row, it does not fill", {
  # The legacy schedule loop was: odf <- rbind(odf, f, fill = TRUE)
  # `fill` is data.table syntax. base rbind.data.frame has no such argument, so TRUE lands
  # in ... and is bound as ANOTHER ROW, recycled across every column.
  acc <- data.frame(game_pk = integer(), team = character())
  day  <- data.frame(game_pk = 565000L, team = "Boston Red Sox")

  broken <- rbind(acc, day, fill = TRUE)
  expect_equal(nrow(broken), 2)                     # one real row, one injected
  expect_true(any(broken$game_pk == 1))             # TRUE coerced to 1 in an integer col

  # 180 days a season produce ~180 of these, all with game_pk == 1, which the legacy
  # dedupe on game_pk collapses to exactly one. That is why the file carries
  # `NEW <- filter(NEW, game_pk != 1)  #remove error row` 280 lines downstream.
  clean <- dplyr::bind_rows(acc, day)
  expect_equal(nrow(clean), 1)
  expect_false(any(clean$game_pk == 1))
})

test_that("collecting then binding once beats rbind in a loop", {
  # Not a micro-benchmark, a shape assertion: the list-then-bind form produces exactly the
  # rows fetched, with no accumulator to misuse and no fill argument to pass by mistake.
  days <- as.character(seq(as.Date("2019-04-01"), by = "day", length.out = 5))
  fake <- function(d) data.frame(game_pk = as.integer(gsub("-", "", d)), Date = d)
  out <- purrr::map_dfr(days, fake)
  expect_equal(nrow(out), 5)
  expect_equal(length(unique(out$game_pk)), 5)
})

test_that("normality_p survives a comparable set too thin to test", {
  # tseries::jarque.bera.test errors on fewer than 2 values. In the legacy for-loop that
  # error killed the whole season on the first thin bucket.
  expect_true(is.na(normality_p(numeric(0))))
  expect_true(is.na(normality_p(c(4))))
  expect_true(is.na(normality_p(c(4, 5))))
  expect_false(is.na(normality_p(rnorm(200))))
})

test_that("regress_to_mean shrinks only above the threshold, and toward the mean", {
  # p below the threshold: the comparable set is distinguishable from noise, leave it.
  expect_equal(regress_to_mean(6, 0.01, population_mean = 4.5), 6)
  # p above it: shrink by 0.2 + 0.5p, toward the mean, never past it.
  shrunk <- regress_to_mean(6, 0.50, population_mean = 4.5)
  expect_lt(shrunk, 6)
  expect_gt(shrunk, 4.5)
  expect_equal(shrunk, 6 - (6 - 4.5) * (0.2 + 0.5 * 0.5))
  # a missing p uses the 0.75 default rather than propagating NA
  expect_false(is.na(regress_to_mean(6, NA, population_mean = 4.5)))
})

test_that("comparable_outcomes brackets correctly on both sides of zero", {
  history <- data.frame(exscore = c(-3, -2.1, -1.9, 1.9, 2.0, 2.1, 9),
                        score   = c( 1,    2,    3,   4,   5,   6, 7))
  pos <- comparable_outcomes(2.0, history, tol = 0.05)
  expect_equal(pos$occurrences, 3)
  expect_equal(pos$mean_score, 5)

  # The legacy advantage loop had an explicit if/else to flip the comparison for negative
  # targets. Getting it wrong returns an empty set, which then reads as "no comparables".
  neg <- comparable_outcomes(-2.0, history, tol = 0.05)
  expect_equal(neg$occurrences, 2)
})

test_that("comparable_outcomes refuses a dated history with no as_of", {
  # The leak this guards: without a date filter, a July game can be "predicted" from
  # September games. It looks like a good model and is arithmetic on the answer key.
  history <- data.frame(
    Date    = as.Date(c("2019-05-01", "2019-06-01", "2019-09-01")),
    exscore = c(2.0, 2.0, 2.0),
    score   = c(1, 3, 99)
  )
  expect_error(comparable_outcomes(2.0, history, tol = 0.05), "as_of is required")
})

test_that("comparable_outcomes with as_of excludes games that had not been played", {
  history <- data.frame(
    Date    = as.Date(c("2019-05-01", "2019-06-01", "2019-09-01")),
    exscore = c(2.0, 2.0, 2.0),
    score   = c(1, 3, 99)
  )
  out <- comparable_outcomes(2.0, history, tol = 0.05, as_of = "2019-07-01")
  expect_equal(out$occurrences, 2)   # the September game is not eligible
  expect_equal(out$mean_score, 2)    # mean(1, 3), not mean(1, 3, 99) = 34.33
})

test_that("comparable_outcomes still works on an undated fixture", {
  # No Date column means no time to leak, so the guard must not fire.
  history <- data.frame(exscore = c(1.9, 2.0, 2.1), score = c(4, 5, 6))
  out <- comparable_outcomes(2.0, history, tol = 0.05)
  expect_equal(out$occurrences, 3)
})

test_that("expected_score is a pure function of its six inputs", {
  a <- expected_score(0.45, 8, 0.22, 0.20, 0.40, 0.42)
  b <- expected_score(0.45, 8, 0.22, 0.20, 0.40, 0.42)
  expect_equal(a, b)
  # More opposing strikeouts lowers the expected score, which is the sign the coefficient
  # block has to preserve. The legacy version repeated this expression four times by hand.
  expect_lt(expected_score(0.45, 8, 0.30, 0.20, 0.40, 0.42), a)
})

test_that("to_team_rows produces two rows per game and a correct win flag", {
  games <- data.frame(
    teams.home.score = c(5, 2), teams.away.score = c(3, 7),
    home_expected_score = c(4.8, 3.1), away_expected_score = c(3.9, 5.2),
    home_exscore = c(1.1, 0.9), away_exscore = c(0.8, 1.4)
  )
  out <- to_team_rows(games)
  expect_equal(nrow(out), 4)
  expect_equal(sum(out$win), 2)                    # exactly one winner per game
  expect_equal(out$actual_diff, c(2, -5, -2, 5))
})

test_that("impute_column_means leaves a complete column untouched", {
  df <- data.frame(a = c(1, 2, NA, 4), b = c(1, 2, 3, 4))
  out <- impute_column_means(df)
  expect_equal(out$a[3], mean(c(1, 2, 4)))
  expect_equal(out$b, df$b)
})
