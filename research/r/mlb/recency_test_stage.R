# Test stage of the recency study (RECENCY-PLAN.md test 5), sourced by recency_study.R in test
# mode after the tables are built. Every choice comes from the validation files written before
# any test row existed; 2021-2025 rows are only scored. Lambda is picked on 2017-2019 rows here.

out_csv <- file.path(OUT, "test-components.csv")
if (file.exists(out_csv) && !"--force" %in% commandArgs(TRUE))
  stop(out_csv, " exists: the test is scored once. --force only if 2021-2025 are to become validation.")
picks  <- utils::read.csv(file.path(OUT, "picks-validation.csv"))
curves <- utils::read.csv(file.path(OUT, "decay-curves-validation.csv"))
grid   <- utils::read.csv(file.path(OUT, "grid-validation.csv"))
era    <- function(s) ifelse(s == 2021, "2021", ifelse(s == 2022, "2022", "2023-25"))

errors <- function(ev, q, num, den, w, lg, lambda = 0, r = 7) {
  S <- asof_decay(ev, q, c(num, den), w$h, w$c, lambda, r)
  y <- q[[paste0("y_", num)]] / q[[paste0("y_", den)]]; wt <- q[[paste0("y_", den)]]
  list(e = wt * (y - shrink_rate(S[, 1], S[, 2], w$k, lg))^2, b = wt * (y - lg)^2)
}
by_group <- function(e, b, g) {
  s <- tapply(e, g, sum); s0 <- tapply(b, g, sum)
  stats::setNames(1 - s / s0, names(s))
}

comp_rows <- list(); curve_rows <- list(); lam_rows <- list()
for (p in PLAN) {
  comp <- p[[1]]; rate <- p[[2]]; ev <- p[[3]]; q <- p[[4]]; num <- p[[5]]; den <- p[[6]]
  q <- q[!is.na(q[[paste0("y_", den)]]) & q[[paste0("y_", den)]] > 0, ]
  message(comp, " / ", rate, ": ", sum(q$season %in% TEST), " test predictions")
  lg <- league_target(ev, q, num, den)
  te <- q$season %in% TEST; va <- q$season %in% VALID
  pk <- picks[picks$rate == rate, ][1, ]
  W  <- list(h = pk$h, c = pk$c, k = pk$k)
  g0 <- grid[grid$rate == rate & is.infinite(grid$h) & grid$c == 1, ] |> dplyr::group_by(k) |>
    dplyr::summarise(s = 1 - sum(sse) / sum(sse0), .groups = "drop")
  W0 <- list(h = Inf, c = 1, k = g0$k[which.max(g0$s)])
  a  <- errors(ev, q, num, den, W, lg); a0 <- errors(ev, q, num, den, W0, lg)
  grp <- c(as.character(q$season[te]), era(q$season[te]), rep("pooled", sum(te)))
  rep3 <- function(x) c(x[te], x[te], x[te])
  sk <- by_group(rep3(a$e), rep3(a$b), grp); sk0 <- by_group(rep3(a0$e), rep3(a0$b), grp)
  comp_rows[[rate]] <- data.frame(component = comp, rate = rate, group = names(sk), h = W$h, c = W$c,
                                  k = W$k, skill = sk, skill_no_decay = sk0[names(sk)], row.names = NULL)
  # the decay curve: each h at the (c, k) validation chose for it
  cv <- curves[curves$rate == rate, ]
  for (i in seq_len(nrow(cv))) {
    e <- errors(ev, q, num, den, list(h = cv$h[i], c = cv$c[i], k = cv$k[i]), lg)
    s <- by_group(rep3(e$e), rep3(e$b), grp)
    curve_rows[[paste(rate, i)]] <- data.frame(component = comp, rate = rate, h = cv$h[i], c = cv$c[i],
                                               k = cv$k[i], group = names(s), skill = s, row.names = NULL)
  }
  # lambda: picked on validation rows at the frozen (h, c), scored on test rows
  best <- NULL
  for (i in seq_len(nrow(LAMBDA))) for (k in W$k * 2^(-2:2)) {
    e <- errors(ev, q, num, den, list(h = W$h, c = W$c, k = k), lg, LAMBDA$lambda[i], LAMBDA$r[i])$e
    if (is.null(best) || sum(e[va]) < best$sse) best <- list(lambda = LAMBDA$lambda[i], r = LAMBDA$r[i], k = k, sse = sum(e[va]), e = e)
  }
  m  <- cbind(a$e, best$e, a$b)[te, , drop = FALSE]
  by <- rowsum(m, q$cluster[te])
  gain <- function(x) (sum(x[, 1]) - sum(x[, 2])) / sum(x[, 3])
  set.seed(20261003)
  boot <- replicate(1000, gain(by[sample(nrow(by), replace = TRUE), , drop = FALSE]))
  ci <- stats::quantile(boot, c(0.05, 0.95))
  verdict <- if (ci[1] > SESOI) "matters" else if (ci[1] > -SESOI && ci[2] < SESOI) "equivalent to zero" else "inconclusive"
  eras <- vapply(c("2021", "2022", "2023-25"), function(g) gain(m[era(q$season[te]) == g, , drop = FALSE]), 0)
  lam_rows[[rate]] <- data.frame(component = comp, rate = rate, lambda = best$lambda, r = best$r, k = best$k,
                                 test_gain = gain(m), lo90 = ci[1], hi90 = ci[2], verdict = verdict,
                                 gain_2021 = eras[1], gain_2022 = eras[2], gain_2023_25 = eras[3], row.names = NULL)
}
utils::write.csv(dplyr::bind_rows(curve_rows), file.path(OUT, "test-decay-curves.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(lam_rows), file.path(OUT, "test-lambda.csv"), row.names = FALSE)
utils::write.csv(dplyr::bind_rows(comp_rows), out_csv, row.names = FALSE)
message("wrote test stage to ", OUT)
quit(save = "no")
