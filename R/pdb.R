#' Connect to a posterior database
#'
#' A `pdb` object says where a posterior database lives. Every getter in the
#' package takes one, and objects read from a database remember the
#' connection they came from.
#'
#' * `pdb_local()` uses a database on disk. `path` can point at the
#'   `posterior_database` folder or at a clone of the posteriordb repository
#'   that contains it.
#' * `pdb_github()` reads a database from a GitHub repository. Files are
#'   downloaded on first use and cached for the session. It needs the `gh`
#'   package; set `GITHUB_PAT` to avoid rate limits.
#' * `pdb_config()` reads `.pdb_config.yml` (see the posteriordb repository
#'   for an example) and calls one of the two constructors with its fields.
#' * `pdb_default()` uses `.pdb_config.yml` in the working directory if
#'   there is one, then a local database from the `pdb_path` option or the
#'   `PDB_PATH` environment variable, and otherwise `stan-dev/posteriordb`
#'   on GitHub.
#'
#' Zipped files (data and reference draws) are extracted to `cache_path`.
#' Each connection gets its own folder under the R temporary directory by
#' default. Use [pdb_clear_cache()] to drop cached files.
#'
#' @param path Path to a local posterior database.
#' @param repo GitHub repository as `owner/repo[/subdir][@ref]`.
#' @param ref Git branch, tag or commit to read. A ref given in `repo` wins.
#' @param subdir Folder in the repository that holds the database. Found
#'   automatically when it is the repository root or `posterior_database`.
#' @param auth_token GitHub personal access token, or `NULL`.
#' @param host GitHub API URL.
#' @param cache_path Folder for cached and extracted files.
#' @param directory Folder that contains `.pdb_config.yml`.
#' @param x For `pdb()`, an object read from a database (returns its
#'   connection), or a path or repository spec (creates one).
#' @param pdb_type For a character `x`: `"local"` or `"github"`.
#' @param ... Passed on to `pdb_local()` or `pdb_github()`.
#' @return A `pdb` object.
#' @examples
#' \dontrun{
#' pdbl <- pdb_local("~/posteriordb")
#' pdbg <- pdb_github("stan-dev/posteriordb@master")
#' }
#' @export
pdb_local <- function(path = getOption("pdb_path", Sys.getenv("PDB_PATH")),
                      cache_path = NULL) {
  checkmate::assert_string(path)
  if (!nzchar(path)) {
    stop2("No database path given. Supply `path`, or set the `pdb_path` option or PDB_PATH.")
  }
  root <- find_local_root(path)
  new_pdb(list(pdb_id = root, path = root), "local", cache_path)
}

#' @rdname pdb_local
#' @export
pdb_github <- function(repo = getOption("pdb_repo", "stan-dev/posteriordb"),
                       ref = "master", subdir = NULL, cache_path = NULL,
                       auth_token = github_pat(), host = "https://api.github.com") {
  require_package("gh", "for GitHub connections")
  spec <- parse_repo_spec(repo)
  gh <- list(owner = spec$owner, repo = spec$repo,
             ref = spec$ref %||% ref, subdir = spec$subdir %||% subdir %||% "",
             pat = auth_token, host = host)
  gh$subdir <- find_github_root(gh)
  id <- paste0(gh$owner, "/", gh$repo,
               if (nzchar(gh$subdir)) paste0("/", gh$subdir), "@", gh$ref)
  new_pdb(list(pdb_id = id, github = gh), "github", cache_path)
}

#' @rdname pdb_local
#' @export
pdb_config <- function(directory = getwd()) {
  require_package("yaml", "to read .pdb_config.yml")
  config <- yaml::read_yaml(file.path(directory, ".pdb_config.yml"), eval.expr = FALSE)
  checkmate::assert_list(config, names = "unique")
  checkmate::assert_choice(config$type, c("local", "github"))
  constructor <- if (config$type == "local") pdb_local else pdb_github
  pdb <- do.call(constructor, config[setdiff(names(config), "type")])
  pdb$config <- config
  pdb
}

#' @rdname pdb_local
#' @export
pdb_default <- function(cache_path = NULL) {
  if (file.exists(".pdb_config.yml")) return(pdb_config())
  path <- getOption("pdb_path", Sys.getenv("PDB_PATH"))
  if (nzchar(path)) return(pdb_local(path, cache_path = cache_path))
  pdb_github(cache_path = cache_path)
}

#' @rdname pdb_local
#' @export
pdb <- function(x, ...) UseMethod("pdb")

#' @rdname pdb_local
#' @export
pdb.default <- function(x, ...) attr(x, "pdb")

#' @rdname pdb_local
#' @export
pdb.pdb <- function(x, ...) x

#' @rdname pdb_local
#' @export
pdb.character <- function(x, pdb_type = c("local", "github"), ...) {
  pdb_type <- match.arg(pdb_type)
  if (pdb_type == "local") pdb_local(x, ...) else pdb_github(x, ...)
}

`pdb<-` <- function(x, value) {
  checkmate::assert_class(value, "pdb", null.ok = TRUE)
  attr(x, "pdb") <- value
  x
}

new_pdb <- function(fields, type, cache_path) {
  x <- structure(fields, class = c(paste0("pdb_", type), "pdb"))
  x$cache_path <- cache_path %||%
    file.path(tempdir(), "posteriordb", gsub("[^A-Za-z0-9._-]+", "_", x$pdb_id))
  dir.create(x$cache_path, recursive = TRUE, showWarnings = FALSE)
  x$version <- pdb_version(x)
  x
}

find_local_root <- function(path) {
  for (candidate in c(path, file.path(path, "posterior_database"))) {
    if (all(dir.exists(file.path(candidate, c("data", "models", "posteriors"))))) {
      return(normalizePath(candidate, winslash = "/"))
    }
  }
  stop2("No posterior database in '", path, "'. The folder (or its ",
        "`posterior_database` subfolder) must contain data/, models/ and posteriors/.")
}

#' @export
print.pdb <- function(x, ...) {
  cat0("Posterior Database (", sub("^pdb_", "", class(x)[1]), ")\n")
  cat0("Path: ", x$pdb_id, "\n")
  cat0("Version: ", x$version$sha %||% "unknown", "\n")
  invisible(x)
}

#' Version of a posterior database
#'
#' @param pdb A [pdb][pdb_local] connection.
#' @param ... Not used.
#' @return A list with the git commit `sha` of the database, or `NA` when it
#'   cannot be determined (for example a local copy outside git).
#' @export
pdb_version <- function(pdb, ...) {
  if (!is.null(pdb$version)) return(pdb$version)
  UseMethod("pdb_version")
}

#' @export
pdb_version.pdb_local <- function(pdb, ...) list(sha = git_head_sha(pdb$path))

# Read the HEAD commit from a git checkout without a git dependency.
git_head_sha <- function(path) {
  dir <- normalizePath(path, winslash = "/")
  repeat {
    git <- file.path(dir, ".git")
    if (dir.exists(git)) break
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NA_character_)
    dir <- parent
  }
  head <- trimws(readLines(file.path(git, "HEAD"), n = 1L, warn = FALSE))
  if (!startsWith(head, "ref: ")) return(head)
  ref <- sub("^ref: ", "", head)
  ref_file <- file.path(git, ref)
  if (file.exists(ref_file)) return(trimws(readLines(ref_file, n = 1L, warn = FALSE)))
  packed <- file.path(git, "packed-refs")
  if (file.exists(packed)) {
    lines <- readLines(packed, warn = FALSE)
    hit <- lines[endsWith(lines, paste0(" ", ref))]
    if (length(hit)) return(sub(" .*$", "", hit[1]))
  }
  NA_character_
}

#' Clear the file cache of a connection
#'
#' Removes cached and extracted files. Local connections notice changed
#' ZIP files on their own; GitHub connections keep downloaded files until the
#' cache is cleared.
#'
#' @inheritParams pdb_version
#' @return `pdb`, invisibly.
#' @export
pdb_clear_cache <- function(pdb) {
  checkmate::assert_class(pdb, "pdb")
  if (inherits(pdb, "pdb_local") &&
      identical(normalizePath(pdb$cache_path, mustWork = FALSE), pdb$path)) {
    stop2("The cache path is the database itself; refusing to clear it.")
  }
  unlink(list.files(pdb$cache_path, full.names = TRUE, all.files = TRUE, no.. = TRUE),
         recursive = TRUE)
  invisible(pdb)
}

# File access -----------------------------------------------------------------
# Every reader goes through these two functions, so a backend only has to
# say how to list a folder and how to get one file onto local disk.

# Return a local path to the database file `path`. With `zip = TRUE` the
# database stores `path` as `path.zip` and the extracted file is returned.
pdb_file <- function(pdb, path, zip = FALSE) {
  UseMethod("pdb_file")
}

#' @export
pdb_file.pdb_local <- function(pdb, path, zip = FALSE) {
  source <- file.path(pdb$path, if (zip) paste0(path, ".zip") else path)
  if (!file.exists(source)) stop2("File not found in the database: ", source)
  if (!zip) return(source)
  cached <- file.path(pdb$cache_path, path)
  if (!file.exists(cached) || file.mtime(cached) < file.mtime(source)) {
    unzip_json(source, cached)
  }
  cached
}

# File names (not paths) of regular files in the database folder `dir`.
pdb_list <- function(pdb, dir) UseMethod("pdb_list")

#' @export
pdb_list.pdb_local <- function(pdb, dir) {
  files <- list.files(file.path(pdb$path, dir))
  files[!dir.exists(file.path(pdb$path, dir, files))]
}

# Names of the resources in `dir`, stripping `suffix` from file names.
pdb_names <- function(pdb, dir, suffix) {
  files <- pdb_list(pdb, dir)
  files <- files[endsWith(files, suffix)]
  sort(substr(files, 1L, nchar(files) - nchar(suffix)))
}

pdb_read_json <- function(pdb, path, zip = FALSE, simplify = TRUE) {
  read_json_file(pdb_file(pdb, path, zip = zip), simplify = simplify)
}
