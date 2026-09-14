-- NCAA Baseball Transfer Portal — evaluation pipeline schema (SQLite)
-- Mirrors the existing "2025 Transfer Portal Main Database.xlsx" structure:
--   CRM/call-assignment layer  +  advanced-metrics hot boards (hitter / pitcher).
-- Run:  python scripts/init_db.py   (creates db/baseball.db from this file)

PRAGMA foreign_keys = ON;

-- ── Canonical player identity ───────────────────────────────────────────────
-- One row per real human, stable across schools/sources (cf. 6-4-3 cross-school Player ID).
CREATE TABLE IF NOT EXISTS players (
    player_id            INTEGER PRIMARY KEY,
    first_name           TEXT,
    last_name            TEXT,
    full_name            TEXT NOT NULL,
    position             TEXT,            -- POS / pos
    bats                 TEXT,            -- B
    throws               TEXT,            -- T
    class_year           TEXT,            -- Year (FR/SO/JR/SR/GR)
    division             TEXT,            -- Div (D1/D2/D3/NAIA/JUCO)
    from_school          TEXT,            -- school they entered from
    to_school            TEXT,            -- destination once committed
    summer_team          TEXT,            -- Summer Team
    eligibility_remaining INTEGER,        -- years left, if known
    current_status       TEXT DEFAULT 'ENTERED',  -- ENTERED | WITHDRAWN | COMMITTED
    external_ids         TEXT,            -- json: {"ncaa": .., "643": .., "trumedia": ..}
    -- ── canonical bio rollup from player_bio (cf. geo.py score_geo_ties) ──
    hometown_city        TEXT,            -- canonical hometown city
    hometown_state       TEXT,            -- canonical hometown state (USPS, e.g. CA)
    high_school          TEXT,            -- canonical high school (+ JUCO if that's the roster's "previous")
    height_in            INTEGER,         -- canonical height in inches (NCAA roster, most-recent season)
    weight_lb            INTEGER,         -- canonical weight in lbs (team-site roster; NCAA carries no weight)
    ca_tie               INTEGER DEFAULT 0,  -- 1 if ANY California connection (hometown/HS/prior school/summer)
    socal_tie            INTEGER DEFAULT 0,  -- 1 if a Southern California connection (mid tier; sd_tie ⊆ socal_tie ⊆ ca_tie)
    sd_tie               INTEGER DEFAULT 0,  -- 1 if a San Diego-area connection specifically (USD recruiting edge)
    ca_tie_reasons       TEXT,            -- ';'-joined evidence, e.g. "hometown=CA;prev_school=SDSU"
    first_seen           TEXT,            -- ISO ts we first saw them
    last_updated         TEXT
);
CREATE INDEX IF NOT EXISTS idx_players_name ON players(full_name);
CREATE INDEX IF NOT EXISTS idx_players_status ON players(current_status);

-- ── Portal event log (full history; never overwrite) ────────────────────────
CREATE TABLE IF NOT EXISTS portal_events (
    event_id     INTEGER PRIMARY KEY,
    player_id    INTEGER NOT NULL REFERENCES players(player_id),
    event_type   TEXT NOT NULL,          -- ENTERED | WITHDRAWN | COMMITTED
    event_date   TEXT,                   -- date reported (source's date)
    source       TEXT NOT NULL,          -- d1baseball | verbalcommits | 64analytics | twitter | 643 | ncaa
    source_url   TEXT,
    observed_at  TEXT NOT NULL,          -- when WE ingested it
    raw_json     TEXT,                   -- original parsed blob, for re-processing
    UNIQUE(player_id, event_type, source, event_date)   -- idempotent re-runs
);
CREATE INDEX IF NOT EXISTS idx_events_player ON portal_events(player_id);

-- ── Hitter hot board (cf. "Hitter Hot Board Data" sheet) ────────────────────
CREATE TABLE IF NOT EXISTS stats_hitting (
    id           INTEGER PRIMARY KEY,
    player_id    INTEGER NOT NULL REFERENCES players(player_id),
    season       TEXT NOT NULL,          -- e.g. "2025" or "24-25"
    team         TEXT,
    level        TEXT,                   -- division/level of the line
    pa           INTEGER,
    ba           REAL,  obp REAL,  slg REAL,
    xwoba        REAL,  woba REAL,
    hr           INTEGER, sb INTEGER,
    avg_ev       REAL,  ev90 REAL,        -- AVG EV, 90EV
    hardhit_pct  REAL,  barrel_pct REAL,
    gb_pct       REAL,  pull_pct REAL,
    k_pct        REAL,
    zcon_pct     REAL,  chase_pct REAL, swstr_pct REAL,   -- Z-Con%, Chase%, SwStrk%
    seager       REAL,
    xslg         REAL,                   -- expected SLG (hitter-app XGBoost model, TrackMan)
    decision_value REAL,                 -- swing-decision value, 20-80 (hitter-app)
    pitches      INTEGER,                -- TrackMan pitch sample backing this line
    -- 6-4-3 batted-ball / discipline extras (full export coverage)
    max_ev REAL, xba REAL, swspot_pct REAL, la REAL,
    fb_pct REAL, ld_pct REAL, swing_pct REAL, zswing_pct REAL,
    sd_plus REAL, barrels INTEGER, bbe INTEGER,
    -- D1Baseball box-score season totals (hr/sb/pa/ba/obp/slg already above):
    -- games, at-bats, hits, runs, RBI, walks, strikeouts, 2B, 3B, HBP, caught stealing, OPS.
    gp INTEGER, ab INTEGER, h INTEGER, r INTEGER, rbi INTEGER, bb INTEGER, so INTEGER,
    doubles INTEGER, triples INTEGER, hbp INTEGER, cs INTEGER, ops REAL,
    pu_pct REAL, hr_fb_pct REAL,         -- D1Baseball Batted Ball: pop-up%, HR per fly ball
    -- D1Baseball Advanced Batting (k_pct, woba already above): walk%, K:BB, ISO, BABIP, wRC, wRAA, wRC+.
    bb_pct REAL, k_bb_ratio REAL, iso REAL, babip REAL, wrc INTEGER, wraa INTEGER, wrc_plus INTEGER,
    source       TEXT,                   -- 643 | d1baseball | collegebaseball | trackman | ncaa | manual
    source_file  TEXT,                   -- exact CSV/file behind this stat row, when available
    observed_at  TEXT,                   -- when WE loaded/refreshed this stat row
    UNIQUE(player_id, season, source)
);

-- ── Pitcher hot board (cf. "All Divisions Pitcher Data" sheet) ──────────────
CREATE TABLE IF NOT EXISTS stats_pitching (
    id              INTEGER PRIMARY KEY,
    player_id       INTEGER NOT NULL REFERENCES players(player_id),
    season          TEXT NOT NULL,
    team            TEXT,
    level           TEXT,                -- newestTeamLevel
    ip              REAL,
    fip             REAL,
    slg_against     REAL,                -- SLG
    k_bb            REAL,                -- K/BB
    perceived_value REAL,                -- Perceived Value
    hardhit_pct     REAL,
    ground_pct      REAL,                -- Ground%
    strike_pct      REAL,                -- Strike%
    miss_pct        REAL,                -- Miss%
    inzone_whiff_pct REAL,               -- InZoneWhiff%
    chase_pct       REAL,
    t2_stuff        REAL,                -- T2 Stuff (TruMedia) / overall TJ Stuff+ (trackman)
    xwhiff_pct      REAL,                -- modeled whiff% (pitcher-app RandomForest, TrackMan)
    pitches         INTEGER,             -- pitch sample backing this line (TrackMan or 6-4-3)
    fb_velo REAL, fb_ivb REAL, fb_hb REAL,   -- 6-4-3 fastball shape: velo / iVB / HB
    -- per-pitch stuff+ (cf. "CB/CH/CT/FB/SI/SL - stuff+")
    cb_stuff REAL, ch_stuff REAL, ct_stuff REAL, fb_stuff REAL, si_stuff REAL, sl_stuff REAL,
    -- per-pitch strike% (cf. "CB/CH/CT/FB/SI/SL - strike%")
    cb_strike_pct REAL, ch_strike_pct REAL, ct_strike_pct REAL,
    fb_strike_pct REAL, si_strike_pct REAL, sl_strike_pct REAL,
    -- D1Baseball box-score season totals (ip/k_bb already above; no HR-allowed → no FIP):
    -- ERA, W, L, saves, appearances, games started, complete games, shutouts, hits, runs,
    -- earned runs, walks, strikeouts, HBP, opponent batting average.
    era REAL, w INTEGER, l INTEGER, sv INTEGER, app INTEGER, gs INTEGER, cg INTEGER, sho INTEGER,
    h INTEGER, r INTEGER, er INTEGER, bb INTEGER, k INTEGER, hbp INTEGER, ba_against REAL,
    source          TEXT,
    source_file     TEXT,                -- exact CSV/file behind this stat row, when available
    observed_at     TEXT,                -- when WE loaded/refreshed this stat row
    UNIQUE(player_id, season, source)
);

-- ── Pitch arsenal: one row per (pitcher, season, pitch type) ────────────────
-- Pitchers are evaluated PER PITCH; this is the source of truth. The wide
-- stats_pitching line (per-pitch *_stuff columns) is a derived rollup of this.
-- Holds 6-4-3's full per-pitch suite: shape + the "+"-family + outcomes allowed.
CREATE TABLE IF NOT EXISTS pitch_arsenal (
    id          INTEGER PRIMARY KEY,
    player_id   INTEGER NOT NULL REFERENCES players(player_id),
    season      TEXT NOT NULL,
    pitch_type  TEXT NOT NULL,        -- Fastball/Slider/Changeup/Sinker/Curveball/Cutter/Splitter/Sweeper...
    code        TEXT,                 -- normalized bucket: fb/si/sl/cb/ch/ct
    throws      TEXT,
    team        TEXT,
    pitches     INTEGER, bbe INTEGER, barrels INTEGER,
    -- shape
    velo REAL, velo90 REAL, max_velo REAL, spin REAL,
    ivb REAL, hb REAL, vaa REAL, haa REAL, rel_height REAL, rel_side REAL, extension REAL,
    -- 6-4-3 "+" quality family
    stuff_plus REAL, location_plus REAL, xrv_plus REAL,
    anomaly_plus REAL, tunnel_plus REAL, predmovdiff_plus REAL,
    -- outcomes allowed on this pitch
    ev REAL, hardhit_pct REAL, barrel_pct REAL,
    ba REAL, xba REAL, woba REAL, xwoba REAL,
    swing_pct REAL, zcontact_pct REAL, chase_pct REAL, whiff_pct REAL,
    source      TEXT,
    source_file TEXT,                   -- exact CSV/file behind this per-pitch row
    observed_at TEXT,                   -- when WE loaded/refreshed this per-pitch row
    UNIQUE(player_id, season, pitch_type, source)
);
CREATE INDEX IF NOT EXISTS idx_arsenal_player ON pitch_arsenal(player_id);
CREATE INDEX IF NOT EXISTS idx_arsenal_season_code ON pitch_arsenal(season, code);

-- ── CRM: call assignments (cf. "Hot List/Call Assignments" + "Names + Notes") ─
-- Also the round-trip target for the coach-facing board overlay: coaches set a lead
-- temperature, star favorites, and leave notes on the published board; sync-overlay
-- (src/portal/overlay.py) writes those back here, keyed by the stable player_id.
CREATE TABLE IF NOT EXISTS call_assignments (
    id           INTEGER PRIMARY KEY,
    player_id    INTEGER NOT NULL REFERENCES players(player_id),
    assigned_date TEXT,                  -- Date / DATE
    priority     INTEGER,                -- Priority
    contact      TEXT,                   -- Contact (who calls)
    notes        TEXT,                   -- Notes
    scout_notes  TEXT,                   -- json: {"TW": "...", "Kevin Karstetter": "..."}
    lead_temp    TEXT,                   -- coach lead rating '1'..'5' (5 = hottest); NULL = untagged
    favorite     INTEGER DEFAULT 0,      -- 1 = starred by the staff
    overlay_updated_by TEXT,             -- name (dropdown) of whoever last changed temp/favorite
    overlay_updated_at TEXT,             -- ISO ts of the last overlay change
    updated_at   TEXT
);
CREATE INDEX IF NOT EXISTS idx_calls_player ON call_assignments(player_id);
CREATE INDEX IF NOT EXISTS idx_calls_lead_temp ON call_assignments(lead_temp);

-- ── Roster reference (cf. "RosterInfo") ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS roster_info (
    id                 INTEGER PRIMARY KEY,
    full_name          TEXT,
    pos_season_concat  TEXT
);

-- ── Player bio by season (height/weight change year to year) ────────────────
-- "by year": one row per (player, season, source). Height normalized to inches.
CREATE TABLE IF NOT EXISTS player_bio (
    id          INTEGER PRIMARY KEY,
    player_id   INTEGER NOT NULL REFERENCES players(player_id),
    season      TEXT NOT NULL,
    height_in   INTEGER,          -- height in inches (6'2" -> 74)
    weight_lb   INTEGER,
    bats        TEXT,
    throws      TEXT,
    class_year  TEXT,
    position    TEXT,             -- team-site roster position (rolled onto players)
    team        TEXT,
    hometown_city  TEXT,          -- from NCAA roster "Hometown" / Sidearm / PG
    hometown_state TEXT,          -- USPS abbrev (CA, TX, ...) when parseable
    high_school    TEXT,          -- roster "High School" (or previous school)
    source      TEXT,             -- ncaa | sidearm | perfectgame | 643 | d1baseball | manual
    UNIQUE(player_id, season, source)
);
CREATE INDEX IF NOT EXISTS idx_bio_player ON player_bio(player_id);

-- Granular bio/source evidence: one row per observed source row, kept for
-- future citation/provenance even when player_bio rolls up to one canonical
-- row per (player, season, source).
CREATE TABLE IF NOT EXISTS player_bio_evidence (
    evidence_id INTEGER PRIMARY KEY,
    player_id   INTEGER NOT NULL REFERENCES players(player_id),
    season      TEXT NOT NULL,
    source      TEXT NOT NULL,
    source_file TEXT,
    source_url  TEXT,
    observed_at TEXT NOT NULL,
    row_hash    TEXT NOT NULL UNIQUE,
    team        TEXT,
    height_in   INTEGER,
    weight_lb   INTEGER,
    bats        TEXT,
    throws      TEXT,
    class_year  TEXT,
    position    TEXT,
    hometown_city  TEXT,
    hometown_state TEXT,
    high_school    TEXT,
    raw_json    TEXT
);
CREATE INDEX IF NOT EXISTS idx_bio_evidence_player ON player_bio_evidence(player_id);
CREATE INDEX IF NOT EXISTS idx_bio_evidence_lookup ON player_bio_evidence(player_id, season, source);
CREATE INDEX IF NOT EXISTS idx_bio_evidence_source ON player_bio_evidence(source, source_file);

CREATE INDEX IF NOT EXISTS idx_players_ca_tie ON players(ca_tie);
CREATE INDEX IF NOT EXISTS idx_players_socal_tie ON players(socal_tie);

-- ── Evaluation: roster-need profiles + computed fit scores ──────────────────
CREATE TABLE IF NOT EXISTS need_profiles (
    id              INTEGER PRIMARY KEY,
    label           TEXT,
    position        TEXT,
    priority        INTEGER,
    min_eligibility INTEGER,
    min_class       TEXT,
    target_metrics  TEXT,                -- json of metric -> threshold expr
    active          INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS evaluations (
    id              INTEGER PRIMARY KEY,
    player_id       INTEGER NOT NULL REFERENCES players(player_id),
    need_profile_id INTEGER REFERENCES need_profiles(id),
    fit_score       REAL,                -- Rating: 20-80 OFP grade, true-SD vs all-college reference (overall future value)
    components      TEXT,                -- json breakdown (rating/hit/power/likelihood/perf/level/...)
    run_at          TEXT
);
CREATE INDEX IF NOT EXISTS idx_eval_player ON evaluations(player_id);

-- ── Ingestion audit ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS source_runs (
    id          INTEGER PRIMARY KEY,
    source      TEXT,
    started_at  TEXT,
    finished_at TEXT,
    rows_in     INTEGER,
    rows_new    INTEGER,
    errors      TEXT
);
