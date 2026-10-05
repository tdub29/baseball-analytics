# Conventional sabermetric baseline vs the matchup model (validation, 2017-2022)

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
Interested parties may contact Retrosheet at "www.retrosheet.org".

Generated 2026-10-05 by [`sabr_baseline.R`](../sabr_baseline.R). Validation seasons only: Retrosheet 2015-2022 is the only data read, nothing from the 2023-2025 test seasons. Odds appear only as `p_close` from the matchup model's saved predictions, 2021-2022, aggregates only.

## Question

How much of the matchup model's skill would a conventional sabermetric game model, built from the stats an analyst would reach for first (ERA, FIP, xFIP, SIERA, OPS, wOBA, bullpen FIP, run margin), already capture?

## Answer

- Pooled log loss on the frozen table's 12,142 games: S1 0.6775, S2 0.6722, S3 0.6725, S4 0.6714, S5 0.6716.
- Matchup model on the same games: M5 0.6703, ensemble 0.6699, recency E 0.6706, team-only 0.6743, home-only 0.6909 (all reproduce `matchup-model-v2-validation.md`).
- Each S model minus M5, per-game log loss, home team-season block bootstrap 95% (positive = S worse):
  - S1_era_ops: +0.00714 [0.00493, 0.00934]
  - S2_fip_woba_pen: +0.00183 [0.00027, 0.00336]
  - S3_siera_xfip: +0.00213 [0.00070, 0.00366]
  - S4_plus_team: +0.00109 [-0.00017, 0.00228]
  - S5_splits: +0.00123 [-0.00003, 0.00247]
- Handedness splits over S4 (S5 minus S4): +0.00014 [-0.00051, 0.00077].
- Best S model (S4_plus_team) against the no-vig close, 2021-2022, 4,130 games, S minus close: +0.00349 [0.00078, 0.00595] (M5 minus close on the same games: +0.00207 [-0.00007, 0.00415]). Positive = trails the close.

## Log loss by season (lower is better)

2020 is scored by neither: the frozen matchup table drops it because the recency model has no 2020 predictions. Every model here is still walked through 2020 and trains on it.

| season | games | S1_era_ops | S2_fip_woba_pen | S3_siera_xfip | S4_plus_team | S5_splits | M5_plus_defense | ENS | E_recency | C_team_only | B_home |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2427 | 0.6829 | 0.6757 | 0.6763 | 0.6763 | 0.6764 | 0.6763 | 0.6755 | 0.6759 | 0.6822 | 0.6902 |
| 2018 | 2429 | 0.6763 | 0.6704 | 0.6709 | 0.6708 | 0.6726 | 0.6714 | 0.6703 | 0.6705 | 0.6736 | 0.6918 |
| 2019 | 2429 | 0.6732 | 0.6684 | 0.6677 | 0.6655 | 0.6648 | 0.6633 | 0.6639 | 0.6657 | 0.6660 | 0.6915 |
| 2021 | 2428 | 0.6808 | 0.6760 | 0.6768 | 0.6746 | 0.6744 | 0.6720 | 0.6715 | 0.6720 | 0.6761 | 0.6902 |
| 2022 | 2429 | 0.6741 | 0.6703 | 0.6706 | 0.6698 | 0.6696 | 0.6686 | 0.6684 | 0.6691 | 0.6738 | 0.6910 |
| pooled | 12142 | 0.6775 | 0.6722 | 0.6725 | 0.6714 | 0.6716 | 0.6703 | 0.6699 | 0.6706 | 0.6743 | 0.6909 |

## Against the no-vig close (2021-2022)

| season | games | close | M5 | S4_plus_team |
| --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6734 | 0.6754 |
| 2022 | 2342 | 0.6668 | 0.6692 | 0.6702 |

S4_plus_team minus close: +0.00349 [0.00078, 0.00595]. M5 minus close: +0.00207 [-0.00007, 0.00415]. Positive = trails the close.

## Models

Weekly walk-forward logistic regressions of home win, the same loop as `matchup_model.R`: for each calendar week of 2017-2022, fit on every game (2016 on) dated before the week, predict the week. Home field is the intercept. Every gap is home minus away. Ties dropped.

| model | terms | coefficients fit on 2016-2022 (descriptive only) |
| --- | --- | --- |
| S1_era_ops | d_era + d_t_ops | (Intercept) 0.143, d_era -0.464, d_t_ops 4.845 |
| S2_fip_woba_pen | d_fip + d_lu_woba + d_pen_fip | (Intercept) 0.145, d_fip -0.316, d_lu_woba 15.697, d_pen_fip -0.364 |
| S3_siera_xfip | d_siera + d_xfip + d_lu_woba + d_pen_fip | (Intercept) 0.145, d_siera -0.33, d_xfip 0.035, d_lu_woba 15.653, d_pen_fip -0.371 |
| S4_plus_team | d_siera + d_xfip + d_lu_woba + d_pen_fip + drd | (Intercept) 0.145, d_siera -0.295, d_xfip 0.026, d_lu_woba 9.442, d_pen_fip -0.211, drd 0.142 |
| S5_splits | d_siera_s + d_xfip_s + d_lu_woba_s + d_pen_fip + drd | (Intercept) 0.145, d_siera_s -0.264, d_xfip_s 0.014, d_lu_woba_s 7.596, d_pen_fip -0.2, drd 0.149 |

- `d_era`, `d_fip`, `d_xfip`, `d_siera`: home starter minus away starter. `_s`: the split version (below).
- Check: refitting the matchup model's team-only model (y ~ drd) with this script's drd and walk-forward loop reproduces its saved predictions to a maximum absolute difference of 5.6e-16.
- `d_t_ops`: team OPS. `d_lu_woba`: posted-lineup wOBA (mean of the nine). `d_pen_fip`: team relief FIP. `drd`: team run margin per game, exactly `matchup_model.R`'s (decayed h = 120, carry 0.75, shrunk with 5 games).

## Inputs, all as of the day before the game

- **Who:** each team's actual starter (first pitcher in the Retrosheet play-by-play) and posted lineup (first nine batters), as `matchup_build.R`. Relief = every other pitcher-game for that team.
- **Window:** prior plus current season only. Within that, `asof_decay()` (windows.R), the model's recency weighting: weight 0.5^(in-season days / h) times carry^(seasons back). A query on date d reads events dated d - 1 or earlier, so doubleheader game 2 never sees game 1.
- **Pitcher components** per batter faced, each decayed at its own window and shrunk toward the trailing-365-day league rate by adding k BF of league average, then combined into the stat (so shrinkage happens where the reliability is measured):

| component | half-life (in-season days) | carry | k (BF) | k source |
| --- | --- | --- | --- | --- |
| k | 120 | 0.75 | 75 | reliability.md starters (73-76) |
| ubb | 240 | 0.75 | 230 | reliability.md (216-241) |
| hbp | 240 | 0.75 | 850 | reliability.md (839-880) |
| hr | 240 | 0.75 | 800 | reliability.md (743-897) |
| gb | Inf | 0.5 | 100 | reliability.md ground-ball share 63 batted balls |
| fb | Inf | 0.5 | 100 | judgement, near the hitter fly and popup shares (84-92 batted balls) |
| pu | Inf | 0.5 | 100 | same |
| outs | Inf | 0.5 | 500 | judgement |
| er | Inf | 0.5 | 1000 | judgement (ERA is the slowest to settle) |

  Windows: K, BB, HBP and HR are the model's `PIT_CFG` windows; batted-ball types, outs and earned runs take its balls-in-play window. Bullpens use the same components with the team as the entity.
- **Hitters and teams:** batting line decayed (hitters h = Inf, carry 0.75, the model's balls-in-play window for hitters; teams h = 120, carry 0.75, the run-margin window), plus 300 PA of league-average batting, then OPS and wOBA from the augmented line.
- **League rates:** trailing 365 days of every PA, as of the query date.
- **Median levels across starters and sides** (sanity): ERA 4.198, FIP 4.261, xFIP 4.267, SIERA 4.251, bullpen FIP 4.115; lineup OPS 0.745, lineup wOBA 0.323, team OPS 0.732, team wOBA 0.318.

## Formulas

Rates below are per batter faced after shrinkage; IP = outs / 3 from the Retrosheet box lines. uBB = unintentional walks: `retro.R` drops intentional walks from the plate appearances, so every BB here is unintentional and BF / PA exclude them.

- **ERA** = 9 ER / IP (earned runs from the Retrosheet pitching lines).
- **FIP** = (13 HR + 3 (uBB + HBP) - 2 K) / IP + C. C for season S = lgERA - (13 lgHR + 3 (lguBB + lgHBP) - 2 lgK) / lgIP from season S - 1 (strictly prior; it is common to both starters, so it cancels in every gap). Source: FanGraphs Library, FIP, https://library.fangraphs.com/pitching/fip/ (Tom Tango, from Voros McCracken's DIPS work).
- **xFIP** = (13 (FB + PU) lgHR/FB + 3 (uBB + HBP) - 2 K) / IP + C, lgHR/FB = league HR / (FB + PU) over the trailing 365 days. Source: FanGraphs Library, xFIP, https://library.fangraphs.com/pitching/xfip/ (Dave Studeman).
- **SIERA** (FanGraphs 2011 coefficients) = 5.534 - 15.518 K/PA + 9.146 (K/PA)^2 + 8.648 BB/PA + 27.252 (BB/PA)^2 - 2.298 nGB/PA - 4.920 sign(nGB) (nGB/PA)^2 - 4.036 (K/PA)(BB/PA) + 5.155 (K/PA)(nGB/PA) + 4.546 (BB/PA)(nGB/PA), nGB = GB - FB - PU, PA = batters faced. The squared term follows the source's sign rule ("+/-" with coefficient -4.920). The published year constants and the 0.367 x share-of-innings-as-starter term are replaced by one constant per season, set so the league-average rates of season S - 1 give that season's league ERA (FanGraphs re-sets SIERA's constant yearly to the run environment); it is common to both starters and cancels in the gap. Source: Matt Swartz, "New SIERA, Part Two (of Five)", FanGraphs, 2011-07-19, https://blogs.fangraphs.com/new-siera-part-two-of-five-unlocking-underrated-pitching-skills/ (original SIERA: Swartz and Eric Seidman, Baseball Prospectus, 2010).
- **wOBA** = (0.69 uBB + 0.72 HBP + 0.88 1B + 1.25 2B + 1.58 3B + 2.03 HR) / (AB + uBB + SF + HBP), the fixed weights already in `windows.R` (FanGraphs Library, wOBA, https://library.fangraphs.com/offense/woba/; Tom Tango, *The Book*). Fixed across seasons; the season-to-season weight drift is common to both teams.
- **OPS** = OBP + SLG, OBP = (H + uBB + HBP) / (AB + uBB + HBP + SF), SLG = TB / AB, AB = PA - uBB - HBP - SH - SF (sacrifice flags read from the Retrosheet plays file).

FIP and SIERA constants (the constant used for season S comes from S - 1):

| season | FIP_C_own_season | FIP_C_used | SIERA_C_used | lgERA_prior_season |
| --- | --- | --- | --- | --- |
| 2016 | 3.211 | 3.200 | 0.627 | 3.962 |
| 2017 | 3.225 | 3.211 | 0.856 | 4.189 |
| 2018 | 3.226 | 3.225 | 1.028 | 4.358 |
| 2019 | 3.267 | 3.226 | 0.889 | 4.151 |
| 2020 | 3.230 | 3.267 | 1.298 | 4.506 |
| 2021 | 3.220 | 3.230 | 1.278 | 4.453 |
| 2022 | 3.146 | 3.220 | 1.089 | 4.266 |

## Handedness splits (S5)

- **Starter:** every component vs left- and right-handed batters, each shrunk with 600 BF toward his overall shrunk rate times the league platoon ratio for his throwing hand (league rate vs that batter side / league rate for that pitcher hand), the side-specific prior idea of `matchup_build.R`. IP per BF stays his overall rate (outs come from the box lines, which have no batter-side split). FIP, xFIP and SIERA vs each side, then weighted by the share of the opposing posted lineup batting from that side; switch hitters bat opposite the pitcher.
- **Lineup:** each hitter's wOBA vs the starter's throwing hand, shrunk with 600 PA toward his overall wOBA times the league ratio for his batting type (left, right or switch) vs that hand.
- **Switch hitters:** Retrosheet codes them `B` on nearly every PA (21,325 to 22,771 PAs in each of 2015, 2019 and 2022, the seasons checked), not the side they batted from. Here a `B` PA counts as batting opposite the pitcher. `matchup_build.R` maps `B` to `R`, so the matchup model rates every switch hitter as a right-handed batter, including against right-handed pitchers; worth a look by whoever owns that file.

## Limits

- Shrink constants and windows were set once, before any fit, and never tuned; a tuned baseline could do somewhat better. The comparison is a fixed recipe against the matchup model's chosen variant.
- No park adjustment: conventional ERA, FIP and OPS are not park-neutral (the matchup model neutralises parks).
- Retrosheet's batted-ball coding changed in 2020 (popups 0.2-1.2% of balls in play before, about 7% after; fly balls down, liners up). xFIP and SIERA counts span the change in 2020-2021; league rates are trailing, so they adapt within a season.
- Unintentional walks only (intentional walks are dropped upstream), so FIP and SIERA differ slightly from FanGraphs' published values.

## Verdict

**The matchup model is ahead of a conventional sabermetric baseline by about 0.001 log loss, an edge the interval cannot separate from zero.** The best conventional model (S4_plus_team: starter SIERA and xFIP, posted-lineup wOBA, bullpen FIP, team run margin, home field) scores 0.6714 pooled against M5's 0.6703; it covers 95% of the distance from home-only (0.6909) to M5. M5 is ahead in 3 of 5 seasons (tied in 1).

- What the matchup structure adds (per-outcome matchups, parks, times through the order, bullpen availability, defense) over the stats an analyst reaches for first is positive but small, and six validation seasons cannot separate it from zero: +0.00109 [-0.00017, 0.00228] for S4_plus_team, +0.00123 [-0.00003, 0.00247] for S5.
- ERA plus team OPS (S1) is clearly worse (+0.00714 [0.00493, 0.00934] vs M5). The conventional skill comes from FIP-family pitching, lineup wOBA and the run margin, not from ERA.
- SIERA and xFIP do no better than plain FIP here (S3 0.6725 vs S2 0.6722 pooled); one candidate cause is Retrosheet's 2020 batted-ball recoding, which their fly-ball and popup counts straddle.
- Handedness splits add nothing measurable: S5 minus S4 +0.00014 [-0.00051, 0.00077].
- Against the close (2021-2022), S4_plus_team trails by +0.00349 [0.00078, 0.00595] (interval excludes zero) and M5 by +0.00207 [-0.00007, 0.00415] (includes zero): the matchup model sits about 0.0014 closer to the market.
- Selection runs both ways and leans toward M5: M5 was picked among matchup variants on these seasons and its components were ablated here, while the S recipe was fixed before any fit and never tuned (only the choice of the best of five S models used these seasons). A tuned conventional model would likely narrow the gap, not widen it.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
