# Plan: which look-back window to trust, per component

Written 2026-10-02, before any window result was looked at. Charter v1. If anything below changes
after a validation result is seen, the change is logged at the bottom with the reason; if it
changes after the test is scored, the test result is exploratory and 2026 becomes the test.

## Question

Predicting an MLB game with only what is known before that day: for hitters, starting pitchers
and bullpens separately, how much past data should the estimate use, how fast does old data go
stale, and does recent form add anything once a long, shrunk window is in?

A null answer ("recency adds nothing beyond talent") is a valid result.

## Data

StatsAPI game logs (`gamelogs.R`, `fetch_gamelogs.R`): each team's hitting and pitching line per
game; every pitcher's and hitter's line per appearance (pitch counts, saves, holds included);
full-season rosters; the schedule with probable starters. Seasons 2015-2019 and 2021-2025.

## Split (fixed now)

| Role | Seasons | Use |
|---|---|---|
| History only | 2015-2016 | feeds windows, never scored |
| Validation | 2017-2019 | every choice: windows, half-lives, shrink constants, model terms |
| Test, scored once | 2021-2025 | frozen model, reported per season and as 2021-22 vs 2023-25 |

2019 was the old model's test; it is validation now. 2020 is excluded. 2023 brought the pitch
clock, shift ban and bigger bases, so the test is reported in two eras as well as pooled.
Tuning stays frozen on 2017-2019 for every test season (no re-tuning inside the test).

## As-of rule

An estimate for a game on date d uses appearances dated before d only. Doubleheader game 2 does
not see game 1. Leak test (required, offline): scramble or delete every row on or after d and
the estimate for d must not change; a control that perturbs rows before d must change it.

## Components

| Component | Estimate | Opportunity unit | Outcome it must predict |
|---|---|---|---|
| Team offense | linear-weights wOBA per PA from team hitting lines | PA | runs scored that game |
| Lineup | PA-weighted mean of each hitter's own shrunk wOBA, for that game's hitters with 3+ PA | PA | runs scored that game |
| Starter | K-BB per BF; FIP-style (13HR + 3(BB+HBP) - 2K) per BF; runs per BF | BF | starter's runs allowed per out that game, and his K-BB per BF |
| Bullpen skill | relief-BF-weighted mean of the shrunk rates of pitchers who relieved for the team in the last 21 days | BF | bullpen runs allowed per out that game |
| Bullpen fatigue | pitches thrown in the previous 1 and 3 days by that relief group | pitches | bullpen runs allowed per out that game, given skill |
| Team run differential | runs scored minus allowed per game | games | game margin |

The lineup uses the hitters who actually batted. Lineups post about three hours before first
pitch, so this is legal for a pregame model, but counting pinch hitters is a mild optimism; it is
flagged in the writeup, not hidden.

Opponent strength: raw form is not schedule-adjusted, which can hide recency. Each component is
also run with the opponent's long-window estimate as a covariate, and Elo is a competitor (below).

## Windows (the grid, counted)

- Exponential decay on calendar days, weight 0.5^(age/h), h in {3, 7, 14, 30, 60, 120, 240, 480,
  960} days, plus no decay. History carries across seasons; the offseason ages it.
- Fixed windows for plain-words answers: last 7, 16, 32, 64 days; season to date; prior season
  only; everything since 2015.
- Starters also: last 1, 3, 5, 10, 20 starts.
- About 20 windows x 6 components x up to 3 metrics, roughly 300 cells. Every cell is logged,
  and the best-of-grid validation score is reported as biased upward, never as expected skill.

Shrinkage, always applied before comparing windows: estimate = (sum of weighted events + k x
league rate) / (weighted opportunities + k). League rate = all games before d. k per component
and metric from split-half reliability on validation: k = n(1 - r)/r at the sample n where r is
measured (odd vs even appearances, Spearman-Brown). Without this, short windows lose only
because small samples are noisy.

## Tests

1. **Reliability.** Split-half r against sample size per component and metric, the stabilization
   point (r = 0.5) and k.
2. **Which window predicts.** For each shrunk window, skill against the outcome: weighted MSE
   relative to the league-rate prediction, weighted by the outcome's opportunities.
3. **Does recency add.** outcome ~ long + short, both shrunk, long = best long window, short in
   {7, 16, 32 days, last 3 starts}. Recency "matters" for a component only if the short term's
   incremental skill has a week-block bootstrap 95% interval above zero on 2017-2019 pooled AND
   the same sign in each of 2017, 2018, 2019.
4. **Stability of the choice.** Rerun the half-life selection on 2017-2018 only; report whether
   the chosen h moves. A flat loss surface is not, alone, evidence of robustness.

## Win model and baselines

One row per game, home side. Walk-forward weekly refit (each Monday-Sunday block fit on games
before that Monday), as in `walk_forward()`.

| Tier | Model |
|---|---|
| A | constant (training home rate) |
| B | home field only |
| C, incumbent | frozen run-differential model (commit b15a7af: run gap + season-to-date run differential, k = 20) |
| D | Elo with margin, K and between-season regression tuned on validation |
| E, candidate | logistic on home field + best-window lineup, starter, bullpen skill, bullpen fatigue gaps (+ run differential if it still adds) |

Metrics, locked: log loss primary; Brier (mean (p - y)^2, 0 to 1 scale) and a calibration table
with bin counts secondary; accuracy reported, never decisive. Uncertainty: paired week-block
bootstrap of per-game log-loss differences, plus the per-season table.

Market odds: no key-free licensed historical source is in hand, so there is no market baseline.
Results are not evidence of betting profit and the writeup says so.

## Decision rules (fixed now)

- Best window per component: highest validation skill; if a longer window is inside its bootstrap
  interval, take the longer one.
- E ships (replaces C on the slide) only if, on 2021-2025: pooled log loss beats C with the paired
  week-block 95% interval above zero, E beats C in at least 4 of the 5 seasons, the leakage
  verifier finds no look-ahead, and calibration has no bin off by more than its 95% interval.
- Otherwise the slide keeps C's number, and the study's findings stand on their own.

## Done

`results/recency-study.md`: per component, in plain words, which window to trust, how fast data
goes stale, and whether recent form adds; reliability curves; the per-season test table; the
leakage verdict. Then the slide decision above, the accomplishments row, commits.

## Iteration log

- 2026-10-02, it 1: charter written after a max skill scout (lead: `sports-modeling-doctrine`,
  `validation-design`); its critiques folded in (log loss primary, per-season and per-era test
  table, 4-of-5 rule, Elo tier, opponent covariate, stability rerun, counted grid). Game-log fetch
  for 2015-2025 running; 2019 probe: 2,429 games, 21,342 pitcher lines, 50,174 hitter lines.
