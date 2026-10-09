-- One row per Retrosheet game. `start_date` is Retrosheet's game date (the day it started).
-- `suspend` holds the completion date of a suspended game, so `completion_date` is the first day
-- the final score was known: 35 games in 2015-2025 finish on a later day (leakage_tamper.R).
select
    gid,
    cast(season as integer)                              as season,
    gametype                                             as game_type,
    strptime(date, '%Y%m%d')::date                       as start_date,
    coalesce(strptime(suspend, '%Y%m%d')::date,
             strptime(date, '%Y%m%d')::date)             as completion_date,
    suspend is not null                                  as is_suspended,
    cast(number as integer)                              as game_number,
    visteam                                              as away_team,
    hometeam                                             as home_team,
    site,
    daynight                                             as day_night,
    usedh = 'true'                                       as used_dh,
    try_cast(temp as integer)                            as temp_f,
    winddir                                              as wind_dir,
    try_cast(windspeed as integer)                       as wind_mph,
    umphome                                              as ump_home,
    wp                                                   as winning_pitcher,
    lp                                                   as losing_pitcher,
    cast(vruns as integer)                               as away_runs,
    cast(hruns as integer)                               as home_runs
from {{ source('retrosheet', 'gameinfo') }}
