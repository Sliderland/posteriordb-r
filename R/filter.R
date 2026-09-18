#' Filter Posteriors in Database
#'
#' @details
#' Filter posteriors in the database and return list of
#' posteriors/models/data to work with as a list.
#'
#' The function is built upon the dplyr filter function and
#' follows the exact same syntax. All elements in the
#' `posteriors/[posterior_name].json`, `models/info/[model_name].json`
#' and `data/info/[data_name].json` can be used to filter the
#' posterior database. See examples below.
#'
#' @param pdb a \code{pdb} object.
#' @param ... further arguments to supply to \code{dplyr::filter()}
#' @export
filter_posteriors <- function(pdb = pdb_default(), ...){
  pdb_filter(path = "posteriors", pdb = pdb, ...)
}

#' Search posterior metadata
#'
#' @details
#' Search the keyword metadata attached to posteriors, their data, and their
#' models. The search is case-insensitive and uses fixed-string matching.
#' Metadata files are loaded as needed; data archives, model code, and
#' reference draws are not loaded.
#'
#' @param pdb a \code{pdb} object.
#' @param query a non-empty search string.
#' @param fields metadata scopes to search. One or more of
#'   \code{"posterior"}, \code{"data"}, and \code{"model"}.
#' @param match whether a posterior must match \code{"any"} or \code{"all"}
#'   selected scopes.
#'
#' @return A tibble with one row per matching posterior and columns
#'   \code{posterior_name}, \code{data_name}, \code{model_name},
#'   \code{matched_in}, and \code{matched_keywords}.
#'
#' @export
search_posteriors <- function(
  pdb = pdb_default(),
  query,
  fields = c("posterior", "data", "model"),
  match = c("any", "all")
) {
  checkmate::assert_class(pdb, "pdb")
  checkmate::assert_string(query, min.chars = 1L)
  checkmate::assert_character(fields, min.len = 1L, unique = TRUE)
  checkmate::assert_subset(
    fields,
    choices = c("posterior", "data", "model")
  )
  match <- match.arg(match)

  posterior_tbl <- posteriors_tbl_df(pdb)
  checkmate::assert_names(
    names(posterior_tbl),
    must.include = c("name", "data_name", "model_name")
  )
  posterior_rows <- unique(
    as.data.frame(
      posterior_tbl[c("name", "data_name", "model_name")],
      stringsAsFactors = FALSE
    )
  )

  keyword_matches <- list()
  if ("posterior" %in% fields) {
    posterior_keywords <- split(
      posterior_tbl$keywords,
      posterior_tbl$name,
      drop = TRUE
    )
    keyword_matches$posterior <- pdb_search_keyword_values(
      posterior_keywords,
      query
    )
  }
  if ("data" %in% fields) {
    keyword_matches$data <- pdb_search_keyword_info(
      pdb,
      data_names(pdb),
      function(name) data_info(name, pdb),
      query
    )
  }
  if ("model" %in% fields) {
    keyword_matches$model <- pdb_search_keyword_info(
      pdb,
      model_names(pdb),
      function(name) model_info(name, pdb),
      query
    )
  }

  result <- lapply(seq_len(nrow(posterior_rows)), function(i) {
    posterior_name <- as.character(posterior_rows$name[[i]])
    data_name <- as.character(posterior_rows$data_name[[i]])
    model_name <- as.character(posterior_rows$model_name[[i]])

    hits <- lapply(fields, function(field) {
      key <- switch(
        field,
        posterior = posterior_name,
        data = data_name,
        model = model_name
      )
      matches <- keyword_matches[[field]]
      matches$keyword[matches$name == key]
    })
    names(hits) <- fields
    matched_in <- fields[lengths(hits) > 0L]

    if (!length(matched_in) ||
        (match == "all" && length(matched_in) != length(fields))) {
      return(NULL)
    }

    data.frame(
      posterior_name = posterior_name,
      data_name = data_name,
      model_name = model_name,
      matched_in = paste(matched_in, collapse = ", "),
      matched_keywords = paste(
        unique(unlist(hits[matched_in], use.names = FALSE)),
        collapse = ", "
      ),
      stringsAsFactors = FALSE
    )
  })
  result <- result[!vapply(result, is.null, logical(1))]

  if (!length(result)) {
    return(tibble::tibble(
      posterior_name = character(),
      data_name = character(),
      model_name = character(),
      matched_in = character(),
      matched_keywords = character()
    ))
  }

  tibble::as_tibble(do.call(rbind, result))
}

#' @keywords internal
pdb_search_keyword_values <- function(values, query) {
  matches <- lapply(names(values), function(name) {
    keywords <- as.character(unlist(
      values[[name]],
      recursive = TRUE,
      use.names = FALSE
    ))
    keywords <- keywords[!is.na(keywords) & nzchar(keywords)]
    keywords <- unique(keywords[grepl(
      tolower(query),
      tolower(keywords),
      fixed = TRUE
    )])
    if (!length(keywords)) {
      return(NULL)
    }
    data.frame(
      name = name,
      keyword = keywords,
      stringsAsFactors = FALSE
    )
  })
  matches <- matches[!vapply(matches, is.null, logical(1))]
  if (!length(matches)) {
    return(data.frame(
      name = character(),
      keyword = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, matches)
}

#' @keywords internal
pdb_search_keyword_info <- function(pdb, names, info_fun, query) {
  values <- lapply(names, info_fun)
  names(values) <- names
  values <- lapply(values, function(info) info$keywords)
  pdb_search_keyword_values(values, query)
}

#' Internal filter function
#'
#' Works for filtering models, data and posteriors.
#'
#' @keywords internal
#' @param pdb a pdb connection
pdb_filter <- function(path, pdb, ...){
  checkmate::assert_class(pdb, "pdb")
  checkmate::assert_choice(path, c("posteriors", "models/info", "data/info"))

  dat <- pdb_tibble(pdb, path)

  dat_tbl <- dplyr::filter(dat, ...)

  nms <- unique(dat_tbl$name)
  obj_list <- list()
  for(i in seq_along(nms)) {
    obj_list[[i]] <- posterior(nms[i], pdb = pdb)
  }
  obj_list
}
