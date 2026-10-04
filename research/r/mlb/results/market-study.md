# Market study: frozen recency model vs the closing line

Generated 2026-10-04 by `Rscript research/r/mlb/market_study.R`. Charter: MARKET-PLAN.md.

Matched 10583 games (91.5% of model games 2021-03-20 to 2025-08-16), 394 more excluded (Sept-Oct 2021 lines scraped after first pitch). Mean closing overround 1.044; books per game 5.6.
Post-hoc correction: the pre-registered run (`market-study-v1-asrun.md`) included those games; its validation choices are superseded here, so 2023-2025 results in this file are exploratory where they depend on Q2's blend or Q3's threshold.

## Q1: forecast, no tuning (log loss, lower is better)

| season | games | no-vig close | E | incumbent C | accuracy close | accuracy E |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 |  1789 | 0.6718 | 0.6730 | 0.6793 | 58.9% | 58.4% |
| 2022 |  2343 | 0.6668 | 0.6700 | 0.6762 | 60.0% | 60.1% |
| 2023 |  2381 | 0.6767 | 0.6796 | 0.6828 | 57.6% | 57.2% |
| 2024 |  2382 | 0.6702 | 0.6755 | 0.6819 | 58.1% | 57.7% |
| 2025 |  1688 | 0.6768 | 0.6775 | 0.6835 | 56.8% | 57.0% |
| pooled | 10583 | 0.6722 | 0.6751 | 0.6807 | 58.3% | 58.1% |

E minus close, per-game log loss (positive = E better): -0.00290 [-0.00421, -0.00150].

## Q2: does E add information? (blend fit 2021-2022, scored 2023-2025)

Blend: logit p = 0.021 + 0.925 logit(close) + 0.079 logit(E). Test gain over the close alone: -0.00013 [-0.00041, 0.00012].

## Q3: betting at the best closing price

Thresholds on 2021-2022:

| tau | bets | ROI |
| --- | --- | --- |
| 0.01 | 3142 | -0.006 |
| 0.02 | 2306 | -0.003 |
| 0.03 | 1580 | 0.004 |
| 0.04 | 1021 | 0.010 |
| 0.05 | 596 | 0.037 |
| 0.06 | 346 | 0.076 |

Chosen tau 0.06. Test 2023-2025: 600 bets, 278 won, 96.2 units, ROI 0.160, week-block 95% [0.056, 0.252]. Quarter Kelly ROI on stake 0.245.

| season | bets | units | ROI |
| --- | --- | --- | --- |
| 2023 | 240 | 17.9 | 0.075 |
| 2024 | 211 | 57.6 | 0.273 |
| 2025 | 149 | 20.7 | 0.139 |

Private research on scraped odds; not betting advice.
