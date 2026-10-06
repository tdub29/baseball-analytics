# Matchup model: shrink-constant tuning-v4-base2

Generated 2026-10-06. Features: `data/mlb/matchup/features-v4-base2.rds` and 11 grid files. Score: walk-forward log loss of M5 on 2017-2019 (7288 games); nothing later is read.

Multipliers scale the reliability study's random-effects k (`k_cfg()` in matchup.R): `m_pit` the pitchers' batted-ball expected outcomes
(starters 157 / 210 / 129 / 106 / 121 for single / double / triple / HR / out in play, relievers 89 / 152 / 97 / 79 / 69), `m_bat` the
hitters' singles 195, triples 534 and outs in play 75, `m_rel_bb` the relievers' walks 134.

Base file (constants as built): 0.67033.
Best: m_pit 8, m_bat 8, m_rel_bb 1, log loss 0.67028; base minus best 0.00005 [-0.00012, 0.00022] (team-season cluster bootstrap).
Its constants: hitters single 1560, triple 4272, out_ip 600; starters single 1256, double 1680, triple 1032, hr 848, out_ip 968; relievers ubb 134, single 712, double 1216, triple 776, hr 632, out_ip 552.

| m_pit | m_bat | m_rel_bb | log loss 2017-2019 | base minus this |
| --- | --- | --- | --- | --- |
| 8 | 8 | 1 | 0.67028 | 0.00005 |
| 16 | 8 | 1 | 0.67028 | 0.00005 |
| 8 | 16 | 1 | 0.67029 | 0.00003 |
| 16 | 16 | 1 | 0.67030 | 0.00003 |
| 8 | 4 | 1 | 0.67030 | 0.00003 |
| 16 | 4 | 1 | 0.67030 | 0.00003 |
| 32 | 8 | 1 | 0.67031 | 0.00002 |
| 32 | 16 | 1 | 0.67033 | 0.00000 |
| 32 | 4 | 1 | 0.67033 | -0.00000 |
| 4 | 8 | 1 | 0.67033 | -0.00001 |
| 4 | 16 | 1 | 0.67035 | -0.00002 |

The information used here was obtained free of charge from and is copyrighted by Retrosheet.
