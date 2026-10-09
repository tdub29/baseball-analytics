-- One row per schedule listing, 2015-2019. A postponed game is listed twice (the postponed slot and
-- the makeup) and a suspended game twice (start and resumption) under one game_pk, so the key is
-- (game_pk, listed_at). `official_date` is the makeup date for a postponement but the START date for
-- both listings of a suspended game: dating results by it reads a resumed game's score early.
select
    "gamePk"                                       as game_pk,
    "gameDate"::timestamp                          as listed_at,
    "officialDate"::date                           as official_date,
    cast(season as integer)                        as season,
    "gameType"                                     as game_type,
    "status.detailedState"                         as status,
    "gameNumber"                                   as game_number,
    "doubleHeader"                                 as double_header,
    "dayNight"                                     as day_night,
    "teams.home.team.id"                           as home_id,
    "teams.away.team.id"                           as away_id,
    "teams.home.score"                             as home_score,
    "teams.away.score"                             as away_score,
    "teams.home.probablePitcher.id"                as home_probable_id,
    "teams.away.probablePitcher.id"                as away_probable_id,
    "venue.id"                                     as venue_id,
    "rescheduledFrom"::timestamp                   as rescheduled_from,
    "resumedFrom"::timestamp                       as resumed_from
from {{ source('statsapi', 'schedule') }}
