#-------------------------------------------------------------------------------
# Generate the bundled example datasets for electrocpue.
#
# Produces two objects saved under data/:
#   example_catch  - long-format multi-pass electrofishing catch records
#   example_reach  - reach metadata keyed by reach_id
#
# The catch counts are simulated from a constant-probability removal model
# (binomial depletion across passes) so that depletion estimators recover
# sensible abundances. A fixed seed keeps the shipped data reproducible.
#
# Run with:  source("data-raw/make_example_data.R")
#-------------------------------------------------------------------------------

set.seed(42)

# ---- Reach metadata ----------------------------------------------------------

example_reach <- data.frame(
  reach_id      = sprintf("R%02d", 1:4),
  length_m      = c(120, 95, 150, 80),
  mean_width_m  = c(6.5, 5.0, 8.2, 4.1),
  habitat_class = c("riffle", "run", "pool", "riffle"),
  crew          = "BW-Gold Field Team",
  gear          = "Smith-Root LR-24",
  stringsAsFactors = FALSE
)
example_reach$area_m2 <- round(example_reach$length_m * example_reach$mean_width_m, 1)

# ---- Simulation settings -----------------------------------------------------

dates   <- as.Date(c("2025-06-15", "2025-08-20"))   # two visits per reach
species <- c("BNT", "RBT")                            # brown + rainbow trout
n_pass  <- 3L

# "True" abundance and per-pass capture probability per reach x species.
truth <- expand.grid(
  reach_id = example_reach$reach_id,
  species  = species,
  stringsAsFactors = FALSE
)
truth$N <- c(140, 90, 210, 60,    # BNT by reach
             70,  130, 45,  100)  # RBT by reach
truth$p <- c(0.62, 0.55, 0.48, 0.70,
             0.58, 0.50, 0.66, 0.45)

# ---- Simulate removal series -------------------------------------------------

sim_passes <- function(N, p, k) {
  out  <- integer(k)
  left <- N
  for (i in seq_len(k)) {
    out[i] <- stats::rbinom(1, left, p)
    left   <- left - out[i]
  }
  out
}

rows <- list()
r    <- 0L
for (d in seq_along(dates)) {
  for (i in seq_len(nrow(truth))) {
    rid <- truth$reach_id[i]
    sp  <- truth$species[i]
    # Mild between-visit variation in true abundance.
    Nv  <- max(1, round(truth$N[i] * stats::runif(1, 0.85, 1.15)))
    cnt <- sim_passes(Nv, truth$p[i], n_pass)
    # Effort: longer reaches take more shocking time; small per-pass noise.
    base_eff <- example_reach$length_m[example_reach$reach_id == rid] * 4
    for (pass in seq_len(n_pass)) {
      r <- r + 1L
      rows[[r]] <- data.frame(
        reach_id       = rid,
        date           = dates[d],
        pass_number    = as.integer(pass),
        species        = sp,
        count          = as.integer(cnt[pass]),
        effort_seconds = round(base_eff + stats::runif(1, -20, 20)),
        amperage       = round(stats::runif(1, 2.8, 4.2), 1),
        voltage        = round(stats::runif(1, 200, 400)),
        stringsAsFactors = FALSE
      )
    }
  }
}

example_catch <- do.call(rbind, rows)
example_catch <- example_catch[order(example_catch$reach_id,
                                     example_catch$date,
                                     example_catch$species,
                                     example_catch$pass_number), ]
rownames(example_catch) <- NULL

# Effort, amperage, and voltage describe a single shocking event, so they are
# properties of a reach x date x pass -- not of a species. The per-row draws
# above gave each species row its own values; collapse each pass to its first
# row's value so the shipped data reflects one shocking event per pass. (Counts
# are untouched, so depletion estimates are unchanged.)
pass_key <- with(example_catch,
                 paste(reach_id, date, pass_number, sep = "|"))
for (col in c("effort_seconds", "amperage", "voltage")) {
  example_catch[[col]] <- stats::ave(
    example_catch[[col]], pass_key, FUN = function(v) v[1]
  )
}

# ---- Save --------------------------------------------------------------------

usethis::use_data(example_catch, example_reach, overwrite = TRUE)
