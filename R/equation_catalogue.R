#' The catalogue of adjustable MARTIN equations
#'
#' Reads `extdata/equation_catalogue.csv` and returns a tibble of MARTIN
#' equations with plain-English descriptions, sector groupings, units, an
#' `adjustable` flag (pure identities should be `FALSE`), typical historical
#' add-factor SD, and transmission channel notes. Drives add-factor validation
#' (which equations may carry a tune) and the `sensitivity_matrix()` shock set.
#'
#' The catalogue is curated, seeded from the English `'comments` in
#' `the EViews MARTIN equations.prg` and the `COMMENT>` blocks
#' in `the bimets MARTIN port MARTINMOD_AF.txt`.
#'
#' @return A tibble with columns: `code`, `name`, `sector`, `equation_type`,
#'   `plain_english`, `units`, `adjustable`, `typical_af_sd`,
#'   `transmission_channel`.
#' @export
equation_catalogue <- function() {
  readr::read_csv(extdata_path("equation_catalogue.csv"), show_col_types = FALSE)
}
