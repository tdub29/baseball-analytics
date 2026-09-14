-- Engineer per-pitch event flags from the raw TrackMan PitchCall + location.
-- Mirrors the flag logic in src/portal/trackman._pitch_flags (and the hitter-app
-- swing/contact semantics), expressed as deterministic SQL:
--
--   is_swing   : StrikeSwinging OR any foul OR in-play (incl. ExitSpeed > 0)
--   is_whiff   : PitchCall = StrikeSwinging
--   is_strike  : swing OR StrikeCalled
--   in_zone    : standard zone box — PlateLocHeight 1.5-3.5 & |PlateLocSide| <= 0.83
--   is_contact : swing AND NOT whiff
--   is_in_play : PitchCall = InPlay  (kept strict to the call, per spec; a separate
--                has_batted_ball flag captures the ExitSpeed>0 superset used by the
--                Python aggregator)
--   barrel_proxy: PROXY ONLY — ExitSpeed >= 98 & launch_angle in [26, 30]. Real
--                barrels need the full Statcast EV*LA boundary; this is a coarse
--                stand-in flagged as such.
--   pitch_code : normalized bucket via the pitch_code macro (prefers the tagged
--                type, falls back to the auto type).

with pitches as (

    select * from {{ ref('stg_trackman__pitches') }}

),

flagged as (

    select
        *,

        -- normalized event flags (coalesced to false so each is a clean boolean) -
        coalesce(lower(pitch_call) = 'strikeswinging', false)             as is_whiff,

        coalesce(
            lower(pitch_call) = 'strikeswinging'
            or lower(pitch_call) like '%foul%'
            or lower(pitch_call) = 'inplay'
            or coalesce(exit_speed, 0) > 0
        , false)                                                           as is_swing,

        coalesce(
            lower(pitch_call) = 'strikeswinging'
            or lower(pitch_call) like '%foul%'
            or lower(pitch_call) = 'inplay'
            or coalesce(exit_speed, 0) > 0
            or lower(pitch_call) = 'strikecalled'
        , false)                                                           as is_strike,

        coalesce(
            plate_loc_height between 1.5 and 3.5
            and abs(plate_loc_side) <= 0.83
        , false)                                                           as in_zone,

        -- strict to the call (spec); has_batted_ball is the ExitSpeed>0 superset
        coalesce(lower(pitch_call) = 'inplay', false)                     as is_in_play,
        (coalesce(exit_speed, 0) > 0)                                      as has_batted_ball,

        -- barrel PROXY (not a true Statcast barrel — coarse EV*LA stand-in).
        -- coalesce to false so the flag is never null (a missing EV is "not a barrel").
        coalesce(exit_speed >= 98 and launch_angle between 26 and 30, false) as barrel_proxy,

        -- normalized pitch bucket: prefer tagged, fall back to auto
        coalesce(
            {{ pitch_code('tagged_pitch_type') }},
            {{ pitch_code('auto_pitch_type') }}
        )                                                                  as pitch_code

    from pitches

),

with_contact as (

    select
        *,
        (is_swing and not is_whiff)                                        as is_contact
    from flagged

)

select * from with_contact
