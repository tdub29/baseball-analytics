-- One row per Retrosheet event, keyed (gid, pn). `play_date` is the day the event was played, which
-- for a suspended game is not the game's start date. The outcome flags are 0/1 integers.
select
    gid,
    cast(pn as integer)                as pn,
    strptime(date, '%Y%m%d')::date     as play_date,
    gametype                           as game_type,
    cast(inning as integer)            as inning,
    cast(top_bot as integer)           as top_bot,
    batteam                            as bat_team,
    pitteam                            as pit_team,
    batter,
    pitcher,
    bathand                            as bat_hand,
    pithand                            as pit_hand,
    event,
    {% for c in ['outs_pre', 'outs_post', 'balls', 'strikes', 'pa', 'ab', 'single', 'double', 'triple',
                 'hr', 'walk', 'iw', 'hbp', 'k', 'sf', 'sh', 'roe', 'fc', 'bip', 'bunt', 'ground', 'fly',
                 'line', 'runs', 'rbi', 'er', 'score_v', 'score_h'] -%}
    cast("{{ c }}" as integer)         as "{{ c }}"{{ ',' if not loop.last }}
    {% endfor %}
from {{ source('retrosheet', 'plays') }}
