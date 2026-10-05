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
