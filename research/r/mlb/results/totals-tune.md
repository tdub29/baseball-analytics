# Totals study: run-environment tuning, 2017-2020

Generated 2026-10-04 by `Rscript research/r/mlb/totals_study.R tune`. Charter: TOTALS-PLAN.md it 3. features.rds md5 67b60417d85f10baa823bc4f5ca9922f. No row after 2020 was read and no odds were read.

Walk-forward weekly fits on 2017-2020 as in validation. H = half-life in days of the fit weights (charter v1: 365). h = half-life in days of the as-of league runs per nine innings, entered as log(level / 9) in every candidate (NA = not used). Rule fixed before the run: highest pooled 2017-2020 T2 mean log score of the actual total wins.

## Pooled 2017-2020 (higher log score is better)

| config | H | h | games | logscore_T1 | logscore_T2 |
| --- | --- | --- | --- | --- | --- |
| 1 | 365 | NA | 8168 | -2.8791 | -2.8791 |
| 2 | 180 | NA | 8168 | -2.8793 | -2.8792 |
| 3 | 120 | NA | 8168 | -2.8797 | -2.8794 |
| 4 | 90 | NA | 8168 | -2.8803 | -2.8798 |
| 5 | 60 | NA | 8168 | -2.8821 | -2.8813 |
| 6 | 30 | NA | 8168 | -2.8905 | -2.8883 |
| 7 | 365 | 15 | 8168 | -2.8788 | -2.8789 |
| 8 | 365 | 30 | 8168 | -2.8788 | -2.8789 |
| 9 | 365 | 60 | 8168 | -2.8790 | -2.8791 |
| 10 | 365 | 120 | 8168 | -2.8792 | -2.8793 |

## Mean predicted total (T2) minus actual, per season

| season | actual | c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8 | c9 | c10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 9.293 | -0.060 | -0.034 | -0.011 | 0.007 | 0.026 | 0.020 | -0.007 | -0.015 | -0.037 | -0.039 |
| 2018 | 8.898 | 0.282 | 0.216 | 0.158 | 0.111 | 0.052 | -0.013 | 0.255 | 0.261 | 0.259 | 0.275 |
| 2019 | 9.673 | -0.346 | -0.282 | -0.207 | -0.142 | -0.052 | 0.032 | -0.211 | -0.145 | -0.110 | -0.162 |
| 2020 | 9.297 | 0.120 | 0.103 | 0.026 | -0.066 | -0.204 | -0.293 | 0.146 | 0.151 | 0.175 | 0.177 |
| pooled | 9.288 | -0.023 | -0.018 | -0.015 | -0.014 | -0.015 | -0.021 | 0.027 | 0.046 | 0.053 | 0.041 |

**Chosen: config 7 (H 365, h 15)**, pooled T2 log score -2.8789 vs charter v1 -2.8791. Paired per-game gain (chosen minus v1), week-block bootstrap 95%: 0.00025 [-0.00029, 0.00081] over 8168 games.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
