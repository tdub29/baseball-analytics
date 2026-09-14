-- Cast + rename the raw TrackMan export to a clean, typed, snake_case pitch row.
-- Source is read all-varchar (so a messy export never fails the load); we coerce
-- the numeric fields here and keep the grain at one row per PitchUID.
--
-- Mirrors src/portal/trackman.py load_trackman(): same numeric columns coerced,
-- same lowercase canonical names, and a synthesized key only if PitchUID is null.

with source as (

    select * from {{ source('trackman', 'pitches') }}

),

renamed as (

    select
        -- ── identity / context ───────────────────────────────────────────────
        coalesce(
            nullif(trim("PitchUID"), ''),
            -- synthesize a stable key if the export lacks one (cf. load_trackman)
            'syn_' || cast(row_number() over () as varchar)
        )                                                            as pitch_uid,
        nullif(trim("GameID"), '')                                   as game_id,
        try_strptime("Date", '%-m/%-d/%Y')::date                     as game_date,
        try_cast("Inning" as integer)                                as inning,
        nullif(trim("Top/Bottom"), '')                               as inning_half,
        try_cast("PAofInning" as integer)                            as pa_of_inning,
        try_cast("PitchofPA" as integer)                             as pitch_of_pa,
        try_cast("Balls" as integer)                                 as balls,
        try_cast("Strikes" as integer)                               as strikes,
        try_cast("Outs" as integer)                                  as outs,

        -- ── pitcher / batter ─────────────────────────────────────────────────
        nullif(trim("Pitcher"), '')                                  as pitcher,
        nullif(trim("PitcherId"), '')                                as pitcher_id,
        nullif(trim("PitcherThrows"), '')                            as pitcher_throws,
        nullif(trim("PitcherTeam"), '')                              as pitcher_team,
        nullif(trim("Batter"), '')                                   as batter,
        nullif(trim("BatterSide"), '')                               as batter_side,
        nullif(trim("BatterTeam"), '')                               as batter_team,

        -- ── pitch classification / result ────────────────────────────────────
        nullif(trim("TaggedPitchType"), '')                          as tagged_pitch_type,
        nullif(trim("AutoPitchType"), '')                            as auto_pitch_type,
        nullif(trim("PitchCall"), '')                                as pitch_call,
        nullif(trim("KorBB"), '')                                    as kor_bb,
        nullif(trim("PlayResult"), '')                               as play_result,

        -- ── release / movement (typed doubles) ───────────────────────────────
        try_cast("RelSpeed" as double)                               as rel_speed,
        try_cast("SpinRate" as double)                               as spin_rate,
        try_cast("SpinAxis" as double)                               as spin_axis,
        try_cast("RelHeight" as double)                              as rel_height,
        try_cast("RelSide" as double)                                as rel_side,
        try_cast("Extension" as double)                              as extension,
        try_cast("InducedVertBreak" as double)                       as induced_vert_break,
        try_cast("HorzBreak" as double)                              as horz_break,
        try_cast("VertApprAngle" as double)                          as vert_appr_angle,
        try_cast("HorzApprAngle" as double)                          as horz_appr_angle,

        -- ── location / batted ball ───────────────────────────────────────────
        try_cast("PlateLocHeight" as double)                         as plate_loc_height,
        try_cast("PlateLocSide" as double)                           as plate_loc_side,
        try_cast("ExitSpeed" as double)                              as exit_speed,
        try_cast("Angle" as double)                                  as launch_angle,
        try_cast("Distance" as double)                               as distance,

        -- ── level / quality flags (TrackMan confidence) ──────────────────────
        nullif(trim("Level"), '')                                    as level,
        nullif(trim("PitchReleaseConfidence"), '')                   as pitch_release_confidence,
        nullif(trim("PitchLocationConfidence"), '')                  as pitch_location_confidence,
        nullif(trim("PitchMovementConfidence"), '')                  as pitch_movement_confidence

    from source

)

select * from renamed
-- Drop non-pitch tracking artifacts (catcher throws / untagged rows carry a null
-- pitcher). Mirrors src/portal/trackman.aggregate_pitching: `if not clean_str(pitcher): continue`.
where pitcher is not null
