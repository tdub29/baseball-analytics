-- One row per person in the Chadwick register. The cache stores a missing text id as '' rather than
-- NULL, which would make 495k people share one Retrosheet id; nullif restores NULL.
select
    key_person,
    key_mlbam,
    nullif(key_retro, '')          as key_retro,
    nullif(key_bbref, '')          as key_bbref,
    key_fangraphs,
    name_first,
    name_last,
    birth_year,
    mlb_played_first,
    mlb_played_last
from {{ source('chadwick', 'register') }}
