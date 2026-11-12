-- Pins the reason official_date is not a results-known date: both listings of a suspended game carry
-- the start's official date while the resumption is listed days later. If StatsAPI ever re-dates
-- resumptions, this fails and the warning in stg_statsapi__schedule is stale.
select r.game_pk, r.listed_at, r.official_date, r.resumed_from
from {{ ref('stg_statsapi__schedule') }} r
where r.resumed_from is not null
  and r.official_date <> (
      select min(s.official_date) from {{ ref('stg_statsapi__schedule') }} s
      where s.game_pk = r.game_pk and s.listed_at < r.listed_at)
