-- One row per (team, game, stat group). source_file is <team_id>_<season>_<group>.
select
    team_id,
    game_pk,
    "Date"                                                   as game_date,
    cast(split_part(source_file, '_', 2) as integer)         as season,
    split_part(source_file, '_', 3)                          as stat_group,
    is_home,
    opp_id,
    * exclude (team_id, game_pk, "Date", is_home, opp_id, source_file)
from {{ source('statsapi', 'team_log') }}
