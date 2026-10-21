# Provenance sidecars for new outputs (the reproducibility contract in the 2026-10 review): what built a
# file, from which inputs, under which settings. The frozen scripts do not call this; new experiments do.
#
#   source("research/r/mlb/provenance.R")
#   write_provenance("data/mlb/x/predictions.csv", inputs = "data/mlb/matchup/features.rds", env = c("OUT_TAG", "ASOF_LAG"))
#   check_provenance("data/mlb/x/predictions.csv", inputs = "data/mlb/matchup/features.rds", env = c("OUT_TAG", "ASOF_LAG"))
#
# write_provenance() writes <output>.provenance.json: git commit and dirty files under research/r/mlb, R and
# attached package versions, platform, command line, the named env vars as set ("" when unset), and sha256
# of every input and output. check_provenance() stops when a named env var or input hash differs from the
# run that built the file, so a cached artifact is not reused under another recipe.
#
#   Rscript research/r/mlb/provenance.R    # self-check in a temp dir

sha256_of <- function(f) c(as.character(openssl::sha256(file(f))))   # c() drops the "hash" class

write_provenance <- function(outputs, inputs = character(), env = character()) {
  git <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  si <- utils::sessionInfo()
  meta <- list(
    written_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    git_commit = git("rev-parse", "HEAD"),
    git_dirty = git("status", "--porcelain", "--", "research/r/mlb"),
    r_version = R.version.string, platform = R.version$platform,
    packages = lapply(si$otherPkgs, function(p) p$Version),
    command = commandArgs(FALSE),
    env = as.list(Sys.getenv(env, unset = "", names = TRUE)),
    inputs = as.list(vapply(inputs, sha256_of, "")),
    outputs = as.list(vapply(outputs, sha256_of, "")))
  for (o in outputs) jsonlite::write_json(meta, paste0(o, ".provenance.json"), auto_unbox = TRUE, pretty = TRUE)
  invisible(meta)
}

check_provenance <- function(output, inputs = character(), env = character()) {
  p <- paste0(output, ".provenance.json")
  if (!file.exists(p)) stop("no provenance sidecar for ", output)
  old <- jsonlite::read_json(p, simplifyVector = TRUE)
  now <- Sys.getenv(env, unset = "", names = TRUE)
  for (n in env) if (!identical(as.character(old$env[[n]]), now[[n]]))
    stop("env ", n, " is '", now[[n]], "' but ", output, " was built with '", old$env[[n]], "'")
  for (f in inputs) if (!identical(as.character(old$inputs[[f]]), sha256_of(f)))
    stop("input ", f, " changed since ", output, " was built")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {                                          # Rscript provenance.R
  d <- tempfile(); dir.create(d); i <- file.path(d, "in.csv"); o <- file.path(d, "out.csv")
  writeLines("a", i); writeLines("b", o)
  Sys.setenv(PROV_TEST = "1"); write_provenance(o, inputs = i, env = "PROV_TEST")
  stopifnot(check_provenance(o, inputs = i, env = "PROV_TEST"))
  Sys.setenv(PROV_TEST = "2"); stopifnot(inherits(try(check_provenance(o, env = "PROV_TEST"), silent = TRUE), "try-error"))
  writeLines("c", i); stopifnot(inherits(try(check_provenance(o, inputs = i), silent = TRUE), "try-error"))
  cat("provenance self-check ok\n")
}
