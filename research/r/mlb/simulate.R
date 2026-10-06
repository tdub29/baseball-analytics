#!/usr/bin/env Rscript
# Plate-appearance game simulator and its validation (SIM-PLAN.md). Validation seasons only.
#
#   Rscript research/r/mlb/simulate.R run 2016 2017   # data/mlb/sim/sim-<season>.rds (needs bullpen_model.R inputs)
#   Rscript research/r/mlb/simulate.R evaluate        # results/sim-validation.md
#
# Monte Carlo in lockstep: every lane (one game, one simulation) plays one plate appearance per step,
# vectorized over all lanes of a batch. N_SIM simulations per game in two halves, so the Monte Carlo
# error can be measured. Per-game outputs stay in data/ (never committed).
#
# The information used here was obtained free of charge from and is copyrighted by Retrosheet.

suppressPackageStartupMessages(library(data.table))
SRC <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(SRC) || SRC == "") SRC <- "research/r/mlb"
for (f in c("windows.R", "retro.R")) source(file.path(SRC, f))
OUT <- "data/mlb/sim"
N_SIM <- as.integer(Sys.getenv("N_SIM", "2000"))   # SIM-PLAN.md it 2: 4,000 halved for runtime
LANES <- as.integer(Sys.getenv("SIM_LANES", "1500000"))
CAP_INN <- 25L
bin <- function(x, br) findInterval(x, br, left.open = TRUE)

#' Simulate games `gsel` (row numbers of I$games) N times each. Returns tallies for those games, in
#' the order of `gsel`; with `track`, also every (lane, batting team, slot, pitcher column) plate appearance.
sim_games <- function(I, gsel, N, seed, track = FALSE) {
  set.seed(seed)
  G <- length(gsel); K <- I$kmax; PM <- K + 2L; nkey <- G * 2L * 9L * PM
  sub3 <- function(a) a[gsel, , , drop = FALSE]
  # outcome thresholds: key = ((g * 2 + b) * 9 + slot) * PM + col, all 0-based; 8 cumulative cuts per key
  pr <- aperm(I$rates[gsel, , , , , drop = FALSE], c(5, 4, 3, 2, 1))
  dim(pr) <- c(8L, nkey)
  thr <- matrix(0, 8L, nkey)
  for (j in 2:8) thr[j, ] <- thr[j - 1L, ] + pr[j - 1L, ]
  thr <- as.vector(thr + rep(0:(nkey - 1L), each = 8L)); rm(pr)
  tr <- I$tables$trans; tr <- tr[order(s_pre, o, -p)]
  k2 <- tr$s_pre * 9L + (tr$o - 1L)
  stopifnot(length(unique(k2)) == 216L)
  thr2 <- k2 + ave(tr$p, k2, FUN = function(p) cumsum(p) - p)
  pt <- I$tables$pitch[order(o, dp)]
  thr3 <- (pt$o - 1L) + ave(pt$p, pt$o, FUN = function(p) cumsum(p) - p)
  pibb <- I$tables$ibb
  hk <- I$hook; ex <- I$exit; br <- I$br; cf <- I$choice$coef
  nPB <- length(br$PB) + 1L; nBB <- length(br$BB) + 1L; nAB <- length(br$AB) + 1L; nRP <- length(br$RP) + 1L
  mPB <- bin(0:300, br$PB); mRP <- bin(0:300, br$RP); mBB <- bin(0:80, br$BB); mAB <- bin(0:80, br$AB)   # bin(x) = bin(ceiling(x)), integer breaks
  ghost <- I$season >= 2020; rule3 <- I$season >= 2020
  sched_g <- I$games$sched[gsel]
  cd <- lapply(I$cand, function(a) if (length(dim(a)) == 3L) sub3(a) else a[gsel, , drop = FALSE])
  flat <- function(a) as.vector(a)                                  # [G, 2, K] -> g + f*G + (k-1)*2G (1-based g)
  base <- flat(cf[["gm"]] * cd$gm + cf[["fin"]] * cd$fin + cf[["lmbf"]] * cd$lmbf + cf[["ss"]] * cd$ss + cf[["p1"]] * cd$p1 +
               cf[["p2"]] * cd$p2 + cf[["p3"]] * cd$p3 + cf[["b2b"]] * cd$b2b + cf[["lds"]] * cd$lds + cf[["n14"]] * cd$n14)
  c_gl <- cf[["gm:lLI"]]; c_fs <- cf[["fin:save9"]]; c_le <- cf[["lmbf:early"]]; c_lb <- cf[["lmbf:blow"]]
  c_se <- cf[["ss:early"]]; c_gb <- cf[["gm:blow"]]; c_sm <- cf[["same"]]; c_s3 <- cf[["share3:late"]]
  gmv <- flat(cd$gm); finv <- flat(cd$fin); lmbfv <- flat(cd$lmbf); ssv <- flat(cd$ss); handv <- flat(cd$handL); effv <- flat(cd$eff)
  ncand <- as.vector(cd$n); full <- as.integer(2^ncand - 1)
  bitk <- as.integer(2^(0:(K - 1)))
  sp_eff <- as.vector(I$starter$eff[gsel, , drop = FALSE]); sp_eff[is.na(sp_eff)] <- 1
  sp_leash <- as.vector(I$starter$leash[gsel, , drop = FALSE]); sp_leash[is.na(sp_leash)] <- mean(I$starter$leash, na.rm = TRUE)
  bsv <- as.vector(sub3(I$batside))                                 # [G, 2, 9]: 0 R, 1 L, 2 switch
  li <- I$li

  # lanes
  gl <- rep(seq_len(G), each = N); L <- length(gl)
  hs <- rep(rep(1:2, each = N %/% 2), G)
  lane_id <- seq_len(L)
  inn <- rep(1L, L); half <- integer(L); st <- integer(L); alive <- rep(TRUE, L)
  sched <- sched_g[gl]
  score <- integer(2 * L); bat <- integer(2 * L); cp <- integer(2 * L); bf <- integer(2 * L)
  pc <- numeric(2 * L); ra <- integer(2 * L); used <- integer(2 * L)
  # tallies: cell indices are collected per step and counted once at the end
  pa_cnt <- numeric(nkey); rec <- list(); rs <- list(); rr_ <- list(); rw <- list(); rwv <- list(); runs_idx <- list()
  rec_starter <- function(i, f) if (length(i)) rs[[length(rs) + 1L]] <<- gl[i] + f * G + pmin(bf[i + f * L], 59L) * 2L * G
  rec_rel <- function(i, f) if (length(i)) {
    k <- cp[i + f * L]
    rr_[[length(rr_) + 1L]] <<- gl[i] + f * G + (k - 1L) * 2L * G + pmin(bf[i + f * L], 15L) * 2L * G * K
  }
  record_app <- function(i, f) {                                    # the fielding team f's current pitcher leaves
    s <- cp[i + f * L] == 0L; r <- cp[i + f * L] > 0L
    rec_starter(i[s], f[s]); rec_rel(i[r], f[r])
  }
  step <- 0L
  while (L > 0) {
    step <- step + 1L
    lane <- seq_len(L)
    bt <- half; ft <- 1L - half
    ib <- lane + bt * L; jf <- lane + ft * L
    # resolve pending changes: the fielding team picks its reliever as it takes the field
    pend <- which(alive & cp[jf] < 0L)
    if (length(pend)) {
      gp <- gl[pend]; fp <- ft[pend]; bp <- bt[pend]; ip <- pend + fp * L
      md <- score[ip] - score[pend + bp * L]
      mgh <- pmax(pmin(score[pend + L] - score[pend], 7L), -7L)
      innc <- pmin(pmax(inn[pend] - sched[pend] + 9L, 1L), 10L)
      lLI <- log(li[((innc - 1L) * 2L + half[pend]) * 360L + st[pend] * 15L + (mgh + 7L) + 1L])
      save9 <- inn[pend] >= sched[pend] & md >= 1L & md <= 3L
      early <- inn[pend] <= 5L; blow <- abs(md) >= 5L; late <- inn[pend] >= sched[pend] - 1L
      sl <- bat[pend + bp * L]
      bsx <- function(s) bsv[gp + bp * G + ((sl + s) %% 9L) * 2L * G]
      b0 <- bsx(0L); b1 <- bsx(1L); b2 <- bsx(2L)
      # every candidate at once (n x nk, column-major); draw one with probability proportional to exp(utility)
      n <- length(pend); gf <- gp + fp * G; nk <- max(ncand[gf]); ks <- rep(seq_len(nk), each = n)
      fi <- gf + (ks - 1L) * 2L * G
      h <- handv[fi]; s0 <- b0 == h
      u <- base[fi] + gmv[fi] * (c_gl * lLI + c_gb * blow) + finv[fi] * (c_fs * save9) + lmbfv[fi] * (c_le * early + c_lb * blow) +
        ssv[fi] * (c_se * early) + c_sm * s0 + (s0 + (b1 == h) + (b2 == h)) * (c_s3 / 3 * late)
      ew <- exp(u) * (ks <= ncand[gf] & bitwAnd(used[ip], bitk[ks]) == 0L)
      dim(ew) <- c(n, nk)
      rr0 <- stats::runif(n) * rowSums(ew); cs <- numeric(n); pick <- 1L
      for (k in seq_len(nk)) { cs <- cs + ew[, k]; pick <- pick + (cs <= rr0) }
      ok <- rowSums(ew) > 0; jj <- ip[ok]
      cp[jj] <- pick[ok]; used[jj] <- bitwOr(used[jj], bitk[pick[ok]]); bf[jj] <- 0L; pc[jj] <- 0; ra[jj] <- 0L
      cp[ip[!ok]] <- 0L                                             # nobody left: cannot happen (changes need a free arm)
    }
    cpf <- cp[jf]; bff <- bf[jf]
    col <- (cpf == 0L) * (bff >= 18L) + (cpf > 0L) * (cpf + 1L)      # starter third pass from his 19th batter
    sl <- bat[ib]
    key <- (((gl - 1L) * 2L + bt) * 9L + sl) * PM + col
    o <- (findInterval(key + stats::runif(L), thr) - 1L) %% 8L + 1L
    o[stats::runif(L) < pibb[st + 1L]] <- 9L
    if (track) rec[[step]] <- data.table(lane = lane_id, g = gl, b = bt, slot = sl, col = col)[alive]
    pa_cnt <- pa_cnt + tabulate(key[alive] + 1L, nkey)
    j <- findInterval(st * 9L + (o - 1L) + stats::runif(L), thr2)
    nst <- tr$s_nxt[j]; rr <- tr$r_tr[j]
    e <- sp_eff[gl + ft * G]; rl <- which(cpf > 0L); e[rl] <- effv[gl[rl] + ft[rl] * G + (cpf[rl] - 1L) * 2L * G]
    pc[jf] <- pc[jf] + pt$dp[findInterval((o - 1L) + stats::runif(L), thr3)] * e
    bf[jf] <- bff + 1L; ra[jf] <- ra[jf] + rr
    score[ib] <- score[ib] + rr
    bat[ib] <- (sl + 1L) %% 9L
    ie <- nst == 24L
    st <- nst; st[ie] <- 0L
    sa <- score[lane]; sh <- score[lane + L]
    walkoff <- half == 1L & inn >= sched & sh > sa
    e_top <- ie & half == 0L; e_bot <- ie & half == 1L & !walkoff
    done <- alive & (walkoff | (e_top & inn >= sched & sh > sa) | (e_bot & inn >= sched & sa > sh) | (e_bot & inn >= CAP_INN))
    # hook and exit hazards for the fielding team's pitcher, games still going
    hz <- which(alive & !done)
    if (length(hz)) {
      f <- ft[hz]; jh <- hz + f * L; c0 <- cp[jh]; b_ <- bf[jh]; p_ <- pc[jh]; r_ <- ra[jh]; e_ <- ie[hz]
      eta <- numeric(length(hz))
      s0 <- c0 == 0L
      if (any(s0)) {
        lsh <- sp_leash[gl[hz[s0]] + f[s0] * G]
        eta[s0] <- hk$eta[mPB[pmin(ceiling(p_[s0]), 300L) + 1L] + 1L + nPB * (e_[s0] + 2L * (mBB[pmin(b_[s0], 80L) + 1L] + nBB * pmin(r_[s0], 8L)))] +
          hk$b_leash * lsh + hk$b_dev * pmax(p_[s0] - lsh, 0)
      }
      r1 <- !s0
      if (any(r1)) {
        lm_ <- lmbfv[gl[hz[r1]] + f[r1] * G + (c0[r1] - 1L) * 2L * G]
        l9 <- as.integer(inn[hz[r1]] >= sched[hz[r1]])
        eta[r1] <- ex$eta[mAB[pmin(b_[r1], 80L) + 1L] + 1L + nAB * (e_[r1] + 2L * (pmin(r_[r1], 4L) + 5L * (mRP[pmin(ceiling(p_[r1]), 300L) + 1L] + nRP * l9)))] +
          ex$b_lmbf * lm_ + ex$b_lmbf_ie * lm_ * e_[r1]
      }
      allow <- used[jh] != full[gl[hz] + f * G]
      if (rule3) allow <- allow & (b_ >= 3L | e_)
      ch <- allow & stats::runif(length(hz)) < stats::plogis(eta)
      if (any(ch)) { record_app(hz[ch], f[ch]); cp[jh[ch]] <- -1L }
    }
    # next half or inning (extra innings start with a runner on second from 2020)
    nt <- e_top & !done
    half[nt] <- 1L; st[nt & ghost & inn > sched] <- 2L
    nb <- e_bot & !done
    inn[nb] <- inn[nb] + 1L; half[nb] <- 0L; st[nb & ghost & inn > sched] <- 2L
    # finished games
    if (any(done)) {
      d <- which(done)
      w <- ifelse(sh[d] > sa[d], 1, ifelse(sa[d] > sh[d], 0, 0.5))
      rwv[[length(rwv) + 1L]] <- w; rw[[length(rw) + 1L]] <- gl[d] + (hs[d] - 1L) * G
      runs_idx[[length(runs_idx) + 1L]] <- gl[d] + (hs[d] - 1L) * G + pmin(sa[d], 30L) * 2L * G + pmin(sh[d], 30L) * 2L * G * 31L
      for (ff in 0:1) { live <- d[cp[d + ff * L] >= 0L]; record_app(live, rep(ff, length(live))) }
      alive[d] <- FALSE
    }
    if (sum(alive) < 0.75 * L) {                                    # compact
      kp <- which(alive); L2 <- length(kp); k2i <- c(kp, kp + L)
      gl <- gl[kp]; hs <- hs[kp]; lane_id <- lane_id[kp]; inn <- inn[kp]; half <- half[kp]; st <- st[kp]; sched <- sched[kp]
      score <- score[k2i]; bat <- bat[k2i]; cp <- cp[k2i]; bf <- bf[k2i]; pc <- pc[k2i]; ra <- ra[k2i]; used <- used[k2i]
      alive <- rep(TRUE, L2); L <- L2
    }
  }
  wi <- unlist(rw)
  list(wins = matrix(vapply(split(unlist(rwv), factor(wi, levels = seq_len(2L * G))), sum, 0), G, 2),
       runs = tabulate(unlist(runs_idx), G * 2L * 31L * 31L), sbf = tabulate(unlist(rs), G * 2L * 60L),
       rbf = tabulate(unlist(rr_), G * 2L * K * 16L), pa = pa_cnt, steps = step, track = if (track) rbindlist(rec) else NULL)
}

run_season <- function(S) {
  I <- readRDS(file.path(OUT, sprintf("inputs-%d.rds", S)))
  G <- nrow(I$games); K <- I$kmax; PM <- K + 2L
  gb <- max(1L, LANES %/% N_SIM); batches <- split(seq_len(G), ceiling(seq_len(G) / gb))
  wins <- matrix(0, G, 2); runs <- array(0L, c(G, 2, 31, 31)); sbf <- array(0L, c(G, 2, 60)); rbf <- array(0L, c(G, 2, K, 16))
  pa <- array(0, c(PM, 9, 2, G)); t0 <- Sys.time()
  for (bi in seq_along(batches)) {
    g <- batches[[bi]]; n <- length(g)
    r <- sim_games(I, g, N_SIM, seed = S * 1000L + bi)
    wins[g, ] <- r$wins; runs[g, , , ] <- array(r$runs, c(n, 2, 31, 31)); sbf[g, , ] <- array(r$sbf, c(n, 2, 60))
    rbf[g, , , ] <- array(r$rbf, c(n, 2, K, 16)); pa[, , , g] <- array(r$pa, c(PM, 9, 2, n))
    message(S, " batch ", bi, "/", length(batches), " steps ", r$steps, ", ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min")
  }
  out <- list(season = S, N = N_SIM, games = I$games, wins = wins, runs = runs, sbf = sbf, rbf = rbf, pa = pa,
              cand = I$cand$pitcher, starter = I$starter, batter = I$batter)
  saveRDS(out, file.path(OUT, sprintf("sim-%d.rds", S)))
}

# --- evaluation ---------------------------------------------------------------------------------------

#' The totals study's T2 (TOTALS-PLAN.md, totals_study.R validation mode), reproduced walk-forward on the
#' frozen v2 features: per-side negative binomial on log expected runs, environment, umpire and as-of
#' league run level, weekly fits weighted by a 365-day half-life. Returns per-game means and theta.
t2_reproduce <- function() {
  FEAT <- "data/mlb/matchup/features.rds"
  stopifnot(unname(tools::md5sum(FEAT)) == "67b60417d85f10baa823bc4f5ca9922f")   # the file totals-validation.md used
  F <- readRDS(FEAT)[season <= 2022]
  gi <- rbindlist(lapply(2015:2022, function(s) fread(retro_file(s, "gameinfo"), select = c("gid", "date", "gametype", "innings", "sky", "vruns", "hruns"), showProgress = FALSE)))
  F <- merge(F, gi[gametype == "regular", .(gid, innings, sky)], by = "gid", all.x = TRUE)
  F[is.na(innings), innings := 9L]
  P <- outcome_matrix(rbindlist(lapply(2015:2022, retro_pa)))
  tg <- P[season <= 2016, c(lapply(.SD, sum), list(R = sum(runs))), by = .(gid, batteam), .SDcols = OUT8]
  rv_fit <- stats::lm(stats::reformulate(OUT8[OUT8 != "out_ip"], "R"), tg)
  rv <- c(stats::coef(rv_fit)[OUT8[OUT8 != "out_ip"]], out_ip = 0)
  xr <- function(side) stats::coef(rv_fit)[[1]] + Reduce(`+`, lapply(c("sp12", "sp3", "pen"), function(p)
    as.numeric(as.matrix(F[, paste0(p, "_", OUT8, "_", side), with = FALSE]) %*% rv[OUT8])))
  F[, xr_h := xr("home")][, xr_a := xr("away")]
  F <- merge(F, P[, .(maxinn = max(inning)), by = gid], by = "gid", all.x = TRUE)
  F <- F[is.na(maxinn) | maxinn >= innings]
  day <- P[, .(k = sum(k), ubb = sum(ubb), n = .N), by = Date][order(Date)]
  den <- decay_sum(day$Date, day$n, day$Date, 30)
  day[, `:=`(lk = decay_sum(Date, k, Date, 30) / den, lb = decay_sum(Date, ubb, Date, 30) / den)]
  P[, `:=`(rk = k - day$lk[match(Date, day$Date)], rb = ubb - day$lb[match(Date, day$Date)])]
  U <- P[is.finite(rk) & !is.na(umphome) & umphome != "", .(rk = sum(rk), rb = sum(rb), n = .N), by = .(entity = umphome, Date, season)]
  U[, t := 0]
  us <- asof_decay(as.data.frame(U), data.frame(entity = F$umphome, Date = F$Date, season = F$season, t = 0), c("rk", "rb", "n"), h = Inf, c = 0.75)
  F[, ump_k := 100 * us[, "rk"] / (us[, "n"] + 4000)][, ump_bb := 100 * us[, "rb"] / (us[, "n"] + 4000)]
  rm(P, U); invisible(gc())
  F[, dome := as.integer(!is.na(sky) & sky == "dome")]
  F[, temp_c := fifelse(dome == 1 | is.na(temp) | temp < 25 | temp > 115, 0, temp - 72)]
  spd <- fifelse(is.na(F$windspeed) | F$windspeed < 0, 0, F$windspeed)
  F[, wind_out := fifelse(dome == 0 & winddir %in% c("tocf", "tolf", "torf"), spd, 0)]
  F[, wind_in := fifelse(dome == 0 & winddir %in% c("fromcf", "fromlf", "fromrf"), spd, 0)]
  F[, `:=`(total = hruns + vruns, off = log(innings / 9))]
  lday <- gi[gametype == "regular", .(runs = sum(vruns + hruns), n9 = sum(fifelse(is.na(innings), 1, innings / 9))),
             by = .(Date = as.Date(as.character(date), "%Y%m%d"))][order(Date)]
  F[, lenv := log(decay_sum(lday$Date, lday$runs, Date, 15) / decay_sum(lday$Date, lday$n9, Date, 15) / 9)]
  setorder(F, Date, gid)
  D <- as.data.frame(F); n <- nrow(D)
  S2 <- rbind(transform(D, runs = hruns, lxr = log(xr_h), home = 1), transform(D, runs = vruns, lxr = log(xr_a), home = 0))
  blk <- as.Date(cut(S2$Date, "week")); bl <- sort(unique(blk[S2$season %in% 2017:2022]))
  mu <- th <- rep(NA_real_, nrow(S2))
  form <- runs ~ lxr + home + temp_c + wind_out + wind_in + dome + ump_k + ump_bb + lenv + offset(off)
  for (j in seq_along(bl)) {
    tr <- S2[S2$Date < bl[j], ]; tr$w_ <- 0.5^(as.numeric(bl[j] - tr$Date) / 365)
    m <- suppressWarnings(MASS::glm.nb(form, data = tr, weights = w_))
    i <- which(blk == bl[j] & S2$season %in% 2017:2022)
    mu[i] <- stats::predict(m, S2[i, ], type = "response"); th[i] <- m$theta
  }
  data.table(gid = D$gid, season = D$season, hometeam = D$hometeam, total = D$total, mh = mu[1:n], ma = mu[n + 1:n], th = th[1:n])
}

evaluate <- function() {
  local({ tmp <- tempfile(fileext = ".R")
    writeLines(system2("git", c("-C", SRC, "show", "4e47746:./matchup.R"), stdout = TRUE), tmp); source(tmp) })
  SIMS <- lapply(2016:2022, function(S) readRDS(file.path(OUT, sprintf("sim-%d.rds", S))))
  N <- SIMS[[1]]$N; K <- dim(SIMS[[1]]$rbf)[3]
  act <- readRDS(file.path(OUT, "actual.rds"))
  ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
  clampN <- function(p, n) pmin(pmax(p, 0.5 / n), 1 - 0.5 / n)
  cboot <- function(d, cl, B = 2000) { by <- tapply(d, cl, sum); nn <- tapply(d, cl, length); set.seed(20261005)
    b <- replicate(B, { k <- sample(length(by), replace = TRUE); sum(by[k]) / sum(nn[k]) })
    c(est = mean(d), lo = unname(stats::quantile(b, 0.025)), hi = unname(stats::quantile(b, 0.975))) }
  fmt <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
  ci <- function(z, d = 4) sprintf("%s [%s, %s]", fmt(z[["est"]], d), fmt(z[["lo"]], d), fmt(z[["hi"]], d))
  row <- function(x) paste0("| ", paste(x, collapse = " | "), " |")
  tab <- function(dt, d = 4) c(row(names(dt)), paste0("|", strrep(" --- |", ncol(dt))),
    apply(dt, 1, function(r) row(vapply(r, function(v) { z <- suppressWarnings(as.numeric(v)); if (!is.na(z) && grepl("[.]", v)) fmt(z, d) else trimws(v) }, ""))))

  # --- per-game summaries ---------------------------------------------------------------------------
  GM <- rbindlist(lapply(SIMS, function(s) {
    g <- copy(s$games); rr <- s$runs
    g[, `:=`(w1 = s$wins[, 1], w2 = s$wins[, 2])]
    Ja <- apply(rr, c(1, 3), sum); Jh <- apply(rr, c(1, 4), sum)
    g[, `:=`(mu_a = as.vector(Ja %*% 0:30) / s$N, mu_h = as.vector(Jh %*% 0:30) / s$N)]
    g[, pa_sp := apply(s$pa[1:2, , , , drop = FALSE], 4, sum) / apply(s$pa, 4, sum)]
    g[, rel_used := apply(s$rbf, 1, sum) / (2 * s$N)]
    g
  }))
  GM[, `:=`(p = (w1 + w2) / N, y = as.integer(hruns > vruns))]
  ag <- act$app[, .(rel = sum(!starter & bf >= 1), bf_sp = sum(bf[starter]), bf = sum(bf)), by = .(gid, team)][
    , .(rel_act = mean(rel), pa_sp_act = sum(bf_sp) / sum(bf)), by = gid]
  GM <- merge(GM, ag, by = "gid", all.x = TRUE)
  diag <- GM[season >= 2017, .(games = .N, runs_sim = mean(mu_a + mu_h), runs_act = mean(vruns + hruns), p_home_sim = mean(p),
                               home_win_act = mean(y[hruns != vruns]), sp_share_sim = mean(pa_sp), sp_share_act = mean(pa_sp_act, na.rm = TRUE),
                               relievers_sim = mean(rel_used), relievers_act = mean(rel_act, na.rm = TRUE)), by = season][order(season)]

  # --- bullpen forecast --------------------------------------------------------------------------------
  BP <- rbindlist(lapply(SIMS, function(s) {
    if (s$season < 2017) return(NULL)
    G <- nrow(s$games)
    ix <- CJ(k = 1:K, f = 1:2, g = 1:G)[, .(g, f, k)]
    m <- matrix(s$rbf, G * 2 * K, 16)                                # rows: g + (f-1) G + (k-1) 2G
    r <- ix$g + (ix$f - 1L) * G + (ix$k - 1L) * 2L * G
    mb <- m[r, 2:16, drop = FALSE]; colnames(mb) <- paste0("b", 1:15)
    cbind(data.table(gid = s$games$gid[ix$g], season = s$season, team = ifelse(ix$f == 2L, s$games$hometeam[ix$g], s$games$visteam[ix$g]),
                     k = ix$k, pitcher = as.vector(s$cand)[r], p = rowSums(m[r, , drop = FALSE]) / s$N,
                     ebf = as.vector(m[r, , drop = FALSE] %*% 0:15) / s$N), as.data.table(mb))[!is.na(pitcher)]
  }))
  rel_act <- act$app[starter == FALSE & bf >= 1, .(gid, team, pitcher, bf_act = bf)]
  BP <- merge(BP, rel_act, by = c("gid", "team", "pitcher"), all.x = TRUE)
  BP[, `:=`(pitched = as.integer(!is.na(bf_act)), bf_act = fifelse(is.na(bf_act), 0L, bf_act))]
  BP <- merge(BP, act$cand[, .(gid, team, pitcher, n_rel)], by = c("gid", "team", "pitcher"))
  BP <- merge(BP, act$team_games, by = c("gid", "team"))
  BP[, p_naive := pmin(pmax(n_rel / pmax(pmin(18L, kprev), 1L), 0.005), 0.95)]
  cover <- merge(rel_act[gid %in% unique(BP$gid)], BP[, .(gid, team, pitcher, listed = TRUE)], by = c("gid", "team", "pitcher"), all.x = TRUE)[, mean(!is.na(listed))]
  bp_ll <- BP[, .(candidates = .N, pitched_rate = mean(pitched), sim = mean(ll(clampN(p, N), pitched)), naive = mean(ll(p_naive, pitched))), by = .(season = as.character(season))][order(season)]
  bp_ll <- rbind(bp_ll, BP[, .(season = "pooled", candidates = .N, pitched_rate = mean(pitched), sim = mean(ll(clampN(p, N), pitched)), naive = mean(ll(p_naive, pitched)))])
  bp_gap <- cboot(ll(BP$p_naive, BP$pitched) - ll(clampN(BP$p, N), BP$pitched), paste(BP$team, BP$season))
  BP[, dec := cut(p, unique(stats::quantile(p, seq(0, 1, 0.1))), include.lowest = TRUE, labels = FALSE)]
  bp_cal <- BP[, .(n = .N, mean_sim = mean(p), observed = mean(pitched), ebf_sim = mean(ebf), bf_obs = mean(bf_act)), by = dec][order(dec)]
  # batters faced in bins 0..8, 9+: simulated (smoothed) vs naive (pitched rate times the prior seasons' relief distribution)
  relq <- act$app[starter == FALSE & bf >= 1, .(season, bb = pmin(bf, 9L))]
  BP[, bb := pmin(bf_act, 9L)]
  cnt <- as.matrix(BP[, paste0("b", 1:15), with = FALSE])
  pm <- cbind(N - rowSums(cnt), cnt[, 1:8], rowSums(cnt[, 9:15, drop = FALSE]))
  BP[, ls_sim := log(((pm + 0.5) / (N + 5))[cbind(seq_len(.N), bb + 1L)])]
  rm(cnt, pm)
  BP[, ls_naive := NA_real_]
  for (S in 2017:2022) {
    dist <- tabulate(relq[season < S]$bb, 9) / nrow(relq[season < S])
    BP[season == S, ls_naive := log(ifelse(bb == 0L, 1 - p_naive, p_naive * dist[pmax(bb, 1L)]))]
  }
  bf_tab <- rbind(BP[, .(sim = mean(ls_sim), naive = mean(ls_naive), mae_sim = mean(abs(ebf - bf_act))), by = .(season = as.character(season))][order(season)],
                  BP[, .(season = "pooled", sim = mean(ls_sim), naive = mean(ls_naive), mae_sim = mean(abs(ebf - bf_act)))])
  bf_gap <- cboot(BP$ls_sim - BP$ls_naive, paste(BP$team, BP$season))

  # --- starter hook ----------------------------------------------------------------------------------
  HK <- rbindlist(lapply(SIMS, function(s) {
    if (s$season < 2017) return(NULL)
    G <- nrow(s$games); m <- matrix(s$sbf, G * 2, 60); colnames(m) <- paste0("V", 1:60)
    cbind(data.table(gid = rep(s$games$gid, 2), season = s$season, team = c(s$games$visteam, s$games$hometeam)), as.data.table(m))
  }))
  HK <- merge(HK, act$starters, by = c("gid", "team"))
  cnt <- as.matrix(HK[, paste0("V", 1:60), with = FALSE]); tot <- rowSums(cnt)
  HK[, mean_sim := as.vector(cnt %*% 0:59) / tot]
  HK[, ls_sim := log((cnt[cbind(seq_len(.N), pmin(bf, 59L) + 1L)] + 0.5) / (tot + 30))]
  cdf <- t(apply(cnt, 1, cumsum)) / tot
  HK[, `:=`(q10 = max.col(cdf >= 0.1, "first") - 1L, q90 = max.col(cdf >= 0.9, "first") - 1L)]
  HK[, ls_base := NA_real_]
  for (S in 2017:2022) {
    sdv <- act$starters[as.integer(substr(gid, 4, 7)) < S, stats::sd(bf - exp_bf)]
    HK[season == S, ls_base := log(pmax(stats::pnorm(bf + 0.5, exp_bf, sdv) - stats::pnorm(bf - 0.5, exp_bf, sdv), 1e-6))]
  }
  hk_tab <- rbind(HK[, .(starts = .N, actual_bf = mean(bf), sim_mean = mean(mean_sim), build_exp_bf = mean(exp_bf), ls_sim = mean(ls_sim), ls_normal = mean(ls_base),
                         mae_sim = mean(abs(mean_sim - bf)), mae_build = mean(abs(exp_bf - bf)), cover80 = mean(bf >= q10 & bf <= q90)), by = .(season = as.character(season))][order(season)],
                  HK[, .(season = "pooled", starts = .N, actual_bf = mean(bf), sim_mean = mean(mean_sim), build_exp_bf = mean(exp_bf), ls_sim = mean(ls_sim), ls_normal = mean(ls_base),
                         mae_sim = mean(abs(mean_sim - bf)), mae_build = mean(abs(exp_bf - bf)), cover80 = mean(bf >= q10 & bf <= q90))])
  hk_gap <- cboot(HK$ls_sim - HK$ls_base, paste(HK$team, HK$season))
  rm(cnt, cdf); HK[, paste0("V", 1:60) := NULL]

  # --- value: win probability ------------------------------------------------------------------------
  G15 <- rbindlist(lapply(2015:2022, retro_games))
  bnd <- as.data.frame(G15[, .(start = min(Date), end = max(Date)), by = season])
  tm <- rbind(G15[, .(entity = hometeam, Date, season, margin = hruns - vruns)], G15[, .(entity = visteam, Date, season, margin = vruns - hruns)])
  tm[, t := season_day(Date, season, bnd)][, n := 1]
  V <- GM[hruns != vruns]
  setorder(V, Date, gid)
  qv <- function(team) data.frame(entity = team, Date = V$Date, season = V$season, t = season_day(V$Date, V$season, bnd))
  rdx <- function(team) { s <- asof_decay(as.data.frame(tm), qv(team), c("margin", "n"), h = 120, c = 0.75); s[, 1] / (s[, 2] + 5) }
  V[, drd := rdx(hometeam) - rdx(visteam)]
  V <- merge(V, readRDS("data/mlb/matchup/context.rds")[season <= 2022, .(gid, dder)], by = "gid", all.x = TRUE)
  V[is.na(dder), dder := 0]
  V[, `:=`(p1 = clampN(w1 / (N / 2), N / 2), p2 = clampN(w2 / (N / 2), N / 2), pf = clampN(p, N))]
  V[, lsim := stats::qlogis(pf)]
  pv2 <- fread("data/mlb/matchup/predictions-v2-validation.csv",            # no odds column is read
               select = c("gid", "season", "M5_plus_defense", "ENS", "E_recency", "C_incumbent"))[season <= 2022]
  V <- merge(V, pv2[, .(gid, M5 = M5_plus_defense, ENS, E_recency, C_incumbent)], by = "gid", all.x = TRUE)
  setorder(V, Date, gid)
  walk <- function(df, form, seasons, need = NULL) {
    blk <- as.Date(cut(df$Date, "week")); p <- rep(NA_real_, nrow(df)); last <- NULL
    for (b in sort(unique(blk[df$season %in% seasons]))) {
      i <- which(blk == b & df$season %in% seasons)
      tr <- df[df$Date < b, ]; if (!is.null(need)) tr <- tr[!is.na(tr[[need]]), ]
      last <- stats::glm(form, stats::binomial, tr); p[i] <- stats::predict(last, df[i, ], type = "response")
    }
    attr(p, "coef") <- stats::coef(last); p
  }
  rc <- walk(V, y ~ lsim + drd + dder, 2017:2022); V[, recal := as.numeric(rc)]
  sk <- walk(V, y ~ stats::qlogis(M5) + lsim, 2018:2022, need = "M5"); V[, stack := as.numeric(sk)]
  CMP <- V[!is.na(M5) & !is.na(ENS) & !is.na(E_recency) & !is.na(C_incumbent) & season %in% c(2017:2019, 2021:2022)]
  CMP[, `:=`(l_m5 = ll(M5, y), l_ens = ll(ENS, y), l_raw = ll(pf, y), l_recal = ll(recal, y), l_stack = ll(stack, y),
             l_raw_inf = 2 * ll(pf, y) - (ll(p1, y) + ll(p2, y)) / 2)]
  vsum <- function(x, lab) x[, .(season = lab, games = .N, M5 = mean(l_m5), ENS = mean(l_ens), sim_raw = mean(l_raw), sim_raw_inf = mean(l_raw_inf),
                                 sim_recal = mean(l_recal), stack = if (all(season >= 2018)) mean(l_stack) else NA_real_)]
  vt <- rbind(rbindlist(lapply(sort(unique(CMP$season)), function(s) vsum(CMP[season == s], as.character(s)))),
              vsum(CMP, "pooled"), vsum(CMP[season >= 2018], "pooled 2018-2022"))
  cl <- paste(CMP$hometeam, CMP$season); c18 <- CMP$season >= 2018
  gaps <- list(raw_m5 = cboot(CMP$l_m5 - CMP$l_raw, cl), raw_inf_m5 = cboot(CMP$l_m5 - CMP$l_raw_inf, cl),
               recal_m5 = cboot(CMP$l_m5 - CMP$l_recal, cl), recal_ens = cboot(CMP$l_ens - CMP$l_recal, cl),
               raw_ens = cboot(CMP$l_ens - CMP$l_raw, cl),
               stack_m5 = cboot(CMP$l_m5[c18] - CMP$l_stack[c18], cl[c18]), stack_ens = cboot(CMP$l_ens[c18] - CMP$l_stack[c18], cl[c18]))
  rawcor <- CMP[, stats::cor(stats::qlogis(M5), lsim)]
  v2020 <- V[season == 2020 & !is.na(M5), .(games = .N, M5 = mean(ll(M5, y)), sim_raw = mean(ll(pf, y)), sim_recal = mean(ll(recal, y)))]
  CMP[, dec := cut(pf, unique(stats::quantile(pf, seq(0, 1, 0.1))), include.lowest = TRUE, labels = FALSE)]
  rel_tab <- CMP[, .(games = .N, sim_raw = mean(pf), sim_recal = mean(recal), M5 = mean(M5), home_won = mean(y)), by = dec][order(dec)]

  # --- totals ---------------------------------------------------------------------------------------
  T2 <- t2_reproduce()
  T2 <- T2[season %in% 2017:2022]
  pmf2 <- function(k, mh, ma, th) { out <- 0; for (j in 0:max(k)) out <- out + stats::dnbinom(j, size = th, mu = mh) * suppressWarnings(stats::dnbinom(k - j, size = th, mu = ma)); out }
  T2[, ls_t2 := log(pmf2(total, mh, ma, th))]
  tot_h <- lapply(SIMS[-1], function(s) {                          # total-runs histogram per game and half
    G <- nrow(s$games); rr <- s$runs; tt <- array(0, c(G, 2, 61))
    for (a in 0:30) tt[, , a + 1:31] <- tt[, , a + 1:31] + rr[, , a + 1, ]
    list(gid = s$games$gid, h1 = tt[, 1, ], h2 = tt[, 2, ])
  })
  hg <- unlist(lapply(tot_h, `[[`, "gid")); H1 <- do.call(rbind, lapply(tot_h, `[[`, "h1")); H2 <- do.call(rbind, lapply(tot_h, `[[`, "h2"))
  TS <- T2[gid %in% hg, .(gid, season, hometeam, total, ls_t2)]
  ih <- match(TS$gid, hg)
  c1 <- H1[ih, , drop = FALSE]; c2 <- H2[ih, , drop = FALSE]; cf_ <- c1 + c2; rm(H1, H2, tot_h)
  mu <- as.vector(cf_ %*% 0:60) / N; vv <- as.vector(cf_ %*% (0:60)^2) / N - mu^2
  nbp <- ifelse(vv > mu * 1.0001, stats::dnbinom(TS$total, size = mu^2 / pmax(vv - mu, 1e-9), mu = mu), stats::dpois(TS$total, mu))
  at <- cbind(seq_len(nrow(TS)), pmin(TS$total, 60L) + 1L)
  TS[, `:=`(ls_full = log(0.99 * cf_[at] / N + 0.01 * nbp),
            ls_half = (log(0.99 * c1[at] / (N / 2) + 0.01 * nbp) + log(0.99 * c2[at] / (N / 2) + 0.01 * nbp)) / 2, mu_sim = mu)]
  TS[, ls_inf := 2 * ls_full - ls_half]
  # post-hoc (SIM-PLAN.md it 3): the moment-matched negative binomial alone, and the delta-method finite-N penalty
  TS[, ls_nb := log(nbp)]
  pen_th <- mean((1 - cf_[at] / N) / (2 * pmax(cf_[at], 0.5)))
  rm(c1, c2, cf_)
  t2_check <- T2[, mean(ls_t2)]
  tsum <- function(x, lab) x[, .(season = lab, games = .N, actual = mean(total), sim_mean = mean(mu_sim), T2 = mean(ls_t2), sim = mean(ls_full), sim_inf = mean(ls_inf))]
  tt_tab <- rbind(rbindlist(lapply(sort(unique(TS$season)), function(s) tsum(TS[season == s], as.character(s)))), tsum(TS, "pooled"))
  tgap <- cboot(TS$ls_full - TS$ls_t2, paste(TS$hometeam, TS$season)); tgap_inf <- cboot(TS$ls_inf - TS$ls_t2, paste(TS$hometeam, TS$season))
  tgap_nb <- cboot(TS$ls_nb - TS$ls_t2, paste(TS$hometeam, TS$season))

  # --- matchup probabilities for one game (2022), with exact at-least-once tracking ---------------------
  I22 <- readRDS(file.path(OUT, "inputs-2022.rds"))
  gx <- I22$games[order(Date, gid)][Date == as.Date("2022-08-01")][1]
  NX <- 20000L
  rx <- sim_games(I22, gx$gi, NX, seed = 20220801L, track = TRUE)
  reg <- as.data.table(readRDS("data/mlb/raw/chadwick/register.rds"))[!is.na(key_retro) & key_retro != "", .(key_retro, nm = paste(name_first, name_last))]
  nm <- function(id) { x <- reg$nm[match(id, reg$key_retro)]; ifelse(is.na(x), id, x) }
  rx$track[, pc := fifelse(col <= 1L, 0L, col - 1L)]                # 0 starter, k candidate k
  meet <- merge(unique(rx$track[, .(lane, b, slot, pc)])[, .(p_meet = .N / NX), by = .(b, slot, pc)],
                rx$track[, .(epa = .N / NX), by = .(b, slot, pc)], by = c("b", "slot", "pc"))
  rb22 <- array(rx$rbf, c(1, 2, I22$kmax, 16))[1, , , ]
  sb22 <- array(rx$sbf, c(1, 2, 60))[1, , ]
  ex_lines <- character(0)
  for (fb in 1:0) {                                                 # fielding team: 1 home, 0 away; it faces batting team 1 - fb
    bteam <- 1L - fb; tcode <- if (fb == 1L) gx$hometeam else gx$visteam
    pit <- I22$cand$pitcher[gx$gi, fb + 1L, ]; nc <- I22$cand$n[gx$gi, fb + 1L]
    pp <- rowSums(rb22[fb + 1L, , ]) / NX; ebf <- as.vector(rb22[fb + 1L, , ] %*% 0:15) / NX
    top <- order(-pp)[seq_len(min(6, nc))]
    bat <- I22$batter[gx$gi, bteam + 1L, ]
    rows <- vapply(top, function(k) {
      m <- meet[b == bteam & pc == k][order(-p_meet)][1:3]
      row(c(nm(pit[k]), fmt(pp[k], 2), fmt(ebf[k], 2), paste(sprintf("%s %s", nm(bat[m$slot + 1L]), fmt(m$p_meet, 2)), collapse = ", ")))
    }, "")
    spm <- meet[b == bteam & pc == 0L][order(slot)]
    ex_lines <- c(ex_lines, "",
      sprintf("**%s pitching** (starter %s: simulated batters faced %s, actual %s). Relievers most likely to pitch:", tcode,
              nm(I22$starter$pitcher[gx$gi, fb + 1L]), fmt(sum(sb22[fb + 1L, ] * 0:59) / NX, 1), act$starters[gid == gx$gid & team == tcode]$bf), "",
      row(c("reliever", "P(pitches)", "E[batters faced]", "most likely hitters faced, P(at least one PA)")), "| --- | --- | --- | --- |", rows, "",
      sprintf("Expected plate appearances against the starter, batting order 1-9: %s.", paste(fmt(spm$epa, 2), collapse = ", ")))
  }
  ex_act <- act$app[gid == gx$gid & starter == FALSE & bf >= 1][, sprintf("%s (%s, %d BF)", nm(pitcher), team, bf)]
  # --- fitted pieces -------------------------------------------------------------------------------
  ch <- I22$choice
  coef_tab <- data.table(term = names(ch$coef), coef = ch$coef, se = ch$se)
  fitinfo <- rbindlist(lapply(2016:2022, function(S) {
    I <- if (S == 2022) I22 else readRDS(file.path(OUT, sprintf("inputs-%d.rds", S)))
    data.table(season = S, choice_events = I$choice$events, choice_kept = I$choice$kept, hook_rows = I$hook$n, hook_dev_expl = I$hook$dev_expl,
               exit_rows = I$exit$n, exit_dev_expl = I$exit$dev_expl)
  }))

  # --- report -----------------------------------------------------------------------------------------
  verdict <- function(z) if (z[["lo"]] > 0) "interval above zero" else if (z[["hi"]] < 0) "interval below zero" else "interval spans zero"
  lines <- c("# Simulator validation (SIM-PLAN.md)", "",
    sprintf("Generated %s by `Rscript research/r/mlb/simulate.R evaluate`. Validation seasons only: Retrosheet 2015-2022, nothing from 2023-2025. N = %d simulations per game (two halves of %d). Per-game outputs stay in `data/mlb/sim/` (not committed).",
            format(Sys.Date()), N, N / 2), "",
    "## Verdict under the charter's rules", "",
    sprintf("- Win probability, adds value over M5: **%s**. Recalibrated (b) %s; stack (c) %s. The rule needs either interval above zero.",
            if (gaps$recal_m5[["lo"]] > 0 || gaps$stack_m5[["lo"]] > 0) "yes" else "no detectable value", ci(gaps$recal_m5, 5), ci(gaps$stack_m5, 5)),
    sprintf("- Win probability, adds value over the ensemble: **%s**. Recalibrated %s; stack %s. An upper bound near zero is sensitive to the cluster definition (SIM-PLAN.md it 3).",
            if (gaps$recal_ens[["lo"]] > 0 || gaps$stack_ens[["lo"]] > 0) "yes" else "no detectable value", ci(gaps$recal_ens, 5), ci(gaps$stack_ens, 5)),
    sprintf("- Totals, beats T2: **%s**. As simulated %s; extrapolated to infinite N %s. The charter does not say which score gates; see the post-hoc checks in section 4.",
            if (tgap[["lo"]] > 0 && tgap_inf[["lo"]] > 0) "yes" else if (tgap[["hi"]] < 0 && tgap_inf[["hi"]] < 0) "no"
            else if (tgap_inf[["lo"]] > 0) sprintf("undetermined at N = %d (raw no, extrapolated yes)", N) else sprintf("no at N = %d", N),
            ci(tgap, 4), ci(tgap_inf, 4)),
    sprintf("- Reported, not gated: bullpen \"pitched\" log loss beats the naive window rate by %s; starter batters faced beats the normal baseline by %s in log score.", ci(bp_gap, 4), ci(hk_gap, 4)), "",
    "## Simulator calibration, 2017-2022", "",
    "Means over games. sp_share = share of a team's plate appearances against the opposing starter; relievers = relievers used per team-game.", "",
    tab(diag, 3), "",
    "## 1. Bullpen usage forecast: did this candidate pitch in this game?", "",
    sprintf("Candidates per team-game: up to %d (pitchers used by the team in its last 18 games before the date, minus the starter and anyone whose most recent appearance before the date was for another team). Coverage: %.1f%% of actual relief appearances were by a listed candidate.", K, 100 * cover), "",
    "Log loss of \"pitched\" (lower is better); naive = the candidate's relief appearances over his team's games in the window.", "",
    tab(bp_ll), "",
    sprintf("Naive minus simulator, per candidate-game (positive = simulator better), team-season cluster bootstrap 95%%: %s.", ci(bp_gap, 4)), "",
    "Calibration by decile of the simulated probability (pooled):", "",
    tab(bp_cal[, .(decile = dec, n, mean_sim, observed, ebf_sim, bf_obs)], 3), "",
    "Batters faced, log score of the actual count in bins 0, 1, ..., 8, 9+ (higher is better; naive = pitched rate times the prior seasons' relief distribution); mae_sim = mean absolute error of the simulated expected batters faced:", "",
    tab(bf_tab), "",
    sprintf("Simulator minus naive log score per candidate-game: %s.", ci(bf_gap, 4)), "",
    "## 2. Starter hook: batters faced", "",
    "Log score of the starter's actual batters faced (higher is better) under the simulated distribution and under a normal around the v2 build's expected batters faced with the prior seasons' residual spread; mean absolute error of each mean; share of starts inside the simulated 10%-90% range.", "",
    tab(hk_tab, 3), "",
    sprintf("Simulated minus normal log score per start: %s.", ci(hk_gap, 4)), "",
    "## 3. Value: win probability vs M5 and the ensemble", "",
    sprintf("%d games (2017-2019, 2021-2022) where M5 and the ensemble exist in `predictions-v2-validation.csv`; ties dropped. Log loss, lower is better. sim_raw = simulated P(home win); sim_raw_inf = per-game split-half extrapolation to infinite N; sim_recal = weekly walk-forward logistic on logit(sim) + run-margin gap + defensive-efficiency gap; stack = weekly walk-forward logistic on logit(M5) + logit(sim), 2018-2022 only.", nrow(CMP)), "",
    tab(vt), "",
    "Paired per-game differences, baseline minus candidate (positive = simulator better), home team-season cluster bootstrap 95%:", "",
    sprintf("- M5 minus sim raw: %s (%s).", ci(gaps$raw_m5, 5), verdict(gaps$raw_m5)),
    sprintf("- M5 minus sim raw, extrapolated to infinite N: %s.", ci(gaps$raw_inf_m5, 5)),
    sprintf("- M5 minus sim recalibrated: %s (%s).", ci(gaps$recal_m5, 5), verdict(gaps$recal_m5)),
    sprintf("- Ensemble minus sim raw: %s; ensemble minus sim recalibrated: %s (%s).", ci(gaps$raw_ens, 5), ci(gaps$recal_ens, 5), verdict(gaps$recal_ens)),
    sprintf("- M5 minus stack (2018-2022): %s (%s); ensemble minus stack: %s (%s).", ci(gaps$stack_m5, 5), verdict(gaps$stack_m5), ci(gaps$stack_ens, 5), verdict(gaps$stack_ens)), "",
    sprintf("Monte Carlo: the expected log-loss penalty of N = %d is about 1 / (2N) = %s; measured, full minus extrapolated: %s. Correlation of logit(M5) and logit(sim): %s. Last recalibration fit: %s. Last stack fit: %s.",
            N, fmt(1 / (2 * N), 5), fmt(mean(CMP$l_raw - CMP$l_raw_inf), 5), fmt(rawcor, 3),
            paste(sprintf("%s %s", names(attr(rc, "coef")), fmt(attr(rc, "coef"), 3)), collapse = ", "),
            paste(sprintf("%s %s", names(attr(sk, "coef")), fmt(attr(sk, "coef"), 3)), collapse = ", ")),
    sprintf("2020 (no ensemble; not in the comparison): %d games, M5 %s, sim raw %s, sim recalibrated %s.", v2020$games, fmt(v2020$M5), fmt(v2020$sim_raw), fmt(v2020$sim_recal)), "",
    "Reliability by decile of sim P(home win):", "",
    tab(rel_tab[, .(decile = dec, games, sim_raw, sim_recal, M5, home_won)], 3), "",
    "## 4. Totals: simulated run distributions vs the totals study's T2", "",
    sprintf("T2 reproduced walk-forward here (frozen v2 features, md5 67b60417...): pooled 2017-2022 log score %s on %d complete games (totals-validation.md: -2.8616 on 13,010). Log score of the actual total, higher is better. Simulated distribution = histogram of total runs mixed 99/1 with a negative binomial matched to its mean and variance; sim_inf = split-half extrapolation to infinite N.",
            fmt(t2_check), nrow(T2)), "",
    tab(tt_tab), "",
    sprintf("Simulator minus T2, per game (positive = simulator better), home team-season cluster bootstrap 95%%: %s (%s); extrapolated: %s.", ci(tgap, 4), verdict(tgap), ci(tgap_inf, 4)), "",
    sprintf("Post-hoc checks on the extrapolation (SIM-PLAN.md it 3, added after this result was seen; they do not change the rule): the delta-method expected finite-N penalty of the histogram, mean of (1 - p) / (2 N p) at the actual total, is %s, against a measured full minus extrapolated %s. The moment-matched negative binomial alone (simulated mean and variance, almost no Monte Carlo error) scores %s; minus T2: %s.",
            fmt(pen_th), fmt(mean(TS$ls_inf - TS$ls_full)), fmt(mean(TS$ls_nb)), ci(tgap_nb, 4)), "",
    "## 5. Matchup probabilities, one game", "",
    sprintf("%s, %s at %s (%s), simulated %d times with every plate appearance tracked. P(home win) %s; actual %d-%d. Probabilities are aggregates of the simulation, no odds.",
            gx$gid, gx$visteam, gx$hometeam, format(gx$Date), NX, fmt(sum(rx$wins[1, ]) / NX, 3), gx$vruns, gx$hruns),
    ex_lines, "", sprintf("Relievers who actually pitched: %s.", paste(ex_act, collapse = "; ")), "",
    "## Fitted pieces", "",
    "Who enters: conditional logit fit on 2019-2021 relief entries (the 2022 fit). Candidate terms, and interactions with the situation at entry: lLI = log LI; save9 = last scheduled inning or later, leading by 1-3; early = inning 5 or before; blow = margin 5+; late = the inning before the last scheduled one or later. p1-p3 = pitches on each of the three previous days, in tens.", "",
    tab(coef_tab, 3), "",
    "Per season: relief entries in the training window and those whose reliever was a listed candidate (the rest are dropped from the fit), and the hazard models' rows and deviance explained.", "",
    tab(fitinfo, 3), "",
    "The information used here was obtained free of charge from and is copyrighted by Retrosheet. Interested parties may contact Retrosheet at \"www.retrosheet.org\".")
  writeLines(lines, file.path(SRC, "results", "sim-validation.md"))
  fwrite(V[, .(gid, Date, season, y, p_sim = pf, recal, stack, M5)], file.path(OUT, "sim-predictions-validation.csv"))
  message("wrote results/sim-validation.md")
}

args <- commandArgs(TRUE)
if (length(args) && args[1] == "evaluate") evaluate()
if (length(args) && args[1] == "run") {
  for (S in as.integer(args[-1])) { stopifnot(S %in% 2016:2022); run_season(S) }
} else if (length(args) && args[1] == "bench") {
  I <- readRDS(file.path(OUT, sprintf("inputs-%d.rds", as.integer(args[2]))))
  n <- as.integer(args[3]); t0 <- Sys.time()
  r <- sim_games(I, 1:min(nrow(I$games), as.integer(args[4])), n, seed = 1)
  message("lanes ", n * min(nrow(I$games), as.integer(args[4])), ": ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s, steps ", r$steps)
  gs <- I$games; idx <- 1:min(nrow(gs), as.integer(args[4])); ng <- length(idx)
  p <- r$wins[, 1] + r$wins[, 2]
  tot <- apply(array(r$runs, c(ng, 2, 31, 31)), 1, function(a) { a <- apply(a, c(2, 3), sum); sum(a * outer(0:30, 0:30, "+")) / sum(a) })
  message("mean P(home) ", round(mean(p / n), 3), "; mean total ", round(mean(tot), 2), " vs actual ", round(mean(gs$vruns[idx] + gs$hruns[idx]), 2))
  sb <- array(r$sbf, c(ng, 2, 60)); message("starter mean BF ", round(sum(sweep(sb, 3, 0:59, "*")) / sum(sb), 2))
  rb <- array(r$rbf, c(ng, 2, I$kmax, 16)); message("relievers per team-game ", round(sum(rb) / (2 * ng * n), 2))
}
