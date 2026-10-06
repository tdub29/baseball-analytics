# Plan: bullpen usage, starter hook and a plate-appearance game simulator

Charter v1, 2026-10-05, written before any simulator prediction was compared with an outcome.
Changes after a validation result is seen are logged at the bottom with the reason.

## Question

Trevor's ask: "it should know who's available in the bullpen and what matchups are most likely,
even simulate the probability of each matchup, if it adds value." The matchup model (M5,
MATCHUP-PLAN.md) turns per-PA rates into three expected-run gaps (starter first and second time
through, starter third time and later, a weighted bullpen) and a walk-forward logistic. It never
plays a game out: the bullpen is one availability-weighted blend, the starter's length is a mean,
and the batting order, the base-out state and the score never interact with who pitches.

Does a simulator that does play the game out, plate appearance by plate appearance, with an
explicit model of which reliever enters when, add value over M5 on the validation seasons?

## Information rule

- **The 2023-2025 test was scored once (MATCHUP-PLAN.md it 6). Nothing here reads a 2023-2025
  row.** Retrosheet is loaded for 2015-2022 only; checkpoints that hold later seasons are filtered
  to 2022 at load.
- Every per-game input is as of the start of the game's date (events through the day before), the
  convention of `windows.R`: hitter and pitcher rates, league rates, bullpen membership, role,
  fatigue, starter workload.
- Every fitted piece for season S (base-running transitions, win-swing (LI) table, hook and bullpen
  models, times-through-order and home factors, pitch-count distributions) uses seasons
  max(2015, S - 3) to S - 1 only. 2016 is simulated so the walk-forward recalibration has history;
  it is never scored.
- No odds are read. Per-game outputs stay under `data/` (never committed); only aggregates reach
  `results/`.

## Components

1. **Per-PA outcome rates** (reused read-only from `matchup.R` at commit 4e47746, the frozen v2
   engine): batter rates by pitcher hand and pitcher rates by batter side, decayed and shrunk,
   combined by log5 against the as-of league pair rate, times the site's park factor (prior three
   seasons). Eight outcomes: K, unintentional BB, HBP, 1B, 2B, 3B, HR, out in play. Added on top,
   from prior seasons: a home and away factor per outcome (park-neutral rates of home and away
   batters over all batters) and a starter times-through-order factor per outcome (starters' rates
   on the first two passes and on the third and later, each over the starter average). Switch
   hitters stay mapped to right-handed in the rates, as in the v2 build, so the starter matchups
   reproduce `slots.rds`; the bullpen choice model treats them as never facing a same-side pitcher.
   Intentional walks: a league rate per base-out state, applied before the matchup draw.
2. **Base running.** Empirical transitions per (base-out state, outcome) to the base-out state at
   the next plate appearance and the runs scored in between, so stolen bases, wild pitches, pickoffs
   and caught stealing between plate appearances are folded into the outcome they follow. A half
   that ends on a caught stealing leaves the batter at the plate to lead off the next inning, which
   lineup tracking reproduces by construction.
3. **Bullpen membership.** A team's candidates for a game: every pitcher who appeared for it in its
   last 18 games dated before the game's date (crossing into the prior season in April), minus the
   game's starter and minus anyone whose most recent appearance was for another team; at most 22,
   ranked by relief appearances then recency.
4. **Bullpen usage.** (a) A conditional logit for who enters when a change is made, among available
   candidates not yet used in the game, fit on every relief entry of the prior seasons. Candidate
   terms: role (decayed mean entry LI, share of relief appearances that finished the game,
   log mean batters faced per appearance, share of recent appearances that were starts, relief
   appearances in the last 14 days), fatigue (pitches on each of the three previous days, both of
   the last two days, log days since the last appearance), handedness (same side as the next batter,
   share of the next three batters on the same side). Situation interactions: role LI x log
   LI now, finisher x save situation, batters per appearance x early innings and x
   blowout, start share x early innings, role LI x blowout, same-side share x late innings.
   (b) An exit hazard after each batter a reliever faces (batters faced so far, inning just ended,
   runs allowed, pitches, late innings, his batters per appearance). (c) The three-batter minimum
   from 2020: a reliever cannot leave before three batters unless the inning ends, and the hazard
   is fit on the plate appearances where leaving was allowed.
5. **Starter hook.** A discrete hazard after each batter faced: pitches so far by bin (and by bin
   when the inning just ended), batters faced by bin (the third time through is batter 19), runs
   allowed, his as-of mean pitches per start (the leash) and pitches over the leash. Pitches in the
   simulation are drawn per plate appearance from the prior seasons' distribution given the outcome,
   scaled by the pitcher's as-of pitches per batter relative to the league.
6. **Win swing (LI).** Win expectancy and LI, the standard index of how much a plate appearance
   can swing the game (mean absolute change in win expectancy over the next plate appearance, over
   its mean), per (inning relative to scheduled length, half, outs, bases, margin capped at 7), from
   prior seasons, shrunk to the (inning, half, margin) cell.
7. **Simulator.** Monte Carlo, vectorized across games and simulations in lockstep, one plate
   appearance per step: the batting order advances, the starter's third pass uses the third-pass
   rates, a removed pitcher's replacement is chosen when his team next takes the field, extra innings
   start with a runner on second in 2020-2022, seven-inning doubleheaders (2020-2021) end after the
   seventh, home leading after the top of the last inning ends the game, a walk-off ends it at once,
   and a game still tied after 25 innings counts half. N = 4,000 simulations per game in two halves
   of 2,000, so the Monte Carlo error can be measured and extrapolated away.

The simulator does not have: team defense, weather, umpires, pinch hitters or defensive changes, and
pitchers batting in National League parks before 2022 bat with their own shrunk rates all game.

## Outputs per game

P(home win); the joint distribution of home and away runs; each starter's distribution of batters
faced; each candidate reliever's probability of pitching and distribution of batters faced; the
expected plate appearances of every hitter against every pitcher (for a reliever this is close to
the probability of facing him, since he rarely sees a hitter twice).

## Evaluation and decision rules (fixed now)

All on 2017-2022 (2020 included only where the baseline has it).

1. **Bullpen forecast.** "Pitched in this game" for every candidate: log loss and calibration by
   decile of the simulated probability, against a naive baseline (the candidate's share of his
   team's games in which he pitched, over the same 18-game window). Batters faced: log score of the
   actual count in bins 0, 1, ..., 8, 9+ against the naive baseline, and calibration of the mean.
   Coverage: the share of actual relief appearances by a listed candidate. Reported, not a gate.
2. **Starter hook.** Log score of the starter's actual batters faced under the simulated
   distribution, against a baseline normal around the v2 build's expected batters faced with the
   prior seasons' residual spread; mean absolute error; 80% interval coverage. Reported.
3. **Value, win probability.** On the 12,142 games with M5 and the ensemble in
   `data/mlb/matchup/predictions-v2-validation.csv` (2017-2019, 2021-2022; ties dropped):
   (a) simulator P(home win) raw; (b) recalibrated by a weekly walk-forward logistic
   y ~ logit(p_sim) + team run margin gap + defensive efficiency gap (the M5 inputs `drd` and `dder`,
   fit on all games before the week, 2016 onward); (c) a stack, weekly walk-forward
   y ~ logit(M5) + logit(p_sim), scored on 2018-2022 only (needs a season of M5 predictions to fit).
   Per-game paired differences, baseline minus candidate (positive = simulator better), 95%
   intervals from 2,000 bootstrap draws of home team-season clusters. **"Adds value over M5" only if
   the interval for (b) or (c) is above zero**; the same for the ensemble. The Monte Carlo penalty
   (about 1 / (2N) in log loss) is reported, and a split-half extrapolation to infinite N.
4. **Totals.** Log score of the actual total runs under the simulated distribution against the
   totals study's T2 (TOTALS-PLAN.md, reproduced walk-forward here and checked against its pooled
   -2.8616) on the complete games of 2017-2022, paired, home team-season clusters. "Beats T2" only
   if the interval is above zero. Zero simulated counts are smoothed by a 1% mixture with a negative
   binomial matched to the simulated mean and variance; the finite-N bias is extrapolated from the
   two halves.

## Iteration log

- 2026-10-05, it 1: charter written. Code: `bullpen_model.R` (inputs and fits), `simulate.R`
  (simulation and evaluation). Results go to `results/sim-validation.md`.
- 2026-10-05, it 2, before any simulated game was scored against an outcome: (1) LI floored at
  0.01, because decided-game cells (for example the top of the ninth, home up seven or more) have
  zero swing and log(0) broke the choice model fit; (2) N cut from 4,000 to 2,000 simulations per
  game (two halves of 1,000): the R simulator costs about 0.2 ms of CPU per simulated game on a
  shared machine, so 4,000 for 17,000 games was more than six hours. The expected Monte Carlo
  penalty in raw log loss rises from 0.000125 to 0.00025; the split-half extrapolation is reported
  as chartered. Check before running: the rebuilt starter matchup rates equal the v2 `slots.rds`
  rates (mean absolute difference 6e-6 over 43,704 slots in 2016; two games differ, where the
  first pitcher in the raw plays and in the cached plate appearances disagree).
- 2026-10-06, it 3, the result (`results/sim-validation.md`). Simulated 2016-2022 at N = 2,000.
  Process notes: the first 2016 run died after saving its simulation because `simulate.R` was
  edited while Rscript was still reading it (R parses the script file incrementally); 2016 was
  rerun with the final code and its output is identical to the first run in every array, so all
  seasons come from equivalent simulation code. `evaluate` now reads only the gid, season, M5,
  ensemble, recency and incumbent columns of `predictions-v2-validation.csv`, so no odds column is
  loaded at all. Audit before scoring: games per season 2428, 2430, 2429, 2429, 898, 2429, 2430
  (2016-2022), no row after 2022, every candidate's last appearance is before the game date, rates
  complete and summing to one, and the simulated games, candidates and starters equal the inputs.
  Verdict under the rules fixed in the charter:
  (1) **Win probability: no detectable value over M5 or the ensemble.** M5 minus recalibrated
  -0.00051 [-0.00140, 0.00038]; M5 minus stack -0.00026 [-0.00060, 0.00007]; ensemble minus
  recalibrated -0.00093 [-0.00179, -0.00005], ensemble minus stack -0.00059 [-0.00122, -0.00001],
  an upper bound that borders zero.
  The raw simulator is worse than M5 by 0.0030 (0.0028 at infinite N); logit(sim) correlates 0.947
  with logit(M5) and the last stack fit puts -0.03 on it, so the explicit bullpen, base-out state
  and batting order add no detectable win information to the expected-run gaps. Raw simulated
  probabilities are too compressed at the extremes (top decile 0.664 simulated, 0.697 observed);
  the recalibration fixes that.
  (2) **Totals: undetermined at N = 2000 (raw no, extrapolated yes).** As simulated -0.0030
  [-0.0091, 0.0033]; the charter does not say whether the totals gate uses the raw or the
  split-half extrapolated score, and the extrapolated one is above zero, 0.0085 [0.0023, 0.0148]. Post-hoc checks, added after seeing this and not changing the rule:
  the delta-method finite-N penalty is 0.0085 against a measured extrapolation of 0.0114, so the
  extrapolation likely overshoots by about 0.003, and the moment-matched negative binomial alone
  is worse than T2 (-0.0100 [-0.0131, -0.0070]), so any gain lives in the histogram shape. A
  larger-N run would settle it. The simulated run level is too high in 2018 and 2020-2022 (2022:
  9.45 simulated, 8.57 actual), which T2's 15-day league run level handles and the simulator does not.
  (3) Reported, not gated: the bullpen forecast beats the naive window rate on "pitched" log loss
  by 0.0385 [0.0371, 0.0399] (95.1% of relief appearances by a listed candidate) and on batters
  faced by 0.0513 [0.0497, 0.0528] in log score, but overpredicts in deciles 3-5 and 10 (0.569
  simulated, 0.504 observed). The starter hook beats the normal baseline by 0.119 [0.104, 0.136]
  in log score with 85.4% of starts inside the 80% range; its mean is slightly worse than the
  build's in 2021-2022, when starters went longer than the 2019-2021 hook fit expected (2022
  starter share 0.557 simulated, 0.591 actual).
  Adversarial review (inline, leakage-audit and validation-design checklists; no subagent tool was
  available in this run): weekly folds train only on games dated before the week; one row per game;
  no tuned hyperparameters in the recalibration or stack; the bootstrap clusters home team-seasons
  and ignores away-team dependence. Baselines were selected with in-sample information (M5 chosen
  on 2017-2022 log loss, the ensemble weight on 2017-2019, MATCHUP-PLAN.md it 5), which favors the
  baselines; it cannot turn a no into a yes. Leakage verdict: REVIEW REQUIRED only for lineups and
  starters, which are the actual ones as in the v2 build (known before first pitch, not before the
  date), so the comparison with M5 uses the same information.
- 2026-10-06, it 3 review: an independent critic agent (leakage-audit, sports-predictive-modeling
  and model-interpretation skills) recomputed every win-probability number exactly and found three
  issues, all fixed. (a) `simulate.R` read byte-identical copies of `features.rds` and the
  odds-bearing `predictions-v2-validation.csv` from `data/mlb/sim/`, which was not gitignored; it
  now reads the `data/mlb/matchup/` originals, the copies are deleted and `data/mlb/sim/` is
  ignored. (b) The totals verdict had been picked as "no" after both scores were seen; it now reads
  "undetermined at N = 2000". The delta-method penalty (0.0085) added to the raw score gives about
  +0.0055, so a larger-N run decides it. (c) "No value" became "no detectable value": with
  game-date clusters the ensemble-minus-stack interval is [-0.00127, 0.00006], spanning zero, and
  the 2019 gap is positive. The no-value verdict on win probability stands.
