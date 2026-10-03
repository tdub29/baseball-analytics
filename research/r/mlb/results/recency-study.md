# Which look-back window to trust when predicting MLB games

Pre-registered in [RECENCY-PLAN.md](../RECENCY-PLAN.md) (charter v2, with the iteration log of
every change and why). Choices made on 2017-2019; scored once on 2021-2025.

## The answer

**Trust long windows, for every part of the team.** Hitters, starting pitchers, relievers and
team strength all predict best from months of play, not days: the best estimates give a game half
its weight after 120 to 240 in-season days (four to eight months of baseball) and keep 50 to 100%
of each earlier season. **Recent form adds nothing** once that long, shrunk estimate is in: extra
weight on the last week or two was equivalent to zero for 10 of 13 rates, and for starters'
strikeouts it made predictions worse. **Old data does go stale, slowly:** the decayed windows beat
"all history, weighted equally" for every component on 2021-2025, and at the win level.

A model built from these windows (lineup, probable starter, bullpen, bullpen workload, run
differential) called 58.0% of 12,148 games from 2021 to 2025, against 56.0% for a season-to-date
run-differential model and 53.1% for always picking the home team, with lower log loss in all five
seasons. Decision time is first pitch: it uses the posted lineups and the actual starter.

## Per component

Skill is the share of a single game's variance, beyond the league average, that the estimate
explains. Single games are mostly noise, so talent explains only a few percent; the comparisons
between windows are what matter.

| Component | Rate | Best window: half-life, carry per season | Shrink toward league | Reliable at (split-half r = 0.5) | Extra weight on recent games |
|---|---|---|---|---|---|
| Hitters | strikeouts per PA | 120 days, 100% | 25 PA | about 60 PA | equivalent to zero |
| Hitters | walks + HBP per PA | 240 days, 75% | 100 PA | about 110 PA | equivalent to zero |
| Hitters | home runs per PA | no decay, 50% | 100 PA | about 200 PA | equivalent to zero |
| Hitters | wOBA per PA | no decay, 75% | 200 PA | about 450 PA | equivalent to zero |
| Starters | strikeouts per BF | 120 days, 75% | 50 BF | about 90 BF | **hurts** (-0.0015, interval below zero) |
| Starters | walks + HBP per BF | 240 days, 75% | 200 BF | about 300 BF | equivalent to zero |
| Starters | home runs per BF | 240 days, 75% | 800 BF | about 1,300 BF | equivalent to zero |
| Starters | runs per BF | no decay, 50% | 800 BF | about 1,100 BF | equivalent to zero |
| Relievers | K-BB per BF | 240 days, 50% | 50 BF | about 130 BF | inconclusive (see below) |
| Relievers | FIP-style per BF | 120 days, 100% | 200 BF | about 330 BF | equivalent to zero |
| Relievers | runs incl. inherited, per BF | 240 days, 75% | 400 BF | about 660 BF | equivalent to zero |
| Team | run margin per game | 120 days, 75% | 5 games | about 40 games | equivalent to zero |
| Team | offense wOBA per PA | 60 days, 75% | 800 PA | about 1,400 PA | equivalent to zero |

"Equivalent to zero" is a pre-registered equivalence verdict: the 90% interval of the gain sits
inside plus or minus 0.1% of outcome variance. Verdicts above are from 2021-2025. On 2017-2019 they
were the same or inconclusive (starter strikeouts and walks, team offense), except reliever K-BB,
noted below.

**Hitters.** Strikeout and walk rates become trustworthy fast (about 60 and 110 plate
appearances), power takes about 200 and overall production about 450. Even so, the best estimate
looks back months and carries last season at 50 to 100%: a hitter's last week tells you nothing
his last four months do not. Hot and cold streaks added nothing in any era.

**Starting pitchers.** Strikeouts settle in about four starts, walks in about twelve, home runs
and runs allowed only over a season or more. So lean on multi-season, heavily shrunk numbers for
run prevention, and a 120-day half-life for strikeouts. Weighting the last few starts extra made
strikeout predictions worse in every test era: a starter's recent strikeout spike is mostly noise
that a longer window correctly ignores.

**Bullpens.** Individual relievers are the noisiest unit (runs allowed need about 660 batters,
several seasons of a reliever's work). What works is each current reliever's long window, weighted
by how much he has pitched lately, not a short team-bullpen window. A small recent-form gain for
reliever K-BB on 2021-2025 (+0.0013 [+0.0010, +0.0017]) did not show up on 2017-2019 (-0.00001),
so it is not a finding. Recent workload (relief pitches the previous one and three days) is in the
win model as an association; managers rest tired arms, so it is not a causal fatigue effect.

**Team.** Run differential per game with a 120-day half-life, 75% carry and a 5-game shrink is
the single best team number; the incumbent's season-to-date version forgets last season, which is
why it is weakest in April.

**How fast data goes stale.** Skill by half-life on 2021-2025 climbs steeply from a one-week to a
two-month half-life, then flattens; "no decay" sits just under the peak for most rates:

| Half-life (in-season days) | 7 | 14 | 30 | 60 | 120 | 240 | none |
|---|---|---|---|---|---|---|---|
| Hitter strikeouts | 0.035 | 0.045 | 0.053 | 0.058 | 0.059 | 0.059 | 0.058 |
| Starter strikeouts | 0.056 | 0.085 | 0.106 | 0.118 | 0.121 | 0.121 | 0.119 |
| Team run margin | 0.010 | 0.015 | 0.019 | 0.020 | 0.020 | 0.020 | 0.020 |

## The win model, 2021-2025 (scored once)

| Season | Games | Home field | Run differential (incumbent) | Elo | No-decay windows | Chosen windows |
|---|---|---|---|---|---|---|
| 2021 | 2,429 | 0.6903 | 0.6779 | 0.6745 | 0.6754 | **0.6721** |
| 2022 | 2,430 | 0.6910 | 0.6757 | 0.6730 | 0.6700 | **0.6692** |
| 2023 | 2,430 | 0.6926 | 0.6823 | 0.6808 | 0.6826 | **0.6793** |
| 2024 | 2,429 | 0.6924 | 0.6826 | 0.6808 | 0.6783 | **0.6756** |
| 2025 | 2,430 | 0.6898 | 0.6831 | 0.6783 | 0.6810 | **0.6775** |
| All | 12,148 | 0.6912 | 0.6803 | 0.6775 | 0.6775 | **0.6748** |

Log loss, lower is better. Gains of the chosen-window model, team-season cluster bootstrap 95%
intervals: over the incumbent +0.0056 [+0.0034, +0.0076]; over the same inputs with no decay
+0.0027 [+0.0014, +0.0041]; over Elo +0.0027 [+0.0012, +0.0043]. Calibration intercept -0.007
[-0.043, 0.029], slope 0.95 [0.86, 1.05]. Accuracy 58.0% vs 56.0%. The pre-registered ship rule
(interval above zero, at least 4 of 5 seasons, calibrated) passed. On 2017-2019, where the windows
were chosen, the same model scored 0.6707 vs 0.6765.

## Caveats

- **First pitch, not day ahead.** StatsAPI's historical "probable" starter is the actual starter
  (99.85% match, openers included) and the lineups are the posted starting nine. Without the
  starter and lineup inputs the model still beats the incumbent by +0.0031 [+0.0016, +0.0045] in
  5 of 5 seasons; those inputs carry up to about 45% of the gain.
- **No betting-market baseline**, so this is not evidence of a betting edge.
- The incumbent is scored as its run-differential part (home field + season-to-date margin shrunk
  by 20 games); its Baseball-Reference pitching term does not exist past 2019 and did not help when
  it did. Decided before any win-model result.
- The bullpen is weighted by recent relief batters faced only; the charter also named saves and
  holds, which were not used.
- Hitter strikeouts chose the smallest shrink on the grid (25 PA). Its window carries several
  seasons, so the shrink barely matters, but the true optimum may be lower.
- A precision bug in the window code (a running sum across players) was found while reading the
  test curves and fixed. Every chosen window was unaffected (all 13 picks identical on rerun), so
  the frozen model and its test score stand; the short half-life cells were rescored.
- An independent leakage audit, including a real-data tamper test on the 2023-06-12 block, found
  no look-ahead.

## Reproduce

```
Rscript research/r/mlb/fetch_gamelogs.R 2015 2025      # StatsAPI cache, key-free, resumable
Rscript research/r/mlb/recency_study.R                 # validation: choose windows on 2017-2019
Rscript research/r/mlb/recency_model.R validation
Rscript research/r/mlb/recency_study.R test            # once; refuses to rerun without --force
Rscript research/r/mlb/recency_model.R test            # once
```

Outputs: `results/recency/` (grids, picks, curves, reliability, lambda, test tables, predictions),
`results/recency-model-validation.md`, `results/recency-model-test.md`.
