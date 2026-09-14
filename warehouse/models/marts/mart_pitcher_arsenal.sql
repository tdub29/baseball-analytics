-- mart_pitcher_arsenal — the dbt replacement for src/portal/rollup.rollup_arsenal.
--
-- Collapses the per-(pitcher, pitch-type) 6-4-3 arsenal (stg_643__pitch_arsenal)
-- into ONE wide row per pitcher, exactly the way rollup.py builds a stats_pitching
-- line:
--
--   * overall quality numbers are PITCHES-WEIGHTED across the pitcher's mix
--     (a 70%-fastball guy is graded mostly on his fastball) — this is the
--     _weighted_mean(value, pitches) call, sum(v*w)/sum(w), round to 1 dp,
--     ignoring rows where value OR weight is null.
--   * per-pitch Stuff+ fans out into the wide {code}_stuff columns.
--   * fastball shape (velo/iVB/HB) comes from the code='fb' rows (pitches-weighted).
--   * pitches = sum of pitches across types.
--
-- A reusable weighted-mean is expressed inline as
--     round(sum(v*w) filter (where v is not null and w is not null)
--           / nullif(sum(w) filter (where v is not null and w is not null), 0), 1)
-- which reproduces _weighted_mean's null-skip + zero-weight-guard semantics.

with arsenal as (

    select * from {{ ref('stg_643__pitch_arsenal') }}

),

rolled as (

    select
        player,
        team,
        -- recompute player_key from the (single) name within the group
        max(player_key)                                                      as player_key,
        max(throws)                                                          as throws,

        -- ── pitches-weighted overall numbers ────────────────────────────────
        {{ weighted_mean('stuff_plus', 'pitches') }}                         as stuff_plus,   -- t2_stuff
        {{ weighted_mean('xrv_plus', 'pitches') }}                           as perceived_value,
        {{ weighted_mean('hardhit_pct', 'pitches') }}                        as hardhit_pct,
        {{ weighted_mean('chase_pct', 'pitches') }}                          as chase_pct,
        {{ weighted_mean('location_plus', 'pitches') }}                      as location_plus,

        -- ── per-pitch Stuff+ fanned into wide columns ───────────────────────
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'fb'") }}          as fb_stuff,
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'si'") }}          as si_stuff,
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'sl'") }}          as sl_stuff,
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'cb'") }}          as cb_stuff,
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'ch'") }}          as ch_stuff,
        {{ weighted_mean('stuff_plus', 'pitches', "code = 'ct'") }}          as ct_stuff,

        -- ── fastball shape from the fb rows (pitches-weighted) ───────────────
        {{ weighted_mean('velo', 'pitches', "code = 'fb'") }}                as fb_velo,
        {{ weighted_mean('ivb', 'pitches', "code = 'fb'") }}                 as fb_ivb,
        {{ weighted_mean('hb', 'pitches', "code = 'fb'") }}                  as fb_hb,

        -- ── total pitches across types ──────────────────────────────────────
        nullif(sum(coalesce(pitches, 0)), 0)                                 as pitches,
        count(*)                                                             as pitch_type_rows

    from arsenal
    -- group on (player, team): names are NOT globally unique in the national
    -- 6-4-3 set, so (player, team) is the identity grain here. The Python pipeline
    -- groups by the RESOLVED player_id; absent the resolver, (player, team) is the
    -- faithful analogue. Exact-duplicate source rows collapse into the group.
    group by player, team

)

select
    {{ dbt_utils.generate_surrogate_key(['player', 'team']) }}               as pitcher_sk,
    player                                                                   as pitcher_name,
    player_key,
    team,
    throws,
    stuff_plus,
    perceived_value,
    location_plus,
    hardhit_pct,
    chase_pct,
    fb_stuff,
    si_stuff,
    sl_stuff,
    cb_stuff,
    ch_stuff,
    ct_stuff,
    fb_velo,
    fb_ivb,
    fb_hb,
    pitches,
    pitch_type_rows
from rolled
