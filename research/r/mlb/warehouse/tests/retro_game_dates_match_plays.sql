-- A game's first play is on its start date and its last play on its completion date, and nothing
-- crosses a season. Fails if Retrosheet ever changes what `date` or `suspend` mean.
select g.gid, g.season, g.start_date, g.completion_date,
       min(p.play_date) as first_play, max(p.play_date) as last_play
from {{ ref('stg_retro__games') }} g
join {{ ref('stg_retro__plays') }} p using (gid)
group by all
having min(p.play_date) <> g.start_date
    or max(p.play_date) <> g.completion_date
    or year(g.start_date) <> g.season
