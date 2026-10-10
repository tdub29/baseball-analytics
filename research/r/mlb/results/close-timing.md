# Closing-line timing check

Generated 2026-10-09 by `close_timing.R`. Registered in MATCHUP-PLAN.md (2026-10-09) before scoring; post hoc data-quality
correction, reported beside the join-fix numbers and never replacing them. Rule: flag a date with at least 5 matched games whose mean
|no-vig close minus no-vig open| is over 3 times that season's median daily mean; flagged dates leave the moneyline and totals joins.

Parity: without the rule, the script reproduces the join-fix numbers (close minus M5 -0.00354, 988 close bets at -0.046, 573 open
bets at 2.01 points, totals -0.00520 on 6,310 games).

## Flagged dates

| date | games | mean open-to-close move | times season median |
| --- | --- | --- | --- |
| 2022-06-14 | 15 | 0.103 | 5.9 |
| 2024-05-15 | 15 | 0.106 | 5.4 |
| 2024-06-17 | 9 | 0.063 | 3.2 |
| 2024-07-31 | 14 | 0.092 | 4.7 |
| 2024-08-01 | 5 | 0.070 | 3.6 |
| 2024-08-02 | 15 | 0.063 | 3.2 |
| 2024-08-03 | 15 | 0.079 | 4.0 |
| 2024-08-04 | 15 | 0.071 | 3.6 |
| 2024-08-05 | 9 | 0.077 | 3.9 |
| 2024-08-06 | 13 | 0.062 | 3.1 |
| 2024-08-07 | 15 | 0.070 | 3.6 |
| 2025-08-12 | 15 | 0.071 | 3.4 |

Season medians of the daily mean move: 2021 0.019, 2022 0.017, 2023 0.019, 2024 0.020, 2025 0.021.

Why it reads as after first pitch (descriptive, outcomes used): on flagged dates the close scores 0.5853 log loss against 0.6678 for the open over 155 games; on all other dates 0.6733 against 0.6739 over 10676.

## 2023-2025 test, join fix vs join fix plus timing rule

| measure | join fix | plus timing rule |
| --- | --- | --- |
| Close minus M5, pooled (positive = M5 better) | -0.0035 [-0.0055, -0.0017], 6576 games | -0.0018 [-0.0036, -0.0001], 6436 games |
| Close minus M5, 2023 | -0.0028 [-0.0061, 0.0002], 2381 | -0.0028 [-0.0061, 0.0002], 2381 |
| Close minus M5, 2024 | -0.0069 [-0.0101, -0.0037], 2382 | -0.0023 [-0.0055, 0.0008], 2257 |
| Close minus M5, 2025 | -0.0002 [-0.0029, 0.0024], 1813 | 0.0002 [-0.0026, 0.0026], 1798 |
| v2 bets at the close, tau 0.05, ROI | -0.046 [-0.126, 0.040] on 988 | 0.005 [-0.064, 0.080] on 907 |
| Day-ahead bets at the open, tau 0.06, CLV points | 2.01 [1.67, 2.36] on 573 | 1.94 [1.62, 2.26] on 561 |
| Same bets, ROI at the median open price | 0.046 [-0.052, 0.136] | 0.045 [-0.054, 0.137] |
| Totals, market minus T2 | -0.00520 [-0.00867, -0.00201], 6310 games | -0.00610 [-0.00969, -0.00268], 6171 games |

Intervals: home team-season bootstrap for log loss, week-block bootstrap for bets (1,000 draws; totals 2,000), seed 20261004.

## 2021-2022 validation

The rule flags 15 validation games. Close minus M5 there: -0.00212 [-0.00384, -0.00022] on 4253 games as run, -0.00196 [-0.00373, -0.00005] on 4238 without them. v2's threshold and blend
were tuned with them in and stay frozen; dropping them is recorded as a fix for the next version.

## Reading under the registered rule

The corrected pooled interval lies below zero: the close beats M5 on 2023-2025 stands.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
