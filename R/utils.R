assert_pdb_resource_name <- function(name) {
  checkmate::assert_string(name, min.chars = 1)
  if (name %in% c(".", "..") || grepl("[/\\\\]", name) ||
      grepl("[[:cntrl:]]", name)) {
    stop("Names must be single path components without separators or control characters.",
         call. = FALSE)
  }
  invisible(name)
}

remove_file_extension <- function(x) {
  checkmate::assert_character(x, pattern = "\\..{1,5}$")
  unlist(lapply(strsplit(x, "\\."), function(x) x[1]))
}

get_file_extension <- function(x) {
  checkmate::assert_character(x, pattern = "\\..{1,5}$")
  unlist(lapply(strsplit(x, "\\."), function(x) x[2]))
}

stop2 <- function(...) {
  stop(..., call. = FALSE)
}

# cat with without separating elements
cat0 <- function(..., file = "", fill = FALSE, labels = NULL, append = FALSE) {
  cat(..., sep = "", file = file, fill = fill, labels = labels, append = append)
}

# file.path that remove null elementd
file.path0 <- function(...){
  arg <- list(...)
  do.call(file.path, arg[!unlist(lapply(arg, FUN = is.null))])
}

# Print a list as a yaml recursively
print_list <- function(x, pad = "  "){
  for(i in seq_along(x)){
    if(is.list(x[[i]])) {
      print_list(x[[i]], pad = paste0(pad, pad))
    } else {
      cat0(pad, names(x)[i], ": ", x[[i]], "\n")
    }
  }
}
