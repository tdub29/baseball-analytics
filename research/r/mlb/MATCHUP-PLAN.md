# Plan: a matchup run model, built to close the gap to the closing line

Charter v1, 2026-10-04. The recency model (E) trails the no-vig close by 0.0029 log loss and adds
nothing to it (MARKET-PLAN.md). E was a logistic on six team-level gaps. This replaces it with the
structure a projection system uses: plate-appearance outcome rates for every batter and pitcher,
split by handedness, combined matchup by matchup, turned into expected runs, then a win probability.

## Data

- Retrosheet per-season CSVs, 2015-2025 (every plate appearance: batter, pitcher, both hands,
  outcome, batted-ball type, fielders, umpires, park). Free with the Retrosheet notice: "The
  information used here was obtained free of charge from and is copyrighted by Retrosheet."
- StatsAPI (already cached): posted lineups, probable starters, venues, pitch counts.
- StatsAPI schedule `hydrate=weather`: temperature and wind at first pitch.
- Odds (MARKET-PLAN.md): opening and closing moneylines 2021-03-20 to 2025-08-16, local only.

## Components (every one as of the day before the game, windows from the recency study)

1. **Pitcher skill.** Per-PA rates of K, BB, HBP, HR, 1B, 2B+3B, and batted-ball mix (GB, FB, LD, PU),
   decayed and shrunk; derived SIERA, xFIP and FIP. Separate rates vs left- and right-handed batters,
   each shrunk toward the pitcher's overall rate scaled by the league platoon split.
2. **Hitter skill.** The same outcome rates vs left- and right-handed pitchers, shrunk the same way.
3. **Matchup.** Odds-ratio (log5) combination of batter rate, pitcher rate and league rate for each
   outcome, for each of the nine posted hitters against the probable starter's hand.
4. **Park and weather.** Outcome-level park factors by batter hand (prior three seasons); temperature
   and wind (out to center vs in) as multipliers on HR and in-play rates, fit on training seasons.
5. **Starter length.** Expected batters faced from the starter's recent workload, with a
   times-through-the-order penalty on his rates for the third pass.
6. **Bullpen.** Remaining batters against the current relievers, weighted by role (save and hold
   usage) and availability (pitches thrown the previous one to three days, back-to-back days).
7. **Defense, rest, travel, umpire.** Team defensive efficiency on balls in play (as of), days of
   rest and time-zone change, home-plate umpire K and BB tendency (as of).
8. **Runs to wins.** Expected runs per side from linear weights on expected outcomes, Pythagenpat to a
   win probability, then a walk-forward logistic recalibration with home field.

## Validation and test

| Role | Seasons | Use |
|---|---|---|
| Model fitting and component tuning | 2015-2020 history, 2017-2019 outcomes | windows, shrinkage, multipliers |
| Market tuning | 2021, 2022 | any blend with the market, betting threshold |
| Test, scored once | 2023, 2024, 2025 (odds to 2025-08-16) | frozen model vs the no-vig close and the open |

Every component is ablated on validation (log loss with and without it) and kept only if it helps.

## Decision rules (fixed now)

Same as MARKET-PLAN.md: "matches or beats the close" only if the paired test interval says so;
"profitable" only with a week-block ROI interval above zero at fair (median-book) prices, positive
in 2 of 3 test seasons; positive closing-line value when bet at the open is the secondary skill
test. Best-of-books prices are reported but never decide anything (the scraped quotes include
stale ones).

## Iteration log

- 2026-10-04, it 1: charter written; Retrosheet 2015-2025 downloading.
- 2026-10-04, it 2: v1 built (22,762 games) and validated (`results/matchup-model-validation-v1.md`).
  Best variant (matchup components + team run margin) 0.6713 log loss on 2017-2022 vs the recency
  model's 0.6706; trails the close by 0.0029 [0.0007, 0.0051] on 2021-2022; blend weight 0.02.
  Two flaws found reading the code, fixed before any test row: (1) the platoon prior used one
  league ratio for all batters instead of one per batter side and pitcher hand, which flattened
  the same-hand effect; (2) pitchers were rated on actual hits and home runs; they are now rated
  on the league outcome mix of their batted-ball types (ground ball, fly, liner, popup) from the
  prior three seasons, the xFIP/SIERA principle. Hitters keep actual outcomes. Rebuilding.
- 2026-10-04, it 3: v2 (both fixes) 0.6705 pooled, trails the close by 0.0026 [0.0003, 0.0046].
  Context ablation (`results/context-ablation.md`): only team defensive efficiency helps (M5).
- 2026-10-04, it 4: Statcast batted balls 2015-2025 (1,282,277 balls, 97.8% matched to Retrosheet).
  Exit velocity and launch angle replacing the batted-ball type for pitchers made it worse (v3 M3
  0.6709 vs 0.6705), and blending hitters' Statcast expected outcomes at 0.5 worse again (0.6711).
  Both dropped (`PIT_SC=0`, `HIT_X=0` defaults). Day-ahead lineups (projected from each team's last
  game against a same-hand starter), v3 features: bets at the open where the model disagrees by 4+
  points gain 0.94 points of closing-line value [0.78, 1.11] on 1,256 bets, but lose 0.1% at the
  median opening price; the edge is real and smaller than the vig. v2 day-ahead rerunning.
- 2026-10-04, it 5: v2 plus defense (M5) is the best model: 0.6703 pooled, ensemble with E 0.6699.
  Against the close it trails by 0.0021 [-0.0042, +0.0001], the first interval that includes zero,
  and the 2021-2022 blend puts 0.17 weight on it next to the close. v2 day-ahead at the open: 1.05
  points of closing-line value [0.88, 1.22] on 1,213 bets at a 4-point threshold, ROI at the median
  open +0.7% (+1.6% on 764 bets at 5 points), not yet an interval claim.
  Two test-mode flaws found and fixed before any test row: the best variant was picked on the test
  seasons, and 2017-2022 were not predicted in test mode, so the ensemble weight and thresholds
  could not be tuned. Test mode now predicts 2017-2025 walk-forward and makes every choice on
  2017-2022. **Frozen for the test:** `features.rds` (v2, `PIT_SC=0`, `HIT_X=0`), best variant by
  2017-2022 log loss, ensemble weight from 2017-2019, closing and opening thresholds from 2021-2022;
  day-ahead features `features-v2-dayahead.rds` for the opening-line test.
- 2026-10-04, it 6, **test scored once** (`results/matchup-model-v2-test.md`, `-v2-dayahead-test.md`).
  Close: the model trails the no-vig close by 0.0036 [0.0016, 0.0054] log loss on 6,451 games;
  betting at the median close at the frozen 5-point threshold lost 4.4% on 965 bets [-12.6%, +4.2%].
  Open, day-ahead lineups (the honest pre-lineup test): 561 bets at the frozen 6-point threshold
  gained 2.01 points of closing-line value [1.67, 2.35] and returned +4.7% at the median opening
  price [-5.0%, +13.7%]; by season +3.2% (222), +12.1% (216), -5.4% (123, odds end 2025-08-16).
  Verdicts under the fixed rules: does not match the close; not profitable (interval spans zero);
  positive closing-line value at the open, the secondary skill test, passes. Everything after
  this line is exploratory.
- 2026-10-05, exploratory: stat reliability study (`results/reliability.md`, 2015-2022). Hitter K
  stabilizes at about 45 PA, BB 110, HR 150 to 170; starter K about 75 BF, BB 215 to 240, HR 740 to
  900, BABIP over 1,000 balls in play. `PIT_CFG` shrinks the pitchers' batted-ball expected outcomes
  7 to 31 times too hard (1,300 to 3,000 vs 70 to 220); hitter singles, outs in play and triples
  3 to 10 times too hard; reliever BB about 2x. Retrosheet batted-ball coding changed in 2020, so
  the prior-three-season expected-outcome mix biases 2020-2022 pitcher x rates (league x-HR / HR
  0.58 in 2020). Any re-tune belongs on 2017-2022 validation; nothing here touches the test.
