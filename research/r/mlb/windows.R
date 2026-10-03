# As-of window sums for the recency study (RECENCY-PLAN.md).
#
# Every function answers "what did this entity do BEFORE date d": a query on d never sees an
# event dated d or later, so doubleheader game 2 does not see game 1. Sums are kept as
# numerator and denominator (events and opportunities) so any rate can be shrunk afterwards.

#' Exponentially decayed sums for one entity, as of the start of each query date.
#'
#' An event `age` days before the query weighs 0.5^(age / h); h = Inf is a plain cumulative
#' sum. Runs on a daily grid with a recursive filter, so long spans never overflow the way a
#' closed-form exp() would at small h.
decay_sum <- function(dates, x, query, h) {
  if (!length(query)) return(numeric(0))
  if (!length(dates)) return(numeric(length(query)))
  d0 <- min(dates, query)
  n  <- as.integer(max(dates, query) - d0) + 1L
  daily <- numeric(n)
  idx <- as.integer(dates - d0) + 1L
  daily <- daily + tabulate_sum(idx, x, n)
  a <- if (is.infinite(h)) 1 else 0.5^(1 / h)
  y <- as.numeric(stats::filter(daily, a, method = "recursive"))
  # value at the start of day q: everything through q - 1, aged one more day
  qi <- as.integer(query - d0) + 1L
  out <- ifelse(qi > 1L, a * y[pmax(qi - 1L, 1L)], 0)
  out
}

#' Sum of events in the `days` days before each query: [q - days, q - 1].
trailing_sum <- function(dates, x, query, days) {
  if (!length(query)) return(numeric(0))
  if (!length(dates)) return(numeric(length(query)))
  o <- order(dates); dates <- dates[o]; cs <- c(0, cumsum(x[o]))
  hi <- findInterval(as.numeric(query) - 1, as.numeric(dates))          # events <= q - 1
  lo <- findInterval(as.numeric(query) - days - 1, as.numeric(dates))   # events <= q - days - 1
  cs[hi + 1L] - cs[lo + 1L]
}

#' Sum over the last `n` events before each query (a starter's last n starts).
last_n_sum <- function(dates, x, query, n) {
  if (!length(query)) return(numeric(0))
  if (!length(dates)) return(numeric(length(query)))
  o <- order(dates); dates <- dates[o]; cs <- c(0, cumsum(x[o]))
  hi <- findInterval(as.numeric(query) - 1, as.numeric(dates))
  cs[hi + 1L] - cs[pmax(hi - n, 0L) + 1L]
}

tabulate_sum <- function(idx, x, n) {
  out <- numeric(n)
  s <- rowsum(x, idx, reorder = FALSE)
  out[as.integer(rownames(s))] <- s[, 1]
  out
}

#' Apply one window to many entities at once.
#'
#' `events` has `entity`, `Date` and the columns in `cols`; `queries` has `entity` and `Date`.
#' `fun` is decay_sum, trailing_sum or last_n_sum and `arg` its h, days or n. Returns one
#' column per entry of `cols`, aligned with `queries`; an entity with no history gets zeros.
asof_sums <- function(events, queries, cols, fun, arg) {
  out <- matrix(0, nrow(queries), length(cols), dimnames = list(NULL, cols))
  ev  <- split(seq_len(nrow(events)), events$entity)
  qs  <- split(seq_len(nrow(queries)), queries$entity)
  for (e in intersect(names(qs), names(ev))) {
    qi <- qs[[e]]; ei <- ev[[e]]
    for (c in cols) out[qi, c] <- fun(events$Date[ei], events[[c]][ei], queries$Date[qi], arg)
  }
  out
}

#' Shrink a rate toward the league: (events + k * league) / (opportunities + k).
shrink_rate <- function(num, den, k, league) (num + k * league) / (den + k)

#' League rate as of each query date from the trailing `days` days of every entity's events.
league_rate <- function(events, num, den, query, days = 365) {
  trailing_sum(events$Date, events[[num]], query, days) /
    pmax(trailing_sum(events$Date, events[[den]], query, days), 1)
}

#' Linear-weights wOBA numerator from a batting line (weights fixed across seasons on purpose:
#' the study compares windows, not eras, and a fixed scale keeps windows comparable).
woba_num <- function(l) {
  singles <- l$hits - l$doubles - l$triples - l$homeRuns
  0.69 * (l$baseOnBalls - l$intentionalWalks) + 0.72 * l$hitByPitch + 0.88 * singles +
    1.25 * l$doubles + 1.58 * l$triples + 2.03 * l$homeRuns
}
woba_den <- function(l) l$atBats + l$baseOnBalls - l$intentionalWalks + l$sacFlies + l$hitByPitch

#' FIP-style numerator per batter faced: 13 HR + 3 (BB + HBP) - 2 K (no constant; it is a rate).
fip_num <- function(l) 13 * l$homeRuns + 3 * (l$baseOnBalls + l$hitByPitch) - 2 * l$strikeOuts
kbb_num <- function(l) l$strikeOuts - l$baseOnBalls

# --- the study's workhorse: every entity at once -------------------------------------------

#' In-season day: days since the first game of the entity's season plus the lengths of every
#' earlier season, so offseason days never age anything. `bounds` has season, start, end.
season_day <- function(dates, seasons, bounds) {
  bounds <- bounds[order(bounds$season), ]
  len    <- as.numeric(bounds$end - bounds$start) + 1
  offset <- stats::setNames(c(0, cumsum(len))[seq_along(len)], bounds$season)
  start  <- stats::setNames(bounds$start, bounds$season)
  unname(offset[as.character(seasons)] + as.numeric(dates - start[as.character(seasons)]))
}

#' As-of decayed sums for many entities in one vectorised pass.
#'
#' `events` and `queries` carry entity, Date, season and t (season_day()). The weight on an
#' event dated before the query is 0.5^((t_q - t_e) / h) * c^(s_q - s_e) + lambda * [Date_q -
#' Date_e <= r]. Closed form with per-entity cumulative sums; exponents are anchored at each
#' entity's first event, so any h >= 5 over a decade of in-season days stays in double range.
#' c = 0 keeps the current season only. Returns one column per entry of `cols`.
asof_decay <- function(events, queries, cols, h, c = 1, lambda = 0, r = 7) {
  stopifnot(h >= 5, c >= 0, c <= 1)
  if (c == 0) {
    events$entity  <- paste(events$entity, events$season)
    queries$entity <- paste(queries$entity, queries$season)
    c <- 1
  }
  lev <- unique(c(events$entity, queries$entity))
  ei  <- match(events$entity, lev); qi <- match(queries$entity, lev)
  o   <- order(ei, events$Date); events <- events[o, , drop = FALSE]; ei <- ei[o]
  first <- match(seq_along(lev), ei)                          # first event row per entity, NA if none
  t0 <- events$t[first]; s0 <- events$season[first]
  L  <- if (is.infinite(h)) 0 else log(2) / h
  lc <- log(c)
  e_lw <- (events$t - t0[ei]) * L - (events$season - s0[ei]) * lc
  q_lw <- -(queries$t - t0[qi]) * L + (queries$season - s0[qi]) * lc
  ekey <- ei * 1e6 + as.numeric(events$Date)
  hi   <- findInterval(qi * 1e6 + as.numeric(queries$Date) - 1, ekey)      # rows dated <= d - 1
  lo   <- findInterval(qi * 1e6 + as.numeric(queries$Date) - r - 1, ekey)  # rows dated <= d - r - 1
  base <- first[qi] - 1L                                                   # rows before this entity
  has  <- !is.na(base) & hi > base
  out  <- matrix(0, nrow(queries), length(cols), dimnames = list(NULL, cols))
  for (col in cols) {
    x  <- events[[col]]
    cw <- c(0, cumsum(x * exp(e_lw)))
    cr <- c(0, cumsum(x))
    v  <- numeric(nrow(queries))
    v[has] <- (cw[hi[has] + 1] - cw[base[has] + 1]) * exp(q_lw[has])
    if (lambda > 0) {
      l2 <- pmax(lo, base)
      v[has] <- v[has] + lambda * (cr[hi[has] + 1] - cr[l2[has] + 1])
    }
    out[, col] <- v
  }
  out
}
