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
- 2026-10-04, it 7, **exploratory** (after the test; nothing tuned on 2023-2025, every choice made by
  the script on 2017-2022). An adversarial review found two gaps in the day-ahead test: the starter
  was the actual one (Retrosheet's first pitcher; no archived pre-game probables exist locally), and
  every input used results through the day before, though the open may be posted before those games
  end. Two stricter builds test whether the open-line result survives:
  `STARTER_MODE=rotation` guesses each starter from the team's starts known two days out (longest
  rest among the last 6 games' starters with 4+ days of rest; unknown starts in between predicted in
  order; previous-season starters by count as fallback; 6 games chosen on 2017-2022 match rate, 10
  games kept picking pitchers who had left the rotation, 0.44). The guess equals the actual starter
  0.669, 0.644, 0.639, 0.515, 0.595, 0.623 in 2017-2022 and 0.624, 0.661, 0.661 in 2023-2025, far
  below announced probables, so this variant is a lower bound. `ASOF_LAG=1` moves every as-of query
  back a day: hitter, pitcher and league rates, starter length, bullpen membership and availability,
  the projected-lineup source game, and in `matchup_model.R` the run margin, defensive efficiency
  (`der_gap()`, which reproduces `context.rds` exactly at lag 0) and the walk-forward fit window.
  Park factors use prior seasons only and need no shift; the recency model feeds only the ensemble
  column and is not lagged. Defaults reproduce `features-v2-dayahead.rds` exactly (identical).
  Results (`results/matchup-model-explore-rot-test.md`, `-explore-rotlag-test.md`), best variant M5
  in both, opening threshold 6 points:
  rotation: trails the close by 0.0042 [0.0020, 0.0064]; at the open 955 bets, 0.73 points of
  closing-line value [0.53, 0.94], ROI at the median open -1.4% [-9.7%, +5.9%].
  rotation plus lag: trails the close by 0.0044 [0.0023, 0.0066]; at the open 975 bets, 0.81 points
  [0.60, 1.02], ROI +0.4% [-7.1%, +7.9%].
  Split of the frozen actual-starter day-ahead test bets: on 2023-2025 games where both starters
  matched the rotation guess (44.6% of games), CLV 1.54 [1.03, 2.08] on 183 bets but ROI -10.7%; on
  the rest, CLV 2.23 [1.84, 2.64] on 378 bets, ROI +12.3%. Reading: positive closing-line value
  survives both stricter information sets, at about 0.7-0.8 points instead of 2.01, and survives
  where the starter was knowable without announcements; the profit sits in games where
  actual-starter knowledge could include late scratches, so there is no profit claim.
- 2026-10-06, it 8 (v4), **keep rule written before any ablation was run**: each v4 component
  (`SWITCH=1`, `BB_REGIME=1`, tuned `K_SET=v4`, `RECAL=1`, and their combination) is scored by
  `matchup_model.R` in validation mode against v2 with `matchup_compare.R` (paired home-team-season
  cluster bootstrap, 1,000 draws). A component is kept only if it helps on 2021-2022: the paired
  interval of v2 minus component log loss lies above zero, or its point estimate is above zero.
  Pooled 2017-2022 is reported but does not decide. The k multipliers are chosen on 2017-2019 only
  (`matchup_tune.R`); `RECAL` is fit on 2017-2020, so only its 2021-2022 number is honest. If no
  component passes, v4 = v2. The 2023-2025 test is spent and is not read.
- 2026-10-06, it 8 (v4), **exploratory** result (2017-2022 only; 2023-2025 not read). Defaults
  reproduce `features.rds` exactly (identical). Shrink k tuned on 2017-2019 (`matchup_tune.R`): every
  multiplier 0.5 to 4 of the reliability-study k lost to v2, and log loss fell as k grew; an extended
  grid peaked at 8 / 8 (0.67028 vs v2 0.67033), about v2's own scale, so the reliability study's
  "far too hard" does not carry over to game prediction. Ablation vs v2 on 2021-2022 under the rule
  above: tuned k +0.00013 [+0.00002, +0.00027] kept; `SWITCH` +0.00003 [-0.00023, +0.00031] kept on
  the point estimate; `BB_REGIME` -0.00026 [-0.00042, -0.00008] dropped; `RECAL` -0.000001 dropped
  (v2 ECE 0.0067 on 2021-2022 already). Frozen v4 = `SWITCH=1 K_SET=v4` (`M_PIT_V4 = 8`,
  `M_BAT_V4 = 8`, `M_REL_BB_V4 = 1`): pooled 2017-2022 +0.00002 [-0.00022, +0.00025], 2021-2022
  +0.00016 [-0.00015, +0.00046], both selection-biased. Tuned k alone had the cleaner record; SWITCH
  rides on a lenient rule. v4 enters the 2026 forward test only (`results/matchup-model-v4-validation.md`).
- 2026-10-06, it 8 **amendment** (before any 2026 row was scored): independent review found SWITCH's
  2021-2022 validation file (2026-10-05 11:02) predates the keep rule above, so its admission on the
  point estimate was post hoc; the rule's interval arm is also empty (an interval above zero implies a
  point estimate above zero). **v4 = tuned k only** (`K_SET=v4`, `SWITCH=0`). Checks
  (`results/matchup-model-v4-checks.md`): tuned k's 2021-2022 gain is all 2021 (2022 +0.00001
  [-0.00015, +0.00017]) and its interval spans zero under a two-way home and away team-season
  bootstrap (+0.00013 [-0.00009, +0.00037]); ECE 2021-2022 (10 equal-count bins) 0.0118 vs v2 0.0136.
  Future keep rules must say whether the frozen combination itself has to pass.
- 2026-10-06, odds-join fix (MARKET-PLAN.md, same date): 125 more 2025 games reach the market
  comparison. Corrected runs `results/matchup-model-v2-joinfix-test.md` and
  `results/matchup-model-v2-dayahead-joinfix-test.md` sit beside the as-run files. Verdicts
  unchanged: the close beats v2 by 0.00354 [0.00170, 0.00550] (as run 0.00356) and v2 day-ahead by
  0.00374 [0.00199, 0.00560] (as run 0.00383); v2's closing-line value at tau 0.06 is 2.45 points
  [2.16, 2.73] (as run 2.44), with ROI at the median open 0.013 [-0.077, 0.103] (as run 0.018).
- 2026-10-07, **exploratory** (2023-2025 spent, tau frozen at 0.06, nothing tuned): listed starters.
  `fetch_pregame_probables.py` read MLB StatsAPI's live feed at a pregame timecode for 21,050
  2017-2025 games (0 failed; `data/mlb/raw/statsapi/pregame-probables.csv`, gitignored). Both
  probables are listed in 92% to 99.7% of games by season and match the actual starter in 99.7% to
  99.9% of team-games, against 51% to 69% for the two-day rotation guess. `matchup_build.R` mode
  `probable` uses them (rotation guess for the 34 Retrosheet games and 36 pks with no match).
  Day-ahead at the open: 558 bets, CLV 1.97 [1.62, 2.30], ROI at the median open 0.044 [-0.056,
  0.136]; close minus model log loss -0.00368 [-0.00556, -0.00194]
  (`results/matchup-model-explore-prob-test.md`). Voiding bets where a listed starter did not start
  leaves 555 bets at 1.96 [1.62, 2.29]; where both listed starters were the rotation's pick, 190
  bets at 1.46 [0.92, 2.05], ROI -0.110; the other 368 at 2.23 [1.85, 2.65], ROI 0.124
  (`results/starter-void-explore-prob.md`). Independent adversarial review the same day: no feature
  leak, every claim holds with two disclosures. (1) The stored probable is not backfilled (63 of
  39,967 differ from the actual starter) but the timecode adds nothing: it equals the final stored
  probable on all 4,855 listed 2025 team-games and the cached schedule's on all 14,580 in
  2017-2019, and 4 late scratches persist in 2025 final feeds, so it is MLB's last stored listing.
  The earlier premise that StatsAPI's historical probable "is the actual starter" was wrong.
  (2) The open has no timestamp, so 1.97 is an upper bound; the snapshots sit a median 84, 88 and
  187 minutes before first pitch in 2023, 2024 and 2025.
- 2026-10-08, truncation (participation) test scored (`results/leakage-tamper.md`). Every play and
  game dated on or after the cutoff dropped, v2 rebuilt and rerun. 2019-07-01: all 8,542 earlier
  games bit-identical. 2024-07-01: as run, FAIL on one game, BOS202406260, suspended June 26 after
  10 plate appearances and finished August 26. Retrosheet dates the game on its start day and each
  play on the day it was played, so truncation removes that game's own completion-day plays and its
  lineup (first nine batters in its plays) changes: M5 0.608 against 0.439 (the truncated run has a
  partial lineup, 4 BOS and 6 TOR batters, so the gap is not the size of the oracle). The other
  19,164 games and 3,691 predictions are bit-identical, so no play-dated input leaked. Both results
  are published; the comparison now shows straddling games apart. Truncation drops rows by their own
  date, so it cannot see game-row facts dated at the start. Unfixed properties of frozen v2: the
  lineup of a suspended game can include a completion-day batter (10 of 68 team-lineups, 6 games);
  `drd` counts a suspended game's score from its start date (at most 0.132 runs, 0.113 in
  2023-2025, mean under 0.001); `der_gap()` joins reached-on-error counts by game id onto both
  dates (unmeasured); the day-ahead lineup build can copy completion-day batters into later games
  (untested). Independent review agreed with the numbers and required these wording changes. Next
  pre-registered version: date suspended scores and errors on completion and take the lineup from
  the start-day card.
- 2026-10-08, checkpoint. State: v2 frozen; 2023-2025 test and 2026 forward test spent; the close
  still beats every variant. A senior-director style review rated the analysis as having significant
  gaps; its queue, each exploratory on 2017-2022 only or a pre-registered 2027 test: (1) weight
  relievers by role and by how close the game was when they pitched; (2) a starter expected-batters-faced model instead of the naive one;
  (3) Shin de-vig and CLV split by favourite and underdog; (4) injured-list and transaction data;
  (5) run values refit beyond 2015-2016; (6) forecast, not observed, weather for totals; (7) catcher
  framing; (8) switch hitters coded by platoon side (v2 codes them R); (9) aging curves and fielder
  defense beyond team DER; (10) scope some nulls more narrowly and check the M5 blend weight out of
  sample. Also queued: the suspended-game fixes above; travel miles only from verified coordinates.
- 2026-10-09, queue item 3 done, post hoc and exploratory:
  [results/devig-check.md](results/devig-check.md). Removing the margin by Shin (1993) instead of
  proportionally moves the 2023-2025 closing log loss from 0.6743 to 0.6744 and leaves M5 behind
  the close by 0.0035 [0.0015, 0.0054]. The 561 listed-starter open bets keep their closing-line
  value under Shin, +2.09 [+1.74, +2.45] points against +2.01 proportional. Favourites and
  underdogs show it with overlapping intervals (+1.95 and +2.04), and so do the 36 longshot bets,
  sides under 35% at the open (+2.31 [+1.01, +3.68]). The CLV reading is not an artifact of the
  de-vig method and is not confined to longshots. No published number changes.
- 2026-10-09, queue item 2 registered before any scoring, exploratory on 2017-2022 only
  (`starter_length.R`). v2's expected batters faced is the starter's decayed mean over past starts,
  shrunk 3 starts toward the league. The candidate is a linear model on as-of inputs: that naive
  mean, his previous start's batters faced and pitches, days of rest, starts so far this season,
  his relief share of the past 365 days, his decayed pitches per batter, and his team's decayed
  starter length. It is fit on 2017-2019 starts and scored on 2021-2022 starts. Keep rule, stage 1:
  the 2021-2022 mean squared error must fall, with the week-block bootstrap interval on the paired
  difference above zero. Stage 2 runs only if stage 1 keeps: the games are rebuilt with the new
  value from the frozen v2 slot checkpoint, which must first reproduce `features.rds` exactly, and
  `matchup_model.R validation` reruns. The candidate goes to a pre-registered 2027 test only if M5's
  2017-2022 log loss falls and the 2021-2022 home team-season bootstrap interval on the paired
  per-game difference excludes zero. A diagnostic, not a candidate: the same rebuild with each
  starter's actual batters faced, a ceiling on what starter length can add. v2 does not change.
- 2026-10-09, queue item 2 done, exploratory on 2017-2022:
  [results/starter-length.md](results/starter-length.md),
  [results/starter-length-stage2.md](results/starter-length-stage2.md). Stage 1 keeps: on 2021-2022
  starts the candidate cuts mean squared error from 19.67 to 16.55, a paired gain of 3.12 [2.50,
  3.73]. Queried at v2's game date, the naive formula reproduces v2's `exp_bf` on all 30,946 starts;
  one start of the suspended game NYN202104110 is dated by the day it was pitched and moves. Stage 2
  drops. The frozen checkpoint reproduces `features.rds` exactly (`starter_length_rebuild.R` stops
  otherwise), and with the candidate M5's 2017-2022 log loss falls from 0.6703 to 0.6700, but the
  2021-2022 home team-season
  interval on the paired per-game difference is 0.00051 [-0.00004, 0.00111] and includes zero, so
  the candidate does not go to a 2027 test. The pooled row leaves out 2020, as v2's own pooled
  numbers do, and the 2017-2019 candidate values are in-sample for the starter model, so only the
  2021-2022 interval is clean. The oracle, each starter's actual batters faced, gains 0.0113
  [0.0078, 0.0147] pooled and 0.0080 [0.0035, 0.0121] on 2021-2022, and puts M5 ahead of the
  2021-2022 close by 0.0065 [0.0019, 0.0107]. That is an
  upper bound with outcome leakage, not a reachable target: how long a starter lasts depends on how
  he pitched that day, so it says nothing about beating the market before first pitch. v2 does not
  change.
- 2026-10-09, queue item 10 registered before any scoring (`blend_oos.R`). The 0.17 weight on M5
  in the 2021-2022 blend, logit p = a + b logit(close) + c logit(M5), was fit and read on the same
  games. Checks: (a) cross-fit, the blend fit on 2021 and scored on 2022 and the reverse, with the
  close minus blend per-game log loss and a home team-season bootstrap interval, each season and
  pooled; (b) a home team-season bootstrap interval on c from the 2021-2022 fit; (c) post hoc on the
  spent 2023-2025 test, the frozen 2021-2022 blend scored against the close the same way, labeled
  post hoc. The inputs are v2's frozen walk-forward M5 predictions and the corrected odds join; the
  script stops unless its 2021-2022 fit reproduces the published blend (0.018, 0.856, 0.173). Claim
  rule: "M5 adds information to the close out of sample" is written only if the pooled cross-fit
  interval in (a) lies above zero; (c) can narrow that claim, never establish it. Nothing in v2,
  its thresholds or any published number changes.
- 2026-10-09, queue item 10 done ([results/blend-oos.md](results/blend-oos.md)). The 2021-2022
  fit reproduces the published blend (0.018, 0.856, 0.173 on 4,253 games). Cross-fit, the blend's
  gain over the close alone is -0.00010 [-0.00116, +0.00094] fit on 2021 and scored on 2022, and
  +0.00005 [-0.00048, +0.00058] the other way; pooled -0.00003 [-0.00061, +0.00062], so under the
  claim rule the report does not say M5 adds information to the close out of sample. The weight
  itself is 0.173 [-0.139, 0.494] under the bootstrap. Post hoc on 2023-2025 the frozen blend is
  0.00032 worse than the close alone [-0.00071, +0.00006], 2024 clearly worse, and a refit there
  gives the model a weight of -0.137. REPORT.md section 2 now says the weight is in-sample only, and
  three null claims are scoped to what their intervals show (handedness splits, totals blend, the
  recency model's blend), with the "what did not work" table limited to the idea as built here.
- 2026-10-09, closing-line timing check registered before any outcome is scored on it
  (`close_timing.R`). The adversarial review found the closes of 2024-07-31 to 2024-08-07 moving
  three to five times more than usual from the open, the Sept-Oct 2021 failure (lines scraped after
  first pitch) in a window too short for the monthly check. Rule, set after a daily-move scan of
  2021-2025 but before scoring any outcome under it (the reviewer had already scored the 2024
  window, so this is a post hoc data-quality correction): a date is flagged when it has at least 5
  matched games and its mean |no-vig close minus no-vig open| is over 3 times that season's median
  daily mean. Flagged dates leave the moneyline and totals joins. Reported beside the join-fix
  numbers, never replacing them: on 2023-2025, close minus M5 per season and pooled; v2's close bets
  at tau 0.05; the day-ahead CLV and ROI at the open at tau 0.06; the totals gap; on 2021-2022, the
  games dropped. The script stops unless the unflagged run reproduces the join-fix numbers
  (-0.00354, 988 bets at -0.046, 573 bets at 2.01 points, totals -0.00520 on 6,310 games). Reading
  rule: "the close beats M5 on 2023-2025" stands if the corrected pooled interval lies below zero.
  v2, its thresholds and its blend do not change; flagged validation dates are recorded as a fix
  for the next version.
- 2026-10-09, closing-line timing check scored ([results/close-timing.md](results/close-timing.md)).
  Parity held. The rule flags 12 dates: 2022-06-14, 2024-05-15, 2024-06-17, 2024-07-31 to
  2024-08-07 and 2025-08-12. On them the "close" scores 0.5853 log loss against 0.6678 for the open
  (155 games); elsewhere 0.6733 against 0.6739 (10,676). Corrected 2023-2025: close minus M5
  -0.0018 [-0.0036, -0.0001] on 6,436 games, so under the reading rule "the close beats M5" stands;
  2024 -0.0023 [-0.0055, +0.0008]; close bets 907 at +0.5% [-6.4%, +8.0%]; CLV at the open 1.94
  [1.62, 2.26] on 561, ROI +4.5%; totals -0.0061 [-0.0097, -0.0027] on 6,171. The rule drops 15
  validation games (gap -0.00212 to -0.00196); v2 stays frozen and that drop is a next-version fix.
  Same day, blend wording fixed per the review: the weight is "not detected" out of sample rather
  than "does not hold", the item-10 registration is noted as committed with its result, the
  backward fold is labeled, and a nested test (close recalibrated alone vs close plus M5) is added:
  +0.00007 [-0.00018, +0.00036] cross-fit, -0.00020 [-0.00051, +0.00009] post hoc.
- Result, 2026-10-09 (post hoc, second review of the timing fix): without the 12 late-close dates
  the frozen blend is -0.00010 [-0.00049, +0.00027] against the raw close and +0.00002 [-0.00027,
  +0.00030] against the recalibrated close, refit weight +0.111, so the negative test weight came
  from the late closes. The corrected gap is borderline: 10,000 draws give -0.0018 [-0.0036,
  -0.0001], an edge about 0.0001 from zero. A looser 2x flag (18 dates) leaves it at -0.0018 on
  6,401 games. Dropping flagged dates widens the totals gap, so the totals closes show no log-loss sign of being late. The screen is one-sided: stale closes that moved too little were not checked.
  Wording: "were most likely taken after first pitch" replaces "early innings".
- 2026-10-10, rest and travel v2 registered before any scoring, exploratory on 2017-2022 only. This
  is a second look: the same rows already rejected the five-term rest and travel group at -0.0004
  [-0.0007, -0.0001], so a pass here is weaker evidence than a first look. New script
  `travel_features.R` writes `results/travel-ablation.md` and edits no existing script or output.
  Features, per team, from schedule facts before the game plus the game's own site and scheduled
  start: days since the previous game (cap 3); great-circle miles from the previous site and summed
  over the previous 7 days (thousands, caps 3 and 6), from a per-site coordinate table checked site
  by site; remaining circadian lag east and west in hours, the body clock moving 1 hour a day toward
  local time (Song, Severini and Allada 2017); start hour on the body clock, as hours before 1 pm and
  hours after 10 pm (missing start times: 1:05 pm day, 7:05 pm night); games in the previous 7 days
  and consecutive days with a game; day game after a night game; doubleheader the previous day;
  games into the current home stand or road trip (cap 10); played at Coors Field in the previous 3
  days and not there today. Home and away columns enter separately, not as differences.
  Model: the v2 M5 base (d12, d3, dpen, drd, dder), weekly walk-forward as in matchup_model.R.
  Primary test, the only one that can keep anything: base plus every travel feature in a ridge
  logistic (glmnet, alpha 0, base terms unpenalised, lambda.min by 10-fold cross-validation on the
  earlier games only, folds by calendar week, seed 20261004). Keep rule: the paired gain over the
  base (base log loss minus variant, per game) must have a 95% interval above zero over 2017-2022
  pooled (home team-season cluster bootstrap, 1000 draws, seed 20261004). A pass makes it a
  candidate for a pre-registered 2027 test only; v2 does not change. Descriptive, never a keep:
  the same features in an unpenalised glm; each family alone; and on 2021-2022, the no-vig close
  plus the travel features cross-fit by season (Sept-Oct 2021 and the flagged late-close dates out),
  asking whether the market already prices travel. The script stops unless the rebuilt base
  reproduces the saved v2 M5_plus_defense validation predictions and the old five rest terms
  reproduce M4_plus_rest, both to 1e-9.
