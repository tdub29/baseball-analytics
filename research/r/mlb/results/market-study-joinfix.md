# Market study: frozen recency model vs the closing line

Generated 2026-10-06 by `Rscript research/r/mlb/market_study.R`. Charter: MARKET-PLAN.md.

Matched 10831 games (93.6% of model games 2021-03-20 to 2025-08-16), 423 more excluded (Sept-Oct 2021 lines scraped after first pitch). Mean closing overround 1.044; books per game 5.6.
Post-hoc correction: the pre-registered run (`market-study-v1-asrun.md`) included those games; its validation choices are superseded here, so 2023-2025 results in this file are exploratory where they depend on Q2's blend or Q3's threshold.

## Q1: forecast, no tuning (log loss, lower is better)

| season | games | no-vig close | E | incumbent C | accuracy close | accuracy E |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 |  1912 | 0.6708 | 0.6724 | 0.6787 | 59.4% | 58.5% |
| 2022 |  2343 | 0.6668 | 0.6700 | 0.6762 | 60.0% | 60.1% |
| 2023 |  2381 | 0.6767 | 0.6796 | 0.6828 | 57.6% | 57.2% |
| 2024 |  2382 | 0.6702 | 0.6755 | 0.6819 | 58.1% | 57.7% |
| 2025 |  1813 | 0.6764 | 0.6772 | 0.6839 | 56.6% | 56.9% |
| pooled | 10831 | 0.6720 | 0.6750 | 0.6806 | 58.4% | 58.1% |

E minus close, per-game log loss (positive = E better): -0.00293 [-0.00416, -0.00167].

## Q2: does E add information? (blend fit 2021-2022, scored 2023-2025)

Blend: logit p = 0.019 + 0.953 logit(close) + 0.065 logit(E). Test gain over the close alone: -0.00015 [-0.00037, 0.00009].

## Q3: betting at the best closing price

Thresholds on 2021-2022:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3236 | -0.009 |
| 0.02 | 2379 | -0.004 |
| 0.03 | 1633 | 0.004 |
| 0.04 | 1054 | 0.010 |
| 0.05 | 620 | 0.033 |
| 0.06 | 363 | 0.060 |

Chosen tau 0.06. Test 2023-2025: 606 bets, 279 won, 92.6 units, ROI 0.153, week-block 95% [0.050, 0.244]. Quarter Kelly ROI on stake 0.238.

| season | bets | units | ROI |
| --- | --- | --- | --- |
| 2023 | 240 | 17.9 | 0.075 |
| 2024 | 211 | 57.6 | 0.273 |
| 2025 | 155 | 17.1 | 0.110 |

Private research on scraped odds; not betting advice.
