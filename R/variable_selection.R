validate_variable_selection <- function(x, arg) {
  if (is.null(x)) {
    return(NULL)
  }
  checkmate::assert_character(x, any.missing = FALSE)
  if (any(!nzchar(trimws(x))) || anyDuplicated(x)) {
    stop(
      "`",
      arg,
      "` must contain unique, non-empty base names.",
      call. = FALSE
    )
  }
  x <- unname(x)
  if (identical(x, "none")) {
    return(character())
  }
  if (arg == "include" && identical(x, "all")) {
    return(NULL)
  }
  x
}

validate_variable_selections <- function(include, exclude) {
  include <- validate_variable_selection(include, "include")
  exclude <- validate_variable_selection(exclude, "exclude")
  if ("lp__" %in% include) {
    stop("`lp__` cannot be included in model-output selections.", call. = FALSE)
  }
  overlap <- if (identical(exclude, "all")) {
    character()
  } else {
    intersect(include, exclude)
  }
  if (length(overlap)) {
    stop(
      "Variable(s) appear in both `include` and `exclude`: ",
      paste(overlap, collapse = ", "),
      call. = FALSE
    )
  }
  list(include = include, exclude = exclude)
}

# Workflows provide their available names and any mandatory variables.
resolve_variable_selection <- function(
  available,
  required = character(),
  include = NULL,
  exclude = NULL
) {
  selection <- validate_variable_selections(include, exclude)
  include <- selection$include
  exclude <- selection$exclude
  available <- setdiff(unique(available), "lp__")
  for (argument in c("include", "exclude")) {
    values <- if (argument == "include") include else exclude
    if (argument == "exclude" && identical(values, "all")) {
      next
    }
    unknown <- setdiff(values, c(available, if (argument == "exclude") "lp__"))
    if (length(unknown)) {
      stop(
        "Unknown base variable(s) in `",
        argument,
        "`: ",
        paste(unknown, collapse = ", "),
        call. = FALSE
      )
    }
  }
  if (identical(exclude, "all")) {
    return(required)
  }
  protected <- intersect(required, exclude)
  if (length(protected)) {
    stop(
      "Cannot exclude required posterior dimensions or parameter-block variables: ",
      paste(protected, collapse = ", "),
      call. = FALSE
    )
  }
  setdiff(
    union(required, if (is.null(include)) available else include),
    exclude
  )
}
