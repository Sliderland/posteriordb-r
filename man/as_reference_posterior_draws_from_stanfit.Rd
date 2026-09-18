% Generated manually because roxygen2 cannot update DESCRIPTION in the restricted workspace.
\name{as_reference_posterior_draws}
\alias{as_reference_posterior_draws}
\alias{as_reference_posterior_draws_from_stanfit}
\title{Convert an externally sampled rstan fit to reference-posterior draws}
\usage{
as_reference_posterior_draws(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
)

as_reference_posterior_draws_from_stanfit(
  fit,
  posterior,
  pdb = pdb_default(),
  dimensions = NULL,
  policy = NULL,
  ...
)
}
\arguments{
  \item{fit}{A completed post-warmup \code{rstan::stanfit} object.}
  \item{posterior}{A PosteriorDB posterior name or \code{pdb_posterior} object.}
  \item{pdb}{A PosteriorDB connection used to resolve a posterior name.}
  \item{dimensions}{Optional named PosteriorDB dimension list. If omitted, the posterior's dimensions are authoritative.}
  \item{policy}{Reserved for a future diagnostic policy; must currently be \code{NULL}.}
  \item{...}{Optional metadata fields such as \code{comments}, \code{added_by}, \code{added_date}, and \code{sampling_timestamp}.}
}
\value{A \code{pdb_reference_posterior_draws} object containing post-warmup draws, diagnostics, checks, and sampler metadata.}
\description{Converts a fit sampled outside posteriordb-r. Only scalar variables declared by the PosteriorDB dimensions are retained; sampler parameters such as \code{lp__} and \code{divergent__} are used for diagnostics only.}
\details{If required checks fail, the object is returned with the failure recorded in its \code{checks_made} metadata and is not eligible for writing. Dimensions are not inferred from every variable in the fit. Supplied dimensions must agree with any dimensions declared by the posterior.}
\seealso{\code{\link{import_reference_posterior_draws}}}
\keyword{internal}
