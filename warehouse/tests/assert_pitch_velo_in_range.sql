-- DATA-QUALITY GATE the Python pipeline lacks (real added value).
--
-- A genuinely-thrown, classified pitch should release between ~50 and 105 mph.
-- Sub-50 / over-105 readings on a tagged pitch are radar/tracking errors (lobbed
-- pickoffs, mis-tracks) that silently poison velo aggregates in the Python path.
--
-- Scope: only pitches that carry a normalized pitch_code (i.e. a real pitch type,
-- not 'Undefined'/'Other') AND have a non-null rel_speed. Untagged junk pitches
-- are excluded on purpose — the gate flags bad data on REAL pitches, which is the
-- thing that would corrupt a Stuff+ / fastball-velo number.
--
-- A flagged row = a classified pitch with an out-of-range release speed.
--
-- Severity: WARN (not error) with a hard error_if escape hatch. On the full
-- 2025 USD season this correctly surfaces 4 mis-tracked sub-50-mph "pitches"
-- (TrackMan auto-classified them despite an Undefined tag) — known radar
-- artifacts the Python pipeline silently averages in. We want that visible on
-- every run WITHOUT blocking the build; if the count ever balloons (>10) it
-- becomes a hard error signalling a real ingestion regression. CI runs on the
-- cleaned sample fixture, so CI stays green.
{{ config(severity='warn', error_if='>10', warn_if='>0') }}

select
    pitch_uid,
    pitcher,
    pitch_code,
    tagged_pitch_type,
    rel_speed
from {{ ref('fct_pitch') }}
where pitch_code is not null
  and rel_speed is not null
  and (rel_speed < 50 or rel_speed > 105)
