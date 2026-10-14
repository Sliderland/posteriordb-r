# Scalar-variable metrics shared by report and stored-diagnostic paths.
reference_variable_diagnostic <- function(draws, fun) {
  draws <- posterior::as_draws_array(draws)
  vars <- posterior::variables(draws)
  stats::setNames(
    vapply(
      seq_along(vars),
      function(j) {
        z <- matrix(draws[,, j], nrow = dim(draws)[1L], ncol = dim(draws)[2L])
        tryCatch(as.numeric(fun(z))[1L], error = function(error) NA_real_)
      },
      numeric(1)
    ),
    vars
  )
}

sampler_divergence_counts <- function(sampler) {
  vapply(
    seq_len(posterior::nchains(sampler)),
    function(i) {
      sum(sampler[, i, "divergent__"])
    },
    numeric(1)
  )
}
