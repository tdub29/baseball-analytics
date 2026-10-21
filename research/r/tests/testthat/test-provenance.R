# Provenance sidecars: a cached output is refused once its recipe or inputs change.

test_that("a sidecar round-trips and catches env and input changes", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  i <- file.path(d, "in.csv"); o <- file.path(d, "out.csv")
  writeLines("a", i); writeLines("b", o)
  old <- Sys.getenv("PROV_TEST", unset = NA); on.exit(if (is.na(old)) Sys.unsetenv("PROV_TEST") else Sys.setenv(PROV_TEST = old), add = TRUE)

  Sys.setenv(PROV_TEST = "1")
  write_provenance(o, inputs = i, env = "PROV_TEST")
  expect_true(file.exists(paste0(o, ".provenance.json")))
  expect_true(check_provenance(o, inputs = i, env = "PROV_TEST"))

  Sys.setenv(PROV_TEST = "2")
  expect_error(check_provenance(o, env = "PROV_TEST"), "PROV_TEST")

  writeLines("c", i)
  expect_error(check_provenance(o, inputs = i), "changed")
})

test_that("a missing sidecar is an error, not a pass", {
  expect_error(check_provenance(tempfile()), "no provenance sidecar")
})
