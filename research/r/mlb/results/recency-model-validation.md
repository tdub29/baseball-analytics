# Recency study: win model, validation

Generated 2026-10-03 by `Rscript research/r/mlb/recency_model.R validation`. 7290 games, one row per game, home side, weekly walk-forward refits.

Tiers: B home field (equals the constant model in a home-side frame); C incumbent run differential
(season to date, shrunk 20 games); D Elo with margin (K 4, carry 0.8, picked on 2017-2019); E0 E's inputs with no
decay (all history, carry 1, no recency term); E lineup, probable starter, bullpen, fatigue and run differential at the chosen windows.

## Log loss by season (lower is better)

| season | games | B | C | D | E0 | E | accuracy E | accuracy C |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2017 | 2430 | 0.6902 | 0.6837 | 0.6826 | 0.6773 | 0.6760 | 56.9% | 55.2% |
| 2018 | 2431 | 0.6918 | 0.6750 | 0.6730 | 0.6732 | 0.6705 | 58.9% | 57.8% |
| 2019 | 2429 | 0.6915 | 0.6707 | 0.6665 | 0.6669 | 0.6657 | 59.2% | 58.7% |
| pooled | 7290 | 0.6912 | 0.6765 | 0.6740 | 0.6725 | 0.6707 | 58.3% | 57.2% |

## Paired log-loss gains, team-season cluster bootstrap (positive = second model better)

| contrast | gain | 95% interval |
| --- | --- | --- |
| C over B (incumbent vs home field) | 0.01468 | [0.01075, 0.01907] |
| E over C (slide decision) | 0.00577 | [0.00287, 0.00879] |
| E over E0 (recency at win level) | 0.00178 | [0.00068, 0.00306] |
| E over D (vs Elo) | 0.00332 | [0.00089, 0.00589] |

Calibration of E: intercept -0.001 [-0.048, 0.046], slope 1.047 [0.925, 1.170].

E beats C in 3 of 3 seasons. Ship rule (test only): E over C interval above zero, 4 of 5 seasons, calibration intervals cover 0 and 1: **not applied on validation**.

Not evidence of betting profit: there is no market baseline.
