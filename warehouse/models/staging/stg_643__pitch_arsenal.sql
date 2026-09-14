-- 6-4-3 per-(pitcher, pitch-type) export -> typed arsenal rows.
-- This is the dbt analogue of src/portal/arsenal.import_643_arsenal: strip the
-- Team "Name|logo_url" decoration, strip units off the dimensional cells
-- (iVB '0.3"', VAA '-9.1°') via clean_numeric (mirrors arsenal._dim), strip '%'
-- off the percent cells (mirrors util.to_float), and map the pitch-type label to
-- the normalized code via pitch_code (mirrors arsenal._CODE).
--
-- It does NOT recompute Stuff+/Location+/xRV+ — those are 6-4-3's model outputs
-- and are consumed as-is.

with source as (

    select * from {{ source('six_four_three', 'pitching') }}

),

cleaned as (

    select
        -- ── identity ─────────────────────────────────────────────────────────
        nullif(trim("Player"), '')                                   as player,
        {{ name_key('"Player"') }}                                   as player_key,
        -- Team is decorated "Name|logo_url"; keep the name half (cf. arsenal.py)
        nullif(trim(split_part(cast("Team" as varchar), '|', 1)), '') as team,
        nullif(trim("Throws"), '')                                   as throws,
        nullif(trim("Pitch Type"), '')                               as pitch_type,
        {{ pitch_code('"Pitch Type"') }}                             as code,

        -- ── volume ───────────────────────────────────────────────────────────
        try_cast("Pitches" as integer)                               as pitches,
        try_cast("BBE" as integer)                                   as bbe,
        try_cast("Barrels" as integer)                               as barrels,

        -- ── outcomes allowed (percent cells -> clean_numeric strips '%') ──────
        {{ clean_numeric('"EV"') }}                                  as ev,
        {{ clean_numeric('"HH%"') }}                                 as hardhit_pct,
        {{ clean_numeric('"Barrel%"') }}                             as barrel_pct,
        {{ clean_numeric('"BA"') }}                                  as ba,
        {{ clean_numeric('"xBA"') }}                                 as xba,
        {{ clean_numeric('"wOBA"') }}                                as woba,
        {{ clean_numeric('"xwOBA"') }}                               as xwoba,
        {{ clean_numeric('"Swing%"') }}                              as swing_pct,
        {{ clean_numeric('"Z-Contact%"') }}                          as zcontact_pct,
        {{ clean_numeric('"Chase%"') }}                              as chase_pct,
        {{ clean_numeric('"Whiff%"') }}                              as whiff_pct,

        -- ── shape (dimensional cells with units -> clean_numeric strips them) ─
        {{ clean_numeric('"Velo"') }}                                as velo,
        {{ clean_numeric('"Velo 90"') }}                             as velo90,
        {{ clean_numeric('"Max Velo"') }}                            as max_velo,
        {{ clean_numeric('"Spin Rate"') }}                           as spin,
        {{ clean_numeric('"iVB"') }}                                 as ivb,
        {{ clean_numeric('"HB"') }}                                  as hb,
        {{ clean_numeric('"VAA"') }}                                 as vaa,
        {{ clean_numeric('"HAA"') }}                                 as haa,
        {{ clean_numeric('"RelHeight"') }}                           as rel_height,
        {{ clean_numeric('"RelSide"') }}                             as rel_side,
        {{ clean_numeric('"Extension"') }}                           as extension,

        -- ── 6-4-3 "+" quality family (model outputs; consumed as-is) ──────────
        {{ clean_numeric('"Stuff+"') }}                              as stuff_plus,
        {{ clean_numeric('"Location+"') }}                           as location_plus,
        {{ clean_numeric('"xRV+"') }}                                as xrv_plus,
        {{ clean_numeric('"Anomaly+"') }}                            as anomaly_plus,
        {{ clean_numeric('"Tunnel+"') }}                             as tunnel_plus,
        {{ clean_numeric('"PredMovDiff+"') }}                        as predmovdiff_plus

    from source
    where nullif(trim("Player"), '') is not null
      and nullif(trim("Pitch Type"), '') is not null

)

select * from cleaned
