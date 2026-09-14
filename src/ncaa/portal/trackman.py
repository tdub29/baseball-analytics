"""TrackMan enrichment — score USD's pitch-by-pitch with the hitter/pitcher
app models and write one season stat line per player.

This runs, headless, the exact math the two Streamlit apps run in their UI:
  • pitcher-app (tdub29/streamlit-app-1): TJ Stuff+ (sklearn Pipeline → LightGBM)
        and xWhiff (sklearn Pipeline → RandomForest), on engineered release/movement
        features. tj_stuff_plus = 100 - 10*z(target).
  • hitter-app (tdub29/hitterapp): xSLG (XGBoost on launch_speed/angle/interaction)
        and decision value (XGBoost take/swing models → 20-80 scale).
Model design credited in those repos to Thomas Nestico, Kyle Bland, Max Bay.

We score every pitch, aggregate to one row per player, and upsert into
stats_hitting / stats_pitching (source="trackman") via the shared Resolver — so
Stuff+/xSLG flow into evaluate() and the hot board exactly like a 6-4-3 export.

Heavy ML deps (xgboost, joblib, scikit-learn, lightgbm) are imported lazily;
without them, scoring raises a clear message and the rest of the pipeline is
unaffected (cf. enrich.collegebaseball_baseline).
"""
from __future__ import annotations

import importlib
import logging
import sqlite3
from pathlib import Path

import numpy as np
import pandas as pd

from .resolve import Resolver
from .util import clean_str

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parents[2]

# ── TJ Stuff+ scaling (from pitcher-app run_model_and_scale) ─────────────────
_STUFF_TARGET_MEAN = 0.011532333993710725
_STUFF_TARGET_STD = 0.009399038486978739
_STUFF_FEATURES = ["start_speed", "spin_rate", "extension", "az", "ax", "x0", "z0",
                   "speed_diff", "az_diff", "ax_diff", "is_fastball"]
_FASTBALL_AUTOTYPES = {"Four-Seam", "Sinker"}   # exact AutoPitchType strings, per app

# ── decision-value 20-80 calibration (from hitter-app) ───────────────────────
_DV = {"no_swing": (0.0119, 0.0199), "swing": (-0.0194, 0.0129), "overall": (-0.0032, 0.0130)}

# AutoPitchType → per-pitch schema bucket (cb/ch/ct/fb/si/sl_stuff columns)
_PITCH_CODE = {
    "four-seam": "fb", "fourseam": "fb", "fastball": "fb", "four seam": "fb",
    "sinker": "si", "two-seam": "si", "twoseam": "si", "two seam": "si",
    "cutter": "ct",
    "slider": "sl",
    "curveball": "cb", "curve": "cb", "knuckle curve": "cb", "knucklecurve": "cb",
    "changeup": "ch", "change-up": "ch", "change up": "ch", "change": "ch", "splitter": "ch",
}

# Strike-zone box (feet) shared by both apps.
_ZONE_SIDE = (-0.83, 0.83)
_ZONE_HEIGHT = (1.5, 3.5)


def _need(mod: str, hint: str):
    try:
        return importlib.import_module(mod)
    except Exception as e:  # pragma: no cover - exercised only without the dep
        raise RuntimeError(
            f"TrackMan scoring needs '{mod}' ({hint}). "
            "Install with: pip install xgboost scikit-learn lightgbm joblib"
        ) from e


# ── loading / column normalization ───────────────────────────────────────────
def load_trackman(path: str | Path) -> pd.DataFrame:
    """Read a TrackMan export and lowercase headers to a canonical set.

    Accepts a local path or an http(s) URL (pandas reads both).
    """
    df = pd.read_csv(path)
    df.columns = [str(c).strip() for c in df.columns]
    # collapse duplicate-after-lowercasing columns, keep first
    df = df.loc[:, ~pd.Index([c.lower() for c in df.columns]).duplicated()].copy()
    df.columns = [c.lower() for c in df.columns]
    for c in ("relspeed", "spinrate", "extension", "relheight", "relside", "horzbreak",
              "inducedvertbreak", "platelocheight", "platelocside", "exitspeed", "angle",
              "direction", "distance", "balls", "strikes"):
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    if "pitchuid" not in df.columns:
        df["pitchuid"] = np.arange(len(df))   # synthesize a key if the export lacks one
    return df


# ── pitch-call → boolean event flags (TrackMan-standard) ─────────────────────
def _pitch_flags(df: pd.DataFrame) -> pd.DataFrame:
    pc = df.get("pitchcall", pd.Series("", index=df.index)).astype(str).str.lower()
    ev = pd.to_numeric(df.get("exitspeed"), errors="coerce")
    out = pd.DataFrame(index=df.index)
    out["whiff"] = pc.eq("strikeswinging")
    foul = pc.str.contains("foul", na=False)
    inplay = pc.eq("inplay") | ev.fillna(0).gt(0)
    out["swing"] = out["whiff"] | foul | inplay
    out["strike"] = out["whiff"] | foul | inplay | pc.eq("strikecalled")
    side = pd.to_numeric(df.get("platelocside"), errors="coerce")
    height = pd.to_numeric(df.get("platelocheight"), errors="coerce")
    out["inzone"] = side.between(*_ZONE_SIDE) & height.between(*_ZONE_HEIGHT)
    return out


def _rate(num: float, den: float) -> float | None:
    return round(100 * num / den, 1) if den else None


# ── pitcher: feature engineering (mirrors pitcher-app feature_engineering) ────
def _pitcher_features(df: pd.DataFrame) -> pd.DataFrame:
    cols = ["pitcher", "relside", "relspeed", "spinrate", "extension", "relheight",
            "horzbreak", "inducedvertbreak", "autopitchtype", "pitchuid"]
    f = df[[c for c in cols if c in df.columns]].copy()

    hand = f.groupby("pitcher", as_index=False)["relside"].mean().rename(columns={"relside": "avg_side"})
    hand["pitcher_hand"] = np.where(hand["avg_side"] > 0, "R", "L")
    f = f.merge(hand[["pitcher", "pitcher_hand"]], on="pitcher", how="left")

    f = f.rename(columns={"relspeed": "start_speed", "spinrate": "spin_rate",
                          "relheight": "z0", "relside": "x0", "horzbreak": "ax",
                          "inducedvertbreak": "az", "autopitchtype": "pitch_type"})
    f["ax"] = np.where(f["pitcher_hand"] == "L", -f["ax"], f["ax"])
    f["x0"] = np.where(f["pitcher_hand"] == "L", -f["x0"], f["x0"])

    fb = f[f["pitch_type"].isin(_FASTBALL_AUTOTYPES)].copy()
    agg = (fb.groupby(["pitcher", "pitch_type"], as_index=False)
             .agg(avg_fastball_speed=("start_speed", "mean"),
                  avg_fastball_az=("az", "mean"), avg_fastball_ax=("ax", "mean"),
                  count=("start_speed", "count"))
             .sort_values(["count", "avg_fastball_speed"], ascending=[False, False])
             .drop_duplicates(subset=["pitcher"], keep="first"))
    f = f.merge(agg[["pitcher", "avg_fastball_speed", "avg_fastball_az", "avg_fastball_ax"]],
                on="pitcher", how="left")
    f["speed_diff"] = f["start_speed"] - f["avg_fastball_speed"]
    f["az_diff"] = f["az"] - f["avg_fastball_az"]
    f["ax_diff"] = f["ax"] - f["avg_fastball_ax"]
    f["is_fastball"] = f["pitch_type"].isin(_FASTBALL_AUTOTYPES)
    f["z0"] = f["z0"] * 12
    f["x0"] = f["x0"] * 12
    return f


def score_pitching(df: pd.DataFrame, models_dir: Path) -> pd.DataFrame:
    """Return df with per-pitch `stuff_plus` and `xwhiff` merged on pitchuid."""
    joblib = _need("joblib", "loads the Stuff+/whiff pipelines")
    _need("sklearn", "the models are scikit-learn Pipelines")
    _need("lightgbm", "Stuff+ is a LightGBM regressor")
    f = _pitcher_features(df)
    for c in _STUFF_FEATURES:
        if c not in f.columns:
            f[c] = np.nan
        f[c] = pd.to_numeric(f[c], errors="coerce")

    stuff_model = joblib.load(models_dir / "NCAA_STUFF_PLUS_ALL.joblib")
    whiff_model = joblib.load(models_dir / "whiff_model_grouped_training.joblib")
    X = f[_STUFF_FEATURES]
    target = stuff_model.predict(X)
    z = (target - _STUFF_TARGET_MEAN) / _STUFF_TARGET_STD
    f["stuff_plus"] = 100 - z * 10
    try:
        f["xwhiff"] = whiff_model.predict(X)
    except Exception as e:  # whiff model is optional sugar; never block Stuff+
        log.warning("xWhiff model failed (%s); continuing without it", e)
        f["xwhiff"] = np.nan
    return df.merge(f[["pitchuid", "pitch_type", "stuff_plus", "xwhiff"]],
                    on="pitchuid", how="left")


def aggregate_pitching(scored: pd.DataFrame) -> list[dict]:
    """One dict of schema columns per pitcher from a stuff-scored frame."""
    flags = _pitch_flags(scored)
    d = scored.assign(**{k: flags[k] for k in flags.columns})
    d["code"] = d.get("autopitchtype", "").astype(str).str.strip().str.lower().map(_PITCH_CODE)
    # exitspeed is recomputed per pitcher as `bip` inside the loop below, so this
    # frame-level pass was dead. `ang` is not: it is indexed per group as ang.loc[g.index].
    ang = pd.to_numeric(d.get("angle"), errors="coerce")

    rows = []
    for pitcher, g in d.groupby(d.get("pitcher")):
        if not clean_str(pitcher):
            continue
        gi, gsw = g["inzone"], g["swing"]
        bip = pd.to_numeric(g.get("exitspeed"), errors="coerce")
        in_play = bip > 0
        row: dict = {
            "__name__": clean_str(pitcher),
            "team": clean_str(g.get("pitcherteam", pd.Series([None])).iloc[0]) if "pitcherteam" in g else None,
            "level": clean_str(g.get("level", pd.Series([None])).iloc[0]) if "level" in g else None,
            "pitches": int(len(g)),
            "t2_stuff": round(float(g["stuff_plus"].mean()), 1) if g["stuff_plus"].notna().any() else None,
            "strike_pct": _rate(g["strike"].sum(), len(g)),
            "miss_pct": _rate(g["whiff"].sum(), gsw.sum()),
            "inzone_whiff_pct": _rate((gi & g["whiff"]).sum(), (gi & gsw).sum()),
            "chase_pct": _rate((~gi & gsw).sum(), (~gi).sum()),
            "ground_pct": _rate((in_play & (ang.loc[g.index] < 10)).sum(), in_play.sum()),
            "hardhit_pct": _rate((in_play & (bip >= 95)).sum(), in_play.sum()),
            "xwhiff_pct": round(float(g["xwhiff"].mean()) * 100, 1) if g["xwhiff"].notna().any() else None,
        }
        # per-pitch-type Stuff+ and strike%
        for code, sub in g.groupby("code"):
            if code not in {"cb", "ch", "ct", "fb", "si", "sl"}:
                continue
            if sub["stuff_plus"].notna().any():
                row[f"{code}_stuff"] = round(float(sub["stuff_plus"].mean()), 1)
            sf = flags.loc[sub.index]
            row[f"{code}_strike_pct"] = _rate(sf["strike"].sum(), len(sub))
        rows.append(row)
    return rows


# ── hitter: scoring (mirrors hitter-app xSLG + decision models) ──────────────
def score_hitting(df: pd.DataFrame, models_dir: Path) -> pd.DataFrame:
    """Return df with per-pitch xSLG, decision_rv, and swing/contact flags."""
    xgb = _need("xgboost", "xSLG + decision models are XGBoost")

    def _booster(name):
        b = xgb.Booster()
        b.load_model(str(models_dir / name))
        return b

    d = df.copy()
    ev = pd.to_numeric(d.get("exitspeed"), errors="coerce")
    ang = pd.to_numeric(d.get("angle"), errors="coerce")
    pc = d.get("pitchcall", pd.Series("", index=d.index)).astype(str).str.lower()
    pr = d.get("playresult", pd.Series("", index=d.index)).astype(str).str.lower()
    # swing / whiff / contact (hitter-app semantics)
    d["swing"] = ev.fillna(0).gt(0) | pc.str.contains("swinging|foul", na=False) | pc.eq("inplay") | pr.isin(
        ["single", "double", "triple", "homerun", "out", "fielderschoice", "error", "sacrifice"])
    d["whiff"] = pc.eq("strikeswinging")
    d["contact"] = d["swing"] & ~d["whiff"]
    side = pd.to_numeric(d.get("platelocside"), errors="coerce")
    height = pd.to_numeric(d.get("platelocheight"), errors="coerce")
    d["inzone"] = side.between(*_ZONE_SIDE) & height.between(*_ZONE_HEIGHT)

    # xSLG on batted balls
    d["xslg"] = np.nan
    bb = d[ev > 0].copy()
    if not bb.empty:
        X = pd.DataFrame({"launch_speed": ev[ev > 0].values,
                          "launch_angle": ang[ev > 0].values})
        X["interaction"] = X["launch_speed"] * X["launch_angle"]
        booster = _booster("xSLG_model.json")
        d.loc[ev > 0, "xslg"] = booster.predict(xgb.DMatrix(X[["launch_speed", "launch_angle", "interaction"]]))

    # decision value: take→no_swing model, swing→swing model. App negates plate side.
    dz = d.dropna(subset=["platelocside", "platelocheight", "strikes", "balls"]).copy()
    dz["__side"] = -1 * pd.to_numeric(dz["platelocside"], errors="coerce")
    d["decision_rv"] = np.nan
    if not dz.empty:
        feats = ["Platelocside", "Platelocheight", "strikes", "balls"]
        for mask, model_name in [(~dz["swing"], "model_no_swing.json"), (dz["swing"], "model_swing.json")]:
            sub = dz[mask]
            if sub.empty:
                continue
            X = pd.DataFrame({"Platelocside": sub["__side"].values,
                              "Platelocheight": pd.to_numeric(sub["platelocheight"], errors="coerce").values,
                              "strikes": pd.to_numeric(sub["strikes"], errors="coerce").values,
                              "balls": pd.to_numeric(sub["balls"], errors="coerce").values})
            pred = _booster(model_name).predict(xgb.DMatrix(X[feats]))
            d.loc[sub.index, "decision_rv"] = pred
    return d


def _scale_20_80(mean_pred, mu, std) -> float | None:
    if mean_pred is None or pd.isna(mean_pred):
        return None
    if std == 0:
        return 50.0
    return round(float(np.clip(50 + 10 * (mean_pred - mu) / std, 20, 80)), 1)


def aggregate_hitting(scored: pd.DataFrame) -> list[dict]:
    """One dict of schema columns per batter from an xSLG/decision-scored frame."""
    ev = pd.to_numeric(scored.get("exitspeed"), errors="coerce")
    ang = pd.to_numeric(scored.get("angle"), errors="coerce")
    direction = pd.to_numeric(scored.get("direction"), errors="coerce")
    korbb = scored.get("korbb", pd.Series("", index=scored.index)).astype(str).str.lower()
    # at-bat id for PA / K% / F-strike denominators
    ab = (scored.get("date", "").astype(str) + "_" + scored.get("pitcher", "").astype(str) + "_"
          + scored.get("paofinning", "").astype(str) + "_" + scored.get("inning", "").astype(str))
    d = scored.assign(_ev=ev, _ang=ang, _dir=direction, _korbb=korbb, _ab=ab)

    rows = []
    for batter, g in d.groupby(d.get("batter")):
        if not clean_str(batter):
            continue
        n = len(g)
        sw, inz, con = g["swing"], g["inzone"], g["contact"]
        gev, gang = g["_ev"], g["_ang"]
        pa = g["_ab"].nunique()
        side = clean_str(g.get("batterside", pd.Series([None])).dropna().iloc[0]) if g.get(
            "batterside") is not None and g["batterside"].notna().any() else None
        if side and side.lower().startswith("l"):
            pull = (g["_dir"] > 0).sum()
        elif side and side.lower().startswith("r"):
            pull = (g["_dir"] < 0).sum()
        else:
            pull = None
        dv_overall = _scale_20_80(g["decision_rv"].mean(), *_DV["overall"]) if g["decision_rv"].notna().any() else None
        row = {
            "__name__": clean_str(batter),
            "team": clean_str(g.get("batterteam", pd.Series([None])).iloc[0]) if "batterteam" in g else None,
            "level": clean_str(g.get("level", pd.Series([None])).iloc[0]) if "level" in g else None,
            "pa": int(pa),
            "pitches": int(n),
            "avg_ev": round(float(gev.mean()), 1) if gev.notna().any() else None,
            "ev90": round(float(gev.quantile(0.90)), 1) if gev.notna().any() else None,
            "xslg": round(float(g.loc[sw, "xslg"].mean()), 3) if g.loc[sw, "xslg"].notna().any() else None,
            "decision_value": dv_overall,
            "hardhit_pct": _rate((gev > 90).sum(), n),
            "barrel_pct": _rate(((gev >= 99) & gang.between(25, 31)).sum(), n),
            "gb_pct": _rate((gang < 0).sum(), n),
            "pull_pct": _rate(pull, n) if pull is not None else None,
            "k_pct": _rate(g["_korbb"].eq("strikeout").sum(), pa),
            "chase_pct": _rate((~inz & sw).sum(), (~inz).sum()),
            "zcon_pct": _rate((inz & sw & con).sum(), (inz & sw).sum()),
            "swstr_pct": _rate((sw & ~con).sum(), n),
        }
        rows.append(row)
    return rows


# ── DB upsert ─────────────────────────────────────────────────────────────────
def _upsert(con, table, rows, resolver, season, create_missing):
    from .db import PlayerIndex, now_iso
    idx = PlayerIndex(con)
    matched = created = written = 0
    for r in rows:
        name = r.pop("__name__", None)
        if not name:
            continue
        team = r.get("team")
        cand = resolver.resolve(name, team)
        if cand:
            pid = cand.player_id; matched += 1
        elif create_missing:
            pid, _ = idx.get_or_create(full=name, defaults={"current_status": None})
            created += 1
        else:
            continue
        srow = {"player_id": pid, "season": season, "source": "trackman",
                "source_file": getattr(_upsert, "source_file", None),
                "observed_at": now_iso(),
                **{k: v for k, v in r.items() if v is not None}}
        cols = list(srow)
        ph = ", ".join("?" for _ in cols)
        con.execute(f"INSERT OR REPLACE INTO {table} ({', '.join(cols)}) VALUES ({ph})",
                    [srow[c] for c in cols])
        written += 1
    return matched, created, written


def enrich_from_trackman(con: sqlite3.Connection, config: dict) -> dict:
    cfg = (config.get("enrichment", {}) or {}).get("trackman", {}) or {}
    if not cfg.get("enabled"):
        return {"skipped": "trackman disabled in config"}

    csv_path = cfg.get("csv") or str(ROOT / "pitcher-app" / "data" / "raw" / "usd_baseball_TM_master_file.csv")
    season = str(cfg.get("season", "2025"))
    create_missing = bool(cfg.get("create_missing", True))
    hit_models = Path(cfg.get("hitter_models") or (ROOT / "hitter-app" / "models"))
    pit_models = Path(cfg.get("pitcher_models") or (ROOT / "pitcher-app" / "models"))
    do_hit = cfg.get("hitting", True)
    do_pit = cfg.get("pitching", True)

    df = load_trackman(csv_path)
    resolver = Resolver(con)
    out = {"csv": str(csv_path), "pitches": len(df)}
    _upsert.source_file = Path(csv_path).name

    if do_pit:
        try:
            scored = score_pitching(df, pit_models)
            m, c, w = _upsert(con, "stats_pitching", aggregate_pitching(scored), resolver, season, create_missing)
            out["pitching"] = {"pitchers": w, "matched": m, "created": c}
        except RuntimeError as e:
            out["pitching"] = f"skipped: {e}"
    if do_hit:
        try:
            scored = score_hitting(df, hit_models)
            m, c, w = _upsert(con, "stats_hitting", aggregate_hitting(scored), resolver, season, create_missing)
            out["hitting"] = {"hitters": w, "matched": m, "created": c}
        except RuntimeError as e:
            out["hitting"] = f"skipped: {e}"
    con.commit()
    return out
