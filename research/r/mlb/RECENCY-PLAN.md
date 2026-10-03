# Plan: which look-back window to trust, per component

Charter v2, 2026-10-02, still before any window result was looked at. v1 (commit 54ddec9) was
revised after an independent critique; what changed and why is in the iteration log. If anything
below changes after a validation result is seen, the change is logged with the reason; if it
changes after the test is scored, the test result is exploratory and 2026 becomes the test.

## Question

Predicting an MLB game with only what is known before that day: for hitters, starting pitchers
and bullpens separately, how fast does old data go stale, how much should a thin sample be pulled
toward average, and does recent form add anything beyond a smoothly decaying talent estimate?

Each component ends in one of three verdicts: recency matters, recency is equivalent to zero
(within the smallest effect of interest), or inconclusive. "Not significant" is never reported as
"no effect".

## Data

MLB StatsAPI, key-free (`gamelogs.R`, `fetch_gamelogs.R`):
- each player's line per appearance (hitting; pitching with pitches, inherited runners and
  inherited runners scored, saves, holds, games finished);
- the schedule with venue, probable starters and the posted starting lineups in batting order
  (lineups post before first pitch, so they are legal pregame);
- team lines per game, rosters.

Seasons 2015-2025. 2020 (60 games) is history only, so 2021 does not inherit a 17-month hole.

## Split (fixed now)

| Role | Seasons | Use |
|---|---|---|
| History only | 2015, 2016, 2020 | feeds windows, never scored |
| Validation | 2017, 2018, 2019 | every choice; selections are checked leave-one-season-out |
| Test, scored once | 2021-2025 | frozen choices, reported per season and per era: 2021, 2022, 2023-25 |

Eras: 2022 brought the universal DH; 2023 the pitch clock, shift ban and bigger bases. Tuning is
frozen on 2017-2019 for every test season.

## As-of rule

An estimate for a game on date d uses appearances dated before d only (doubleheader game 2 does
not see game 1). League rates and park factors obey the same rule. Leak tests: rows on or after d
are scrambled or added and the estimate for d must not move; a control that perturbs rows before
d must move it.

## The estimator (one family, every component)

For an entity (hitter, pitcher, relief group, team) and a rate (events per opportunity):

- **Decay.** Weight on an appearance = 0.5^(a / h) x c^s + lambda x [d - date <= r], where a is
  its age in in-season days (offseason days do not count), s the number of season boundaries
  between it and the game, h the in-season half-life, c the carry weight per season back, and
  lambda an extra weight on appearances in the last r calendar days (r in {7, 14}).
- **Shrink.** estimate = (weighted events + k x league) / (weighted opportunities + k).
- **League target.** League rate from all appearances, decayed with a 30-day in-season half-life
  and carried across the offseason, so it tracks the ball, weather and rule changes. The same
  target is the baseline every candidate is scored against.
- **Park.** Each appearance and each outcome is divided by its venue's factor for that rate,
  built from games before d at that venue against the league over the three prior seasons,
  shrunk toward 1. Venue ids come from the schedule (temporary and neutral parks get their own).

h, c and k are chosen together on a grid; reliability (split-half r against sample size, with
Spearman-Brown, effective n = (sum w)^2 / sum w^2) is reported to explain the chosen k, not to
set it.

Grid (every cell logged; the best-of-grid validation score is biased upward and is never quoted
as expected skill): h in {7, 14, 30, 60, 120, 240, Inf} in-season days; c in {0, 0.25, 0.5, 0.75,
1}; k on a log grid of 8 values per rate; lambda in {0, 0.5, 1, 2} for r in {7, 14}.

## Components, rates, outcomes (per opportunity, so the manager's hook does not set the score)

| Component | Unit of prediction | Rates | Outcome |
|---|---|---|---|
| Hitters | hitter-game, starting lineup | wOBA per PA (fixed linear weights, approximate 2016 values, never refit), K per PA, BB+HBP per PA, HR per PA | the same rates in that game, PA-weighted |
| Starting pitcher | start (GS with 7+ outs; shorter starts are flagged openers and go to the bullpen) | K per BF, BB+HBP per BF, HR per BF, runs per BF | the same rates in that start, BF-weighted |
| Reliever | reliever appearance | K-BB per BF, FIP-style per BF, runs per BF (own runs plus inherited runners he let score) | the same in that appearance |
| Team | team-game | run differential per game, offense from non-pitcher hitter lines only | game margin |

Bullpen fatigue is a separate term, not a window: pitches thrown by the team's relievers in the
previous 1 and 3 days, entered in the win model. Its effect is selected (managers rest tired
arms) and is reported as an association.

## Tests

1. **How fast data goes stale (the decay curve).** For each component and rate, held-out skill
   (weighted MSE reduction against the league target) across h, at each component's best c and k.
   Selected leave-one-season-out on 2017-2019; the three held-out choices are reported.
2. **Does recent form add (lambda).** Held-out skill gain of the best lambda > 0 over lambda = 0,
   same rotation.
3. **Smallest effect of interest.** A component-level gain of 0.1% of the outcome's variance
   (talent explains only a few percent of single-game variance), and a win-level log-loss gain of
   0.001. Verdicts by equivalence test (two one-sided 90% intervals): above the SESOI = matters;
   inside plus or minus SESOI = equivalent to zero; otherwise inconclusive.
4. **Uncertainty.** Cluster bootstrap resampling team-seasons (hitters, team) or pitcher-seasons
   (starters, relievers), 1,000 draws. Minimum detectable effect stated per component.
5. **Out of sample.** After freezing, the decay curves and lambda gains are re-scored once on
   2021-2025, per era. This is the answer to the owner's question, not just the win model.
6. **Stability.** The chosen (h, c) on 2017-2018 alone vs 2017-2019; April-May vs June-September
   chosen h reported separately.

## Win model and baselines

One row per game, home side. Walk-forward weekly refit (each Monday-Sunday block fit on games
before that Monday), as in `walk_forward()`. The starter input is the probable starter.

| Tier | Model |
|---|---|
| A | constant (training home rate) |
| B | home field only |
| C, incumbent | frozen run-differential model (commit b15a7af: run gap + season-to-date run differential, k = 20) |
| D | Elo with margin; K and between-season regression chosen on validation |
| E0, ablation | E's inputs with no decay and no recency term (all history, c = 1, lambda = 0) |
| E, candidate | logistic on home field + lineup, probable starter, bullpen (relief-BF weighted, role-weighted by saves and holds), fatigue and run differential gaps, each with its chosen window |

E vs E0 is the game-by-game recency answer at win level. E vs C is the slide decision.

Metrics, locked: log loss primary; Brier (mean (p - y)^2, 0 to 1) secondary; calibration as
intercept and slope from a logistic recalibration fit, with a 10-bin table for display; accuracy
reported, never decisive. Paired cluster bootstrap (team-season) of per-game log-loss differences,
plus the per-season table. Win-level power, from the critique's estimate: a 0.002 gain is
detectable at about 0.98, a 0.001 gain at about 0.45, so a 0.001 result is reported as
inconclusive unless it clears the interval.

Market odds: no key-free licensed historical source is in hand, so there is no market baseline.
Results are not evidence of betting profit and the writeup says so.

## Decision rules (fixed now)

- Chosen window per component: best held-out skill; if a longer h or larger c is inside its
  bootstrap interval, take the longer one.
- E ships (replaces C on the slide) only if, on 2021-2025: pooled log loss beats C with the paired
  95% interval above zero, E beats C in at least 4 of the 5 seasons, the leakage verifier finds no
  look-ahead, and the calibration intercept interval covers 0 and the slope interval covers 1.
- Otherwise the slide keeps C's number, and the study's findings stand on their own.

## Done

`results/recency-study.md`: per component, in plain words, how fast data goes stale, how much to
shrink, and whether recent form adds, with the verdict and its interval, validation and test;
reliability curves; the per-season and per-era test tables; E vs E0 and E vs C; the leakage
verdict. Then the slide decision, the accomplishments row, commits.

## Iteration log

- 2026-10-02, it 1: charter v1 written after a max skill scout (lead: `sports-modeling-doctrine`,
  `validation-design`); its critiques folded in (log loss primary, per-season and per-era test
  table, 4-of-5 rule, Elo tier, opponent covariate, stability rerun, counted grid). Game-log fetch
  for 2015-2025 running; 2019 probe: 2,429 games, 21,342 pitcher lines, 50,174 hitter lines.
- 2026-10-02, it 2: `windows.R` as-of estimators (calendar-day decay on a daily grid, trailing
  days, last N starts, shrinkage, league rate) with exact-arithmetic and leak tests; suite 96 green.
- 2026-10-02, it 3: charter v2 after an independent critique, before any result. Adopted: the
  window answer itself is re-scored on the test (not only E vs C), plus an E0 no-decay ablation;
  park adjustment by venue; a decayed league target instead of all-history; (h, c, k) chosen
  jointly, held out by season, instead of k from split-half; recency as a lambda term inside one
  estimator instead of long + short regression; per-PA and per-BF outcomes instead of runs;
  per-appearance reliever study with inherited runners; equivalence verdicts with a SESOI and
  cluster bootstrap; posted starting lineups from the schedule instead of realized PA; openers
  routed to the bullpen; in-season decay plus a carry weight; 2020 fetched as history; hitter-only
  offense (universal DH); eras 2021 | 2022 | 2023-25; calibration by intercept and slope.
  Dropped from v1: the opponent covariate per component (park and league target take its job;
  Elo stays as a rival).
