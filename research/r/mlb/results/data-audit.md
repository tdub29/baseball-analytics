# Data audit: MLB research pipeline

Generated 2026-10-05 by `Rscript research/r/mlb/data_audit.R` from the local raw cache (no network). Source descriptions, terms and known gaps: [DATA.md](../DATA.md). Aggregates only: no odds row or per-game price appears here.

Method (McGilvray assessment baseline): each check has a population, a pass rule and a reason. Reconciliation pairs records one to one, exact first, then each looser rule on what is left, so every record lands in exactly one category.

## Headline

- Retrosheet vs StatsAPI: 25155 of 25191 Retrosheet regular-season games (99.86%) match a StatsAPI game on date, both teams and final score; 0 score disagreements, 0 date disagreements, 36 home/away swaps, 0 Retrosheet-only and 2 StatsAPI-only games.
- Statcast to Retrosheet balls in play: 99.54% of Retrosheet balls in play matched (range 96.02% to 100.00% by season); 98.70% usable with exit velocity and launch angle.
- Odds to StatsAPI games: 11017 of 11326 final regular-season odds games matched (97.27%; the file also holds 1791 spring, All-Star and postseason rows); 95.24% of StatsAPI games between 2021-04-01 and 2025-08-16 have a matched odds row; 394 matched games fall in the excluded window. 0 StatsAPI games matched by two odds rows.
- Duplicate keys: 15 source keys checked, 2 with duplicates (table 5). The Statcast cache matches the weekly CSVs.

## Prioritized findings

Ranked by how much each could move a committed result. Severity is a judgement on reach and size; none of these has been rerun to measure its effect.

1. **High: switch hitters entered as right-handed (matchup model, totals).** 11.89% of Retrosheet PAs carry batter hand B; `matchup_build.R` maps them to R, so platoon splits, the platoon prior and park factors by batter hand treat a switch hitter as right-handed even against right-handed pitchers. Reaches `features.rds`, the frozen matchup v2 test and the totals study. Fix: side = opposite of the pitcher's hand for B (table 6).
2. **Medium: Retrosheet batted-ball types change definition in 2020 (matchup model, totals).** Pitchers are rated on the outcome mix of their batted-ball types over the prior three seasons, so 2020-2022 balls get mixes fit partly on the pre-2020 definition (table 3). Touches validation seasons 2021-2022 directly and the 2023-2025 test through decayed history.
3. **Medium: odds team names that never match (market study, matchup market tests).** 2021: "Cleveland Guardians" (154 rows); 2025: "Athletics Athletics" (131 rows). Those games are silently missing from `market-joined.csv`, so the 2021 market validation and the 2025 test season each lose one club. `totals_study.R` maps names by majority vote and keeps them (table 4).
4. **Low to medium: StatsAPI player logs miss pitchers absent from the cached rosters (recency model E and everything built on it).** Up to 1.96% of pitcher batters faced missing in a season; 212 starts by 16 such pitchers across 2015-2025 (table 6).
5. **Low: 36 games with home and away swapped between Retrosheet and StatsAPI** (relocated series, mostly 2020; table 2). The Retrosheet-to-StatsAPI join in `matchup_model.R` drops them, so they carry no recency or market row. The 2018 tiebreakers are StatsAPI-only.
6. **Low: Statcast gaps (7 Retrosheet dates without Statcast rows).** Statcast feeds only the dropped v3 ablations, not a frozen model.

## 0. Raw inputs (fingerprints)

md5 of the single file, or of the sorted list of per-file md5s for a directory. `modified` is the local file time, i.e. the retrieval date.

| source | files | MB | modified | md5 |
| --- | --- | --- | --- | --- |
| Retrosheet season zips | 11 | 98.8 | 2026-10-04 | ecdfdddbee07228b77fba5f3e8c22d61 |
| StatsAPI lineups (schedule, scores, probables, lineups) | 11 | 1.0 | 2026-10-03 | e651ac07cc862446ca0ccac626daf66d |
| StatsAPI team game logs | 660 | 2.1 | 2026-10-02 to 2026-10-03 | b6824125977cac67728b83e748f01efd |
| StatsAPI player game logs | 323 | 7.0 | 2026-10-02 to 2026-10-03 | 72ef192d6af57d18bbe383b0e028eafc |
| StatsAPI rosters | 330 | 0.1 | 2026-10-02 to 2026-10-03 | f12f6e7d03dcec8ae6567015f1f07f5f |
| StatsAPI teams | 11 | 0.0 | 2026-10-02 to 2026-10-03 | 24429037ce338ce175f6eba040a5250c |
| StatsAPI schedule (ingest.R, backtest) | 5 | 1.0 | 2026-09-30 to 2026-10-02 | fcc09af67e4f73767eabf0c5d5aec354 |
| StatsAPI season dates | 1 | 0.0 | 2026-09-30 | de9ac5a4ca2719b97ce840544afa3123 |
| Savant batted balls (weekly CSVs) | 351 | 952.7 | 2026-10-04 | cc20be689add006ac12bba6bf31a5b16 |
| Chadwick register | 1 | 25.9 | 2026-09-30 | a92510a99e2415dd0e68da3108470f36 |
| Baseball-Reference daily batting windows | 687 | 14.2 | 2026-09-30 to 2026-10-01 | 70abb2cba47944c28e32a4e969e341f5 |
| Baseball-Reference daily pitching windows | 687 | 18.7 | 2026-09-30 to 2026-10-01 | 8b2cf16529a3d0d1c3f468fabe3fc36a |
| Odds dataset (SportsBookReview scrape) | 1 | 76.4 | 2026-10-04 | 6a0572978fe262dc24a817311a6dbba8 |

## 1. Row counts by season

Retrosheet PAs exclude intentional walks (retro.R). Balls in play: hits and outs in play with a batted-ball type. StatsAPI games are final regular-season games in the season window. Baseball-Reference windows were pulled for 2016-2019 only (the 2019 backtest).

| source | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Retrosheet games | 2429 | 2428 | 2430 | 2429 | 2429 | 898 | 2429 | 2430 | 2430 | 2429 | 2430 |
| Retrosheet PAs | 182677 | 183648 | 184325 | 184074 | 185764 | 66304 | 181115 | 181577 | 183630 | 181940 | 182370 |
| Retrosheet balls in play | 127772 | 125544 | 125341 | 123996 | 123021 | 43569 | 120122 | 123151 | 123131 | 123012 | 123618 |
| StatsAPI games | 2429 | 2428 | 2430 | 2431 | 2429 | 898 | 2429 | 2430 | 2430 | 2429 | 2430 |
| StatsAPI team-log rows | 9716 | 9712 | 9720 | 9724 | 9716 | 3592 | 9716 | 9720 | 9720 | 9716 | 9720 |
| StatsAPI hitter lines | 50517 | 50228 | 50157 | 50255 | 50174 | 18770 | 49929 | 49875 | 50598 | 50612 | 50655 |
| StatsAPI pitcher lines | 19921 | 20137 | 20483 | 21136 | 21342 | 7926 | 21360 | 20719 | 20382 | 20606 | 20708 |
| StatsAPI roster rows | 1484 | 1482 | 1494 | 1533 | 1567 | 1362 | 1702 | 1677 | 1608 | 1649 | 1689 |
| StatsAPI schedule (backtest) | 2429 | 2428 | 2430 | 2431 | 2429 | - | - | - | - | - | - |
| Statcast balls in play | 130474 | 123708 | 127555 | 126283 | 125751 | 43972 | 121702 | 124265 | 124232 | 124201 | 124887 |
| bref batting rows | - | 92390 | 92975 | 95098 | 98090 | - | - | - | - | - | - |
| bref pitching rows | - | 75805 | 77785 | 81767 | 86553 | - | - | - | - | - | - |
| Odds games (all) | - | - | - | - | - | - | 2388 | 2671 | 2888 | 2894 | 2280 |
| Odds games final, scored | - | - | - | - | - | - | 2388 | 2669 | 2888 | 2893 | 2279 |

## 2. Retrosheet vs StatsAPI: games and final scores

Retrosheet team codes are mapped to StatsAPI team ids per season by majority vote over games that agree on date and score (codes per season: 30; ids per season: 30).
Rules in order: exact (date, home, away, both scores); same date and teams, score differs; same teams and score within 3 days; home and away swapped, same date and score; the rest are unmatched.

| season | retrosheet | statsapi | exact | score differs | date differs | home/away swapped | retrosheet only | statsapi only | match rate | score agreement |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2015 | 2429 | 2429 | 2426 | 0 | 0 | 3 | 0 | 0 | 99.88% | 100.00% |
| 2016 | 2428 | 2428 | 2428 | 0 | 0 | 0 | 0 | 0 | 100.00% | 100.00% |
| 2017 | 2430 | 2430 | 2427 | 0 | 0 | 3 | 0 | 0 | 99.88% | 100.00% |
| 2018 | 2429 | 2431 | 2429 | 0 | 0 | 0 | 0 | 2 | 100.00% | 100.00% |
| 2019 | 2429 | 2429 | 2429 | 0 | 0 | 0 | 0 | 0 | 100.00% | 100.00% |
| 2020 | 898 | 898 | 870 | 0 | 0 | 28 | 0 | 0 | 96.88% | 100.00% |
| 2021 | 2429 | 2429 | 2428 | 0 | 0 | 1 | 0 | 0 | 99.96% | 100.00% |
| 2022 | 2430 | 2430 | 2429 | 0 | 0 | 1 | 0 | 0 | 99.96% | 100.00% |
| 2023 | 2430 | 2430 | 2430 | 0 | 0 | 0 | 0 | 0 | 100.00% | 100.00% |
| 2024 | 2429 | 2429 | 2429 | 0 | 0 | 0 | 0 | 0 | 100.00% | 100.00% |
| 2025 | 2430 | 2430 | 2430 | 0 | 0 | 0 | 0 | 0 | 100.00% | 100.00% |

Same teams, same day, same score (doubleheaders that cannot be told apart by score): 4 Retrosheet games and 4 StatsAPI games. `matchup_model.R` keeps the first pairing of such games and `market_study.R` and `totals_study.R` drop them.

Every game outside the exact category:

| category | season | gid | game_pk | Retrosheet date | StatsAPI date | teams | Retrosheet score (away-home) | StatsAPI score (away-home) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| home/away swapped | 2015 | TBA201505010 | 413994 | 2015-05-01 | 2015-05-01 | BAL at TBA | 0-2 | 2-0 |
| home/away swapped | 2015 | TBA201505020 | 414009 | 2015-05-02 | 2015-05-02 | BAL at TBA | 4-0 | 0-4 |
| home/away swapped | 2015 | TBA201505030 | 414024 | 2015-05-03 | 2015-05-03 | BAL at TBA | 4-2 | 2-4 |
| home/away swapped | 2017 | MIL201709150 | 492302 | 2017-09-15 | 2017-09-15 | MIA at MIL | 2-10 | 10-2 |
| home/away swapped | 2017 | MIL201709160 | 492317 | 2017-09-16 | 2017-09-16 | MIA at MIL | 7-4 | 4-7 |
| home/away swapped | 2017 | MIL201709170 | 492332 | 2017-09-17 | 2017-09-17 | MIA at MIL | 3-10 | 10-3 |
| statsapi only | 2018 | - | 570334 | - | 2018-10-01 | Milwaukee Brewers at Chicago Cubs | - | 3-1 |
| statsapi only | 2018 | - | 570335 | - | 2018-10-01 | Colorado Rockies at Los Angeles Dodgers | - | 2-5 |
| home/away swapped | 2020 | BOS202009042 | 630865 | 2020-09-04 | 2020-09-04 | TOR at BOS | 2-3 | 3-2 |
| home/away swapped | 2020 | PHI202009181 | 630907 | 2020-09-18 | 2020-09-18 | TOR at PHI | 0-7 | 7-0 |
| home/away swapped | 2020 | WAS202007290 | 630916 | 2020-07-29 | 2020-07-29 | TOR at WAS | 0-4 | 4-0 |
| home/away swapped | 2020 | WAS202007300 | 630917 | 2020-07-30 | 2020-07-30 | TOR at WAS | 4-6 | 6-4 |
| home/away swapped | 2020 | BAL202009172 | 630953 | 2020-09-17 | 2020-09-17 | TBA at BAL | 10-6 | 6-10 |
| home/away swapped | 2020 | PIT202009182 | 630987 | 2020-09-18 | 2020-09-18 | SLN at PIT | 7-2 | 2-7 |
| home/away swapped | 2020 | CHN202008172 | 630996 | 2020-08-17 | 2020-08-17 | SLN at CHN | 4-5 | 5-4 |
| home/away swapped | 2020 | CHN202008192 | 630997 | 2020-08-19 | 2020-08-19 | SLN at CHN | 2-4 | 4-2 |
| home/away swapped | 2020 | CHN202009052 | 630998 | 2020-09-05 | 2020-09-05 | SLN at CHN | 5-1 | 1-5 |
| home/away swapped | 2020 | SFN202009160 | 631032 | 2020-09-16 | 2020-09-16 | SEA at SFN | 3-9 | 9-3 |
| home/away swapped | 2020 | SFN202009170 | 631034 | 2020-09-17 | 2020-09-17 | SEA at SFN | 4-6 | 6-4 |
| home/away swapped | 2020 | SDN202009190 | 631036 | 2020-09-19 | 2020-09-19 | SEA at SDN | 4-1 | 1-4 |
| home/away swapped | 2020 | SDN202009200 | 631037 | 2020-09-20 | 2020-09-20 | SEA at SDN | 4-7 | 7-4 |
| home/away swapped | 2020 | SDN202009180 | 631040 | 2020-09-18 | 2020-09-18 | SEA at SDN | 1-6 | 6-1 |
| home/away swapped | 2020 | OAK202009262 | 631055 | 2020-09-26 | 2020-09-26 | SEA at OAK | 12-3 | 3-12 |
| home/away swapped | 2020 | SFN202009252 | 631059 | 2020-09-25 | 2020-09-25 | SDN at SFN | 6-5 | 5-6 |
| home/away swapped | 2020 | PHI202008051 | 631220 | 2020-08-05 | 2020-08-05 | NYA at PHI | 7-11 | 11-7 |
| home/away swapped | 2020 | NYA202008302 | 631229 | 2020-08-30 | 2020-08-30 | NYN at NYA | 2-5 | 5-2 |
| home/away swapped | 2020 | NYA202008282 | 631230 | 2020-08-28 | 2020-08-28 | NYN at NYA | 4-3 | 3-4 |
| home/away swapped | 2020 | SLN202009252 | 631292 | 2020-09-25 | 2020-09-25 | MIL at SLN | 1-9 | 9-1 |
| home/away swapped | 2020 | NYN202008252 | 631323 | 2020-08-25 | 2020-08-25 | MIA at NYN | 3-0 | 0-3 |
| home/away swapped | 2020 | BAL202008052 | 631339 | 2020-08-05 | 2020-08-05 | MIA at BAL | 2-1 | 1-2 |
| home/away swapped | 2020 | BAL202008060 | 631340 | 2020-08-06 | 2020-08-06 | MIA at BAL | 8-7 | 7-8 |
| home/away swapped | 2020 | WAS202008222 | 631341 | 2020-08-22 | 2020-08-22 | MIA at WAS | 5-3 | 3-5 |
| home/away swapped | 2020 | OAK202009081 | 631429 | 2020-09-08 | 2020-09-08 | HOU at OAK | 2-4 | 4-2 |
| home/away swapped | 2020 | ANA202009052 | 631440 | 2020-09-05 | 2020-09-05 | HOU at ANA | 6-7 | 7-6 |
| home/away swapped | 2020 | MIN202009042 | 631456 | 2020-09-04 | 2020-09-04 | DET at MIN | 2-3 | 3-2 |
| home/away swapped | 2020 | PIT202009042 | 631602 | 2020-09-04 | 2020-09-04 | CIN at PIT | 3-4 | 4-3 |
| home/away swapped | 2021 | ANA202108101 | 632208 | 2021-08-10 | 2021-08-10 | TOR at ANA | 3-6 | 6-3 |
| home/away swapped | 2022 | DET202205101 | 662412 | 2022-05-10 | 2022-05-10 | OAK at DET | 0-6 | 6-0 |

## 3. Statcast balls in play to Retrosheet

Matched as `statcast.R` does: date, batter and pitcher (MLBAM to Retrosheet ids through the Chadwick register) and the order of their balls in play that day. `usable` needs exit velocity and launch angle, which the expected-outcome mix requires. Agreement columns compare the two sources' scoring of the same ball.

| season | Retrosheet BIP | Statcast BIP | matched | Retrosheet BIP matched | Statcast BIP matched | usable (EV and LA) | outcome agrees | batted-ball type agrees | Statcast rows without a Retrosheet id | Retrosheet dates with no Statcast rows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2015 | 127772 | 130474 | 127701 | 99.94% | 97.87% | 97.50% | 99.64% | 84.29% | 0 | 0 |
| 2016 | 125544 | 123708 | 120552 | 96.02% | 97.45% | 94.11% | 99.51% | 85.70% | 0 | 7 |
| 2017 | 125341 | 127555 | 125340 | 100.00% | 98.26% | 99.21% | 99.76% | 85.42% | 0 | 0 |
| 2018 | 123996 | 126283 | 123975 | 99.98% | 98.17% | 99.28% | 99.77% | 86.01% | 0 | 0 |
| 2019 | 123021 | 125751 | 122975 | 99.96% | 97.79% | 99.07% | 99.60% | 86.72% | 0 | 0 |
| 2020 | 43569 | 43972 | 43526 | 99.90% | 98.99% | 99.22% | 99.85% | 94.45% | 0 | 0 |
| 2021 | 120122 | 121702 | 119911 | 99.82% | 98.53% | 99.52% | 99.88% | 99.75% | 0 | 0 |
| 2022 | 123151 | 124265 | 123107 | 99.96% | 99.07% | 99.54% | 99.86% | 99.80% | 0 | 0 |
| 2023 | 123131 | 124232 | 122941 | 99.85% | 98.96% | 99.56% | 99.87% | 99.82% | 0 | 0 |
| 2024 | 123012 | 124201 | 122912 | 99.92% | 98.96% | 99.63% | 99.87% | 99.81% | 0 | 0 |
| 2025 | 123618 | 124887 | 123497 | 99.90% | 98.89% | 99.56% | 99.89% | 99.77% | 0 | 0 |

Retrosheet game dates with no Statcast rows: 2016-09-06, 2016-09-07, 2016-09-08, 2016-09-09, 2016-09-10, 2016-09-11, 2016-09-12.

Batted-ball type shares by season (percent of balls in play). Retrosheet's types change definition in 2020: popups go from about 1% to 7% and fly balls from about 35% to 26%, and agreement with Statcast's types rises from about 85% to 99.8%, so Retrosheet types from 2020 on follow Statcast's classification while earlier seasons do not. Anything that pools types across that boundary (for example a mix fit on 2017-2019 and applied to 2020-2022 balls) mixes two definitions.

| season | Retrosheet fb | Retrosheet gb | Retrosheet ld | Retrosheet pu | Statcast fb | Statcast gb | Statcast ld | Statcast pu |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2015 | 33.7 | 45.4 | 20.7 | 0.2 | 19.8 | 47.0 | 26.5 | 6.7 |
| 2016 | 33.9 | 45.2 | 19.7 | 1.2 | 21.2 | 46.2 | 25.6 | 7.0 |
| 2017 | 35.4 | 44.3 | 20.1 | 0.2 | 22.4 | 45.3 | 25.1 | 7.1 |
| 2018 | 35.3 | 43.3 | 21.2 | 0.2 | 23.1 | 44.5 | 25.0 | 7.4 |
| 2019 | 35.0 | 43.4 | 20.4 | 1.3 | 23.8 | 43.8 | 25.1 | 7.3 |
| 2020 | 20.9 | 43.3 | 28.6 | 7.2 | 24.0 | 43.7 | 25.0 | 7.4 |
| 2021 | 26.0 | 43.3 | 23.9 | 6.8 | 25.6 | 43.9 | 23.6 | 6.9 |
| 2022 | 25.9 | 43.2 | 23.9 | 7.0 | 25.7 | 43.6 | 23.7 | 7.1 |
| 2023 | 26.4 | 42.7 | 24.1 | 6.8 | 26.2 | 43.1 | 23.9 | 6.9 |
| 2024 | 26.7 | 42.3 | 23.9 | 7.1 | 26.4 | 42.7 | 23.7 | 7.1 |
| 2025 | 26.9 | 41.9 | 24.1 | 7.0 | 26.6 | 42.4 | 23.9 | 7.1 |

## 4. Odds to StatsAPI games

Joined as `market_study.R` does: odds file date, both team names (normalised, "Oakland" dropped) and the final score; a key that repeats on either side is dropped as ambiguous. Unmatched rows are classified by the first looser rule that finds a StatsAPI game. The odds file keys a game on the Eastern date of first pitch for 100.00% of rows and on the UTC date for 75.60%.

| season | odds entries | not final or no score | odds final games | outside regular season | matched | ambiguous | date off by one | score differs | name not in StatsAPI | no game that day | in excluded window | StatsAPI games in odds range | regular-season odds matched | StatsAPI games covered |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2021 | 2388 | 0 | 2388 | 38 | 2189 | 0 | 6 | 1 | 154 | 0 | 394 | 2429 | 93.15% | 90.12% |
| 2022 | 2671 | 2 | 2669 | 308 | 2360 | 0 | 1 | 0 | 0 | 0 | 0 | 2430 | 99.96% | 97.12% |
| 2023 | 2888 | 0 | 2888 | 499 | 2381 | 1 | 6 | 0 | 0 | 1 | 0 | 2430 | 99.67% | 97.98% |
| 2024 | 2894 | 1 | 2893 | 495 | 2394 | 0 | 2 | 1 | 0 | 1 | 0 | 2429 | 99.83% | 98.56% |
| 2025 | 2280 | 1 | 2279 | 451 | 1693 | 0 | 3 | 1 | 131 | 0 | 0 | 1850 | 92.61% | 91.51% |

Regular-season odds names that never match a StatsAPI team name that season (rows, home or away). Each one drops that team's games from the moneyline join:

| season | odds name | rows |
| --- | --- | --- |
| 2021 | Cleveland Guardians | 154 |
| 2025 | Athletics Athletics | 131 |

StatsAPI games inside the odds date range with no matched odds row (the excluded window counts as matched here), and the teams most affected:

| season | games without odds | teams most affected (games) |
| --- | --- | --- |
| 2021 | 240 | Cleveland Indians (162), Chicago White Sox (26), Minnesota Twins (25) |
| 2022 | 70 | Cleveland Guardians (11), New York Mets (10), Detroit Tigers (8) |
| 2023 | 49 | New York Mets (11), Detroit Tigers (8), Washington Nationals (7) |
| 2024 | 35 | St. Louis Cardinals (7), Minnesota Twins (5), Chicago White Sox (5) |
| 2025 | 157 | Athletics (125), Cleveland Guardians (12), Baltimore Orioles (11) |

Sportsbooks named in the moneyline and totals entries: bet_rivers_ny, bet365, betmgm, caesars, draftkings, fanduel.

Fields present on a book's moneyline entry: currentLine, currentLine.awayOdds, currentLine.homeOdds, openingLine, openingLine.awayOdds, openingLine.homeOdds, sportsbook. There is no timestamp on the opening or current line; `currentLine` on a finished game is the last scraped price, taken as the close.

Line-move sanity per month (matched games, no ties): share of games whose consensus no-vig home probability moved more than 15 points from the open, and the closing log loss. In-game scrapes show as a jump in moves and a drop in log loss.

| month | games | moved 15+ points from open | closing log loss | flag |
| --- | --- | --- | --- | --- |
| 2021-04 | 343 | 0.00% | 0.6993 |  |
| 2021-05 | 374 | 0.00% | 0.6646 |  |
| 2021-06 | 366 | 0.00% | 0.6569 |  |
| 2021-07 | 328 | 0.00% | 0.6906 |  |
| 2021-08 | 378 | 0.00% | 0.6518 |  |
| 2021-09 | 352 | 36.36% | 0.5224 | excluded window |
| 2021-10 | 42 | 59.52% | 0.4017 | excluded window |
| 2022-04 | 313 | 0.32% | 0.6682 |  |
| 2022-05 | 393 | 0.00% | 0.6761 |  |
| 2022-06 | 394 | 1.27% | 0.6639 |  |
| 2022-07 | 379 | 0.26% | 0.6769 |  |
| 2022-08 | 411 | 0.00% | 0.6623 |  |
| 2022-09 | 382 | 0.26% | 0.6504 |  |
| 2022-10 | 71 | 0.00% | 0.6837 |  |
| 2023-03 | 20 | 0.00% | 0.7168 |  |
| 2023-04 | 400 | 0.50% | 0.6596 |  |
| 2023-05 | 410 | 0.00% | 0.6898 |  |
| 2023-06 | 386 | 0.00% | 0.6756 |  |
| 2023-07 | 356 | 0.00% | 0.6893 |  |
| 2023-08 | 400 | 0.00% | 0.6638 |  |
| 2023-09 | 394 | 0.00% | 0.6806 |  |
| 2023-10 | 15 | 0.00% | 0.6906 |  |
| 2024-03 | 47 | 0.00% | 0.6828 |  |
| 2024-04 | 389 | 0.00% | 0.6750 |  |
| 2024-05 | 401 | 1.50% | 0.6746 |  |
| 2024-06 | 398 | 0.25% | 0.6619 |  |
| 2024-07 | 362 | 1.10% | 0.6868 |  |
| 2024-08 | 403 | 0.74% | 0.6493 |  |
| 2024-09 | 382 | 0.00% | 0.6744 |  |
| 2025-03 | 61 | 0.00% | 0.6488 |  |
| 2025-04 | 358 | 0.00% | 0.6562 |  |
| 2025-05 | 374 | 0.00% | 0.6805 |  |
| 2025-06 | 364 | 0.27% | 0.6839 |  |
| 2025-07 | 332 | 0.00% | 0.6924 |  |
| 2025-08 | 199 | 1.51% | 0.6760 |  |

## 5. Duplicate keys

| source | key columns | rows | duplicate rows |
| --- | --- | --- | --- |
| Retrosheet gameinfo (regular) | gid | 25191 | 0 |
| Retrosheet gameinfo (all game types) | gid | 25643 | 0 |
| Retrosheet plate appearances | gid, seq | 1897424 | 0 |
| StatsAPI lineups | game_pk | 25193 | 0 |
| StatsAPI lineups | date, home, away, score | 25193 | 2 |
| StatsAPI team game logs | team_id, game_pk, group | 100772 | 0 |
| StatsAPI player game logs | person_id, game_pk, group | 736490 | 1 |
| StatsAPI rosters | person_id, team_id, season | 17247 | 0 |
| Savant weekly CSVs (before dedupe) | game_pk, at_bat_number | 1297030 | 0 |
| Statcast cache bip_all.rds | game_pk, at_bat_number | 1297030 | 0 |
| Chadwick register | key_mlbam | 129732 | 0 |
| Chadwick register | key_retro | 25543 | 0 |
| Chadwick register | key_bbref | 23982 | 0 |
| Odds | date, home, away, start | 13121 | 0 |
| Odds (final) | date, home, away, score | 13117 | 0 |

Notes: a doubleheader with the same final score in both games repeats the (date, home, away, score) key by design; Chadwick ids are many-to-one only where a row lacks the id (blank rows are excluded).

## 6. Missingness of key fields

Share of rows failing each rule, by season. `-` means the source has no rows that season. "Probable is not the actual starter" compares StatsAPI's historical probable with the pitcher credited with the start in StatsAPI's own game logs: a near-zero rate means the stored probable is the actual starter, written after the game, not a pre-game probable.

| field | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Retrosheet PA: batter or pitcher id blank | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| Retrosheet PA: batter hand B (switch hitter, side not recorded) | 12.34% | 12.69% | 12.94% | 13.51% | 12.26% | 12.42% | 11.23% | 11.74% | 10.34% | 10.33% | 11.24% |
| Retrosheet PA: batter hand not L, R or B | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| Retrosheet PA: pitcher hand not L/R | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| Retrosheet PA: hit or out in play without batted-ball type | 2.10% | 2.57% | 1.77% | 1.77% | 2.22% | 1.00% | 1.35% | 0.96% | 0.96% | 1.04% | 1.09% |
| Retrosheet game: temperature 0 or missing | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.08% | 0.00% |
| Retrosheet game: home-plate umpire blank | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| StatsAPI game: a probable starter missing | 0.12% | 0.00% | 0.00% | 0.12% | 0.08% | 0.78% | 0.12% | 0.04% | 0.04% | 0.08% | 0.21% |
| StatsAPI game: probable is not the actual starter | 0.21% | 0.04% | 0.58% | 0.04% | 0.58% | 0.22% | 0.25% | 0.50% | 0.22% | 0.12% | 0.17% |
| StatsAPI game: no starter in the player logs (either side) | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.78% | 1.32% | 5.02% | 0.00% | 1.28% |
| StatsAPI game: a lineup slot missing | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| StatsAPI game: venue missing | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| Statcast BIP: exit velocity missing | 3.43% | 2.80% | 1.63% | 1.41% | 1.51% | 0.70% | 0.31% | 0.44% | 0.29% | 0.30% | 0.36% |
| Statcast BIP: launch angle missing | 3.43% | 2.79% | 1.63% | 1.47% | 1.51% | 0.70% | 0.31% | 0.35% | 0.22% | 0.25% | 0.29% |
| Statcast BIP: batter or pitcher has no Retrosheet id | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% |
| Odds game: no moneyline | - | - | - | - | - | - | 0.34% | 1.09% | 4.26% | 5.01% | 6.49% |
| Odds game: no current moneyline | - | - | - | - | - | - | 0.34% | 1.09% | 4.26% | 5.01% | 6.58% |
| Odds game: no opening moneyline | - | - | - | - | - | - | 0.34% | 1.09% | 4.26% | 5.01% | 6.58% |
| Odds game: no totals | - | - | - | - | - | - | 0.34% | 1.57% | 4.29% | 5.08% | 6.49% |

"Batter hand B" is a switch hitter: Retrosheet's plays file gives the registered hand, not the side he batted from. `matchup_build.R` maps every non-L/R hand to R, so these PAs enter the platoon splits and park factors as right-handed, although a switch hitter bats left against right-handed pitchers.

| check | value |
| --- | --- |
| Statcast batters and pitchers with a Retrosheet id | 100.00% |
| Retrosheet batters and pitchers in the register | 100.00% |
| StatsAPI probable starters with a Baseball-Reference id | 100.00% |

StatsAPI player game logs against the team game logs they should sum to. Player logs are pulled only for players on the cached fullSeason rosters (`gamelogs.R`), so a pitcher missing from those rosters loses his whole season. Pitchers batting before the universal DH (2015-2019, 2021) explain most of the hitter gap in those years, because hitter logs skip roster pitchers by design.

| season | pitcher BF missing vs team logs | team-games with no starter line | starts by pitchers absent from the rosters | such pitchers | hitter PA missing vs team logs |
| --- | --- | --- | --- | --- | --- |
| 2015 | 0.16% | 0 | 0 | 0 | 2.94% |
| 2016 | 0.06% | 0 | 0 | 0 | 2.90% |
| 2017 | 0.09% | 0 | 0 | 0 | 2.84% |
| 2018 | 0.17% | 0 | 0 | 0 | 2.97% |
| 2019 | 0.24% | 0 | 0 | 0 | 2.77% |
| 2020 | 0.26% | 0 | 0 | 0 | 0.01% |
| 2021 | 0.61% | 19 | 19 | 1 | 3.01% |
| 2022 | 0.84% | 32 | 39 | 9 | 0.48% |
| 2023 | 1.96% | 122 | 123 | 5 | 0.00% |
| 2024 | 0.25% | 0 | 0 | 0 | 0.04% |
| 2025 | 0.82% | 31 | 31 | 1 | 0.23% |

The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at "www.retrosheet.org".
