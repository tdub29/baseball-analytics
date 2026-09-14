# Model provenance

Ten trained artifacts ship with this repo. They stay next to the app that loads them
(`apps/hitter/models/`, `apps/pitcher/models/`) because both Streamlit apps resolve them by
relative path; moving them to a central `models/` tree would buy tidiness and cost a working
clone. This file is the index instead.

Every row below was traced by grepping the committed notebooks for the artifact filename, so
"trained in" is what the notebook actually writes, not a guess.

## Pitcher models, in `apps/pitcher/models/`

| Artifact | What it predicts | Trained in |
|---|---|---|
| `NCAA_STUFF_PLUS_24.joblib` | Stuff+ on the 2024 NCAA TrackMan season | `research/notebooks/ncaa/NCAA_Stuffplus.ipynb` (also consumed by `ideallocations`, `effectivevelo`) |
| `NCAA_STUFF_PLUS_ALL.joblib` | Stuff+ across all available NCAA seasons | `research/notebooks/ncaa/NCAA_Stuffplus.ipynb` |
| `NCAA_WHIFF.joblib` | Whiff probability per pitch, NCAA | `research/notebooks/ncaa/NCAA_WHIFF.ipynb` |
| `whiff_model_grouped_training.joblib` | Whiff probability, grouped-by-pitcher training split | `research/notebooks/ncaa/NCAA_WHIFF.ipynb` (`joblib.dump(group_model, ...)`) |
| `rv_with_plateloc.joblib` | Run value conditioned on plate location | `research/notebooks/ncaa/ideallocations.ipynb` |
| `lgbm_model_2020_2023.joblib` | LightGBM pitch outcome, 2020-2023 | `research/notebooks/mlb/baseballmodels.ipynb` |
| `best_xgboost_model.json` | Best-of-sweep XGBoost pitch model | `research/notebooks/mlb/armangle.ipynb`, used by `Post_Game_Report_Generator.ipynb` |

## Hitter models, in `apps/hitter/models/`

| Artifact | What it predicts | Trained in |
|---|---|---|
| `xSLG_model.json` | Expected slugging on contact | `research/notebooks/mlb/baseballmodels.ipynb` |
| `model_swing.json` | Run value given the batter swung | `research/notebooks/mlb/baseballmodels.ipynb` |
| `model_no_swing.json` | Run value given the batter took | `research/notebooks/mlb/baseballmodels.ipynb` |

`app_trumedia_integration.ipynb` and `Trumediadev.ipynb` load several of these rather than
training them; they are the integration layer, not the training run.

## Reading the two-level split

The Stuff+, whiff and plate-location models are trained on NCAA TrackMan. The xSLG and
swing-decision models come out of the MLB Statcast notebooks and are applied to NCAA TrackMan in
the hitter app. That transfer is the point of the repo: the same pitch-level method runs at both
levels, and the MLB half is where it gets validated against far more data.

## What is missing, stated rather than inferred

No serialized artifact ships for the MLB-only research (`3d_wOBA`, `armangle` beyond the XGBoost
dump, `predicting_shoulder_coord`, `Pitcher_scouting_report`). Those notebooks fit models inline
and were never dumped, so the notebook is the artifact. Retraining requires the Statcast pull the
notebook opens with.
