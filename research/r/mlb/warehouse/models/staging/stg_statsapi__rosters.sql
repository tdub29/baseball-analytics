-- One row per (player, team, season) on a full-season roster. source_file is <team_id>_<season>.
select
    person_id,
    team_id,
    cast(split_part(source_file, '_', 2) as integer)         as season,
    pos
from {{ source('statsapi', 'roster') }}
