# setup.R -- load the MARTIN model.
#
# This repo is a flat collection of R scripts (no package install required).
# Sourcing this file:
#   1. records the repo root (so bundled files under extdata/ resolve),
#   2. attaches the runtime dependencies, and
#   3. sources every function in R/ into the global environment.
#
# Usage, from the repo root:
#
#     source("setup.R")
#
# or from anywhere:
#
#     source("/path/to/R-MARTIN/setup.R", chdir = TRUE)
#
# After this, the public functions are available, e.g.:
#   read_fixture(), load_martin(), solve_martin(), solve_martin_stochastic(),
#   sensitivity_matrix(), equation_catalogue(), update_data(),
#   to_martin_database(), nowcast_handover(), splice_handover().

local({
  # The repo root is the directory holding THIS file. Resolve it from setup.R's
  # own path so it is correct however setup.R was loaded:
  #   (a) source("…/setup.R")  -> the source frame's $ofile,
  #   (b) Rscript setup.R       -> commandArgs("--file="),
  #   (c) fallback              -> here::here() (uses the .here / .git marker),
  #                                then the working directory.
  setup_path <- NULL
  ofiles <- Filter(Negate(is.null), lapply(sys.frames(), function(f) f$ofile))
  if (length(ofiles)) setup_path <- ofiles[[length(ofiles)]]
  if (is.null(setup_path)) {
    m <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(m)) setup_path <- sub("^--file=", "", m[[1]])
  }
  root <- if (!is.null(setup_path)) {
    dirname(normalizePath(setup_path))
  } else {
    tryCatch(here::here(), error = function(e) getwd())
  }
  options(martin.root = normalizePath(root))
})

# ---- Runtime dependencies --------------------------------------------------
# Attached because the model code makes some un-namespaced calls (notably the
# bimets verbs TIMESERIES / SIMULATE / ESTIMATE / ...). Everything else is
# called with explicit pkg:: prefixes, so these only need to be installed; we
# attach the common ones for convenience.
local({
  required <- c(
    "bimets",                                   # the model engine
    "dplyr", "tidyr", "tibble", "purrr", "rlang",  # data wrangling
    "stringr", "lubridate", "readr", "glue",
    "readxl", "xts", "zoo",                     # fixture + ts plumbing
    "KFAS", "tempdisagg",                       # state-space trends, Chow-Lin
    "fable", "fabletools", "feasts", "tsibble"  # nowcast bridge models
  )
  missing <- required[!vapply(required, requireNamespace, logical(1),
                              quietly = TRUE)]
  if (length(missing)) {
    stop("Missing required packages: ", paste(missing, collapse = ", "),
         "\nInstall with install.packages(c(",
         paste(sprintf('"%s"', missing), collapse = ", "), "))", call. = FALSE)
  }
  for (p in required) {
    suppressPackageStartupMessages(library(p, character.only = TRUE))
  }

  # Optional: only needed for live data download via update_data().
  optional <- c("arrow", "readabs", "readrba", "fredr", "OECD", "fs", "here")
  absent <- optional[!vapply(optional, requireNamespace, logical(1),
                             quietly = TRUE)]
  if (length(absent)) {
    message("Note: optional packages not installed (live data download / ",
            "path helpers may be limited): ", paste(absent, collapse = ", "))
  }
})

# ---- Source the model ------------------------------------------------------
local({
  root <- getOption("martin.root")
  r_files <- list.files(file.path(root, "R"), pattern = "\\.R$",
                        full.names = TRUE)
  # paths.R defines extdata_path(); source it first so it's available even to
  # any top-level code (function bodies resolve lazily, but this is tidy).
  r_files <- c(
    file.path(root, "R", "paths.R"),
    setdiff(r_files, file.path(root, "R", "paths.R"))
  )
  for (f in r_files) source(f, local = FALSE)
})

invisible(NULL)
