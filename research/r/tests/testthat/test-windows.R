# Recency windows: as-of sums never see the query day or later, and the arithmetic is exact.

d <- as.Date("2019-05-01") + c(0, 1, 1, 5, 9)
x <- c(1, 2, 3, 4, 5)

test_that("decay_sum weights an event age days back by 0.5^(age/h), excluding the query day", {
  q <- as.Date("2019-05-06")                       # sees days 0, 1, 1 (ages 5, 4, 4); not day 5
  expect_equal(decay_sum(d, x, q, h = 2), 1 * 0.5^(5 / 2) + 5 * 0.5^(4 / 2))
  expect_equal(decay_sum(d, x, q, h = Inf), 6)
  expect_equal(decay_sum(d, x, as.Date("2019-05-01"), h = 2), 0)
})

test_that("trailing_sum and last_n_sum cover the window before the query only", {
  q <- as.Date("2019-05-10")                       # days 0..8 before; day 9 is the query day
  expect_equal(trailing_sum(d, x, q, days = 5), 4)   # [May 5, May 9]: the day-5 event only
  expect_equal(trailing_sum(d, x, q, days = 30), 10)
  expect_equal(last_n_sum(d, x, q, n = 2), 7)        # the last two events before May 10: 3 + 4
  expect_equal(last_n_sum(d, x, as.Date("2019-04-01"), n = 3), 0)
})

test_that("no window moves when events on or after the query date change, and all move before", {
  set.seed(7)
  ev <- data.frame(entity = sample(c("A", "B"), 200, TRUE),
                   Date = as.Date("2019-04-01") + sample(0:120, 200, TRUE), v = rpois(200, 3))
  q  <- data.frame(entity = c("A", "B", "A"), Date = as.Date(c("2019-06-01", "2019-06-01", "2019-07-15")))
  cut <- min(q$Date)
  run <- function(e) cbind(asof_sums(e, q, "v", decay_sum, 14), asof_sums(e, q, "v", trailing_sum, 16),
                           asof_sums(e, q, "v", last_n_sum, 5))
  base <- run(ev)
  later <- ev; i <- later$Date >= cut
  later$v[i] <- later$v[i] + 100
  later <- rbind(later, data.frame(entity = "A", Date = cut, v = 999))
  expect_equal(run(later)[1:2, ], base[1:2, ])        # both queries dated `cut` are untouched
  earlier <- ev; earlier$v[earlier$Date == cut - 1] <- 50
  expect_false(isTRUE(all.equal(run(earlier)[1:2, ], base[1:2, ])))
})

test_that("shrinkage pulls a thin sample to the league and leaves a big one near its own rate", {
  expect_equal(shrink_rate(3, 10, k = 90, league = 0.32), (3 + 28.8) / 100)
  expect_lt(abs(shrink_rate(3000, 10000, k = 90, league = 0.32) - 0.3), 0.001)
})
