-- One row per (player, game, team, stat group). source_file is <season>_<group>_<page>. Team is part
-- of the key: Danny Jansen batted for both sides of BOS-TOR game_pk 746942, suspended 2024-06-26 and
-- completed after his trade.
select
    person_id,
    game_pk,
    team_id,
    split_part(source_file, '_', 2)                          as stat_group,
    cast(split_part(source_file, '_', 1) as integer)         as season,
    "Date"                                                   as game_date,
    is_home,
    * exclude (person_id, game_pk, team_id, "Date", is_home, source_file)
from {{ source('statsapi', 'player_log') }}
