-- MIGRATION / EQUIVALENCE PROOF.
--
-- Independently re-derive the pitches-weighted overall Stuff+ straight off the
-- staging arsenal (the same math rollup.py `_weighted_mean(stuff_plus, pitches)`
-- runs), then assert it matches mart_pitcher_arsenal.stuff_plus. If the mart's
-- rollup ever drifts from the hand calculation, this fails — which is exactly the
-- guarantee you want when cutting run.py over from the Python rollup to dbt.
--
-- Tolerance 0.1 absorbs the round(.., 1) the macro applies. A failing row = a
-- pitcher whose mart Stuff+ disagrees with the hand-computed weighted mean.

with hand_check as (

    select
        player,
        team,
        round(
            sum(stuff_plus * pitches) filter (where stuff_plus is not null and pitches is not null)
            / nullif(sum(pitches) filter (where stuff_plus is not null and pitches is not null), 0),
            1
        ) as stuff_plus_hand,
        nullif(sum(coalesce(pitches, 0)), 0) as pitches_hand
    from {{ ref('stg_643__pitch_arsenal') }}
    -- same identity grain as the mart: (player, team)
    group by player, team

),

compared as (

    select
        m.pitcher_name,
        m.team,
        m.stuff_plus       as mart_stuff_plus,
        h.stuff_plus_hand,
        m.pitches          as mart_pitches,
        h.pitches_hand
    from {{ ref('mart_pitcher_arsenal') }} m
    join hand_check h
        on m.pitcher_name = h.player
        and coalesce(m.team, '') = coalesce(h.team, '')

)

select *
from compared
where
    -- overall Stuff+ must reconcile within rounding tolerance
    abs(coalesce(mart_stuff_plus, -999) - coalesce(stuff_plus_hand, -999)) > 0.1
    -- total pitches must match exactly
    or coalesce(mart_pitches, -1) <> coalesce(pitches_hand, -1)
