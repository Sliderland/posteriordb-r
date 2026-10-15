#' GitHub personal access token
#'
#' @param pdb Optional GitHub connection whose token is used when the
#'   `GITHUB_PAT` environment variable is unset.
#' @return The token, or `NULL`.
#' @export
github_pat <- function(pdb = NULL) {
  pat <- Sys.getenv("GITHUB_PAT")
  if (nzchar(pat)) return(pat)
  pdb$github$pat
}

parse_repo_spec <- function(x) {
  checkmate::assert_string(x)
  m <- regmatches(x, regexec("^([^/@]+)/([^/@]+)(/[^@]*)?(@.+)?$", x))[[1]]
  if (!length(m)) stop2("`repo` must look like 'owner/repo[/subdir][@ref]': ", x)
  subdir <- sub("^/", "", sub("/$", "", m[4]))
  list(owner = m[2], repo = m[3],
       subdir = if (nzchar(subdir)) subdir else NULL,
       ref = if (nzchar(m[5])) sub("^@", "", m[5]) else NULL)
}

gh_call <- function(gh, endpoint, ...) {
  gh::gh(endpoint, ..., .token = gh$pat, .api_url = gh$host)
}

gh_contents_path <- function(gh, path = "") {
  full <- paste(c(if (nzchar(gh$subdir)) gh$subdir, if (nzchar(path)) path), collapse = "/")
  paste0("GET /repos/", gh$owner, "/", gh$repo, "/contents", if (nzchar(full)) paste0("/", full))
}

gh_dir <- function(gh, path = "") {
  entries <- gh_call(gh, gh_contents_path(gh, path), ref = gh$ref, .limit = Inf)
  data.frame(name = vapply(entries, `[[`, "", "name"),
             type = vapply(entries, `[[`, "", "type"),
             stringsAsFactors = FALSE)
}

find_github_root <- function(gh) {
  has_db <- function(entries) {
    all(c("data", "models", "posteriors") %in% entries$name[entries$type == "dir"])
  }
  root <- gh_dir(gh)
  if (has_db(root)) return(gh$subdir)
  if (!nzchar(gh$subdir) && "posterior_database" %in% root$name) {
    gh$subdir <- "posterior_database"
    if (has_db(gh_dir(gh))) return(gh$subdir)
  }
  stop2("No posterior database in GitHub repository '", gh$owner, "/", gh$repo, "'.")
}

#' @export
pdb_version.pdb_github <- function(pdb, ...) {
  gh <- pdb$github
  commit <- gh_call(gh, paste0("GET /repos/", gh$owner, "/", gh$repo, "/commits/", gh$ref))
  list(sha = commit$sha)
}

#' @export
pdb_list.pdb_github <- function(pdb, dir) {
  entries <- gh_dir(pdb$github, dir)
  entries$name[entries$type == "file"]
}

#' @export
pdb_file.pdb_github <- function(pdb, path, zip = FALSE) {
  cached <- file.path(pdb$cache_path, path)
  if (file.exists(cached)) return(cached)
  remote <- if (zip) paste0(path, ".zip") else path
  download <- file.path(pdb$cache_path, "download", remote)
  dir.create(dirname(download), recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(download))
  gh_call(pdb$github, gh_contents_path(pdb$github, remote), ref = pdb$github$ref,
          .accept = "application/vnd.github.raw", .destfile = download, .overwrite = TRUE)
  if (zip) {
    unzip_json(download, cached)
  } else {
    dir.create(dirname(cached), recursive = TRUE, showWarnings = FALSE)
    file.copy(download, cached, overwrite = TRUE)
  }
  cached
}
