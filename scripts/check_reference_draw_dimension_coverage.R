# Compare each posterior's declared unconstrained parameter names with the
# variable names physically present in its linked reference-draw JSON/ZIP.
#
# This is a read-only database audit. It does not compile models or call any
# PosteriorDB writers. Draw JSON is scanned line by line to avoid loading the
# numeric draw payloads into memory.

db <- Sys.getenv(
  "PDB_PATH",
  unset = path.expand("~/Documents/posteriordb/posterior_database")
)
db <- normalizePath(db, mustWork = FALSE)
if (!dir.exists(db)) {
  stop("PosteriorDB directory does not exist: ", db)
}

# Set to a finite integer for a smaller trial run, or leave Inf to scan all.
max_posteriors <- Inf

`%||%` <- function(x, y) if (is.null(x)) y else x

read_info <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

read_chain_variable_names <- function(path) {
  if (grepl("[.]zip$", path, ignore.case = TRUE)) {
    members <- utils::unzip(path, list = TRUE)$Name
    json_members <- members[
      grepl("[.]json$", members, ignore.case = TRUE) &
        !grepl("^__MACOSX/", members)
    ]
    expected_member <- sub("[.]zip$", "", basename(path), ignore.case = TRUE)
    exact_member <- json_members[basename(json_members) == expected_member]
    if (length(exact_member) == 1L) {
      json_member <- exact_member[[1L]]
    } else if (length(json_members) == 1L) {
      json_member <- json_members[[1L]]
    } else {
      stop("Could not identify one draw JSON member in archive; found ",
           length(json_members), ".")
    }
    con <- unz(path, json_member, open = "r")
  } else {
    con <- file(path, open = "r")
  }
  on.exit(close(con), add = TRUE)

  # PosteriorDB draw JSON is an array of chain objects. Each variable's draws
  # are serialized on the same line as its key; scan the keys without parsing
  # the potentially large numeric arrays.
  chains <- list()
  current <- character()
  in_chain <- FALSE
  repeat {
    line <- readLines(con, n = 1L, warn = FALSE)
    if (!length(line)) break

    if (!in_chain && grepl("^\\s*\\{\\s*$", line)) {
      in_chain <- TRUE
      current <- character()
      next
    }
    if (in_chain && grepl("^\\s*}\\s*,?\\s*$", line)) {
      chains[[length(chains) + 1L]] <- current
      in_chain <- FALSE
      next
    }
    if (in_chain) {
      key_match <- regexec('^\\s*"([^"\\\\]*)"\\s*:', line, perl = TRUE)
      key <- regmatches(line, key_match)[[1L]]
      if (length(key) >= 2L) current <- c(current, key[[2L]])
    }
  }

  if (in_chain) stop("Draw JSON ended inside a chain object.")
  if (!length(chains)) stop("No chain objects were found in draw JSON.")
  if (any(lengths(chains) == 0L)) {
    stop("At least one chain object has no variable keys.")
  }
  chains
}

posterior_files <- list.files(
  file.path(db, "posteriors"),
  pattern = "[.]json$",
  full.names = TRUE,
  recursive = FALSE
)
if (is.finite(max_posteriors)) {
  posterior_files <- head(posterior_files, max_posteriors)
}

coverage <- list()
errors <- list()
skipped_no_reference_draws <- 0L
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

  draw_name <- po$reference_posterior_name
  if (is.null(draw_name) || length(draw_name) != 1L ||
      is.na(draw_name) || !nzchar(draw_name)) {
    skipped_no_reference_draws <- skipped_no_reference_draws + 1L
    next
  }

  draw_dir <- file.path(db, "reference_posteriors", "draws", "draws")
  zip_path <- file.path(draw_dir, paste0(draw_name, ".json.zip"))
  json_path <- file.path(draw_dir, paste0(draw_name, ".json"))
  draw_path <- if (file.exists(zip_path)) zip_path else json_path
  if (!file.exists(draw_path)) {
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = paste0("Reference-draw file does not exist: ", draw_path),
      stringsAsFactors = FALSE
    )
    next
  }

  chain_names <- tryCatch(read_chain_variable_names(draw_path), error = function(e) e)
  if (inherits(chain_names, "error")) {
    errors[[length(errors) + 1L]] <- data.frame(
      posterior = posterior_name,
      reason = conditionMessage(chain_names),
      stringsAsFactors = FALSE
    )
    next
  }

  # Draw payload names may be scalar-expanded (e.g. beta[1,2]); posterior
  # dimensions use base variable names (beta). Compare at that base-name level.
  bases_by_chain <- lapply(chain_names, function(nms) {
    unique(sub("\\[.*$", "", nms))
  })
  stored_names <- names(po$dimensions %||% list())
  draw_names <- unique(unlist(bases_by_chain, use.names = FALSE))

  for (parameter in union(stored_names, draw_names)) {
    present <- which(vapply(
      bases_by_chain, function(nms) parameter %in% nms, logical(1)
    ))
    status <- if (!parameter %in% stored_names) {
      "draw_variable_not_in_dimensions"
    } else if (!length(present)) {
      "dimension_missing_from_draws"
    } else if (length(present) < length(bases_by_chain)) {
      "dimension_missing_from_some_chains"
    } else {
      "match"
    }

    coverage[[length(coverage) + 1L]] <- data.frame(
      posterior = posterior_name,
      reference_posterior = draw_name,
      parameter = parameter,
      status = status,
      chains_present = paste(present, collapse = ","),
      chains_total = length(bases_by_chain),
      stringsAsFactors = FALSE
    )
  }
}

coverage_table <- if (length(coverage)) {
  do.call(rbind, coverage)
} else {
  data.frame()
}
error_table <- if (length(errors)) {
  do.call(rbind, errors)
} else {
  data.frame()
}

cat("Scanned posterior records:", length(posterior_files), "\n")
cat("Skipped posteriors without a reference_posterior_name:",
    skipped_no_reference_draws, "\n")
cat("\nReference-draw coverage statuses:\n")
if (nrow(coverage_table)) {
  print(table(coverage_table$status))
} else {
  cat("No draw-variable comparisons were produced.\n")
}

cat("\nPosterior dimensions missing from linked reference draws:\n")
if (nrow(coverage_table)) {
  missing <- subset(
    coverage_table,
    status %in% c("dimension_missing_from_draws", "dimension_missing_from_some_chains")
  )
  if (nrow(missing)) print(missing, row.names = FALSE) else cat("None.\n")
}

cat("\nDraw variables not listed in posterior dimensions:\n")
if (nrow(coverage_table)) {
  extra <- subset(coverage_table, status == "draw_variable_not_in_dimensions")
  if (nrow(extra)) {
    print(extra, row.names = FALSE)
    cat("These can be valid transformed parameters or generated quantities.\n")
  } else {
    cat("None.\n")
  }
}

cat("\nPosteriors whose reference draws could not be checked:",
    nrow(error_table), "\n")
if (nrow(error_table)) print(error_table, row.names = FALSE)
