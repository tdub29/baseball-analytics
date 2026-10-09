-- One row per final regular-season game (schedule hydrated with lineups), 2015-2026. `game_date` is
-- StatsAPI's official date, which for a suspended game is the day it started.
select
    game_pk,
    "Date"                                   as game_date,
    year("Date")                             as season,
    venue_id,
    home_id,
    away_id,
    home_score,
    away_score,
    home_sp,
    away_sp,
    {% for side in ['home', 'away'] %}{% for i in range(1, 10) -%}
    {{ side }}_bat{{ i }},
    {% endfor %}{% endfor -%}
    source_file
from {{ source('statsapi', 'lineups') }}
