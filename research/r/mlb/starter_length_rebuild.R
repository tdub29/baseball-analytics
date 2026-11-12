#!/usr/bin/env Rscript
# Stage 2 of review queue item 2 (MATCHUP-PLAN.md): rebuild v2's game features with another starter
# length, holding every other input fixed. Reads the frozen v2 slot checkpoint, first proves it
# reproduces features.rds exactly, then swaps exp_bf on 2016-2022 games only; 2023 on keeps v2's value
# and nothing from the spent test is used (parity rebuilds every season only to compare it).
#
#   EXP_BF=oracle Rscript research/r/mlb/starter_length_rebuild.R   # actual batters faced: a ceiling, not a model
#   EXP_BF=cand   Rscript research/r/mlb/starter_length_rebuild.R   # starter_length.R's candidate
#   FEAT_IN=data/mlb/matchup/features-sl-oracle.rds OUT_TAG=-sl-oracle Rscript research/r/mlb/matchup_model.R validation

suppressPackageStartupMessages({ library(data.table) })
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
source(file.path(SRC, "retro.R"))
MODE <- Sys.getenv("EXP_BF", "oracle"); stopifnot(MODE %in% c("oracle", "cand"))
OUT8 <- OUTCOMES

ck <- readRDS("data/mlb/matchup/slots.rds")      # list(L, m_sp, m_pen, mixL, games) saved by matchup_build.R's counts()
L <- ck$L; m_sp <- ck$m_sp; m_pen <- ck$m_pen; mixL <- ck$mixL; games <- ck$games
F0 <- readRDS("data/mlb/matchup/features.rds")

# The tail of counts() in matchup_build.R, with the starter length as an argument.
TEAM_PA <- 38.3; pos <- 1:40
slot_of <- ((pos - 1) %% 9) + 1
w_tot <- pmin(pmax(TEAM_PA - pos + 1, 0), 1)
grp <- split(seq_len(nrow(L)), paste(L$gid, L$side))
build <- function(exp_bf) {
  feat <- t(vapply(grp, function(rows) {
    b <- exp_bf[rows[1]]
    w_sp <- pmin(pmax(b - pos + 1, 0), 1); w_pen <- pmax(w_tot - w_sp, 0)
    o <- rows[match(slot_of, L$slot[rows])]
    ok <- !is.na(o)
    e12 <- ok & pos <= 18; e3 <- ok & pos > 18
    c(colSums(m_sp[o[e12], , drop = FALSE] * w_sp[e12]), colSums(m_sp[o[e3], , drop = FALSE] * w_sp[e3]),
      colSums(m_pen[o[ok], , drop = FALSE] * w_pen[ok]), b, mixL[rows[1]], sum(ok[1:9]))
  }, numeric(3 * length(OUT8) + 3)))
  colnames(feat) <- c(paste0("sp12_", OUT8), paste0("sp3_", OUT8), paste0("pen_", OUT8), "exp_bf", "pen_mixL", "slots")
  fd <- data.table(grp_id = names(grp), feat)
  fd[, c("gid", "side") := tstrsplit(grp_id, " ")]
  wide <- dcast(fd, gid ~ side, value.var = setdiff(names(fd), c("grp_id", "gid", "side")))
  merge(games, wide, by = "gid")
}
v2 <- build(L$exp_bf)
par <- all.equal(v2, F0, check.attributes = FALSE)
if (!isTRUE(par)) stop("checkpoint does not reproduce features.rds: ", paste(par, collapse = "; "))
message("parity: the checkpoint reproduces all ", nrow(F0), " games of features.rds")

if (MODE == "oracle") {
  act <- rbindlist(lapply(2016:2022, retro_pa))[, .(bf = .N), by = .(gid, pitcher)]
  alt <- act$bf[match(paste(L$gid, L$sp), paste(act$gid, act$pitcher))]
} else {
  s <- readRDS("data/mlb/matchup/starter-length.rds")
  s$st[, cand := predict(s$m_cand, s$st)]
  alt <- s$st$cand[match(paste(L$gid, L$opp, L$sp), paste(s$st$gid, s$st$pitteam, s$st$pitcher))]
}
alt[L$season >= 2023] <- NA
miss <- L[, uniqueN(gid[is.na(alt) & season <= 2022])]
message(MODE, ": swapped on ", L[, uniqueN(gid[!is.na(alt)])], " games, ", miss, " 2016-2022 games keep v2's value")
stopifnot(miss == 0)
out <- build(fifelse(is.na(alt), L$exp_bf, alt))
for (a in c("asof_lag", "starter_mode")) if (!is.null(attr(F0, a))) setattr(out, a, attr(F0, a))
f <- sprintf("data/mlb/matchup/features-sl-%s.rds", MODE)
saveRDS(out, f)
message("wrote ", f, ": ", nrow(out), " games")
