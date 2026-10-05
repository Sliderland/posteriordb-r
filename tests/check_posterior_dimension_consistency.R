# Check whether PosteriorDB posterior dimensions match unconstrained parameter
# counts inferred from each posterior's Stan model and linked data.
#
# This script reads the database; it does not call any PosteriorDB writers.
# RStan compilation and the package's read cache may create temporary/cache
# files outside the database directory.

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_arg)) {
  stop("Run this script with Rscript so it can locate the repository root.")
}
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
repo_root <- normalizePath(file.path(dirname(script_path), ".."))

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Install `pkgload` to load the forked package from this checkout.")
}
pkgload::load_all(repo_root, quiet = TRUE)

db <- path.expand("~/Documents/posteriordb/posterior_database")
if (!dir.exists(db)) {
  stop("PosteriorDB directory does not exist: ", db)
}

# Set this to a finite integer for a smaller trial run, or leave Inf to scan all.
max_posteriors <- Inf

`%||%` <- function(x, y) if (is.null(x)) y else x
read_info <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}
show_value <- function(x) {
  paste(unlist(x, use.names = FALSE), collapse = ",")
}

pdb <- posteriordb::pdb_local(db)
posterior_files <- list.files(
  file.path(db, "posteriors"),
  pattern = "\\.json$",
  full.names = TRUE,
  recursive = FALSE
)
if (is.finite(max_posteriors)) {
  posterior_files <- head(posterior_files, max_posteriors)
}

# Inference is cached by model/data pair, since several posterior records may
# refer to the same pair and therefore have the same unconstrained counts.
inference_cache <- new.env(parent = emptyenv())
comparisons <- list()
errors <- list()

for (posterior_file in posterior_files) {
  po <- tryCatch(read_info(posterior_file), error = function(e) e)
  posterior_name <- if (inherits(po, "error")) {
    basename(posterior_file)
  } else {
    po$name %||% basename(posterior_file)
  }

  if (inherits(po, "error")) {
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = conditionMessage(po),
      stringsAsFactors = FALSE
    )
    next
  }

  model_name <- po$model_name
  data_name <- po$data_name
  if (is.null(model_name) || is.null(data_name)) {
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = "Posterior metadata has no model_name or data_name.",
      stringsAsFactors = FALSE
    )
    next
  }

  key <- paste(model_name, data_name, sep = "\r")
  if (!exists(key, envir = inference_cache, inherits = FALSE)) {
    inferred <- tryCatch({
      code <- posteriordb::model_code(
        model_name, framework = "stan", pdb = pdb
      )
      data <- posteriordb::get_data(data_name, pdb = pdb)
      posteriordb::infer_posterior_dimensions(
        code, data, backend = "rstan"
      )
    }, error = function(e) e)

    assign(key, inferred, envir = inference_cache)
  }
  inferred <- get(key, envir = inference_cache, inherits = FALSE)

  if (inherits(inferred, "error")) {
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = conditionMessage(inferred),
      stringsAsFactors = FALSE
    )
    next
  }

  stored <- po$dimensions %||% list()
  parameter_names <- union(names(stored), names(inferred))

  for (parameter in parameter_names) {
    has_stored <- parameter %in% names(stored)
    has_inferred <- parameter %in% names(inferred)

    if (!has_stored) {
      status <- "missing_from_posterior_dimensions"
    } else if (!has_inferred) {
      status <- "not_inferred_as_a_model_parameter"
    } else {
      stored_count <- suppressWarnings(
        as.numeric(unlist(stored[[parameter]], use.names = FALSE))
      )
      inferred_count <- as.numeric(inferred[[parameter]])

      status <- if (length(stored_count) == 1L &&
                    !is.na(stored_count) &&
                    stored_count == inferred_count) {
        "match"
      } else {
        "count_mismatch"
      }
    }

    comparisons[[length(comparisons) + 1L]] <- data.frame(
      posterior = posterior_name,
      model = model_name,
      data = data_name,
      parameter = parameter,
      status = status,
      stored = if (has_stored) show_value(stored[[parameter]]) else NA_character_,
      inferred = if (has_inferred) show_value(inferred[[parameter]]) else NA_character_,
      stringsAsFactors = FALSE
    )
  }
}

dimension_check <- if (length(comparisons)) {
  do.call(rbind, comparisons)
} else {
  data.frame()
}

inference_errors <- if (length(errors)) {
  do.call(rbind, errors)
} else {
  data.frame()
}

cat("Scanned posterior records:", length(posterior_files), "\n")
cat("\nDimension comparison statuses:\n")
print(table(dimension_check$status))

cat("\nNon-matching or unmatched dimensions:\n")
if (nrow(dimension_check)) {
  print(subset(dimension_check, status != "match"), row.names = FALSE)
} else {
  cat("No comparable dimensions were produced.\n")
}

cat("\nPosteriors that could not be inferred:", nrow(inference_errors), "\n")
if (nrow(inference_errors)) {
  print(inference_errors, row.names = FALSE)
}
