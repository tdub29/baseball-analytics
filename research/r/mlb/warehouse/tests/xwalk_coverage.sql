{{ config(severity = 'error', error_if = '>100', warn_if = '>40') }}
-- Regular-season Retrosheet games with no StatsAPI game_pk. 40 on the 2015-2025 cache, all explained:
-- the 36 home/away swaps DATA.md lists, and both games of two doubleheaders whose games ended with
-- the same score (PIT 2016-06-07, LAN 2023-08-19), dropped as ambiguous. A new miss warns; more than
-- 100 means the join or a source broke.
select g.gid, g.start_date, g.home_team, g.away_team, g.home_runs, g.away_runs
from {{ ref('stg_retro__games') }} g
left join {{ ref('int_game_xwalk') }} x using (gid)
where g.game_type = 'regular' and x.gid is null
