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

test_that("asof_decay matches decay_sum, carries seasons by c, and adds lambda on recent days", {
  set.seed(3)
  ev <- data.frame(entity = sample(c("A", "B", "C"), 300, TRUE),
                   Date = as.Date("2019-04-01") + sample(0:150, 300, TRUE), v = rpois(300, 3))
  ev$season <- 2019L; ev$t <- as.numeric(ev$Date)
  q <- data.frame(entity = c("A", "B", "C", "D"), Date = as.Date("2019-07-01"), season = 2019L)
  q$t <- as.numeric(q$Date)
  got <- asof_decay(ev, q, "v", h = 14)[, 1]
  ref <- sapply(1:3, function(i) { e <- ev[ev$entity == q$entity[i], ]; decay_sum(e$Date, e$v, q$Date[i], 14) })
  expect_equal(got, c(ref, 0))
  # lambda adds the plain sum of the last r calendar days
  lam <- asof_decay(ev, q, "v", h = 14, lambda = 2, r = 7)[, 1]
  rec <- sapply(1:3, function(i) { e <- ev[ev$entity == q$entity[i], ]; trailing_sum(e$Date, e$v, q$Date[i], 7) })
  expect_equal(lam, c(ref + 2 * rec, 0))
  # carry: an event one season back weighs c on top of its in-season decay
  two <- data.frame(entity = "A", Date = as.Date(c("2018-09-30", "2019-04-01")), v = c(1, 1),
                    season = c(2018L, 2019L), t = c(100, 101))
  qq  <- data.frame(entity = "A", Date = as.Date("2019-04-02"), season = 2019L, t = 102)
  expect_equal(unname(asof_decay(two, qq, "v", h = 10, c = 0.5)[, 1]), 0.5 * 0.5^(2 / 10) + 0.5^(1 / 10))
  expect_equal(unname(asof_decay(two, qq, "v", h = 10, c = 0)[, 1]), 0.5^(1 / 10))
})

test_that("asof_decay never sees the query date or later", {
  set.seed(4)
  ev <- data.frame(entity = sample(c("A", "B"), 200, TRUE),
                   Date = as.Date("2019-04-01") + sample(0:120, 200, TRUE), v = rpois(200, 3), season = 2019L)
  ev$t <- as.numeric(ev$Date)
  q  <- data.frame(entity = c("A", "B"), Date = as.Date("2019-06-01"), season = 2019L); q$t <- as.numeric(q$Date)
  run <- function(e) asof_decay(e, q, "v", h = 30, c = 0.5, lambda = 1, r = 7)
  later <- ev; later$v[later$Date >= q$Date[1]] <- 1000
  expect_equal(run(later), run(ev))
  earlier <- ev; earlier$v[earlier$Date == q$Date[1] - 1] <- 1000
  expect_false(isTRUE(all.equal(run(earlier), run(ev))))
})

test_that("season_day removes offseason days", {
  b <- data.frame(season = 2018:2019, start = as.Date(c("2018-03-29", "2019-03-20")),
                  end = as.Date(c("2018-10-01", "2019-09-29")))
  expect_equal(season_day(as.Date(c("2018-10-01", "2019-03-20")), 2018:2019, b), c(186, 187))
})
