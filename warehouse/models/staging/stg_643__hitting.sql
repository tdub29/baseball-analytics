-- 6-4-3 per-hitter (overall) export -> typed hitting rows.
-- One row per hitter. Percent cells via clean_numeric (strips '%', mirrors
-- util.to_float); maps to the stats_hitting target shape in db/schema.sql.

with source as (

    select * from {{ source('six_four_three', 'hitting') }}

),

cleaned as (

    select
        nullif(trim("Player"), '')                                   as player,
        {{ name_key('"Player"') }}                                   as player_key,
        nullif(trim(split_part(cast("Team" as varchar), '|', 1)), '') as team,

        try_cast("Pitches" as integer)                               as pitches,
        try_cast("BBE" as integer)                                   as bbe,
        try_cast("Barrels" as integer)                               as barrels,

        {{ clean_numeric('"EV"') }}                                  as avg_ev,
        {{ clean_numeric('"EV 90"') }}                               as ev90,
        {{ clean_numeric('"Max EV"') }}                              as max_ev,
        {{ clean_numeric('"HH%"') }}                                 as hardhit_pct,
        {{ clean_numeric('"LA"') }}                                  as la,
        {{ clean_numeric('"HH LA"') }}                               as hh_la,
        {{ clean_numeric('"SwSpot%"') }}                             as swspot_pct,
        {{ clean_numeric('"Barrel%"') }}                             as barrel_pct,
        {{ clean_numeric('"BA"') }}                                  as ba,
        {{ clean_numeric('"xBA"') }}                                 as xba,
        {{ clean_numeric('"wOBA"') }}                                as woba,
        {{ clean_numeric('"xwOBA"') }}                               as xwoba,
        {{ clean_numeric('"GB%"') }}                                 as gb_pct,
        {{ clean_numeric('"FB%"') }}                                 as fb_pct,
        {{ clean_numeric('"LD%"') }}                                 as ld_pct,
        {{ clean_numeric('"Swing%"') }}                              as swing_pct,
        {{ clean_numeric('"Z-Swing%"') }}                            as zswing_pct,
        {{ clean_numeric('"Z-Contact%"') }}                          as zcontact_pct,
        {{ clean_numeric('"Chase%"') }}                              as chase_pct,
        {{ clean_numeric('"Whiff%"') }}                              as whiff_pct,
        {{ clean_numeric('"SD+"') }}                                 as sd_plus

    from source
    where nullif(trim("Player"), '') is not null

)

select * from cleaned
