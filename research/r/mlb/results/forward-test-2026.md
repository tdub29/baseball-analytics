# 2026 forward test: scored once

Scored 2026-10-06 02:47 at commit 6d2503c under FORWARD-PLAN.md. As-run report.

Prediction files (sha256, as recorded in FORWARD-PLAN.md before scoring):

- `predictions-v2-forward.csv` `3f5e9ce682e690709bbe175b509d55bcdf282ae35f8ca87472f07b20fc7f102d`
- `predictions-v2-dayahead-forward.csv` `38dfb27406c949597a4368acd24e639179894920069499a64bf6a97f1b954c26`
- `predictions-v4-forward.csv` `8a27a230805d51817e63ebfa9fd9fea5be86b66fe6b0fe5b789d238fa2e59067`
- `sabr-predictions-forward.csv` `159c21f574ada21d94fb17b1db15ac76ea9f1cf2913c910344dcf7dfa0f00434`

Games scored: 2429 of 2026 with a prediction from every model (files: v2 2429, v2 day-ahead 2429, v4 2429, S4 2429).
Frozen best variants: v2 M5_plus_defense, v2 day-ahead M5_plus_defense, v4 M5_plus_defense.

## Outcomes (lower log loss and Brier are better; slope 1 = calibrated)

| model | log loss | Brier | accuracy at 50% | calibration slope |
| --- | --- | --- | --- | --- |
| v2 | 0.6813 | 0.2441 | 0.564 | 0.933 |
| v2_dayahead | 0.6806 | 0.2438 | 0.564 | 0.975 |
| v4 | 0.6813 | 0.2441 | 0.563 | 0.931 |
| B_home | 0.6916 | 0.2492 | 0.529 | -40.406 |
| C_team_only | 0.6840 | 0.2454 | 0.557 | 0.889 |
| S4 | 0.6818 | 0.2444 | 0.560 | 0.921 |

## Paired comparisons (baseline minus model per game; positive = model better)

| model | vs | difference | 95% interval | verdict |
| --- | --- | --- | --- | --- |
| v2 | B_home | 0.01028 | [0.00475, 0.01643] | model better |
| v2 | C_team_only | 0.00270 | [-0.00124, 0.00777] | no detectable difference |
| v2 | S4 | 0.00048 | [-0.00198, 0.00298] | no detectable difference |
| v2_dayahead | B_home | 0.01094 | [0.00515, 0.01711] | model better |
| v2_dayahead | C_team_only | 0.00337 | [-0.00017, 0.00793] | no detectable difference |
| v2_dayahead | S4 | 0.00115 | [-0.00108, 0.00357] | no detectable difference |
| v4 | B_home | 0.01025 | [0.00478, 0.01633] | model better |
| v4 | C_team_only | 0.00268 | [-0.00127, 0.00778] | no detectable difference |
| v4 | S4 | 0.00046 | [-0.00195, 0.00297] | no detectable difference |
| v4 | v2 | -0.00003 | [-0.00018, 0.00012] | no detectable difference |

Intervals resample the 30 home teams (1,000 draws, seed 20261005). No odds: the 2026 test is scored on outcomes only.
v4 replaces v2 as the default only if the v4 vs v2 interval lies above zero.

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
2026 games and plate appearances: MLB StatsAPI, copyright MLB Advanced Media, L.P., used for private research.
