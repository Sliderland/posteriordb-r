% Generated manually because roxygen2 cannot update DESCRIPTION in the restricted workspace.
\name{import_reference_posterior_draws}
\alias{import_reference_posterior_draws}
\title{Import an externally sampled Stan fit into PosteriorDB}
\usage{
import_reference_posterior_draws(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  write = FALSE,
  overwrite = FALSE,
  ...
)
}
\arguments{
  \item{fit}{A completed post-warmup \code{rstan::stanfit} or \code{cmdstanr::CmdStanMCMC} object. Sampling occurs outside posteriordb-r.}
  \item{posterior}{A PosteriorDB posterior name or \code{pdb_posterior} object.}
  \item{pdb}{A local PosteriorDB object when writing.}
  \item{dimensions}{Optional named PosteriorDB dimension list. If omitted, the posterior specification is used.}
  \item{policy}{Reserved for a future diagnostic policy; must currently be \code{NULL}.}
  \item{write}{If \code{FALSE}, return the in-memory checked object. If \code{TRUE}, write after required checks and round-trip verification pass.}
  \item{overwrite}{Whether existing reference-posterior metadata or draw files may be replaced. Defaults to \code{FALSE}.}
  \item{...}{Optional metadata fields forwarded to the conversion function.}
}
\value{A \code{pdb_reference_posterior_draws} object.}
\description{Imports draws and sampling metadata from an externally sampled rstan or CmdStanR fit without sampling the model again.}
\details{The importer extracts chains, iterations, warmup, thinning, sampler arguments, model and Stan versions when available, plus backend, posterior, and R versions. For CmdStanR, draws and sampler diagnostics are read lazily from the fit's CSV output files; the CmdStan executable is not run. Optional seed and timestamp fields are omitted when unavailable. Matrix parameters are filtered using explicit scalar names such as \code{A[1,1]}. Warmup draws and undeclared variables are excluded. Writing stages the metadata, draws, and any new posterior reference link together, verifies the result, and refuses to overwrite existing reference files unless \code{overwrite = TRUE}.}
\examples{\dontrun{
fit <- rstan::stan(
  model_code = "parameters { real theta; } model { theta ~ normal(0, 1); }",
  iter = 10000, warmup = 5000, chains = 4
)
imported <- import_reference_posterior_draws(
  fit = fit,
  posterior = "data-model",
  pdb = pdb,
  write = FALSE
)
}}
\seealso{\code{\link{as_reference_posterior_draws}}, \code{\link{as_reference_posterior_draws_from_cmdstanr}}, \code{\link{write_pdb}}}
\keyword{utilities}
