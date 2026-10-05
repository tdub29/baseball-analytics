# Can a public-data model beat Vegas, game by game?

**No.** Scored once on 6,451 games from 2023 to 2025, the frozen model's log loss was 0.0036 per
game worse than the no-vig closing line (95% interval 0.0016 to 0.0054). Its bets at the opening
line did see where the market was going, gaining 2.01 probability points of closing-line value per
bet [1.67, 2.35] on 561 bets, but the return those bets earned, +4.7% [-5.0%, +13.7%], cannot be
told apart from zero, and about ten seasons of bets would be needed before it could.

| | What was asked | Result on the frozen 2023-2025 test | Verdict under the pre-registered rule |
|---|---|---|---|
| Forecast | Does the model predict winners as well as the closing line? | Trails by 0.0036 [0.0016, 0.0054] log loss per game | Does not match the close |
| Money at the close | Do bets at closing prices make money? | 965 bets, -4.4% [-12.6%, +4.2%] | Not profitable |
| Skill at the open | Do bets at the opening line beat the close? | 561 bets, +2.01 points of closing-line value [1.67, 2.35] | Passes |
| Money at the open | Do those bets make money? | +4.7% [-5.0%, +13.7%] | Not profitable (interval spans zero) |
| Totals | Does a run model beat the closing over/under? | Trails by 0.0052 [0.0020, 0.0087] | Does not beat the closing total |

Sources: `results/matchup-model-v2-test.md`, `results/matchup-model-v2-dayahead-test.md`,
`results/totals-test.md`. Private research on scraped odds; not betting advice.

## The question

Can a model built only from free, public data (Retrosheet play-by-play and MLB's StatsAPI) put a
better probability on each MLB regular-season game than the sportsbooks do? The fair comparison is
the closing moneyline with the bookmaker's margin removed (the "no-vig close"): it is set at first
pitch, it carries everything the market has learned, and it is widely treated as the hardest
baseline in sports forecasting. The prior going in was that matching it would already be a strong
result, and a null result would be reported as an answer, not hidden.

Two secondary questions follow from it. If a model cannot beat the close, does it at least see
information early, so that its bets at the opening line move in its favour before first pitch
(closing-line value)? And does any of it turn into money once the bookmaker's margin is paid?

**How to read the numbers.** Log loss is the penalty a forecast pays for being confident and
wrong; lower is better, and a coin flip scores 0.6931 (`results/backtest-2019.md`). Single
baseball games are close to coin flips, so the whole range between "home team always" and the
betting market spans only about 0.02. A gap of 0.0036 sounds tiny; on this scale it is about a
quarter of everything the best model gains over home field in the same seasons (0.0145).

## The data

| Source | What it gives | Coverage used |
|---|---|---|
| Retrosheet play-by-play | Every regular-season plate appearance: batter, pitcher, hands, outcome, batted-ball type, park | 2015-2025 |
| MLB StatsAPI (key-free) | Schedules, posted lineups, starters, venues, game logs | 2015-2025 |
| Statcast batted balls | Exit velocity and launch angle, 1,282,277 balls, 97.8% matched to Retrosheet | 2015-2025 (tested, dropped) |
| Odds: SportsBookReview scrape (`ArnavSaraogi/mlb-odds-scraper`) | Opening and closing moneylines and totals from FanDuel, DraftKings, Bet365 and others | 2021-03-20 to 2025-08-16 |

Odds matched 10,583 games, 91.5% of model games in the odds window, with an average closing
overround of 1.044 and 5.6 books per game (`results/market-study.md`). September and October 2021
are excluded: their "closing" lines were scraped after first pitch (36% moved more than 15 points
from the open), which a sanity check caught on the first run (`MARKET-PLAN.md`, iteration 2). The
odds dataset has no stated license, so it stays local and only aggregates appear here.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.

## The method

The model is built the way a projection system is built, one layer at a time, and every layer had
to earn its place on validation seasons before the test was touched (`MATCHUP-PLAN.md`).

1. **Player skill, by handedness.** Each batter's and pitcher's per-plate-appearance rates
   (strikeout, walk, hit by pitch, single, double or triple, home run, out in play) against left-
   and right-handed opponents, decayed over time and shrunk toward the league with the windows the
   recency study chose (`results/recency-study.md`). Pitchers are rated on the league outcome mix of
   their batted-ball types, not on hits allowed, so hit and home-run luck stays out (the xFIP and
   SIERA idea).
2. **Matchup.** An odds-ratio (log5) combination of batter, pitcher and league rates for each of the
   nine hitters against the starter, park-adjusted by batter hand, split into the first two passes
   through the order and the third.
3. **Bullpen.** The remaining batters against the current relievers, weighted by role and recent
   availability.
4. **Runs, then wins.** Expected outcome counts become expected runs through run values fit on
   2015-2016 team-games only, and a logistic regression turns the run gaps into a home win
   probability. It is refit every Monday on every earlier game and predicts that week, so no game is
   ever predicted by a model that saw it.

That gives a ladder of candidates, scored side by side on identical games:

| Rung | What it adds |
|---|---|
| Home field only | The league home win rate |
| Team run margin only | Each team's decayed run differential |
| Incumbent | The earlier production model: season-to-date run differential |
| Recency model E | Long-window lineup, starter, bullpen and run-margin gaps (`RECENCY-PLAN.md`) |
| M1, M2 | Matchup expected runs, as a ratio and as starter and bullpen components |
| M3 | M2 plus team run margin |
| M4 | M3 plus rest and travel |
| M5 | M3 plus team defensive efficiency: the frozen pick |
| Ensemble | M5 and E averaged in logit space, weight 0.55 on M5, chosen on 2017-2019 |

**Decision time.** The main model predicts at first pitch: it uses the posted lineups and the actual
starter, which is also when the close is set. The opening-line test uses a day-ahead variant whose
lineups are projected from each team's last game against a same-handed starter.

## Pre-registration and the frozen test

Every rule that decides a verdict was written down before the data that tests it was looked at.

- **Charters first.** `MARKET-PLAN.md` was written before any prediction was compared with any line;
  `MATCHUP-PLAN.md` and `TOTALS-PLAN.md` fixed their decision rules on day one. Each keeps an
  iteration log of every change and why.
- **Split by time.** Model choices on 2017-2022 outcomes; market choices (betting thresholds, blend
  weights) on 2021-2022; 2023-2025 held out and scored once.
- **Rules fixed in advance.** "Matches the close" only if the paired test interval says so.
  "Profitable" only if the week-block ROI interval at fair (median-book) prices sits above zero and
  ROI is positive in at least two of three test seasons. Positive closing-line value at the open is
  the secondary skill test. Best-of-books prices never decide anything, because the scraped quotes
  include stale ones.
- **Frozen, then scored.** Two flaws in test mode were found and fixed before any test row was
  scored: the best variant had been picked on the test seasons, and the thresholds could not be
  tuned because 2017-2022 were not predicted in test mode. The fix (commit 5992fdf) makes every
  choice on 2017-2022. The test was then scored once (commit ba559be); the scripts refuse to
  overwrite a test result. Everything computed after that point, including the baselines and the
  calibration figure below, is labelled exploratory.

## Results

### 1. Team strength does most of the work, and no model reaches the closing line

![Model ladder: pooled log loss for every rung, validation and test, with the no-vig close](results/figures/fig1-model-ladder.png)

| Model | 2017-2022 validation, 12,142 games | 2023-2025 test, 7,288 games |
|---|---:|---:|
| Home field only | 0.6909 | 0.6916 |
| Team run margin only | 0.6743 | 0.6797 |
| Incumbent: season-to-date run margin | 0.6766 | 0.6827 |
| Recency model E | 0.6706 | 0.6775 |
| M1 matchup: expected runs ratio | 0.6723 | 0.6796 |
| M2 matchup: run components | 0.6721 | 0.6794 |
| M3 = M2 + team run margin | 0.6705 | 0.6777 |
| M4 = M3 + rest and travel | 0.6708 | 0.6777 |
| M5 = M3 + team defense (frozen pick) | 0.6703 | 0.6776 |
| Ensemble of M5 and E | **0.6699** | **0.6771** |
| *No-vig close, games with odds only* | *0.6689 on 4,130 games (2021-2022)* | *0.6743 on 6,451 games* |
| *M5 on those same games* | *0.6710* | *0.6779* |

Lower is better. The close exists only where odds do, so it is compared with M5 re-scored on exactly
those games (last two rows), never with the full-sample ladder. Sources:
`results/matchup-model-v2-validation.md`, `results/matchup-model-v2-test.md`; the same-game rows
are computed by `figures.R` and agree with the per-season close tables in those files.

What the ladder says:

- **Team strength carries most of the signal.** On the test seasons, decayed run margin alone closes
  82% of the gap between home field and the best model ((0.6916 - 0.6797) / (0.6916 - 0.6771)); on
  validation, 79%.
- **The matchup engine did not beat the simpler recency model on the test.** M5 scored 0.6776 and E
  scored 0.6775. Averaging the two was the best forecast in both periods (0.6771 on test).
- **The test seasons were harder for every forecast,** the close included (0.6743 vs 0.6689), so
  levels are compared within a period, not across.

### 2. The model trailed the closing line in four of five seasons; 2025 was a draw

![Close minus model by season, 2021-2025, paired intervals; test seasons shaded](results/figures/fig2-gap-to-close.png)

| Season | Games with odds | No-vig close | Model M5 | Close minus model [95%] |
|---|---:|---:|---:|---|
| 2021 (validation) | 1,788 | 0.6717 | 0.6734 | -0.0017 [-0.0034, +0.0003] |
| 2022 (validation) | 2,342 | 0.6668 | 0.6692 | -0.0024 [-0.0053, +0.0010] |
| 2021-2022 pooled | 4,130 | 0.6689 | 0.6710 | -0.0021 [-0.0042, +0.0001] |
| 2023 (test) | 2,381 | 0.6767 | 0.6795 | -0.0028 [-0.0061, +0.0002] |
| 2024 (test) | 2,382 | 0.6702 | 0.6771 | -0.0069 [-0.0101, -0.0037] |
| 2025 (test, to Aug 16) | 1,688 | 0.6768 | 0.6768 | 0.0000 [-0.0027, +0.0029] |
| **2023-2025 pooled** | **6,451** | **0.6743** | **0.6779** | **-0.0036 [-0.0054, -0.0016]** |

Negative means the close was better. Intervals: paired, home team-season cluster bootstrap. Pooled
rows reproduce the committed results exactly; season intervals are computed by `figures.R`.

On validation the gap had shrunk to the first interval that touched zero, which is why the test was
worth running. On the test it widened again, driven by 2024. The day-ahead variant trails by more,
0.0038 [0.0020, 0.0055] (`results/matchup-model-v2-dayahead-test.md`). Even the *opening* line beat
the model on 2021-2022 (open 0.6695, close 0.6689, model 0.6710 on 4,130 games).

A regression of outcomes on both forecasts, fit on 2021-2022, puts most of the weight on the close
(0.847 on the close's logit, 0.166 on the model's). The model holds a sliver the close lacks
in-sample. Whether such a sliver survives out of sample was tested for the earlier recency model,
and it did not (blend gain -0.00013 [-0.00041, +0.00012], `results/market-study.md`).

### 3. Both forecasts track the observed rates; the model leans slightly overconfident

![Reliability diagram for the model and the close, 2023-2025, with games per bin](results/figures/fig3-calibration.png)

When the model says 60%, the home team wins about 60% of the time, and the same holds for the close.
The difference is in the spread: a logistic recalibration slope of 0.88 [0.75, 1.02] for the model
against 0.97 [0.84, 1.10] for the close, so the model's strongest calls are slightly too strong.
Both intervals include 1. This is an exploratory description of the test seasons, computed by
`figures.R`, not a pre-registered test.

### 4. Bets at the open gained about 2 points of closing-line value each, four to six times the naive baselines

![Cumulative closing-line value of bets at the open, model vs two naive baselines](results/figures/fig4-clv-at-open.png)

Closing-line value (CLV) asks a simpler question than profit: when the model bets at the opening
line, does the line then move toward its side? Professional bettors use it to measure skill because
it needs far fewer bets than profit does.

| Strategy, 2023-2025 at the opening line | Bets | Mean CLV, probability points [95%] | ROI at median opening price [95%] | Status |
|---|---:|---|---|---|
| **Model M5, day-ahead lineups, 6+ points off the open** | **561** | **+2.01 [1.67, 2.35]** | **+4.7% [-5.0%, +13.7%]** | Pre-registered |
| Team run margin only, 6+ points off the open | 1,342 | +0.51 [0.36, 0.68] | -3.0% [-10.3%, +3.9%] | Exploratory |
| Always bet the home team | 6,451 | +0.36 [0.28, 0.44] | -3.5% [-5.8%, -1.2%] | Exploratory |

The 6-point threshold was frozen on 2021-2022 by CLV. Intervals are week-block bootstraps. The two
baselines are computed by `figures.R` from the same predictions and odds; they are not in a
committed result.

Two things matter here. The model's CLV is large and steady: the cumulative line climbs through
every season, and at this effect size about 18 bets would be enough for its interval to clear zero.
But the baselines are positive too. Even betting every home team at the open picks up 0.36 points,
because these lines tend to drift toward home sides, so a CLV claim has to beat that drift, not
zero. The model does, by a wide margin. (The first-pitch model posts more CLV at the open, 2.44
points, but it knows lineups the opener did not, so it is not the honest test.)

### 5. A positive return that three seasons cannot tell apart from zero

![Bootstrap distribution of ROI vs break-even, and bets needed to prove an edge](results/figures/fig5-roi-reality-check.png)

The 561 opening-line bets returned +4.7% at the median opening price. By season: +3.2% on 222 bets,
+12.1% on 216, and -5.4% on 123 in a 2025 that ends in August (`MATCHUP-PLAN.md`, iteration 6). In
a week-block bootstrap, 18% of resamples land at or below break-even.

The right panel shows why three seasons cannot settle it. With a per-bet profit standard deviation
of 1.05 units and a week-clustering design effect of 1.23, a true edge of 4.7% needs about 2,283
bets before its 95% interval is even expected to exclude zero, and 4,664 for an 80% chance. At about
219 bets a full season, that is roughly ten seasons. A 2% edge would need about 12,900. Betting the
first-pitch model at *closing* prices, the realistic comparison for that model, lost 4.4%
[-12.6%, +4.2%] on 965 bets.

### 6. On totals, the model trailed the closing over/under in every test season

![Market minus model on over/under log loss, validation and test](results/figures/fig6-totals.png)

The same feature set drove a run-total model (negative binomial, runs per side) against the closing
total (`TOTALS-PLAN.md`). Totals are often called the softer market; here they were not.

| Over/under, pushes excluded | Games | No-vig close | Model T2 | Market minus model [95%] |
|---|---:|---:|---:|---|
| 2021-2022 validation (choices made here) | 4,059 | 0.6919 | 0.6943 | -0.0023 [-0.0055, +0.0009] |
| 2023-2025 test, scored once | 6,310 | 0.6930 | 0.6982 | **-0.0052 [-0.0087, -0.0020]** |

The model won 2021 (+0.0028), but 2021 was one of the seasons used to choose it; it lost each test
season. It adds no information to the close on the test (blend gain -0.00082 [-0.00241, +0.00069]),
and its frozen 10-point threshold produced 718 bets at +4.6% [-3.0%, +12.0%]: the same shape as the
moneyline, positive and unproven (`results/totals-test.md`). Its main flaw in validation was a run
level that lagged league-wide scoring shifts by roughly half of each season's change; a fix tuned on
2017-2020 narrowed the bias without moving the market comparison (`results/totals-tune.md`,
`TOTALS-PLAN.md` iteration 3).

### 7. Stabilization curves: skipped

A figure of how fast each per-PA rate becomes reliable was planned from a separate reliability study
(`results/reliability.md`). That study had not landed when these figures were built, so it is
skipped. The recency study's stabilization points (hitter strikeouts about 60 plate appearances,
walks about 110, starter strikeouts about 90 batters faced) are in `results/recency-study.md`.

## What did not work

Every idea below was tested on validation seasons with a paired interval before it could reach the
model, and was left out when it failed. Sources: `results/context-ablation.md` (paired differences,
home team-season cluster bootstrap) and `MATCHUP-PLAN.md`.

| Idea | Change in log loss per game, 2017-2022 (positive = helps) | Kept? |
|---|---|---|
| Statcast exit velocity and launch angle for pitchers | M3 got worse: 0.6709 vs 0.6705 | No |
| Statcast expected outcomes for hitters, blended at 0.5 | Worse again: 0.6711 | No |
| Weather (temperature and wind on home runs, roof) | -0.0002 [-0.0006, +0.0002] | No |
| Home-plate umpire strike and ball tendency | -0.0003 [-0.0007, +0.0001] | No |
| Rest and travel (days off, moves, time zones) | -0.0004 [-0.0007, -0.0001]: hurts | No |
| Second game of a doubleheader | -0.0001 [-0.0003, +0.0000] | No |
| Bullpen workload over the previous three days | -0.0001 [-0.0001, +0.0000] | No |
| Every context group at once | -0.0009 [-0.0015, -0.0003]: hurts | No |
| Team defensive efficiency on balls in play | +0.0002 [+0.0001, +0.0004] | Yes (M5) |
| Recent form: extra weight on the last one or two weeks | Equivalent to zero for 10 of 13 rates; hurt starter strikeouts | No |

The earlier recency model (E) went through the same market test and also trailed the close, by
0.0029 [0.0015, 0.0042] on 10,583 games, adding nothing to it. Its betting test first showed +16%
at the best available closing price; an audit traced that to stale quotes (18.5% of bets took a
"best" price more than 10% above fair), and the closing line moved *against* its bets by 3.6 points
on average (`MARKET-PLAN.md`, iteration 2). That episode is why best-of-books prices decide nothing
here.

## Limits

- **Unlicensed odds.** The only historical line source in hand is a scraped dataset with no stated
  license. It is used privately, never committed, and only aggregates are shown. Its "current" line
  is taken as the close, which failed for September and October 2021 and is assumed to hold
  elsewhere after a monthly sanity check.
- **Actual starter, not announced starter.** StatsAPI's historical "probable" starter is the actual
  starter (a 99.85% match), and Retrosheet records who actually started. Even the day-ahead model
  therefore knows about late scratches the opening line could not have known. This flatters the
  opening-line CLV result by an unknown amount.
- **No timestamps on opening lines.** The open is whatever the scrape recorded first. If a line
  opened before the starters were announced, part of the move the model "predicted" is simply the
  starter news the model already had. The CLV result is an upper bound on genuine day-ahead skill.
- **2025 is partial.** Odds end on 2025-08-16, so 2025 contributes 1,688 games with odds and 123
  opening-line bets.
- **One market source.** No sharp book, no exchange, no limits or line-shopping costs; median-book
  prices are a fair-price proxy, not an execution record.
- **Not independently audited.** The recency model's leakage was checked by an independent tamper
  test; the matchup model's as-of rules are enforced in code and by weekly walk-forward refits, but
  no independent audit of it is recorded.
- **Scope.** Regular-season MLB only, 2017-2025, home-team perspective, tied games excluded. Nothing
  here speaks to the postseason, other sports, or bet types beyond moneylines and totals.

## What would settle it

The open question is narrow: is the opening-line edge real day-ahead skill, or the model peeking at
starters the opener had not seen? One clean forward test answers it.

1. **Freeze what exists.** Model M5 day-ahead, the 6-point threshold, median-book prices, and the
   decision rules above, unchanged.
2. **Get timestamped lines.** A licensed line history with the opening time, the line when starters
   are announced, and the close.
3. **Predict only from what was known at each timestamp,** with the announced starter rather than
   the actual one, and score the 2026 season once. The model has never been fit or tuned on 2026, so
   it is a clean holdout; a live, prospective version would be 2027.
4. **Read CLV first, money second.** At the observed effect, CLV settles within weeks (about 18
   bets). Profit does not: at +4.7% it needs about 2,300 bets, roughly ten seasons at this
   threshold. A single forward season can confirm or kill the skill claim; it cannot prove a profit.

If CLV against announced-starter lines stays well above the home-drift baseline, the model sees
something the opening line misses. If it collapses toward +0.36 points, the edge was the starter.

## Reproduce

Code is in `research/r/mlb/`; the matchup test is at commit ba559be and the totals test at a0d7e0b.
R 4.6.1 with data.table, ggplot2 and scales.

```
Rscript research/r/mlb/matchup_model.R validation   # 2017-2022 outcomes, 2021-2022 vs market
Rscript research/r/mlb/matchup_model.R test         # 2023-2025, scored once; refuses to overwrite
Rscript research/r/mlb/totals_study.R test          # totals, scored once; refuses to overwrite
Rscript research/r/mlb/figures.R                    # every figure here, from the repo root
```

The day-ahead result comes from the same `matchup_model.R` with its `OUT_TAG` and `FEAT_IN`
environment variables pointed at `features-v2-dayahead.rds`; the exact invocation was not recorded.
`figures.R` first reproduces the committed headline numbers and stops if any has drifted, then
draws the figures and prints every number it computes. Inputs it needs that are not committed: the
per-game predictions in `data/mlb/matchup/` and the local odds join in `data/mlb/raw/odds/`.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
