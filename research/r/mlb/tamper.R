# Outcome scramble for the leakage tamper test (leakage_tamper.R). Every outcome dated on or after D
# is shuffled among rows dated on or after D; who batted, pitched, where and when stays. A model whose
# inputs are as of the game must give bit-identical features and predictions for games dated up to D.
#
# Fixed seeds and the load order of retro_pa() / retro_games() make the build, matchup_model.R and
# der_gap() scramble the same rows the same way. The caller's RNG state is restored.

TAMPER_SEED <- 20261006L

shuffle_from <- function(x, D, cols, seed) {          # permute `cols` jointly among rows with Date >= D (in place)
  if (is.null(x)) return(NULL)
  i <- which(x$Date >= D)
  if (!length(i)) return(x)
  old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv())
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, globalenv()))
  set.seed(seed)
  j <- i[sample.int(length(i))]
  x[i, (cols) := x[j, cols, with = FALSE]]
  x
}

#' P: outcome, batted-ball type, runs on the play and outs before it. G: final score.
tamper_pg <- function(P, G, D) {
  list(P = shuffle_from(P, D, c("outcome", "bb_type", "runs", "outs_pre"), TAMPER_SEED),
       G = shuffle_from(G, D, c("vruns", "hruns"), TAMPER_SEED + 1L))
}

#' Reached-on-error count per fielding team-game (der_gap()), shuffled among team-games dated >= D.
tamper_roe <- function(roe, G, D) {
  roe[, Date := G$Date[match(gid, G$gid)]]
  shuffle_from(roe, D, "roe", TAMPER_SEED + 2L)[, Date := NULL][]
}
