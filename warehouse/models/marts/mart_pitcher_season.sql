-- mart_pitcher_season — one row per pitcher from the TrackMan pitch fact.
-- Mirrors src/portal/trackman.aggregate_pitching: rate stats off the engineered
-- flags (strike% / miss% / in-zone whiff% / chase% / ground% / hardhit%) plus
-- per-pitch-type Stuff+ would normally come from the ML scorer — that scoring
-- stays in Python, so here we surface the MEASURED + FLAG-DERIVED aggregates only
-- (Stuff+ is sourced from mart_pitcher_arsenal / 6-4-3, not recomputed).
--
-- _rate(num, den) = round(100 * num / den, 1) if den else null  -> reproduced as
--     round(100.0 * count(...) / nullif(count(...), 0), 1)

with fct as (

    select * from {{ ref('fct_pitch') }}

),

agg as (

    select
        pitcher                                                              as pitcher_name,
        {{ dbt_utils.generate_surrogate_key(['pitcher']) }}                  as pitcher_sk,
        max(pitcher_team)                                                    as team,
        max(level)                                                           as level,
        count(*)                                                             as pitches,
        count(distinct game_id)                                              as games,

        -- strike% = strikes / all pitches
        round(100.0 * count(*) filter (where is_strike)
              / nullif(count(*), 0), 1)                                      as strike_pct,

        -- miss% (whiff/swing) = whiffs / swings
        round(100.0 * count(*) filter (where is_whiff)
              / nullif(count(*) filter (where is_swing), 0), 1)              as miss_pct,

        -- in-zone whiff% = (in-zone whiffs) / (in-zone swings)
        round(100.0 * count(*) filter (where in_zone and is_whiff)
              / nullif(count(*) filter (where in_zone and is_swing), 0), 1)  as inzone_whiff_pct,

        -- chase% = (out-of-zone swings) / (out-of-zone pitches)
        round(100.0 * count(*) filter (where not in_zone and is_swing)
              / nullif(count(*) filter (where not in_zone), 0), 1)           as chase_pct,

        -- ground% = (batted balls with LA < 10) / batted balls
        round(100.0 * count(*) filter (where has_batted_ball and launch_angle < 10)
              / nullif(count(*) filter (where has_batted_ball), 0), 1)       as ground_pct,

        -- hardhit% allowed = (batted balls EV >= 95) / batted balls
        round(100.0 * count(*) filter (where has_batted_ball and exit_speed >= 95)
              / nullif(count(*) filter (where has_batted_ball), 0), 1)       as hardhit_pct,

        count(*) filter (where is_in_play)                                   as balls_in_play,
        count(*) filter (where lower(kor_bb) = 'strikeout')                  as strikeouts,
        count(*) filter (where lower(kor_bb) = 'walk')                       as walks,

        -- measured fastball velo (avg of fb-coded pitches)
        round(avg(rel_speed) filter (where pitch_code = 'fb'), 1)            as fb_velo_measured,
        round(max(rel_speed), 1)                                             as max_velo_measured

    from fct
    group by pitcher

)

select * from agg
