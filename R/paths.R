# Flat-repo path helpers.
#
# In a packaged build these files lived under inst/extdata/ and were resolved
# with system.file(). This repo is a flat set of sourced R scripts, so bundled
# data files live under <repo-root>/extdata/ and are resolved here instead.
#
# The repo root is recorded by setup.R as options(martin.root = ...). When that
# option is unset (e.g. a file is sourced directly), fall back to here::here()
# which locates the root via the .git directory, then to the working directory.

.martin_root <- function() {
  root <- getOption("martin.root")
  if (!is.null(root) && nzchar(root) && dir.exists(root)) return(root)
  if (requireNamespace("here", quietly = TRUE)) {
    hit <- tryCatch(here::here(), error = function(e) NULL)
    if (!is.null(hit) && dir.exists(hit)) return(hit)
  }
  getwd()
}

#' Absolute path to a bundled data file under extdata/
#'
#' @param file File name, e.g. "MARTINMOD_AF.txt" or "series_catalogue.csv".
#' @return Absolute path. Errors if the file is missing.
extdata_path <- function(file) {
  p <- file.path(.martin_root(), "extdata", file)
  if (!file.exists(p)) {
    stop("extdata file not found: ", p,
         "\n  (source 'setup.R' from the repo root first, or set ",
         "options(martin.root=) to the checkout path).", call. = FALSE)
  }
  p
}
