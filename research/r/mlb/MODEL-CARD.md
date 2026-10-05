# Model card: MLB matchup win model, M5 v2

A frozen, evaluated research model. It is **not approved for wagering or any operational use.**
The full evaluation story is in [REPORT.md](REPORT.md); this card is the operating contract.

## 1. Identity

| Field | Value |
|---|---|
| Name | MLB matchup win model, variant `M5_plus_defense` ("M5") |
| Version | v2: features `data/mlb/matchup/features.rds` built with `PIT_SC=0`, `HIT_X=0`; day-ahead variant on `features-v2-dayahead.rds` |
| Code | `research/r/mlb/matchup_build.R`, `matchup.R`, `matchup_model.R`, `context_features.R`, `retro.R`, `windows.R` at commit ba559be |
| Owner | Trevor White |
| Reviewers | None recorded for this model. (The recency model E, one of its inputs to the ensemble, passed an independent leakage audit: `RECENCY-PLAN.md`, iteration 8.) |
| Status | Evaluated and frozen. Fails the pre-registered "matches the close" and "profitable" rules; passes the secondary closing-line-value rule. Not approved. |
| Frozen | 2026-10-04, commit 5992fdf; test scored once at commit ba559be |
| Card written | 2026-10-05 |
| Next review | When a timestamped, licensed 2026 line history is in hand, and in any case by 2027-03-01, before the 2027 season |

## 2. Intended use

- **In scope:** research into how close a public-data model gets to the MLB betting market; pregame
  home-win probabilities for MLB regular-season games, evaluated on 2017-2025.
- **Intended users and decisions:** the owner and readers of the research write-up. The decision it
  informs is a research one: whether to invest in a forward test with timestamped lines.
- **Out of scope:** postseason and spring training, other leagues, run lines and props. Totals are a
  separate model (T2, `TOTALS-PLAN.md`) and are not covered by this card.
- **Prohibited uses:** wagering decisions or betting advice; any claim of profitability; any claim of
  day-ahead skill that relies on the actual starter rather than the announced one; treating the
  first-pitch variant's results against opening lines as evidence of skill; redistributing the odds
  data or any per-game odds-derived output.

## 3. Target and timing

| Field | Value |
|---|---|
| Target | Home team wins (home runs greater than away runs); tied games are dropped |
| Grain | One row per game, home perspective (not a doubled team-game panel) |
| Decision time, first-pitch variant | First pitch: posted starting lineups and the actual starting pitcher |
| Decision time, day-ahead variant | Lineups projected from each team's most recent game against a same-handed starter; starting pitcher is the actual starter, not the announced one |
| Output | Home win probability from a logistic link, refit weekly |
| Horizon | Same day |

## 4. Data

- **Sport, competition, population:** MLB regular season, all 30 teams.
- **Sources:** Retrosheet per-season play-by-play 2015-2025 (every plate appearance; the
  information used here was obtained free of charge from and is copyrighted by Retrosheet); MLB
  StatsAPI for schedules and game links. Betting odds are used for evaluation only, never as an
  input: a SportsBookReview scrape (`ArnavSaraogi/mlb-odds-scraper`), 2021-03-20 to 2025-08-16, no
  stated license, local only.
- **Window:** features 2016-2025; outcomes scored 2017-2025. 2020 is predicted by the matchup
  variants but sits outside the pooled validation because the recency model has no 2020 predictions.
- **Filters and exclusions:** regular season only; tied games dropped; for market comparisons,
  2021-09-01 to 2021-12-31 excluded (closing lines scraped after first pitch, `MARKET-PLAN.md`).
- **Snapshot:** `features.rds` md5 67b60417d85f10baa823bc4f5ca9922f; `features-v2-dayahead.rds` md5
  42cd7d9a6ae7dbfafc1f856e7407f6de. Both were last modified before the test commit; the matchup
  test itself did not record a hash, the totals runs recorded the same `features.rds` hash.
- **Sample sizes:** validation pool 12,142 games (2017-2019, 2021-2022); test 7,288 games
  (2023-2025); games with odds 4,130 (2021-2022) and 6,451 (2023-2025).

## 5. Features

| Term | Definition |
|---|---|
| `d12` | Home minus away expected runs against the starter, first and second pass through the order |
| `d3` | The same for the third pass and later |
| `dpen` | Home minus away expected runs against the bullpen (role- and availability-weighted relievers) |
| `drd` | Home minus away decayed run margin per game (half-life 120 in-season days, carry 0.75, shrink 5 games) |
| `dder` | Home minus away team defensive efficiency on balls in play, park-neutralised (half-life 120 days, carry 0.75, shrink 3,000 balls) |

Expected runs come from expected outcome counts (strikeout, walk, hit by pitch, single, double,
triple, home run, out in play) times run values fit on 2015-2016 team-games only. Outcome rates are
per batter and pitcher, split by opponent hand with side-specific platoon priors, decayed and shrunk
toward the league, combined by log5 and park-adjusted by batter hand from the three prior seasons.
Pitchers are rated on the league outcome mix of their batted-ball types.

**Time safety:** every input is as of the start of the game's date; the win model is refit each
Monday on games before that Monday and predicts that week only. No independent leakage audit of the
matchup features is recorded.

## 6. Baselines

- **Naive:** home field only (constant), team run margin only.
- **Strong simple:** the incumbent (season-to-date run margin); the recency model E.
- **Market:** the no-vig closing line (primary comparison) and the no-vig opening line.
- **Comparison rule:** identical games and folds; paired per-game log-loss differences with a home
  team-season cluster bootstrap.
- **Candidate family:** M1 to M5 (weekly walk-forward logistic on matchup run gaps), plus an ensemble
  with E (logit average, weight 0.55 on M5).

## 7. Validation

- **Design:** chronological. Model choices (best variant) on 2017-2022; ensemble weight on
  2017-2019; betting thresholds and blend on 2021-2022; 2023-2025 scored once with everything frozen.
- **Primary metric:** log loss, lower is better.
- **Secondary metrics:** closing-line value of bets placed at the opening line (probability points);
  ROI at median-book prices; calibration (exploratory).
- **Decision rules (fixed in `MATCHUP-PLAN.md` before the test):** "matches the close" only if the
  paired test interval says so; "profitable" only if the week-block ROI interval sits above zero and
  ROI is positive in at least two of three test seasons; positive CLV at the open is the secondary
  skill test.

## 8. Results

| Measure, 2023-2025 test | Value | Source |
|---|---|---|
| Log loss, M5, all 7,288 games | 0.6776 (home field 0.6916, E 0.6775, ensemble 0.6771) | `results/matchup-model-v2-test.md` |
| Close minus M5, 6,451 games with odds | -0.0036 [-0.0054, -0.0016] | same |
| Bets at the close, 5+ points, median price | 965 bets, ROI -4.4% [-12.6%, +4.2%] | same |
| Day-ahead bets at the open, 6+ points: CLV | 561 bets, +2.01 points [1.67, 2.35] | `results/matchup-model-v2-dayahead-test.md` |
| Day-ahead bets at the open: ROI at median open | +4.7% [-5.0%, +13.7%] | same |

| Season | Close minus M5 [95%] |
|---|---|
| 2021 (validation) | -0.0017 [-0.0034, +0.0003] |
| 2022 (validation) | -0.0024 [-0.0053, +0.0010] |
| 2023 | -0.0028 [-0.0061, +0.0002] |
| 2024 | -0.0069 [-0.0101, -0.0037] |
| 2025 (odds to Aug 16) | 0.0000 [-0.0027, +0.0029] |

Season intervals are computed by `figures.R`; pooled values are the committed ones.

- **Validation, 2017-2022:** M5 0.6703 on 12,142 games; close minus M5 -0.0021 [-0.0042,
  +0.0001] on 4,130 games with odds. These seasons were used for selection, so they flatter it.
- **Opening-line ROI by season:** +3.2% on 222 bets, +12.1% on 216, -5.4% on 123 (`MATCHUP-PLAN.md`,
  iteration 6).
- **Naive CLV baselines (exploratory, `figures.R`):** team run margin only +0.51 [0.36, 0.68] points
  on 1,342 bets; always home +0.36 [0.28, 0.44] on 6,451.
- **Calibration (exploratory):** logistic recalibration slope 0.88 [0.75, 1.02] against 0.97
  [0.84, 1.10] for the close on the same 6,451 games: close to calibrated, slightly overconfident.
- **Leakage status:** as-of by construction and walk-forward; not independently audited.

## 9. Limits and failure modes

- Does not match the closing line; on the test seasons it also did not beat the simpler recency
  model E (0.6776 vs 0.6775).
- The day-ahead variant uses the actual starter, which flatters opening-line CLV by an unknown amount.
- Opening lines carry no timestamps, so CLV is an upper bound on genuine day-ahead skill.
- The odds source is unlicensed and scraped; 2025 ends on August 16; prices are median-book proxies,
  not executions.
- Its errors are largest in seasons the market read better (2024: -0.0069).
- Profit is unproven and would take about 2,300 bets at the observed +4.7% to show (about ten
  seasons at this threshold).
- Not evaluated for the postseason, for doubled team-game panels, or outside 2017-2025.

## 10. Maintenance

| Trigger | Minimum evidence | Action |
|---|---|---|
| Forward test with announced starters and timestamped lines: mean CLV at the 6-point threshold does not beat the always-home baseline (week-block 95% interval) | 200 bets (about 18 suffice at the observed effect) | Retire the opening-line skill claim |
| M5 fails to beat E's log loss in the next held-out season | One full season | Retire M5 as a standalone forecast; use the ensemble or E |
| Calibration slope interval excludes 1 | One season, 2,000+ games | Recalibrate, new version, new card |
| Retrosheet or StatsAPI schema change breaks a feature family (lineups, batted-ball types, hands) | Any failed build or join | Mark non-reproducible; rebuild and revalidate before scoring |
| Rule or measurement change on the scale of 2023 (pitch clock, shift ban) | Announcement | Revalidate on post-change data before trusting new predictions |
| `figures.R` stop checks fail against committed results | One failed run | Mark non-reproducible until repaired |
| Any profitability claim | Pre-registered ROI rule passes | Otherwise never claim it |

- **Monitoring owner and cadence:** Trevor White, once per season and before any forward test.
- **Retraining:** the weekly walk-forward refit is part of the model. Any change to features, run
  values, windows or selection is a new version with its own card.

## 11. Artifact manifest and reproduction

| Artifact | Location |
|---|---|
| Charters and iteration logs | `MATCHUP-PLAN.md`, `MARKET-PLAN.md`, `RECENCY-PLAN.md`, `TOTALS-PLAN.md` |
| Committed results | `results/matchup-model-v2-validation.md`, `-v2-test.md`, `-v2-dayahead-test.md`, `results/context-ablation.md`, `results/market-study.md` |
| Figures | `results/figures/fig1-model-ladder.png` to `fig6-totals.png`, from `figures.R` |
| Features and per-game predictions (local, gitignored) | `data/mlb/matchup/features.rds`, `features-v2-dayahead.rds`, `predictions-v2-*.csv` |
| Odds join (local, unlicensed, never committed) | `data/mlb/raw/odds/market-joined.csv` |
| Environment | R 4.6.1; data.table, ggplot2, scales |

```
Rscript research/r/mlb/matchup_build.R               # features.rds (PIT_SC=0, HIT_X=0 are the defaults)
Rscript research/r/mlb/matchup_model.R validation    # 2017-2022
Rscript research/r/mlb/matchup_model.R test          # 2023-2025, scored once; refuses to overwrite
Rscript research/r/mlb/figures.R                     # figures and the season intervals above
```

The day-ahead build and test use `LINEUP_MODE=projected` in `matchup_build.R` and the `FEAT_IN` and
`OUT_TAG` variables in `matchup_model.R`; the exact invocation was not recorded. The scripts in the
working tree may have moved on since the test; reproduce from commit ba559be.

## 12. Approval history and linked experiments

| Date | Event | Reference |
|---|---|---|
| 2026-10-04 | Charter v1 written | `MATCHUP-PLAN.md`, iteration 1 |
| 2026-10-04 | v1 validated; platoon prior and pitcher batted-ball fixes before any test row | iteration 2 |
| 2026-10-04 | v2 validated; context ablation keeps only defense | iteration 3, `results/context-ablation.md` |
| 2026-10-04 | Statcast inputs tested and dropped; day-ahead lineups added | iteration 4 |
| 2026-10-04 | Two test-mode flaws fixed; model frozen | iteration 5, commit 5992fdf |
| 2026-10-04 | Test scored once: does not match the close, not profitable, CLV passes | iteration 6, commit ba559be |
| 2026-10-05 | Card written; status evaluated, not approved | this file |
