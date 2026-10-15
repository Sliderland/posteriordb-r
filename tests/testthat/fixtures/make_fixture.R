# Rebuilds pdb.zip from a posteriordb checkout:
#   Rscript make_fixture.R <posteriordb>/posterior_database
# Run from this directory. Needs a `zip` program.
src <- commandArgs(trailingOnly = TRUE)[1]
build <- tempfile(); dir.create(build)
dst <- file.path(build, "pdb")
cp <- function(rel) {
  dir.create(dirname(file.path(dst, rel)), recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(file.path(src, rel), file.path(dst, rel)))
}
ref <- "eight_schools-eight_schools_noncentered"
for (rel in c("data/info/eight_schools.info.json", "data/data/eight_schools.json.zip",
              "models/info/eight_schools_centered.info.json", "models/info/eight_schools_noncentered.info.json",
              "models/stan/eight_schools_centered.stan", "models/stan/eight_schools_noncentered.stan",
              "models/pymc/eight_schools_centered.py", "models/pymc/eight_schools_noncentered.py",
              "posteriors/eight_schools-eight_schools_centered.json", "posteriors/eight_schools-eight_schools_noncentered.json",
              paste0("reference_posteriors/draws/info/", ref, ".info.json"),
              paste0("reference_posteriors/summary_statistics/mean_value/info/", ref, ".info.json"),
              paste0("reference_posteriors/summary_statistics/mean_value/mean_value/", ref, ".json"),
              paste0("reference_posteriors/summary_statistics/mean_squared_value/info/", ref, ".info.json"),
              paste0("reference_posteriors/summary_statistics/mean_squared_value/mean_squared_value/", ref, ".json"))) cp(rel)
# Reference draws: the real file, cut to 100 draws per chain to keep the fixture small.
tmp <- tempfile(); dir.create(tmp)
unzip(file.path(src, "reference_posteriors/draws/draws", paste0(ref, ".json.zip")), exdir = tmp)
draws <- jsonlite::read_json(file.path(tmp, paste0(ref, ".json")))
draws <- lapply(draws, function(chain) lapply(chain, function(v) v[1:100]))
dir.create(file.path(dst, "reference_posteriors/draws/draws"), recursive = TRUE)
json <- file.path(tmp, "small", paste0(ref, ".json")); dir.create(dirname(json))
writeLines(jsonlite::toJSON(draws, digits = NA, auto_unbox = TRUE), json)
zip(normalizePath(file.path(dst, "reference_posteriors/draws/draws", paste0(ref, ".json.zip")), mustWork = FALSE), json, flags = "-jq9X")
dir.create(file.path(dst, "alias"))
writeLines('{\n  "eight_schools": "eight_schools-eight_schools_noncentered",\n  "8schools": "eight_schools-eight_schools_noncentered"\n}', file.path(dst, "alias/posteriors.json"))
bib <- readLines(file.path(src, "bibliography/references.bib"))
starts <- grep("^@", bib)
keep <- unlist(lapply(starts, function(s) {
  e <- min(c(starts[starts > s] - 1, length(bib)))
  if (grepl("rubin1981estimation|gelman2013bayesian", bib[s])) s:e
}))
dir.create(file.path(dst, "bibliography"))
writeLines(bib[keep], file.path(dst, "bibliography/references.bib"))
out <- file.path(getwd(), "pdb.zip")
unlink(out)
owd <- setwd(build)
zip(out, "pdb", flags = "-qr9X")
setwd(owd)
