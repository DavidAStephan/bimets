#' Load a MARTIN database from a plain CSV instead of downloading
#'
#' An alternative to the public-download pipeline ([update_data()] +
#' [to_martin_database()]). Where that path fetches ABS/RBA/FRED/etc. and pivots
#' the raw panels onto MARTIN's variable names, this reads a CSV the caller has
#' already assembled: one column per MARTIN variable (the header *is* the
#' variable name) plus a single period column, and returns the same
#' named-list-of-`bimets::TIMESERIES` shape every downstream function
#' ([load_martin()], [solve_martin()], [sensitivity_matrix()], ...) consumes.
#'
#' This is the offline / air-gapped / "bring your own data" entry point. It does
#' no source dispatch, caching, aggregation, splicing, or Chow-Lin
#' disaggregation — the CSV is assumed to already be quarterly and on MARTIN's
#' definitions. Use [database_to_csv()] to export the bundled fixture (or any
#' database) to this exact format as a starting template.
#'
#' @section CSV format:
#'   * One **period column** identifying each quarter. Either `"yyyyQq"` strings
#'     (`"2019Q3"`, case-insensitive) or quarter-start dates (`"2019-07-01"`).
#'     Auto-detected by name (`Dates`/`Date`/`quarter`/`period`/`time`, or an
#'     unnamed first column); override with `date_col`.
#'   * One column per MARTIN variable, header = the exact variable name
#'     (case-sensitive: `RC`, `NCR`, `WPCOM`, ...). Values numeric; blanks and
#'     `NA` are treated as missing. Thousands separators (commas) are tolerated.
#'   * Rows need not be sorted and may have gaps; the loader sorts by period and
#'     fills missing quarters with `NA` so each series sits on a regular
#'     quarterly axis.
#'
#' @param path Path to the CSV file.
#' @param date_col Name of the period column. `NULL` (default) auto-detects.
#' @param trim_na If `TRUE` (default), leading/trailing `NA`s are trimmed from
#'   each series so it starts and ends on its first/last real observation (the
#'   natural bimets span). Internal gaps are preserved.
#' @param validate If `TRUE` (default), checks the data column headers against
#'   the model's variable list ([martin_model_variables()]) and messages about
#'   any unrecognised columns and how many model variables went unsupplied.
#'   Never fatal — extra columns are still loaded (bimets ignores variables it
#'   does not reference).
#' @param fallback Optional named-list database (e.g. [read_fixture()]) whose
#'   series fill any quarter the CSV leaves `NA`, via [merge_with_fallback()].
#'   `NULL` (default) returns the CSV data alone.
#' @param variant Model variant whose variable list is used for validation.
#'
#' @return A named list of `bimets::TIMESERIES` keyed by MARTIN variable name.
#'   Attributes: `unknown_columns` (headers not in the model), `vars_supplied`
#'   (model variables the CSV provided), `vars_missing` (model variables it did
#'   not), `period_column` (the column used).
#' @export
read_csv_database <- function(path,
                              date_col = NULL,
                              trim_na  = TRUE,
                              validate = TRUE,
                              fallback = NULL,
                              variant  = c("af", "identity", "est")) {
  variant <- match.arg(variant)
  if (!file.exists(path)) {
    stop("CSV not found at ", path, call. = FALSE)
  }
  raw <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                         na.strings = c("NA", "", "."))
  if (ncol(raw) < 2L) {
    stop("CSV must have a period column plus at least one variable column.",
         call. = FALSE)
  }

  date_col <- date_col %||% detect_period_column(names(raw))
  if (!date_col %in% names(raw)) {
    stop("Period column '", date_col, "' not found. Columns: ",
         paste(names(raw), collapse = ", "), call. = FALSE)
  }

  # Period column -> quarter index (year*4 + quarter-1), one per row.
  qi <- parse_period_vector(raw[[date_col]])
  if (anyNA(qi)) {
    bad <- unique(raw[[date_col]][is.na(qi)])
    stop("Could not parse ", sum(is.na(qi)), " period value(s) in '",
         date_col, "', e.g.: ", paste(utils::head(bad, 3), collapse = ", "),
         ". Use 'yyyyQq' (2019Q3) or quarter-start dates (2019-07-01).",
         call. = FALSE)
  }
  if (anyDuplicated(qi)) {
    dup <- raw[[date_col]][duplicated(qi)]
    stop("Duplicate periods in '", date_col, "': ",
         paste(utils::head(unique(dup), 3), collapse = ", "),
         ". Each quarter must appear once.", call. = FALSE)
  }

  # Regular quarterly axis spanning the data; reindex every series onto it.
  full_qi <- seq.int(min(qi), max(qi))
  pos     <- match(qi, full_qi)
  data_cols <- setdiff(names(raw), date_col)

  db <- list()
  empty_cols <- character(0)
  for (nm in data_cols) {
    vals_full <- rep(NA_real_, length(full_qi))
    vals_full[pos] <- coerce_numeric(raw[[nm]])
    ts <- numeric_to_quarterly_ts(vals_full, full_qi, trim_na = trim_na)
    if (is.null(ts)) {
      empty_cols <- c(empty_cols, nm)
      next
    }
    db[[nm]] <- ts
  }
  if (length(empty_cols)) {
    message("read_csv_database: ", length(empty_cols),
            " column(s) had no numeric data and were dropped: ",
            paste(utils::head(empty_cols, 8), collapse = ", "),
            if (length(empty_cols) > 8) ", ..." else "")
  }

  model_vars <- martin_model_variables(variant)
  unknown    <- setdiff(names(db), model_vars)
  supplied   <- intersect(model_vars, names(db))
  missing    <- setdiff(model_vars, names(db))
  if (isTRUE(validate)) {
    if (length(unknown)) {
      message("read_csv_database: ", length(unknown),
              " column(s) are not MARTIN variables (loaded anyway): ",
              paste(utils::head(unknown, 8), collapse = ", "),
              if (length(unknown) > 8) ", ..." else "")
    }
    message("read_csv_database: supplied ", length(supplied), "/",
            length(model_vars), " model variables",
            if (length(missing)) sprintf("; %d not in the CSV", length(missing))
            else "")
  }

  if (!is.null(fallback)) {
    if (!is.list(fallback) || is.null(names(fallback))) {
      stop("`fallback` must be a named list of bimets TIMESERIES ",
           "(e.g. read_fixture()).", call. = FALSE)
    }
    db <- merge_with_fallback(db, fallback)
  }

  attr(db, "unknown_columns") <- unknown
  attr(db, "vars_supplied")   <- supplied
  attr(db, "vars_missing")    <- missing
  attr(db, "period_column")   <- date_col
  db
}

#' Export a MARTIN database to the CSV format [read_csv_database()] reads
#'
#' The inverse of [read_csv_database()]: writes a wide CSV with a period column
#' and one column per variable, on a regular quarterly axis spanning the union
#' of all series (quarters a series does not cover are blank). Handy for
#' producing a fill-in-the-blanks template from the bundled fixture
#' (`database_to_csv(read_fixture(), "template.csv")`) or for round-tripping.
#'
#' @param database A named list of quarterly `bimets::TIMESERIES`.
#' @param path Output CSV path.
#' @param period_format `"quarter"` (default, `"yyyyQq"` strings) or `"date"`
#'   (quarter-start ISO dates).
#' @param period_name Header for the period column. Default `"quarter"`.
#' @return `path`, invisibly.
#' @export
database_to_csv <- function(database, path,
                            period_format = c("quarter", "date"),
                            period_name   = "quarter") {
  period_format <- match.arg(period_format)
  if (!is.list(database) || is.null(names(database))) {
    stop("`database` must be a named list of bimets TIMESERIES.", call. = FALSE)
  }
  is_q <- vapply(database, function(x) {
    inherits(x, "ts") && stats::frequency(x) == 4
  }, logical(1))
  if (!any(is_q)) {
    stop("No quarterly (FREQ=4) series in `database` to export.", call. = FALSE)
  }
  database <- database[is_q]

  labelled <- lapply(database, ts_to_labelled)
  all_qi   <- sort(unique(unlist(lapply(labelled, function(x) x$qi))))
  out <- data.frame(quarter_label(all_qi, period_format),
                    check.names = FALSE, stringsAsFactors = FALSE)
  names(out) <- period_name
  for (nm in names(labelled)) {
    col <- rep(NA_real_, length(all_qi))
    col[match(labelled[[nm]]$qi, all_qi)] <- labelled[[nm]]$values
    out[[nm]] <- col
  }
  utils::write.csv(out, path, row.names = FALSE, na = "")
  invisible(path)
}

#' The variables a MARTIN model variant references
#'
#' Loads the model definition (no data, no estimation) and returns the union of
#' its endogenous (`vendog`) and exogenous (`vexog`) variable names — the set a
#' [read_csv_database()] header is validated against.
#'
#' @param variant See [model_file_path()].
#' @return A sorted character vector of variable names.
#' @export
martin_model_variables <- function(variant = c("af", "identity", "est")) {
  variant <- match.arg(variant)
  model_text <- paste(read_model_lines(variant), collapse = "\n")
  m <- .suppress_bimets_version_warning(suppressMessages(suppressWarnings(
    bimets::LOAD_MODEL(modelText = model_text)
  )))
  sort(unique(c(m$vendog, m$vexog)))
}

# ---- internals -------------------------------------------------------------

# Pick the period column by name, else fall back to the first column.
detect_period_column <- function(cols) {
  known <- c("dates", "date", "quarter", "period", "time", "obs", "qtr")
  lower <- tolower(trimws(cols))
  hit <- which(lower %in% known | cols %in% c("", "V1", "X"))
  if (length(hit) >= 1L) return(cols[hit[1]])
  message("read_csv_database: no obvious period column; ",
          "using the first column '", cols[1], "'.")
  cols[1]
}

# Parse a vector of period labels to quarter indices (year*4 + quarter-1).
# Accepts "yyyyQq" strings, Date objects, or date-like strings. NA where
# unparseable (caller reports). Vectorised.
parse_period_vector <- function(x) {
  if (inherits(x, "Date")) return(date_to_qi(x))
  s <- trimws(as.character(x))
  qi <- rep(NA_integer_, length(s))

  is_q <- grepl("^[0-9]{4}[Qq][1-4]$", s)
  if (any(is_q)) {
    yr <- as.integer(substr(s[is_q], 1, 4))
    q  <- as.integer(substr(s[is_q], 6, 6))
    qi[is_q] <- yr * 4L + (q - 1L)
  }

  rest <- !is_q & !is.na(s) & nzchar(s)
  if (any(rest)) {
    # as.Date() errors (rather than NA) on non-date strings, so parse each
    # element under tryCatch and keep NA where it is not a date.
    d <- do.call(c, lapply(s[rest], function(z) {
      suppressWarnings(tryCatch(as.Date(z), error = function(e) as.Date(NA)))
    }))
    qi[rest][!is.na(d)] <- date_to_qi(d[!is.na(d)])
  }
  qi
}

# Date -> quarter index (year*4 + quarter-1).
date_to_qi <- function(d) {
  d  <- as.Date(d)
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  yr * 4L + ((mo - 1L) %/% 3L)
}

# Quarter index -> label, either "yyyyQq" or quarter-start ISO date.
quarter_label <- function(qi, period_format = "quarter") {
  yr <- qi %/% 4L
  q  <- (qi %% 4L) + 1L
  if (period_format == "date") {
    iso <- sprintf("%04d-%02d-01", yr, (q - 1L) * 3L + 1L)
    return(as.character(as.Date(iso)))
  }
  sprintf("%04dQ%d", yr, q)
}

# Coerce a (possibly character) column to numeric, tolerating thousands commas.
coerce_numeric <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  suppressWarnings(as.numeric(gsub(",", "", trimws(as.character(x)))))
}

# Build a quarterly bimets TIMESERIES from values aligned to `full_qi`,
# optionally trimming leading/trailing NA. Returns NULL if all-NA.
numeric_to_quarterly_ts <- function(vals_full, full_qi, trim_na = TRUE) {
  finite <- which(is.finite(vals_full))
  if (length(finite) == 0L) return(NULL)
  if (isTRUE(trim_na)) {
    keep      <- seq.int(min(finite), max(finite))
    vals_full <- vals_full[keep]
    start_qi  <- full_qi[min(finite)]
  } else {
    start_qi  <- full_qi[1]
  }
  bimets::TIMESERIES(
    vals_full,
    START = c(start_qi %/% 4L, (start_qi %% 4L) + 1L),
    FREQ  = 4
  )
}

# bimets quarterly ts -> list(qi = quarter indices, values = numeric).
ts_to_labelled <- function(ts) {
  t  <- as.numeric(stats::time(ts))
  yr <- floor(t + 1e-9)
  q  <- round((t - yr) * 4 + 1)
  list(qi = as.integer(yr * 4L + (q - 1L)), values = as.numeric(ts))
}
