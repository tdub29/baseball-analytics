# Market study: frozen recency model vs the closing line

Generated 2026-10-04 by `Rscript research/r/mlb/market_study.R`. Charter: MARKET-PLAN.md.

Matched 10977 games (94.9% of model games 2021-03-20 to 2025-08-16). Mean closing overround 1.043; books per game 5.6.

## Q1: forecast, no tuning (log loss, lower is better)

| season | games | no-vig close | E | incumbent C | accuracy close | accuracy E |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 |  2183 | 0.6425 | 0.6726 | 0.6782 | 62.4% | 58.0% |
| 2022 |  2343 | 0.6668 | 0.6700 | 0.6762 | 60.0% | 60.1% |
| 2023 |  2381 | 0.6767 | 0.6796 | 0.6828 | 57.6% | 57.2% |
| 2024 |  2382 | 0.6702 | 0.6755 | 0.6819 | 58.1% | 57.7% |
| 2025 |  1688 | 0.6768 | 0.6775 | 0.6835 | 56.8% | 57.0% |
| pooled | 10977 | 0.6664 | 0.6750 | 0.6804 | 59.1% | 58.1% |

E minus close, per-game log loss (positive = E better): -0.00858 [-0.01085, -0.00632].

## Q2: does E add information? (blend fit 2021-2022, scored 2023-2025)

Blend: logit p = 0.013 + 1.796 logit(close) + -0.735 logit(E). Test gain over the close alone: -0.00162 [-0.00308, -0.00030].

## Q3: betting at the best closing price

Thresholds on 2021-2022:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3495 | -0.039 |
| 0.02 | 2625 | -0.046 |
| 0.03 | 1876 | -0.065 |
| 0.04 | 1292 | -0.094 |
| 0.05 | 845 | -0.133 |
| 0.06 | 583 | -0.183 |

Chosen tau 0.01. Test 2023-2025: 4956 bets, 2323 won, -48.8 units, ROI -0.010, week-block 95% [-0.046, 0.023]. Quarter Kelly ROI on stake 0.091.

| season | bets | units | ROI |
| --- | --- | --- | --- |
| 2023 | 1839 | -47.0 | -0.026 |
| 2024 | 1798 | 11.9 | 0.007 |
| 2025 | 1319 | -13.6 | -0.010 |

Private research on scraped odds; not betting advice.
