# Rest and travel v2: exploratory second look, 2017-2022

Generated 2026-10-10 by research/r/mlb/travel_features.R, under the MATCHUP-PLAN.md entry of 2026-10-10 (committed in 10a1515 before any scoring).
Features for every 2016-2025 game are in data/mlb/matchup/travel.rds (features only). Models train on earlier 2016-2022 rows and are scored on 2017-2022; nothing was scored on 2023-2025.
These rows already rejected the five-term rest and travel group, so a pass here is weaker evidence than a first look; a pass only makes the features a candidate for a pre-registered 2027 test. v2 does not change.

## Method

Base: the v2 M5 formula y ~ d12 + d3 + dpen + drd + dder, rebuilt as matchup_model.R builds it, in its weekly walk-forward (refit each Monday on every earlier game, predict that week).
Primary test, the only one that can keep anything: base plus all 26 travel columns (home and away separately) in a ridge logistic (glmnet 5.1, alpha 0, base terms unpenalised, standardize TRUE), lambda.min by 10-fold cross-validation on the earlier games only, folds assigned by calendar week, set.seed(20261004) before each fold draw, refit in the same weekly walk.
Paired gain = base log loss minus variant log loss per game (positive = the variant is better), pooled over 2017-2022, with a 95% interval from 1000 cluster-bootstrap draws of home team-seasons (seed 20261004).
Keep rule: the primary interval must sit above zero.

## Parity

- Rebuilt base vs saved v2 M5_plus_defense: 13045 of 13045 games matched, max absolute difference 6.1e-16 (tolerance 1e-9).
- M3 plus matchup_model.R's two rest terms (drest, dmoved, built by team across seasons) vs saved M4_plus_rest: max absolute difference 6.1e-16.
- The five old rest terms rebuilt here with context_features.R's definitions equal context.rds on all 22762 games (max difference 0.0e+00); M3 plus those five terms gives -0.365 [-0.668, -0.090] x 1000 against M3, the published context-ablation figure is -0.365 [-0.668, -0.090].
- (For reference, M3 vs saved M3_plus_team: max difference 6.1e-16.)
- Deviation: the registration asks the old five rest terms to reproduce M4_plus_rest, but M4_plus_rest holds only two of them (drest, dmoved), built across seasons. The check is therefore split: M4 is reproduced with its own two terms, and the five terms are reproduced against context.rds and the published five-term result. The script stops if any of these fails.

## Features

Per team, from that season's earlier games (ordered by date, then gid) plus the game's own site and start time. Home and away columns enter separately.

| family | columns (each _h and _a) | definition |
| --- | --- | --- |
| rest | rest | Days since the previous game, capped at 3; 3 at the season opener, 0 in a doubleheader nightcap. |
| distance | mi_prev, mi7 | Great-circle miles from the previous game's site (0 at the opener and in a nightcap), in thousands, capped at 3; and miles summed over the legs into today's game and every earlier game dated in the previous 7 days, in thousands, capped at 6. |
| circadian | lag_east, lag_west | Remaining circadian lag in hours. Each game day the previous lag shrinks 1 hour per day elapsed toward zero, then the time-zone change from the previous game's site is added (48-site UTC table). Positive = travelled east (body clock behind local time), split into east = max(lag, 0) and west = max(-lag, 0). Zero at each season opener. |
| start_clock | early, late | Body-clock start hour = local start hour minus the remaining lag (an eastward-lagged team feels the game earlier). early = hours before 1 pm, late = hours after 10 pm, both on the body clock. |
| load | g7, streak | Earlier games dated in the previous 7 days (a nightcap counts game 1); consecutive calendar days with a game ending the day before. |
| dgan | dgan | Day game after a night game the previous day (as context_features.R). |
| dh_prev | dhprev | Played a doubleheader the previous day. |
| stand | stand | Games into the current home stand (home team) or road trip (away team), counting today, capped at 10, by Retrosheet's home designation. |
| coors | coors | Played at Coors Field (DEN02) in the previous 3 days and not there today. |

Start times: Retrosheet's starttime, local clock, parsed on 50382 team-games with 0 fallbacks (1:05 pm day, 7:05 pm night). This field records actual first pitch, not the schedule: 12 games began at or after 10 pm local, after delays. No schedule time exists locally for 2020-2022, so actual first pitch stands in for the scheduled start (a deviation from the registration's wording).
Time-zone changes are wrapped to at most 12 hours, so Tokyo to Seattle counts as 8 hours east, not 16 west; inside 2017-2022 this touches only the 2019 Tokyo series (Seattle and Oakland). The old context terms keep the raw difference.
Doubleheader ordering: 0 same-day team pairs where gid order and Retrosheet game number disagree.
Sign check on a known trip: LAN 2017-06-11 at LOS03 (UTC-7, 1 day gap) lag 0.0, start 13.17 local / 13.17 body; LAN 2017-06-13 at CLE08 (UTC-4, 2 day gap) lag 3.0, start 19.18 local / 16.18 body; LAN 2017-06-14 at CLE08 (UTC-4, 1 day gap) lag 2.0, start 20.00 local / 18.00 body; LAN 2017-06-15 at CLE08 (UTC-4, 1 day gap) lag 1.0, start 12.18 local / 11.18 body.

Feature summary over 2017-2022 scored games (home and away pooled):

| feature | mean | share nonzero | max |
| --- | --- | --- | --- |
| rest | 1.135 | 0.979 | 3.000 |
| mi_prev | 0.197 | 0.234 | 3.000 |
| mi7 | 1.410 | 0.940 | 6.000 |
| lag_east | 0.141 | 0.094 | 8.000 |
| lag_west | 0.139 | 0.094 | 3.000 |
| early | 0.038 | 0.054 | 7.833 |
| late | 0.001 | 0.007 | 1.750 |
| g7 | 6.013 | 0.993 | 10.000 |
| streak | 4.531 | 0.850 | 23.000 |
| dgan | 0.237 | 0.237 | 1.000 |
| dhprev | 0.019 | 0.019 | 1.000 |
| stand | 4.041 | 1.000 | 10.000 |
| coors | 0.019 | 0.019 | 1.000 |

## Coordinates

48 sites (every site in the UTC table and every Retrosheet site 2015-2025): 41 from MLB StatsAPI venue records, 7 from Wikipedia where StatsAPI has none or misplaces the park. No Retrosheet park list exists under data/; park names were checked against StatsAPI's cached 2017-2019 schedule for the same games.
Checks (all pass, else the script stops): NYC20-LOS03 2,453; BOS07-NYC21 180; NYC20-NYC21 7; CHI11-CHI12 8; ARL02-ARL03 0; ATL02-ATL03 12; OAK01-SFO03 10; ANA01-LOS03 28; STP01-TAM02 17; STP01-DUN01 18; SAC01-SFO03 73 miles.
Longitude / 15 against each site's standard UTC offset: largest gap 0.69 hours (limit 1.5).
Fort Bragg (FTB01, one 2016 game) uses the post's centre, so its legs may be off by a few miles. One DET05 game appears at Oakland Coliseum in StatsAPI's schedule; the Retrosheet site is kept.

| site | park | city | lat | lon | source | StatsAPI 2017-2019 name (games) |
| --- | --- | --- | --- | --- | --- | --- |
| ANA01 | Angel Stadium | Anaheim CA | 33.8002 | -117.8824 | statsapi 1 | Angel Stadium (161); Angel Stadium of Anaheim (81) |
| ARL02 | Globe Life Park in Arlington (now Choctaw Stadium) | Arlington TX | 32.7513 | -97.0827 | statsapi 13 | Globe Life Park in Arlington (245) |
| ARL03 | Globe Life Field | Arlington TX | 32.7473 | -97.0818 | statsapi 5325 |  |
| ATL02 | Turner Field | Atlanta GA | 33.7353 | -84.3894 | wikipedia (statsapi 16 has no coordinates) |  |
| ATL03 | Truist Park (SunTrust Park) | Atlanta GA | 33.8907 | -84.4676 | statsapi 4705 | SunTrust Park (248) |
| BAL12 | Oriole Park at Camden Yards | Baltimore MD | 39.2838 | -76.6217 | statsapi 2 | Oriole Park at Camden Yards (252) |
| BIR01 | Rickwood Field | Birmingham AL | 33.5023 | -86.8564 | statsapi 3949 |  |
| BOS07 | Fenway Park | Boston MA | 42.3465 | -71.0974 | statsapi 3 | Fenway Park (249) |
| BST01 | Bristol Motor Speedway | Bristol TN | 36.5156 | -82.2569 | wikipedia (statsapi 6130 gives 31.5156 -82.5269, in south Georgia) |  |
| BUF05 | Sahlen Field | Buffalo NY | 42.8808 | -78.8740 | statsapi 2756 |  |
| CHI11 | Wrigley Field | Chicago IL | 41.9482 | -87.6555 | statsapi 17 | Wrigley Field (251) |
| CHI12 | Guaranteed Rate Field (Rate Field) | Chicago IL | 41.8300 | -87.6342 | statsapi 4 | Guaranteed Rate Field (253) |
| CIN09 | Great American Ball Park | Cincinnati OH | 39.0974 | -84.5066 | statsapi 2602 | Great American Ball Park (244) |
| CLE08 | Progressive Field | Cleveland OH | 41.4959 | -81.6853 | statsapi 5 | Progressive Field (249) |
| DEN02 | Coors Field | Denver CO | 39.7560 | -104.9941 | statsapi 19 | Coors Field (246) |
| DET05 | Comerica Park | Detroit MI | 42.3391 | -83.0487 | statsapi 2394 | Comerica Park (254); Oakland Coliseum (1) |
| DUN01 | TD Ballpark | Dunedin FL | 28.0036 | -82.7864 | wikipedia (statsapi 2536 gives 27.9746 -82.7913, about 2 mi south in Clearwater) |  |
| DYE01 | Field of Dreams | Dyersville IA | 42.4982 | -91.0565 | statsapi 5445 |  |
| FTB01 | Fort Bragg Field | Fort Bragg NC | 35.1392 | -78.9992 | wikipedia, Fort Bragg post centre (the field's own point not found; statsapi 5010 has none) |  |
| HOU03 | Minute Maid Park (Daikin Park) | Houston TX | 29.7570 | -95.3555 | statsapi 2392 | Minute Maid Park (241) |
| KAN06 | Kauffman Stadium | Kansas City MO | 39.0516 | -94.4805 | statsapi 7 | Kauffman Stadium (248) |
| LON01 | London Stadium | London UK | 51.5386 | -0.0164 | wikipedia (statsapi 5381 gives the city centre 51.5085 -0.1257) | London Stadium (2) |
| LOS03 | Dodger Stadium | Los Angeles CA | 34.0737 | -118.2405 | statsapi 22 | Dodger Stadium (243) |
| MEX02 | Estadio Alfredo Harp Helu | Mexico City MX | 19.4040 | -99.0855 | wikipedia (statsapi 5340 has no coordinates) |  |
| MIA02 | loanDepot park (Marlins Park) | Miami FL | 25.7780 | -80.2195 | statsapi 4169 | Marlins Park (240) |
| MIL06 | American Family Field (Miller Park) | Milwaukee WI | 43.0284 | -87.9710 | statsapi 32 | Miller Park (243) |
| MIN04 | Target Field | Minneapolis MN | 44.9818 | -93.2779 | statsapi 3312 | Target Field (250) |
| MNT01 | Estadio de Beisbol Monterrey (now Walmart Park) | Monterrey MX | 25.7185 | -100.3157 | wikipedia (not in the statsapi venue list) | Estadio de Beisbol Monterrey (7) |
| NYC20 | Citi Field | New York NY (Queens) | 40.7575 | -73.8456 | statsapi 3289 | Citi Field (252) |
| NYC21 | Yankee Stadium | New York NY (Bronx) | 40.8292 | -73.9265 | statsapi 3313 | Yankee Stadium (254) |
| OAK01 | Oakland Coliseum | Oakland CA | 37.7515 | -122.2007 | statsapi 10 | Oakland Coliseum (242) |
| OMA01 | TD Ameritrade Park | Omaha NE | 41.2586 | -95.9378 | statsapi 5365 | TD Ameritrade Park (1) |
| PHI13 | Citizens Bank Park | Philadelphia PA | 39.9054 | -75.1672 | statsapi 2681 | Citizens Bank Park (247) |
| PHO01 | Chase Field | Phoenix AZ | 33.4453 | -112.0667 | statsapi 15 | Chase Field (243) |
| PIT08 | PNC Park | Pittsburgh PA | 40.4469 | -80.0058 | statsapi 31 | PNC Park (242) |
| SAC01 | Sutter Health Park | West Sacramento CA | 38.5799 | -121.5125 | statsapi 2529 |  |
| SAN02 | Petco Park | San Diego CA | 32.7079 | -117.1573 | statsapi 2680 | Petco Park (241) |
| SEA03 | T-Mobile Park (Safeco Field) | Seattle WA | 47.5913 | -122.3325 | statsapi 680 | Safeco Field (162); T-Mobile Park (81) |
| SEO01 | Gocheok Sky Dome | Seoul KR | 37.4982 | 126.8670 | statsapi 5150 |  |
| SFO03 | Oracle Park (AT&T Park) | San Francisco CA | 37.7784 | -122.3894 | statsapi 2395 | AT&T Park (163); Oracle Park (81) |
| SJU01 | Hiram Bithorn Stadium | San Juan PR | 18.4167 | -66.0728 | statsapi 2535 | Hiram Bithorn Stadium (2) |
| STL10 | Busch Stadium | St. Louis MO | 38.6226 | -90.1929 | statsapi 2889 | Busch Stadium (251) |
| STP01 | Tropicana Field | St. Petersburg FL | 27.7678 | -82.6525 | statsapi 12 | Tropicana Field (243) |
| TAM02 | George M. Steinbrenner Field | Tampa FL | 27.9800 | -82.5070 | statsapi 2523 |  |
| TOK01 | Tokyo Dome | Tokyo JP | 35.7056 | 139.7519 | statsapi 2397 | Tokyo Dome (2) |
| TOR02 | Rogers Centre | Toronto ON | 43.6416 | -79.3892 | statsapi 14 | Rogers Centre (244) |
| WAS11 | Nationals Park | Washington DC | 38.8729 | -77.0075 | statsapi 3309 | Nationals Park (258) |
| WIL02 | Bowman Field (BB&T Ballpark, now Journey Bank Ballpark) | Williamsport PA | 41.2420 | -77.0475 | statsapi 2735 | BB&T Ballpark (3) |

## Primary result

Ridge (base plus all travel features) minus base, 2017-2022 pooled over 13045 games: -0.399 [-1.060, 0.132] x 1000.
By season (x 1000): 2017 -0.798; 2018 -0.144; 2019 -1.144; 2020 0.463; 2021 -0.125; 2022 -0.100.
lambda.min over 146 weekly fits: median 0.649, range 0.0995 to 15.7; at the largest lambda on the path (travel terms shrunk to almost nothing) in 1.

Verdict: the interval does not sit above zero. Nothing is kept; v2 does not change.

## Descriptive only (never a keep)

Paired gain against the same base, x 1000, 2017-2022 pooled with the same bootstrap, then by season.

| variant | 2017-2022 [95% CI] | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| primary_ridge | -0.399 [-1.060, 0.132] | -0.798 | -0.144 | -1.144 | 0.463 | -0.125 | -0.100 |
| glm_all | -3.059 [-5.188, -1.258] | -5.123 | -1.977 | -3.998 | -1.895 | -2.476 | -2.151 |
| glm_rest | -0.096 [-0.337, 0.147] | -0.148 | 0.033 | -0.077 | -0.982 | 0.041 | -0.001 |
| glm_distance | -0.421 [-0.760, -0.044] | -1.110 | 0.122 | 0.121 | -1.519 | -0.548 | -0.283 |
| glm_circadian | -0.200 [-0.649, 0.222] | -0.940 | -0.393 | 0.247 | 0.459 | 0.170 | -0.326 |
| glm_start_clock | -0.795 [-1.918, -0.067] | -0.648 | -0.446 | -2.128 | 0.034 | -0.881 | -0.181 |
| glm_load | -0.254 [-0.545, 0.033] | -0.729 | -0.020 | -0.512 | 0.475 | -0.305 | 0.028 |
| glm_dgan | 0.084 [-0.382, 0.574] | 0.302 | 0.445 | 0.208 | -1.428 | 0.055 | -0.033 |
| glm_dh_prev | -0.160 [-0.575, 0.220] | -0.250 | 0.155 | -0.445 | 0.815 | -0.409 | -0.210 |
| glm_stand | -0.097 [-0.297, 0.102] | -0.252 | 0.093 | -0.067 | -0.804 | -0.058 | 0.061 |
| glm_coors | -0.106 [-0.506, 0.278] | -0.483 | -0.174 | 0.329 | 0.582 | -0.128 | -0.326 |

primary_ridge repeats the primary row for comparison. glm_all is every travel column in an unpenalised glm; glm_<family> is the base plus that family alone.

Market check, 2021-2022: no-vig close (corrected odds join, as close_timing.R) recalibrated alone, y ~ logit(close), against the close logit (unpenalised) plus every travel column in a ridge with the primary's recipe; cross-fit by season (fit on one season, score the other). 4253 joined games, 0 in Sept-Oct 2021 and 15 on the 12 flagged late-close dates removed, 4238 scored.
Close alone minus close plus travel: 0.051 [0.007, 0.099] x 1000 (positive = travel adds to the close). By season: 2021: 1911 games, log loss 0.6707 alone vs 0.6706 with travel; 2022: 2327 games, log loss 0.6678 alone vs 0.6678 with travel.
The estimator for this check (ridge with the close unpenalised, compared with a close-only logistic) is this script's reading of the registration, which names the inputs but not the model.

## glm coefficient signs (every travel column plus the base, fit on every 2016-2022 game; descriptive)

| term | coef | z | sign |
| --- | --- | --- | --- |
| rest_h | -0.0235 | -0.35 | - |
| rest_a | 0.0054 | 0.08 | + |
| mi_prev_h | 0.0109 | 0.16 | + |
| mi_prev_a | -0.0123 | -0.23 | - |
| mi7_h | -0.0247 | -1.15 | - |
| mi7_a | -0.0168 | -0.82 | - |
| lag_east_h | -0.0171 | -0.33 | - |
| lag_east_a | -0.0038 | -0.09 | - |
| lag_west_h | 0.0452 | 0.83 | + |
| lag_west_a | 0.0911 | 2.14 | + |
| early_h | 0.1380 | 1.27 | + |
| early_a | -0.1906 | -1.82 | - |
| late_h | -0.5470 | -0.58 | - |
| late_a | -0.3952 | -0.51 | - |
| g7_h | 0.0111 | 0.42 | + |
| g7_a | 0.0018 | 0.07 | + |
| streak_h | 0.0029 | 0.51 | + |
| streak_a | 0.0006 | 0.11 | + |
| dgan_h | 0.4784 | 1.85 | + |
| dgan_a | -0.3902 | -1.51 | - |
| dhprev_h | 0.1728 | 0.83 | + |
| dhprev_a | 0.0138 | 0.07 | + |
| stand_h | -0.0029 | -0.31 | - |
| stand_a | 0.0004 | 0.05 | + |
| coors_h | -0.1688 | -1.28 | - |
| coors_a | 0.2062 | 1.85 | + |

Venue coordinates: MLB StatsAPI (copyright MLB Advanced Media, L.P., private research use) and Wikipedia.
The information used here was obtained free of charge from and is copyrighted by Retrosheet.
