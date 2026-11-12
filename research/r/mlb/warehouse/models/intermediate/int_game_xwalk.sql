-- Retrosheet gid to StatsAPI game_pk, one pk per gid: the SQL form of pk_crosswalk() in matchup.R.
-- Games match on date and final score, then must agree with the team-id map those matches imply
-- (each Retrosheet code to its most frequent StatsAPI id). Unlike R, which keeps the first of an
-- ambiguous pair (a doubleheader with two identical scores), both rows drop: a guess is not a key.
with cand as (
    select r.gid, r.home_team, r.away_team, s.game_pk, s.home_id, s.away_id
    from {{ ref('stg_retro__games') }} r
    join {{ ref('stg_statsapi__games') }} s
      on s.game_date = r.start_date
     and s.home_score = r.home_runs
     and s.away_score = r.away_runs
    where r.game_type = 'regular'
),
hmap as (
    select home_team, home_id from cand group by home_team, home_id
    qualify row_number() over (partition by home_team order by count(*) desc, home_id) = 1
),
amap as (
    select away_team, away_id from cand group by away_team, away_id
    qualify row_number() over (partition by away_team order by count(*) desc, away_id) = 1
),
agreed as (
    select c.gid, c.game_pk
    from cand c
    join hmap using (home_team, home_id)
    join amap using (away_team, away_id)
)
select gid, game_pk
from agreed
qualify count(*) over (partition by gid) = 1
    and count(*) over (partition by game_pk) = 1
