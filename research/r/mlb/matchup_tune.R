#!/usr/bin/env Rscript
# Tune the matchup model's shrink constants (K_SET=v4 in matchup.R) on 2017-2019 outcomes only.
#
#   K_GRID=data/mlb/matchup/k-grid.csv FEAT_OUT=data/mlb/matchup/features-v4-switch.rds SWITCH=1 \
#     Rscript research/r/mlb/matchup_build.R      # base features plus <base>-k<id>.rds per grid row
#   K_GRID=data/mlb/matchup/k-grid.csv FEAT_OUT=data/mlb/matchup/features-v4-switch.rds \
#     Rscript research/r/mlb/matchup_tune.R       # writes results/matchup-k-tune<OUT_TAG>.md
#
# The grid is one multiplier per group of k_cfg() (matchup.R) on the reliability study's k. Each
# file is scored by the walk-forward log loss of matchup_model.R's M5 formula on 2017-2019 games:
# the same run values (2015-2016), team run margin, defensive efficiency and weekly refit on every
# earlier game. Games from 2020 on are never read, so no later season enters the choice.
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R", "matchup.R")) source(file.path(SRC, f))
base <- Sys.getenv("FEAT_OUT"); kg <- fread(Sys.getenv("K_GRID")); TAG <- Sys.getenv("OUT_TAG", "")
TUNE <- 2017:2019

# --- inputs of M5 that do not depend on the features, as in matchup_model.R ----------------------
P <- outcome_matrix(rbindlist(lapply(2015:2016, retro_pa)))
tg <- P[, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
rv <- c(stats::coef(stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg))[OUT8[OUT8 != "out_ip"]], out_ip = 0)
G <- rbindlist(lapply(2015:max(TUNE), retro_games))
tm <- rbind(G[, .(team = hometeam, gid, Date, season, margin = hruns - vruns)],
            G[, .(team = visteam, gid, Date, season, margin = vruns - hruns)])
bounds <- as.data.frame(tm[, .(start = min(Date), end = max(Date)), by = season])
tm[, t := season_day(Date, season, bounds)][, n := 1]
ctx <- readRDS("data/mlb/matchup/context.rds")[, .(gid, dder)]

DRD <- NULL
prep <- function(F) {
  F <- as.data.table(F)[season <= max(TUNE) & hruns != vruns]
  runs <- function(p, s) as.numeric(as.matrix(F[, paste0(p, "_", OUT8, "_", s), with = FALSE]) %*% rv[OUT8])
  F[, `:=`(d12 = runs("sp12", "home") - runs("sp12", "away"), d3 = runs("sp3", "home") - runs("sp3", "away"),
           dpen = runs("pen", "home") - runs("pen", "away"))]
  tq <- function(team) data.frame(entity = team, Date = F$Date, season = F$season, t = season_day(F$Date, F$season, bounds))
  rdx <- function(team) { s <- asof_decay(transform(as.data.frame(tm), entity = team), tq(team), c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
  if (is.null(DRD)) DRD <<- F[, .(gid, drd = rdx(hometeam) - rdx(visteam))]   # same games in every file: compute once
  F <- merge(merge(F, DRD, by = "gid"), ctx, by = "gid", all.x = TRUE); F[is.na(dder), dder := 0]
  F[, y := as.integer(hruns > vruns)]
  setorder(F, Date, gid)
  F
}
walk <- function(df, formula, seasons) {                 # matchup_model.R's weekly walk-forward
  df$block <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df))
  for (b in sort(unique(df$block[df$season %in% seasons]))) {
    i <- which(df$block == b & df$season %in% seasons)
    m <- stats::glm(formula, stats::binomial, df[df$Date < b, ])
    p[i] <- stats::predict(m, df[i, ], type = "response")
  }
  p
}
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
score <- function(path) {
  F <- prep(readRDS(path))
  F[, p := walk(F, y ~ d12 + d3 + dpen + drd + dder, TUNE)]
  F[season %in% TUNE, .(gid, season, hometeam, l = ll(p, y))]
}

t0 <- Sys.time(); S0 <- score(base); message("base scored in ", format(Sys.time() - t0))
res <- rbindlist(lapply(seq_len(nrow(kg)), function(i) {
  s <- score(sub("[.]rds$", sprintf("-k%s.rds", kg$id[i]), base))
  stopifnot(identical(s$gid, S0$gid))
  data.table(kg[i], logloss = mean(s$l), d = list(S0$l - s$l))
}))
setorder(res, logloss)
best <- res[1]
paired <- function(d, cl) { by <- tapply(d, cl, sum); n <- tapply(d, cl, length); set.seed(20261004)
  b <- replicate(1000, { i <- sample(length(by), replace = TRUE); sum(by[i]) / sum(n[i]) }); c(mean(d), stats::quantile(b, c(.025, .975))) }
gap <- paired(best$d[[1]], paste(S0$hometeam, S0$season))
ks <- k_cfg(best$m_pit, best$m_bat, best$m_rel_bb)
fmt <- function(x, d = 5) formatC(as.numeric(x), format = "f", digits = d)
lines <- c(sprintf("# Matchup model: shrink-constant tuning%s", TAG), "",
  sprintf("Generated %s. Features: `%s` and %d grid files. Score: walk-forward log loss of M5 on %d-%d (%d games); nothing later is read.",
          format(Sys.Date()), base, nrow(kg), min(TUNE), max(TUNE), nrow(S0)), "",
  "Multipliers scale the reliability study's random-effects k (`k_cfg()` in matchup.R): `m_pit` the pitchers' batted-ball expected outcomes",
  "(starters 157 / 210 / 129 / 106 / 121 for single / double / triple / HR / out in play, relievers 89 / 152 / 97 / 79 / 69), `m_bat` the",
  "hitters' singles 195, triples 534 and outs in play 75, `m_rel_bb` the relievers' walks 134.", "",
  sprintf("Base file (constants as built): %s.", fmt(mean(S0$l))),
  sprintf("Best: m_pit %s, m_bat %s, m_rel_bb %s, log loss %s; base minus best %s [%s, %s] (team-season cluster bootstrap).",
          best$m_pit, best$m_bat, best$m_rel_bb, fmt(best$logloss), fmt(gap[1]), fmt(gap[2]), fmt(gap[3])),
  sprintf("Its constants: hitters %s; starters %s; relievers %s.",
          paste(sprintf("%s %g", c("single", "triple", "out_ip"), sapply(ks$BAT[c("single", "triple", "out_ip")], `[`, 3)), collapse = ", "),
          paste(sprintf("%s %g", names(ks$PIT)[4:8], sapply(ks$PIT[4:8], `[`, 3)), collapse = ", "),
          paste(sprintf("%s %g", c("ubb", names(ks$REL)[4:8]), sapply(ks$REL[c("ubb", names(ks$REL)[4:8])], `[`, 3)), collapse = ", ")), "",
  "| m_pit | m_bat | m_rel_bb | log loss 2017-2019 | base minus this |", "| --- | --- | --- | --- | --- |",
  res[, sprintf("| %s | %s | %s | %s | %s |", m_pit, m_bat, m_rel_bb, fmt(logloss), fmt(mean(S0$l) - logloss))], "",
  "The information used here was obtained free of charge from and is copyrighted by Retrosheet.")
writeLines(lines, file.path(SRC, "results", sprintf("matchup-k-tune%s.md", TAG)))
message(paste(lines[7:9], collapse = "\n"))
