# Run with:  Rscript research/r/tests/testthat.R
#
# No network. Every test here works on plain data frames, which is the point of splitting
# ingest away from features, model and evaluate.

library(testthat)
library(dplyr)
library(purrr)

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."), mustWork = FALSE)
if (!dir.exists(root)) root <- "research/r"

source(file.path(root, "mlb", "features.R"))
source(file.path(root, "mlb", "model.R"))
source(file.path(root, "mlb", "evaluate.R"))

test_dir(file.path(root, "tests", "testthat"), stop_on_failure = TRUE)
