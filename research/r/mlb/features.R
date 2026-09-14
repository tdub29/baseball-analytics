# MLB features: team name normalisation, rate stats, and the game-level join.
#
# Every function here is pure: data frame in, data frame out, no network and no globals.
# That is what makes the testthat suite runnable offline, which the legacy file could not
# be at any granularity because it was one 604-line top-level script.

library(dplyr)
library(tidyr)

# --- team names ---------------------------------------------------------------------

# Baseball Reference reports "Chicago, IL" plus a Level of "Maj-AL" / "Maj-NL", so the
# city alone is ambiguous for the five two-team cities. The legacy file handled this with
# 82 hand-written `out$Team[out$Team == 'Chicago AL'] <- ...` lines, duplicated almost
# verbatim in the batter loop and the pitcher loop, and the two copies had drifted:
# 'San Diego NL' appeared twice in the batter copy (so 'San Diego AL' was never mapped)
# and 'Cincinnati AL' / 'Pittsburgh AL' existed only in the pitcher copy. One table, used
# by both, is the fix, and the drift is the argument for it.
TEAM_BY_CITY_LEAGUE <- c(
  "Arizona NL"       = "Arizona Diamondbacks",
  "Atlanta NL"       = "Atlanta Braves",
  "Baltimore AL"     = "Baltimore Orioles",
  "Boston AL"        = "Boston Red Sox",
  "Chicago AL"       = "Chicago White Sox",
  "Chicago NL"       = "Chicago Cubs",
  "Cincinnati NL"    = "Cincinnati Reds",
  "Cleveland AL"     = "Cleveland Indians",
  "Colorado NL"      = "Colorado Rockies",
  "Detroit AL"       = "Detroit Tigers",
  "Houston AL"       = "Houston Astros",
  "Kansas City AL"   = "Kansas City Royals",
  "Los Angeles AL"   = "Los Angeles Angels",
  "Los Angeles NL"   = "Los Angeles Dodgers",
  "Miami NL"         = "Miami Marlins",
  "Milwaukee NL"     = "Milwaukee Brewers",
  "Minnesota AL"     = "Minnesota Twins",
  "New York AL"      = "New York Yankees",
  "New York NL"      = "New York Mets",
  "Oakland AL"       = "Oakland Athletics",
  "Philadelphia NL"  = "Philadelphia Phillies",
  "Pittsburgh NL"    = "Pittsburgh Pirates",
  "San Diego NL"     = "San Diego Padres",
  "San Francisco NL" = "San Francisco Giants",
  "Seattle AL"       = "Seattle Mariners",
  "St. Louis NL"     = "St. Louis Cardinals",
  "Tampa Bay AL"     = "Tampa Bay Rays",
  "Texas AL"         = "Texas Rangers",
  "Toronto AL"       = "Toronto Blue Jays",
  "Washington NL"    = "Washington Nationals"
)

# A player traded mid-season shows up under the wrong league for a few days. The legacy
# file papered over that with entries like 'Cincinnati AL' -> Cincinnati Reds. Falling
# back on the city alone is the same fix without 30 more rows, and it is league-agnostic.
TEAM_BY_CITY <- {
  cities <- sub(" (AL|NL)$", "", names(TEAM_BY_CITY_LEAGUE))
  one_team <- names(which(table(cities) == 1))
  stats::setNames(
    unname(TEAM_BY_CITY_LEAGUE)[cities %in% one_team],
    cities[cities %in% one_team]
  )
}

#' Resolve a Baseball Reference "Team" plus "Level" pair to a full club name.
#'
#' Unmapped input returns NA rather than a half-parsed string, so a name change shows up
#' as a visible NA instead of silently dropping out of a join.
normalize_team <- function(team, level) {
  city   <- trimws(sub(",.*$", "", team))
  league <- substr(level, 5, 6)
  out <- unname(TEAM_BY_CITY_LEAGUE[paste(city, league)])
  fallback <- unname(TEAM_BY_CITY[city])
  ifelse(is.na(out), fallback, out)
}

# --- rate stats ---------------------------------------------------------------------

# wOBA weights are the 2013 Fangraphs constants the legacy file hardcoded. Kept as a named
# vector so a reader can see which season they belong to and swap them per year.
WOBA_WEIGHTS_2013 <- c(uBB = 0.687, HBP = 0.718, X1B = 0.881,
                       X2B = 1.256, X3B = 1.594, HR = 2.065)
FIP_CONSTANT <- 3.134

#' Team batting rates from summed counting stats.
batting_rates <- function(df, w = WOBA_WEIGHTS_2013) {
  df |>
    dplyr::mutate(
      avg  = safe_div(.data$H, .data$AB),
      obp  = safe_div(.data$H + .data$BB + .data$HBP,
                      .data$AB + .data$BB + .data$HBP + .data$SF),
      slg  = safe_div(.data$X1B + 2 * .data$X2B + 3 * .data$X3B + 4 * .data$HR, .data$AB),
      OPS  = .data$obp + .data$slg,
      wOBA = safe_div(
        w[["uBB"]] * .data$uBB + w[["HBP"]] * .data$HBP + w[["X1B"]] * .data$X1B +
          w[["X2B"]] * .data$X2B + w[["X3B"]] * .data$X3B + w[["HR"]] * .data$HR,
        .data$AB + .data$BB - .data$IBB + .data$SF + .data$HBP
      )
    )
}

#' Pitching rates from summed counting stats.
pitching_rates <- function(df, fip_c = FIP_CONSTANT) {
  df |>
    dplyr::mutate(
      fip   = safe_div(13 * .data$HR + 3 * (.data$BB + .data$HBP) - 2 * .data$SO,
                       .data$IP) + fip_c,
      era   = 9 * safe_div(.data$ER, .data$IP),
      whip  = safe_div(.data$BB + .data$HBP + .data$H, .data$IP),
      kperc = safe_div(.data$SO, .data$AB)
    )
}

#' Slugging from the four hit-type counts, for any prefix (rp, sp, arp, asp).
slugging <- function(singles, doubles, triples, hr, ab) {
  safe_div(singles + 2 * doubles + 3 * triples + 4 * hr, ab)
}

#' Divide, returning NA rather than Inf when the denominator is zero.
#'
#' The legacy file divided by AB and IP unguarded. A reliever with 0 AB in the window gave
#' Inf, which then propagated through every downstream mean() as Inf rather than being
#' dropped by na.rm.
safe_div <- function(num, den) ifelse(is.na(den) | den == 0, NA_real_, num / den)

# --- aggregation --------------------------------------------------------------------

#' Sum a team's batting counting stats for each as-of date, then compute rates.
#'
#' `min_pa` drops the partial rows the legacy file removed with `filter(df$PA > 100)`,
#' which it applied AFTER the loop rather than per window, so early-season windows were
#' filtered against a season-scale threshold.
team_batting <- function(daily, min_pa = 100) {
  daily |>
    dplyr::mutate(Team = normalize_team(.data$Team, .data$Level)) |>
    dplyr::filter(!is.na(.data$Team)) |>
    dplyr::group_by(.data$Team, .data$as_of) |>
    dplyr::summarise(dplyr::across(dplyr::where(is.numeric), ~ sum(.x, na.rm = TRUE)),
                     .groups = "drop") |>
    dplyr::filter(.data$PA > min_pa) |>
    batting_rates()
}

#' Split pitchers into starters and relievers, aggregate relievers to the team.
#'
#' A starter is kept as an individual row because the game-level join matches the probable
#' starter by name. Relievers are only ever used as a bullpen aggregate.
split_pitching <- function(daily) {
  tidy <- daily |>
    dplyr::mutate(
      Team     = normalize_team(.data$Team, .data$Level),
      position = ifelse(.data$GS < 1, "RP", "SP")
    ) |>
    dplyr::filter(!is.na(.data$Team))

  starters <- tidy |>
    dplyr::filter(.data$position == "SP") |>
    pitching_rates()

  relievers <- tidy |>
    dplyr::filter(.data$position == "RP") |>
    dplyr::group_by(.data$Team, .data$as_of) |>
    dplyr::summarise(dplyr::across(dplyr::where(is.numeric), ~ sum(.x, na.rm = TRUE)),
                     .groups = "drop") |>
    pitching_rates()

  list(starters = starters, relievers = relievers)
}

# --- the game-level join ------------------------------------------------------------

#' Attach each side's batting, bullpen and probable-starter lines to one game row.
#'
#' The legacy version was ten sqldf queries against three dialects, held together by
#' hardcoded column-index surgery: `colnames(X)[93:118] <- ...`, `X <- X[,-154]`,
#' `colnames(NEW)[150] = "Home Starter"`. Any upstream column change silently renamed the
#' wrong fields, and nothing would have errored. Prefixed joins on named keys cannot
#' misalign, and they do not care how many columns the source has.
build_game_features <- function(schedule, batting, starters, relievers, probables) {
  home_sp <- probables |>
    dplyr::select(game_pk, Team = team, starter = fullName)
  away_sp <- home_sp

  join_side <- function(games, side_team, prefix) {
    games |>
      dplyr::left_join(prefix_cols(batting, paste0(prefix, "bat_"), c("Team", "as_of")),
                       by = stats::setNames(c("Team", "as_of"), c(side_team, "Date"))) |>
      dplyr::left_join(prefix_cols(relievers, paste0(prefix, "rp_"), c("Team", "as_of")),
                       by = stats::setNames(c("Team", "as_of"), c(side_team, "Date")))
  }

  out <- schedule |>
    join_side("HTeam", "h") |>
    join_side("ATeam", "a")

  attach_starter <- function(games, side_team, prefix) {
    side <- home_sp |> dplyr::rename(!!paste0(prefix, "starter") := starter)
    games |>
      dplyr::left_join(side, by = stats::setNames(c("game_pk", "Team"),
                                                  c("game_pk", side_team))) |>
      dplyr::left_join(
        prefix_cols(starters, paste0(prefix, "sp_"), c("Name", "as_of")),
        by = stats::setNames(c("Name", "as_of"), c(paste0(prefix, "starter"), "Date"))
      )
  }

  out |>
    attach_starter("HTeam", "h") |>
    attach_starter("ATeam", "a")
}

#' Prefix every column except the join keys, so two sides never collide.
prefix_cols <- function(df, prefix, keys) {
  dplyr::rename_with(df, ~ paste0(prefix, .x), .cols = -dplyr::all_of(keys))
}
