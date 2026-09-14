-- One row per tracked game (from the TrackMan feed).

with pitches as (

    select * from {{ ref('int_pitches__enriched') }}
    where game_id is not null

),

agg as (

    select
        game_id,
        max(game_date)                                              as game_date,
        max(level)                                                  as level,
        count(*)                                                    as pitch_count,
        count(distinct pitcher)                                     as pitchers,
        count(distinct batter)                                      as batters
    from pitches
    group by game_id

)

select
    {{ dbt_utils.generate_surrogate_key(['game_id']) }}             as game_sk,
    game_id,
    game_date,
    {{ dbt_date.day_name('game_date', short=false) }}              as game_day_of_week,
    level,
    pitch_count,
    pitchers,
    batters
from agg
