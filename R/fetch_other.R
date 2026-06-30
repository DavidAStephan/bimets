# Index of the non-FRED source fetchers. Each is implemented in its own file
# (see below) and routed to by [update_data()] / [fetch_source()]. They all
# follow the same shape as fetch_fred():
#
#   1. Look up the catalogue rows for the source.
#   2. Hit the live API (readabs / readrba / OECD SDMX / Pink Sheet xlsx / ftp).
#   3. Normalise the result to (series_id, source, date, value, vintage).
#   4. Sub-quarterly sources are left at raw resolution here so the cached panel
#      preserves it; to_martin_database() aggregates to quarterly on the pivot.
#   5. Return the tidy tibble.

# fetch_abs() lives in fetch_abs.R

# fetch_rba() lives in fetch_rba.R

# fetch_oecd() lives in fetch_oecd.R

# fetch_worldbank() lives in fetch_worldbank.R

# fetch_bom() lives in fetch_bom.R
