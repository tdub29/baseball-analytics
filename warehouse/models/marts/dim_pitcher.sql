-- One row per pitcher seen in the TrackMan feed (USD's tracked pitchers).
-- Surrogate key on the normalized name key so it joins to the 6-4-3 arsenal mart.

with pitches as (

    select * from {{ ref('int_pitches__enriched') }}

),

agg as (

    select
        pitcher                                                      as pitcher_name,
        {{ dbt_utils.generate_surrogate_key(['pitcher']) }}          as pitcher_sk,
        -- name_key here is recomputed off the TrackMan name so it lines up with
        -- the 6-4-3 player_key (same macro both sides).
        max(pitcher_throws)                                          as throws,
        max(pitcher_team)                                            as team,
        count(*)                                                     as tracked_pitches,
        count(distinct game_id)                                      as tracked_games,
        min(game_date)                                               as first_tracked_date,
        max(game_date)                                               as last_tracked_date
    from pitches
    group by pitcher

)

select
    pitcher_sk,
    pitcher_name,
    {{ name_key('pitcher_name') }}                                   as player_key,
    throws,
    team,
    tracked_pitches,
    tracked_games,
    first_tracked_date,
    last_tracked_date
from agg
