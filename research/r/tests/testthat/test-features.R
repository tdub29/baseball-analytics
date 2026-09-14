library(testthat)

test_that("normalize_team resolves the two-team cities by league", {
  expect_equal(normalize_team("Chicago, IL", "Maj-AL"), "Chicago White Sox")
  expect_equal(normalize_team("Chicago, IL", "Maj-NL"), "Chicago Cubs")
  expect_equal(normalize_team("New York, NY", "Maj-AL"), "New York Yankees")
  expect_equal(normalize_team("New York, NY", "Maj-NL"), "New York Mets")
  expect_equal(normalize_team("Los Angeles, CA", "Maj-AL"), "Los Angeles Angels")
  expect_equal(normalize_team("Los Angeles, CA", "Maj-NL"), "Los Angeles Dodgers")
})

test_that("a one-team city resolves under the wrong league instead of dropping out", {
  # This is the case the legacy file patched with 'Cincinnati AL' -> Cincinnati Reds in
  # the pitcher loop only. A mid-season trade produces it; the batter loop lost the row.
  expect_equal(normalize_team("Cincinnati, OH", "Maj-AL"), "Cincinnati Reds")
  expect_equal(normalize_team("Pittsburgh, PA", "Maj-AL"), "Pittsburgh Pirates")
  expect_equal(normalize_team("San Diego, CA", "Maj-AL"), "San Diego Padres")
})

test_that("an unknown club is NA, never a half-parsed string", {
  expect_true(is.na(normalize_team("Montreal, QC", "Maj-NL")))
})

test_that("safe_div returns NA on a zero denominator rather than Inf", {
  expect_true(is.na(safe_div(5, 0)))
  expect_true(is.na(safe_div(5, NA)))
  expect_equal(safe_div(6, 3), 2)
  # Inf is the failure mode: it survives na.rm = TRUE and poisons every downstream mean.
  expect_false(is.infinite(safe_div(5, 0)))
})

test_that("batting_rates reproduces known slash-line arithmetic", {
  df <- data.frame(
    H = 100, AB = 400, BB = 40, HBP = 5, SF = 5, IBB = 2,
    X1B = 60, X2B = 20, X3B = 5, HR = 15, uBB = 38
  )
  out <- batting_rates(df)
  expect_equal(out$avg, 0.25)
  expect_equal(out$obp, (100 + 40 + 5) / (400 + 40 + 5 + 5))
  expect_equal(out$slg, (60 + 40 + 15 + 60) / 400)
  expect_equal(out$OPS, out$obp + out$slg)
  expect_gt(out$wOBA, 0.25)
  expect_lt(out$wOBA, 0.45)
})

test_that("pitching_rates reproduces FIP, ERA and WHIP", {
  df <- data.frame(HR = 10, BB = 30, HBP = 5, SO = 90, IP = 100, ER = 40, H = 85, AB = 380)
  out <- pitching_rates(df)
  expect_equal(out$fip, ((13 * 10) + (3 * 35) - (2 * 90)) / 100 + 3.134)
  expect_equal(out$era, 3.6)
  expect_equal(out$whip, 1.20)
})

test_that("slugging weights the four hit types 1/2/3/4", {
  expect_equal(slugging(10, 5, 2, 3, 100), (10 + 10 + 6 + 12) / 100)
  expect_true(is.na(slugging(10, 5, 2, 3, 0)))
})

test_that("team_batting drops a below-threshold window instead of ranking it", {
  daily <- data.frame(
    Team = c("Chicago, IL", "Chicago, IL"),
    Level = c("Maj-NL", "Maj-NL"),
    as_of = as.Date(c("2019-05-01", "2019-05-02")),
    PA = c(150, 40), H = c(40, 10), AB = c(130, 35), BB = c(15, 4),
    HBP = c(2, 0), SF = c(2, 1), IBB = c(1, 0),
    X1B = c(25, 7), X2B = c(9, 2), X3B = c(1, 0), HR = c(5, 1), uBB = c(14, 4)
  )
  out <- team_batting(daily, min_pa = 100)
  expect_equal(nrow(out), 1)
  expect_equal(out$as_of, as.Date("2019-05-01"))
})

test_that("split_pitching sends starters through individually and relievers as a team", {
  daily <- data.frame(
    Team = rep("Boston, MA", 3), Level = rep("Maj-AL", 3),
    Name = c("SP One", "RP One", "RP Two"),
    as_of = as.Date(rep("2019-05-01", 3)),
    GS = c(1, 0, 0),
    HR = c(2, 1, 1), BB = c(5, 3, 2), HBP = c(1, 0, 1), SO = c(30, 12, 10),
    IP = c(40, 15, 12), ER = c(12, 5, 4), H = c(35, 14, 11), AB = c(150, 55, 44)
  )
  out <- split_pitching(daily)
  expect_equal(nrow(out$starters), 1)
  expect_equal(out$starters$Name, "SP One")
  expect_equal(nrow(out$relievers), 1)     # two relievers collapse to one bullpen row
  expect_equal(out$relievers$IP, 27)
  expect_equal(out$relievers$SO, 22)
})

test_that("prefix_cols leaves the join keys alone and renames everything else", {
  df <- data.frame(Team = "Boston Red Sox", as_of = as.Date("2019-05-01"), slg = 0.44)
  out <- prefix_cols(df, "hbat_", c("Team", "as_of"))
  expect_true(all(c("Team", "as_of", "hbat_slg") %in% names(out)))
  expect_false("hbat_Team" %in% names(out))
})
