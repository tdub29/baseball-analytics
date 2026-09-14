-- Referential integrity: every pitch in the fact must resolve to a pitcher in
-- dim_pitcher. (The relationships test on fct_pitch.pitcher_sk covers the
-- surrogate-key join; this is the explicit, readable orphan check by name.)
--
-- A failing row = a fact pitch whose pitcher has no dimension row.

select
    f.pitch_uid,
    f.pitcher,
    f.pitcher_sk
from {{ ref('fct_pitch') }} f
left join {{ ref('dim_pitcher') }} d
    on f.pitcher_sk = d.pitcher_sk
where d.pitcher_sk is null
