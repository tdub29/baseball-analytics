-- mart_hitter_season — one row per hitter from the 6-4-3 overall hitting export.
-- The 6-4-3 hitting file is already per-hitter (Pitch Type = 'All'), so this is a
-- typed, conformed pass-through mart that maps to the stats_hitting target shape.
-- (TrackMan-derived xSLG / decision-value stay in Python; not recomputed in dbt.)

with hitting as (

    select * from {{ ref('stg_643__hitting') }}

),

deduped as (

    -- names are not globally unique in the national 6-4-3 set; the identity grain
    -- is (player, team). A handful of exact (player, team) duplicate export rows
    -- exist, so keep the largest-sample row per (player, team).
    select *
    from (
        select
            *,
            row_number() over (
                partition by player, team
                order by coalesce(pitches, 0) desc
            ) as _rn
        from hitting
    ) ranked
    where _rn = 1

)

select
    {{ dbt_utils.generate_surrogate_key(['player', 'team']) }}               as hitter_sk,
    player                                                                   as hitter_name,
    player_key,
    team,

    pitches,
    bbe,
    barrels,

    avg_ev,
    ev90,
    max_ev,
    hardhit_pct,
    la,
    swspot_pct,
    barrel_pct,

    ba,
    xba,
    woba,
    xwoba,

    gb_pct,
    fb_pct,
    ld_pct,
    swing_pct,
    zswing_pct,
    zcontact_pct,
    chase_pct,
    whiff_pct,
    sd_plus
from deduped
