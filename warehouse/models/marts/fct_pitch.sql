-- fct_pitch — the pitch-level fact. Grain = one row per pitch (pitch_uid).
--
-- INCREMENTAL: new pitches appended on each run (a thrown pitch is immutable, so
-- new game days only add rows). unique_key='pitch_uid' makes re-runs idempotent —
-- the same way the Python pipeline uses INSERT OR REPLACE keyed by PitchUID. On an
-- incremental run we only scan rows newer than the latest game_date already loaded.

{{
    config(
        materialized='incremental',
        unique_key='pitch_uid',
        on_schema_change='append_new_columns'
    )
}}

with pitches as (

    select * from {{ ref('int_pitches__enriched') }}

    {% if is_incremental() %}
    -- only pull pitches at/after the most recent loaded game date (small overlap
    -- window is fine — unique_key dedupes). game_date can be null, so coalesce.
    where coalesce(game_date, date '1900-01-01')
          >= (select coalesce(max(game_date), date '1900-01-01') from {{ this }})
    {% endif %}

),

joined as (

    select
        p.pitch_uid,
        {{ dbt_utils.generate_surrogate_key(['p.pitcher']) }}        as pitcher_sk,
        {{ dbt_utils.generate_surrogate_key(['p.game_id']) }}        as game_sk,
        {{ dbt_utils.generate_surrogate_key(['p.pitch_code']) }}     as pitch_type_sk,

        p.game_id,
        p.game_date,
        p.inning,
        p.inning_half,
        p.balls,
        p.strikes,

        p.pitcher,
        p.pitcher_throws,
        p.pitcher_team,
        p.batter,
        p.batter_side,

        p.tagged_pitch_type,
        p.auto_pitch_type,
        p.pitch_code,
        p.pitch_call,
        p.kor_bb,
        p.play_result,

        -- measured shape / location
        p.rel_speed,
        p.spin_rate,
        p.spin_axis,
        p.rel_height,
        p.rel_side,
        p.extension,
        p.induced_vert_break,
        p.horz_break,
        p.vert_appr_angle,
        p.horz_appr_angle,
        p.plate_loc_height,
        p.plate_loc_side,
        p.exit_speed,
        p.launch_angle,
        p.distance,

        -- engineered flags
        p.is_swing,
        p.is_whiff,
        p.is_strike,
        p.in_zone,
        p.is_contact,
        p.is_in_play,
        p.has_batted_ball,
        p.barrel_proxy,

        p.level,
        cast(current_timestamp as timestamp)                         as _loaded_at

    from pitches p

)

select * from joined
