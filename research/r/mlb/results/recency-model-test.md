# Recency study: win model, test

Generated 2026-10-03 by `Rscript research/r/mlb/recency_model.R test`. 12148 games, one row per game, home side, weekly walk-forward refits.

Tiers: B home field (equals the constant model in a home-side frame); C incumbent run differential
(season to date, shrunk 20 games); D Elo with margin (K 4, carry 0.8, picked on 2017-2019); E0 E's inputs with no
decay (all history, carry 1, no recency term); E lineup, probable starter, bullpen, fatigue and run differential at the chosen windows.

## Log loss by season (lower is better)

| season | games | B | C | D | E0 | E | accuracy E | accuracy C |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2021 |  2429 | 0.6903 | 0.6779 | 0.6745 | 0.6754 | 0.6721 | 58.4% | 57.0% |
| 2022 |  2430 | 0.6910 | 0.6757 | 0.6730 | 0.6700 | 0.6692 | 60.4% | 57.3% |
| 2023 |  2430 | 0.6926 | 0.6823 | 0.6808 | 0.6826 | 0.6793 | 57.3% | 55.6% |
| 2024 |  2429 | 0.6924 | 0.6826 | 0.6808 | 0.6783 | 0.6756 | 57.6% | 55.5% |
| 2025 |  2430 | 0.6898 | 0.6831 | 0.6783 | 0.6810 | 0.6775 | 56.4% | 54.6% |
| pooled | 12148 | 0.6912 | 0.6803 | 0.6775 | 0.6775 | 0.6748 | 58.0% | 56.0% |

## Paired log-loss gains, team-season cluster bootstrap (positive = second model better)

| contrast | gain | 95% interval |
| --- | --- | --- |
| C over B (incumbent vs home field) | 0.01089 | [0.00797, 0.01454] |
| E over C (slide decision) | 0.00557 | [0.00344, 0.00756] |
| E over E0 (recency at win level) | 0.00271 | [0.00138, 0.00410] |
| E over D (vs Elo) | 0.00271 | [0.00115, 0.00433] |

Calibration of E: intercept -0.007 [-0.043, 0.029], slope 0.952 [0.856, 1.047].

E beats C in 5 of 5 seasons. Ship rule (test only): E over C interval above zero, 4 of 5 seasons, calibration intervals cover 0 and 1: **PASS**.

Not evidence of betting profit: there is no market baseline.
