# Matchup model v4: frozen recipe and validation

Exploratory iteration 8 (MATCHUP-PLAN.md, 2026-10-06). Every choice was made on 2017-2022 validation
games; the 2023-2025 test was scored once in iteration 6 and no 2023-2025 row was read here.

**Amended 2026-10-06, before any 2026 row was scored: v4 is tuned k only.** v4 was first frozen as
tuned k plus `SWITCH=1`. An independent review found that SWITCH's 2021-2022 result
(`matchup-model-v4-switch-validation.md`, written 2026-10-05 11:02) was on disk before the keep rule
below was written (committed 2026-10-06), so admitting SWITCH through the rule's point-estimate arm
was post hoc. SWITCH also lost on the 2017-2019 tune and on the pooled number. It is dropped.

## Recipe

```
K_SET=v4 FEAT_OUT=data/mlb/matchup/features-v4-konly.rds Rscript research/r/mlb/matchup_build.R
FEAT_IN=data/mlb/matchup/features-v4-konly.rds OUT_TAG=-v4-k Rscript research/r/mlb/matchup_model.R validation
```

`K_SET=v4` sets `M_PIT_V4 = 8`, `M_BAT_V4 = 8`, `M_REL_BB_V4 = 1` in matchup.R: the reliability
study's k times 8 for the pitchers' batted-ball expected outcomes and the hitters' singles, triples
and outs in play (starters single 1256, double 1680, triple 1032, HR 848, out in play 968; hitters
single 1560, triple 4272, out in play 600; relievers 134 for walks). `SWITCH=0`, `BB_REGIME=0` and
`RECAL=0`. `K_SET=v4` alone reproduces the tuning grid's file for these multipliers exactly
(identical()), the defaults still reproduce the frozen v2 `features.rds` exactly, and rescoring the
rebuilt file reproduces `predictions-v4-k-validation.csv`. Validation output:
`matchup-model-v4-k-validation.md`.

## How it was chosen

1. Shrink constants, tuned on 2017-2019 outcomes only (`matchup_tune.R`, M5 walk-forward log loss,
   7,288 games). The reliability study said v2 shrinks far too hard, but every multiplier from 0.5 to
   4 lost to v2 (worst 0.67105, best 0.67035, v2 0.67033); log loss fell steadily as k grew. Above
   about 4x the surface is flat within noise: across 75 grid points in three files, 8 / 8 and 16 / 8
   tie at 0.67028 (v2 minus it 0.00005 [-0.00012, 0.00022]) and 8 / 8 was taken from the tie. The
   relievers' walk multiplier made no difference. Lower k tracks per-PA rates better (the reliability
   study) but adds noise to game predictions; the game model prefers heavy shrinkage. Because k was
   tuned on 2017-2019, the pooled 2017-2022 rows below are partly in sample for k. Tables:
   `matchup-k-tune-v4-base.md`, `-v4-base2.md`, `-v4-switch.md`.
2. Keep rule (MATCHUP-PLAN.md, committed 2026-10-06; the SWITCH run predates it, the other runs do
   not): keep a component only if v2 minus component log loss on 2021-2022 has a point estimate above
   zero. As first written the rule also named an interval arm, but an interval above zero implies a
   point estimate above zero, so the arm decided nothing. Ablation (`matchup-model-v4-ablation.md`,
   paired team-season cluster bootstrap, 1,000 draws, 12,142 pooled games, 4,857 in 2021-2022):

| component | pooled 2017-2022 vs v2 | 2021-2022 vs v2 | interval above zero | in v4 |
| --- | --- | --- | --- | --- |
| tuned k (`K_SET=v4`) | +0.00008 [-0.00002, 0.00019] | +0.00013 [+0.00002, +0.00027] | yes (one-way cluster only) | yes |
| `SWITCH=1` | -0.00006 [-0.00025, +0.00014] | +0.00003 [-0.00023, +0.00031] | no | no (post hoc, see above) |
| `BB_REGIME=1` | -0.00010 [-0.00017, -0.00004] | -0.00026 [-0.00042, -0.00008] | no, worse | no |
| `RECAL=1` | -0.00002 [-0.00013, +0.00010] | -0.000001 [-0.00019, +0.00019] | no | no |
| all four | -0.00012 [-0.00038, +0.00013] | -0.00014 [-0.00054, +0.00024] | no | no |
| tuned k + SWITCH (first freeze) | +0.00002 [-0.00022, +0.00025] | +0.00016 [-0.00015, +0.00046] | no | superseded |

Positive means better than v2. v2 itself: pooled 0.6703, 2021-2022 0.6703; v4 (tuned k): 0.6702 and
0.6702.

3. Robustness (`matchup-model-v4-checks.md`, `matchup_v4_checks.R`). Tuned k's 2021-2022 gain is all
   2021: +0.00025 [+0.00009, +0.00042] in 2021, +0.00001 [-0.00015, +0.00017] in 2022. Its 2021-2022
   interval stays above zero under week blocks (+0.00013 [+0.00001, +0.00027]) but spans zero when
   home and away team-seasons are resampled together (+0.00013 [-0.00009, +0.00037]). The one-way
   home team-season intervals used throughout this repo are therefore on the narrow side.

## Reviews

The builder's own checks (leakage-audit, validation-design, calibration-check skills) ran inline in
the same agent. A separate agent then reviewed the result adversarially (leakage-audit,
sports-predictive-modeling, statistical-modeling skills); its findings and what was done:

- Leakage: `REVIEW REQUIRED`, no contamination found. The k tune reads games only through 2019.
  `BB_REGIME`'s regime-start mix counts only earlier days of the season (`cumsum(v) - v`). `RECAL`
  is fit on 2017-2020, in sample there; only its 2021-2022 number is honest. The keep rule reads
  2021-2022, so v4's 2021-2022 numbers are selection-biased upward and are not evidence that v4
  beats v2.
- SWITCH was admitted post hoc (major): fixed by the amendment above.
- The interval arm of the keep rule was empty (minor): rule restated; the table separates the
  interval from the decision.
- The gain is 2021 only, the tune surface is flat, the intervals are one-way (minor): disclosed in
  steps 1 and 3.
- Calibration figures were not reproducible (minor): `matchup_v4_checks.R` now computes ECE with 10
  equal-count bins. On 2021-2022, M5 ECE is 0.0136 for v2, 0.0118 for tuned k, 0.0156 for SWITCH
  and 0.0147 for tuned k + SWITCH (the earlier 0.0067 used a different, unrecorded binning).
  Calibration slope for tuned k is 0.982 on 2017-2020 and 0.995 on 2021-2022. `RECAL` is near
  identity (logit p' = 0.010 + 0.978 logit p), so v2 needs no recalibration.
- Size: every difference is under 0.0003 of log loss per game. Tuned k still trails the 2021-2022
  close by 0.0019 [-0.0040, +0.0002]. v4 is a forward-test entry, not an improvement claim.

v4 joins the 2026 forward test only (FORWARD-PLAN.md, model 3); it replaces v2 as the default only if
the paired 2026 interval favors it.

## Validation output of the first freeze, tuned k + SWITCH (`matchup_model.R validation`, OUT_TAG=-v4, superseded)

Kept as run because `matchup_compare.R -v4` reads it. The frozen recipe's output is
`matchup-model-v4-k-validation.md`.

Generated 2026-10-06. Run values from 2015-2016 team-games: k -0.054, ubb 0.316, hbp 0.354, single 0.460, double 0.755, triple 0.998, hr 1.398, out_ip 0.000.

## Log loss vs outcomes (lower is better)

| season | games | M1_runs_ratio | M2_components | M3_plus_team | M4_plus_rest | M5_plus_defense | B_home | C_team_only | E_recency | C_incumbent | ENS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 |  2427 | 0.6761 | 0.6764 | 0.6762 | 0.6768 | 0.6764 | 0.6902 | 0.6822 | 0.6759 | 0.6836 | 0.6756 |
| 2018 |  2429 | 0.6724 | 0.6728 | 0.6717 | 0.6719 | 0.6717 | 0.6918 | 0.6736 | 0.6705 | 0.6751 | 0.6704 |
| 2019 |  2429 | 0.6667 | 0.6661 | 0.6631 | 0.6634 | 0.6632 | 0.6915 | 0.6660 | 0.6657 | 0.6707 | 0.6638 |
| 2020 |     0 | NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |
| 2021 |  2428 | 0.6751 | 0.6742 | 0.6722 | 0.6723 | 0.6717 | 0.6902 | 0.6761 | 0.6720 | 0.6777 | 0.6713 |
| 2022 |  2429 | 0.6711 | 0.6710 | 0.6694 | 0.6694 | 0.6686 | 0.6910 | 0.6738 | 0.6691 | 0.6757 | 0.6684 |
| pooled | 12142 | 0.6723 | 0.6721 | 0.6705 | 0.6707 | 0.6703 | 0.6909 | 0.6743 | 0.6706 | 0.6766 | 0.6699 |

Best matchup variant on 2017-2022 (validation): M5_plus_defense.

## Against the no-vig closing line (games with odds)

Ensemble weight on the matchup model (chosen on 2017-2019): 0.55.

| season | games | close | matchup | recency E | ensemble |
| --- | --- | --- | --- | --- | --- |
| 2021 | 1788 | 0.6717 | 0.6731 | 0.6729 | 0.6725 |
| 2022 | 2342 | 0.6668 | 0.6691 | 0.6699 | 0.6690 |

Close minus matchup per-game log loss (positive = matchup better): -0.00191 [-0.00394, 0.00023].
Blend fit on 2021-2022: logit p = 0.020 + 0.827 logit(close) + 0.189 logit(model).

Betting thresholds on 2021-2022 at median-book closing prices:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3211 | -0.041 |
| 0.02 | 2386 | -0.025 |
| 0.03 | 1622 | -0.028 |
| 0.04 | 1088 | 0.016 |
| 0.05 | 688 | 0.044 |
| 0.06 | 381 | 0.051 |

Chosen tau: 0.06.

## Opening line (2021-2022): model vs no-vig open, and closing-line value of bets at the open

Log loss on 4130 games: open 0.6695, close 0.6689, model 0.6708.

| tau | bets | mean CLV (prob. points) | 95% | ROI at median open price |
| --- | --- | --- | --- | --- |
| 0.01 | 3255 | 0.85 | [0.74, 0.96] | -0.027 |
| 0.02 | 2486 | 1.01 | [0.88, 1.14] | -0.019 |
| 0.03 | 1748 | 1.23 | [1.08, 1.37] | -0.007 |
| 0.04 | 1193 | 1.43 | [1.25, 1.60] | 0.005 |
| 0.05 | 769 | 1.60 | [1.37, 1.81] | 0.035 |
| 0.06 | 456 | 1.73 | [1.43, 2.00] | 0.015 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
