# Check whether PosteriorDB posterior dimensions match unconstrained parameter
# counts inferred from each posterior's Stan model and linked data.
#
# By default, save reports without changing the database. --no-output disables
# CSV/RDS reports; --update enables dimension changes (with original JSON backups).
# --output and --no-update explicitly select the defaults.
# RStan compilation and the package's read cache may create temporary/cache
# files outside the database directory.
# Run: Rscript scripts/check_posterior_dimension_consistency.R [database] [output]
# Apply saved counts (optional posterior names limit which records are updated):
# Rscript scripts/check_posterior_dimension_consistency.R --update --write-from \
#   scripts/posterior_dimension_audit/audit.rds [posterior-name ...]
# Without --update, --write-from previews the saved audit without compiling.
# Models with only a PyMC implementation are reported as skipped, not errors.

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_arg)) {
  stop("Run this script with Rscript so it can locate the repository root.")
}
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
repo_root <- normalizePath(file.path(dirname(script_path), ".."))

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Install `pkgload` to load the forked package from this checkout.")
}
pkgload::load_all(repo_root, quiet = TRUE, helpers = FALSE, export_all = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (all(c("--output", "--no-output") %in% args) ||
    all(c("--update", "--no-update") %in% args))
  stop("Choose one output flag and one update flag.")
write_output <- !"--no-output" %in% args
update_dimensions <- "--update" %in% args
args <- args[!args %in% c("--output", "--no-output", "--update", "--no-update")]
`%||%` <- function(x, y) if (is.null(x)) y else x
read_info <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

update_posterior_dimensions <- function(audit, backup, selected = names(audit$records)) {
  database <- normalizePath(audit$database, mustWork = TRUE)
  if (anyDuplicated(selected) || any(!selected %in% names(audit$records)))
    stop("Requested posterior names must be unique and present in the saved audit.")

  # Prepare and validate every change before writing any database files.
  changes <- list()
  for (filename in selected) {
    record <- audit$records[[filename]]
    if (!is.null(record$error) || is.null(record$inferred)) {
      message("Skipping ", filename, ": ", record$skip_reason %||% record$error %||% "no inferred counts")
      next
    }
    if (!identical(filename, basename(filename)) || !grepl("[.]json$", filename))
      stop("Invalid posterior filename in audit: ", filename)
    path <- file.path(database, "posteriors", filename)
    current <- read_info(path)
    if (!identical(current, record$original))
      stop("Posterior metadata changed since the audit: ", filename, ". Run a fresh audit.")
    if (is.null(record$input_hashes) || anyNA(record$input_hashes) ||
        !identical(tools::md5sum(names(record$input_hashes)), record$input_hashes))
      stop("Model/data inputs changed since the audit: ", filename, ". Run a fresh audit.")
    counts <- posteriordb:::validate_posterior_dimension_counts(record$inferred)
    if (setequal(names(current$dimensions), names(counts)) &&
        all(vapply(names(counts), function(name) {
          stored <- unlist(current$dimensions[[name]], use.names = FALSE)
          is.numeric(stored) && length(stored) == 1L && !is.na(stored) &&
            stored == counts[[name]]
        }, logical(1)))) next
    current$dimensions <- counts
    content <- jsonlite::toJSON(current, pretty = TRUE, auto_unbox = TRUE,
      null = "null", digits = NA)
    stopifnot(isTRUE(all.equal(jsonlite::fromJSON(as.character(content),
      simplifyVector = FALSE), current, tolerance = 0)))
    changes[[filename]] <- list(path = path, content = as.character(content))
  }

  if (length(changes)) {
    dir.create(backup, recursive = TRUE, showWarnings = FALSE)
    for (filename in names(changes)) {
      if (!file.copy(changes[[filename]]$path, file.path(backup, filename), overwrite = FALSE))
        stop("Could not save original JSON (backup may already exist): ", filename)
    }
    for (filename in names(changes)) {
      change <- changes[[filename]]
      temporary <- tempfile(".dimensions-", tmpdir = dirname(change$path))
      writeLines(change$content, temporary, useBytes = TRUE)
      if (!file.rename(temporary, change$path)) {
        unlink(temporary)
        stop("Could not replace posterior JSON: ", filename)
      }
      message("Updated dimensions: ", filename)
    }
    cat("Original JSON files saved to:", backup, "\n")
  }
  cat("Updated posterior records:", length(changes), "\n")
  invisible(length(changes))
}

if (length(args) && identical(args[[1L]], "--write-from")) {
  if (length(args) < 2L) stop("Supply the path to audit.rds after --write-from.")
  audit_path <- normalizePath(args[[2L]], mustWork = TRUE)
  audit <- readRDS(audit_path)
  selected <- if (length(args) > 2L) paste0(args[-c(1L, 2L)], ".json") else names(audit$records)
  if (anyDuplicated(selected) || any(!selected %in% names(audit$records)))
    stop("Requested posterior names must be unique and present in the saved audit.")
  if (update_dimensions) {
    update_posterior_dimensions(audit, file.path(dirname(audit_path), "original_posteriors"), selected)
  } else {
    cat("Saved audit records selected:", length(selected), "\n")
    selected_names <- vapply(audit$records[selected], function(record)
      record$original$name %||% basename(record$file), character(1))
    print(subset(audit$comparisons, posterior %in% selected_names & status != "match"), row.names = FALSE)
    print(subset(audit$errors, posterior %in% selected_names), row.names = FALSE)
    for (record in audit$records[selected]) {
      if (!is.null(record$skip_reason))
        message("Skipping ", basename(record$file), ": ", record$skip_reason)
    }
    cat("Database unchanged. Add --update to apply these saved counts.\n")
  }
  quit(save = "no", status = 0L)
}

if (any(startsWith(args, "--")) || length(args) > 2L)
  stop("Usage: Rscript check_posterior_dimension_consistency.R [--no-output] [--update] [database] [output]")

db <- path.expand(if (length(args)) args[[1L]] else Sys.getenv("PDB_PATH",
  unset = "~/Documents/posteriordb/posterior_database"))
if (!dir.exists(db)) {
  stop("PosteriorDB directory does not exist: ", db)
}
db <- normalizePath(db)
output <- if (length(args) >= 2L) args[[2L]] else
  file.path(dirname(script_path), "posterior_dimension_audit")
output <- path.expand(output)
if (write_output) dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, mustWork = write_output)
started <- Sys.time()

# Set this to a finite integer for a smaller trial run, or leave Inf to scan all.
max_posteriors <- Inf

show_value <- function(x) {
  paste(unlist(x, use.names = FALSE), collapse = ",")
}

cache_path <- tempfile("pdb-dimension-cache-")
dir.create(cache_path, showWarnings = FALSE)
pdb <- posteriordb::pdb_local(db, cache_path = cache_path)
posterior_files <- list.files(
  file.path(db, "posteriors"),
  pattern = "\\.json$",
  full.names = TRUE,
  recursive = FALSE
)
if (is.finite(max_posteriors)) {
  posterior_files <- head(posterior_files, max_posteriors)
}
if (!length(posterior_files)) stop("No posterior JSON files found in ", db)

# Inference is cached by model/data pair, since several posterior records may
# refer to the same pair and therefore have the same unconstrained counts.
inference_cache <- new.env(parent = emptyenv())
comparisons <- list()
errors <- list()
records <- list()

for (posterior_file in posterior_files) {
  po <- tryCatch(read_info(posterior_file), error = function(e) e)
  posterior_name <- if (inherits(po, "error")) {
    basename(posterior_file)
  } else {
    po$name %||% basename(posterior_file)
  }
  message("[", match(posterior_file, posterior_files), "/", length(posterior_files),
    "] ", posterior_name)
  records[[basename(posterior_file)]] <- list(file = posterior_file,
    original = if (inherits(po, "error")) NULL else po, inferred = NULL,
    input_hashes = NULL, error = NULL, skip_reason = NULL)

  if (inherits(po, "error")) {
    records[[basename(posterior_file)]]$error <- conditionMessage(po)
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
    records[[basename(posterior_file)]]$error <- "Posterior metadata has no model_name or data_name."
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
      model_info <- read_info(file.path(db, "models", "info", paste0(model_name, ".info.json")))
      implementations <- model_info$model_implementations
      frameworks <- names(implementations)[!vapply(implementations, is.null, logical(1))]
      if (identical(frameworks, "pymc")) {
        NULL
      } else {
        code <- posteriordb::model_code(model_name, framework = "stan", pdb = pdb)
        data <- posteriordb::get_data(data_name, pdb = pdb)
        input_files <- c(file.path(db, "models", "info", paste0(model_name, ".info.json")),
          file.path(db, model_info$model_implementations$stan$model_code),
          file.path(db, "data", "data", paste0(data_name, ".json.zip")))
        input_hashes <- tools::md5sum(input_files)
        if (anyNA(input_hashes)) stop("Could not fingerprint model/data input files.")
        records[[basename(posterior_file)]]$input_hashes <- input_hashes
        posteriordb::infer_posterior_dimensions(code, data, backend = "rstan")
      }
    }, error = function(e) e)

    assign(key, inferred, envir = inference_cache)
    assign(paste0(key, "\rhashes"), records[[basename(posterior_file)]]$input_hashes,
      envir = inference_cache)
  }
  inferred <- get(key, envir = inference_cache, inherits = FALSE)
  records[[basename(posterior_file)]]$input_hashes <- get(paste0(key, "\rhashes"),
    envir = inference_cache, inherits = FALSE)

  if (inherits(inferred, "error")) {
    records[[basename(posterior_file)]]$error <- conditionMessage(inferred)
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = conditionMessage(inferred),
      stringsAsFactors = FALSE
    )
    next
  }
  if (is.null(inferred)) {
    records[[basename(posterior_file)]]$skip_reason <- "PyMC-only model; Stan dimension audit not applicable."
    message("Skipping ", posterior_name, ": PyMC-only model.")
    next
  }
  records[[basename(posterior_file)]]$inferred <- inferred

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

      status <- if (is.numeric(unlist(stored[[parameter]], use.names = FALSE)) &&
                    length(stored_count) == 1L &&
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
  data.frame(posterior = character(), model = character(), data = character(),
    parameter = character(), status = character(), stored = character(), inferred = character())
}

inference_errors <- if (length(errors)) {
  do.call(rbind, errors)
} else {
  data.frame(posterior = character(), reason = character())
}

posterior_check <- do.call(rbind, lapply(records, function(record) {
  po <- record$original
  rows <- dimension_check[dimension_check$posterior == (po$name %||% basename(record$file)), ]
  data.frame(posterior = po$name %||% basename(record$file),
    model = po$model_name %||% NA_character_, data = po$data_name %||% NA_character_,
    status = if (!is.null(record$skip_reason)) "skipped_pymc_only" else
      if (!is.null(record$error)) "inference_error" else
      if (any(rows$status != "match")) "dimension_mismatch" else "match",
    mismatches = sum(rows$status != "match"),
    total_unconstrained = if (is.null(record$inferred)) NA_integer_ else sum(unlist(record$inferred)),
    error = record$error %||% "", skip_reason = record$skip_reason %||% "",
    stringsAsFactors = FALSE)
}))
audit <- list(database = db, backend = "rstan", started = started, finished = Sys.time(),
  fork_commit = system2("git", c("-C", shQuote(repo_root), "rev-parse", "HEAD"), stdout = TRUE),
  r_version = R.version.string, rstan_version = as.character(utils::packageVersion("rstan")),
  records = records, comparisons = dimension_check, errors = inference_errors)
if (write_output) {
  utils::write.csv(dimension_check, file.path(output, "dimensions.csv"), row.names = FALSE)
  utils::write.csv(inference_errors, file.path(output, "errors.csv"), row.names = FALSE)
  utils::write.csv(posterior_check, file.path(output, "posteriors.csv"), row.names = FALSE)
  saveRDS(audit, file.path(output, "audit.rds"))
  cat("Saved per-posterior results, comparisons, errors, and inferred counts to:", output, "\n")
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
skipped <- subset(posterior_check, status == "skipped_pymc_only",
  select = c(posterior, model, skip_reason))
cat("\nPyMC-only posteriors skipped:", nrow(skipped), "\n")
if (nrow(skipped)) print(skipped, row.names = FALSE)
if (update_dimensions) {
  update_posterior_dimensions(audit, file.path(output, "original_posteriors"))
} else {
  cat("Database unchanged. Add --update to apply inferred counts.\n")
}
