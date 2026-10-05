#' Reconstruct Stan model output from constrained parameter draws
#'
#' Evaluate a model at existing draws without MCMC or a PosteriorDB connection.
#' Each draw is unconstrained and then constrained while evaluating transformed
#' parameters and generated quantities. Complete constrained parameter-block
#' inputs are mandatory; additional input columns are ignored.
#'
#' @param draws Draws convertible to a \code{posterior::draws_array}, containing
#'   every constrained parameter-block column with Stan bracket-indexed names.
#' @param model A data-bound \code{rstan::stanfit} or
#'   \code{cmdstanr::CmdStanMCMC}, a compiled \code{stanmodel}, a
#'   \code{CmdStanModel}, a Stan source file path, a single Stan source string,
#'   or a \code{pdb_model_code}. Files and source are compiled using RStan;
#'   a CmdStanModel supplies its source for RStan compilation. A CmdStanMCMC
#'   uses native CmdStanR model methods and may compile additional C++ methods.
#' @param data Matching named Stan data list for compiled-model or source input;
#'   use \code{list()} for a model without data. Leave \code{NULL} for fitted
#'   evaluators, which already bind their data.
#' @param variables Output base names or exact indexed column names to return.
#'   \code{NULL} returns all parameters, transformed parameters, and generated
#'   quantities. Sampler columns, including \code{lp__}, are not returned.
#' @param seed Positive integer seed used when initializing a new evaluator.
#'   Existing evaluators retain their internal RNG state; this argument does
#'   not reset that state on repeated calls.
#' @param include_unconstrained Also return the intermediate unconstrained
#'   coordinates. CmdStanR coordinates receive positional \code{upars[i]} names.
#' @return A list with \code{draws} (a \code{draws_array}), reusable
#'   \code{evaluator}, \code{parameter_names}, \code{parameter_shapes},
#'   \code{backend}, optional \code{unconstrained_draws}, and \code{timings}
#'   in seconds (preparation, setup, evaluation, total). Chain and iteration
#'   order are preserved.
#' @details
#' Deterministic outputs reproduce within numerical precision when code and
#' data match. Random generated quantities are regenerated; they are not the
#' original realizations and advance the evaluator RNG. Selecting outputs
#' does not avoid evaluating the full transformed-parameter/generated-quantity
#' blocks. This function does not certify sampling quality or reconstruct
#' divergences, tree depths, energy, acceptance statistics, or a sampled fit.
#'
#' Supported shapes are scalars and rectangular numeric vectors, matrices,
#' and arrays, including constrained types such as simplexes. Tuple-valued
#' parameters are not supported. At least one nonempty parameter is required.
#' Native pointers and supporting files must remain available for fitted
#' evaluators; otherwise supply model source and matching data to recompile.
#' Compilation may create temporary files but no PosteriorDB files are written.
#' Model/data identity is the caller's responsibility. Random transformed-data
#' calculations may also differ when initializing a new evaluator; model code
#' and observed data alone do not preserve their original random realizations.
#' @examples
#' \dontrun{
#' code <- "parameters { real mu; }
#'          transformed parameters { real exp_mu = exp(mu); }
#'          model { mu ~ normal(0, 1); }"
#' draws <- posterior::as_draws_array(array(
#'   c(-1, 0, 1), c(3, 1, 1),
#'   dimnames = list(NULL, NULL, "mu")
#' ))
#' result <- reconstruct_stan_output(draws, code, data = list())
#' result$draws
#' # Reuse compilation and data initialization:
#' selected <- reconstruct_stan_output(
#'   draws, result$evaluator, variables = "exp_mu"
#' )
#' }
#' @export
reconstruct_stan_output <- function(
  draws, model, data = NULL, variables = NULL,
  seed = 1L, include_unconstrained = FALSE
) {
  started <- proc.time()[["elapsed"]]
  checkmate::assert_flag(include_unconstrained)
  if (!is.null(variables) && (!is.character(variables) || !length(variables) ||
      anyNA(variables) || any(!nzchar(variables)) || anyDuplicated(variables))) {
    stop("`variables` must contain unique, non-empty variable names.", call. = FALSE)
  }
  if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) ||
      seed < 1 || seed > .Machine$integer.max || seed != floor(seed)) {
    stop("`seed` must be a positive integer within R's integer range.", call. = FALSE)
  }
  draw_names <- function(names) {
    vapply(strsplit(names, ".", fixed = TRUE), function(parts) {
      if (length(parts) == 1L) parts else paste0(
        parts[[1L]], "[", paste(parts[-1L], collapse = ","), "]"
      )
    }, character(1), USE.NAMES = FALSE)
  }
  base_names <- function(names) sub("\\[.*$", "", names)

  if (inherits(model, "CmdStanMCMC")) {
    if (!is.null(data)) {
      stop("A CmdStanMCMC binds its data; use model source and data to evaluate different data.", call. = FALSE)
    }
    if (!requireNamespace("cmdstanr", quietly = TRUE)) {
      stop("The cmdstanr package is required for a CmdStanMCMC evaluator.", call. = FALSE)
    }
    evaluator <- model
    schema <- tryCatch({
      evaluator$init_model_methods(seed = as.integer(seed))
      parameter_skeleton <- evaluator$variable_skeleton(FALSE, FALSE)
      output_skeleton <- evaluator$variable_skeleton(TRUE, TRUE)
      declarations <- evaluator$runset$args$model_variables
      parameter_declarations <- declarations$parameters
      output_declarations <- c(parameter_declarations,
        declarations$transformed_parameters, declarations$generated_quantities)
      shape_for <- function(x, declaration) {
        if (!is.numeric(x) || is.list(x)) {
          stop("Only scalar and rectangular numeric types are supported.")
        }
        rank <- declaration$dimensions
        if (is.null(rank) || length(rank) != 1L || !is.numeric(rank)) {
          stop("The fit does not expose the declared rank of each model variable.")
        }
        if (rank == 0L) return(integer())
        shape <- dim(x)
        if (is.null(shape) || length(shape) != rank) {
          stop("The compiled variable shape does not match its declared rank.")
        }
        shape
      }
      shapes <- stats::setNames(lapply(names(parameter_skeleton), function(name) {
        shape_for(parameter_skeleton[[name]], parameter_declarations[[name]])
      }), names(parameter_skeleton))
      names_for <- function(skeleton, definitions) {
        unlist(lapply(names(skeleton), function(name) {
          x <- skeleton[[name]]
          shape <- shape_for(x, definitions[[name]])
          if (!length(x)) return(character())
          if (!length(shape)) return(name)
          coordinates <- arrayInd(seq_len(length(x)), .dim = shape)
          paste0(name, "[", apply(coordinates, 1L, paste, collapse = ","), "]")
        }), use.names = FALSE)
      }
      list(parameters = names_for(parameter_skeleton, parameter_declarations),
           outputs = names_for(output_skeleton, output_declarations), shapes = shapes)
    }, error = function(error) {
      stop("Could not initialize CmdStanR reconstruction methods: ",
           conditionMessage(error),
           ". The model's compiled methods and original data must be available.",
           call. = FALSE)
    })
    unconstrain <- function(parameters) evaluator$unconstrain_variables(parameters)
    constrain <- function(upars) evaluator$constrain_variables(
      upars, transformed_parameters = TRUE, generated_quantities = TRUE
    )
    backend <- "cmdstanr"
  } else {
    if (!requireNamespace("rstan", quietly = TRUE)) {
      stop("The rstan package is required for Stan source, stanmodel, or stanfit input.", call. = FALSE)
    }
    if (inherits(model, "stanfit")) {
      if (!is.null(data)) {
        stop("A stanfit already binds its data; pass a stanmodel or source to use data.", call. = FALSE)
      }
      evaluator <- model
    } else {
      if (!is.list(data) || (length(data) &&
          (is.null(names(data)) || anyNA(names(data)) || any(!nzchar(names(data))) ||
           anyDuplicated(names(data))))) {
        stop("Supply the matching named Stan data list (or list() for no data).", call. = FALSE)
      }
      if (inherits(model, "CmdStanModel")) {
        source_file <- model$stan_file()
        model <- if (!is.null(source_file) && file.exists(source_file)) {
          source_file
        } else paste(model$code(), collapse = "\n")
      }
      if (inherits(model, "pdb_model_code")) model <- as.character(model)
      if (is.character(model) && length(model) == 1L && !is.na(model)) {
        if (grepl("[{}\n\r]", model)) {
          model <- rstan::stan_model(model_code = model,
                                    model_name = "reconstruction_evaluator", auto_write = FALSE)
        } else {
          path <- path.expand(model)
          if (!file.exists(path)) stop("Stan source file does not exist: ", path, call. = FALSE)
          model <- rstan::stan_model(file = path,
                                    model_name = "reconstruction_evaluator", auto_write = FALSE)
        }
      }
      if (!inherits(model, "stanmodel")) {
        stop("model must be a stanfit, CmdStanMCMC, stanmodel, CmdStanModel, Stan file, or source string.", call. = FALSE)
      }
      # Zero chains bind data to the compiled model without performing MCMC.
      evaluator <- rstan::sampling(model, data = data, chains = 0L,
                                  seed = as.integer(seed), refresh = 0L)
    }
    instance <- evaluator@.MISC$stan_fit_instance
    if (is.null(instance)) {
      stop("The stanfit has no usable model instance; supply model source and data.", call. = FALSE)
    }
    schema <- tryCatch(list(
      parameters = draw_names(instance$constrained_param_names(FALSE, FALSE)),
      outputs = draw_names(instance$constrained_param_names(TRUE, TRUE)),
      unconstrained = draw_names(instance$unconstrained_param_names(FALSE, FALSE)),
      shapes = evaluator@par_dims
    ), error = function(error) {
      stop("The compiled model instance is invalid; supply model source and data: ",
           conditionMessage(error), call. = FALSE)
    })
    unconstrain <- function(parameters) rstan::unconstrain_pars(evaluator, parameters)
    constrain <- function(upars) rstan::constrain_pars(evaluator, upars)
    backend <- "rstan"
  }
  prepared <- proc.time()[["elapsed"]]
  required <- schema$parameters
  if (!length(required)) stop("Reconstruction requires at least one model parameter.", call. = FALSE)
  draws <- posterior::as_draws_array(draws)
  missing <- setdiff(required, posterior::variables(draws))
  if (length(missing)) {
    stop("Input must contain all parameter-block draw columns. Missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  values <- unclass(draws[, , required, drop = FALSE])
  if (any(!is.finite(values))) stop("Parameter draws must be finite.", call. = FALSE)
  parameter_bases <- unique(base_names(required))
  shapes <- schema$shapes[parameter_bases]
  indices <- lapply(parameter_bases, function(base) which(base_names(required) == base))
  for (j in seq_along(shapes)) {
    shape <- shapes[[j]]
    if (is.null(shape) || !is.numeric(shape) || anyNA(shape) ||
        any(!is.finite(shape)) || any(shape < 1) || any(shape != floor(shape)) ||
        prod(shape) != length(indices[[j]])) {
      stop("Unsupported or inconsistent output shape for parameter `", parameter_bases[[j]], "`.", call. = FALSE)
    }
  }
  output_names <- schema$outputs
  output_bases <- unique(base_names(output_names))
  if (is.null(variables)) {
    selected <- seq_along(output_names)
  } else {
    unknown <- setdiff(variables, c(output_names, output_bases))
    if (length(unknown)) stop("Unknown requested output(s): ", paste(unknown, collapse = ", "), call. = FALSE)
    selected <- which(output_names %in% variables | base_names(output_names) %in% variables)
  }
  nd <- dim(values)[1:2]
  if (any(nd < 1L)) stop("draws must contain at least one iteration and chain.", call. = FALSE)
  # CmdStanR does not expose unconstrained coordinate names without transforming
  # draws. Obtain the size from one supplied draw and use positional names.
  make_parameters <- function(iteration, chain) {
    stats::setNames(lapply(seq_along(parameter_bases), function(j) {
      vals <- unname(values[iteration, chain, indices[[j]]])
      if (!length(shapes[[j]])) vals[[1L]] else array(vals, dim = shapes[[j]])
    }), parameter_bases)
  }
  if (backend == "cmdstanr") {
    first_upars <- unconstrain(make_parameters(1L, 1L))
    schema$unconstrained <- paste0("upars[", seq_along(first_upars), "]")
  }
  output <- array(NA_real_, c(nd, length(selected)),
                  dimnames = c(dimnames(values)[1:2], list(output_names[selected])))
  unconstrained <- if (include_unconstrained) {
    array(NA_real_, c(nd, length(schema$unconstrained)),
          dimnames = c(dimnames(values)[1:2], list(schema$unconstrained)))
  } else NULL
  ready <- proc.time()[["elapsed"]]
  for (chain in seq_len(nd[[2L]])) {
    for (iteration in seq_len(nd[[1L]])) {
      parameters <- make_parameters(iteration, chain)
      evaluated <- tryCatch({
        upars <- unconstrain(parameters)
        reconstructed <- constrain(upars)
        flat <- unlist(reconstructed[output_bases], use.names = FALSE)
        if (length(upars) != length(schema$unconstrained) ||
            !all(output_bases %in% names(reconstructed)) ||
            length(flat) != length(output_names)) {
          stop("The model returned unexpected output names or counts.")
        }
        list(values = flat, upars = upars)
      }, error = function(error) {
        stop("Reconstruction failed at chain ", chain, ", iteration ", iteration,
             ": ", conditionMessage(error), call. = FALSE)
      })
      output[iteration, chain, ] <- evaluated$values[selected]
      if (include_unconstrained) unconstrained[iteration, chain, ] <- evaluated$upars
    }
  }
  evaluated_at <- proc.time()[["elapsed"]]
  result <- list(
    draws = posterior::as_draws_array(output), evaluator = evaluator,
    parameter_names = required, parameter_shapes = shapes, backend = backend,
    unconstrained_draws = if (include_unconstrained) posterior::as_draws_array(unconstrained) else NULL,
    timings = c(preparation = prepared - started, setup = ready - prepared,
                evaluation = evaluated_at - ready, total = NA_real_)
  )
  result$timings[["total"]] <- proc.time()[["elapsed"]] - started
  result
}
