#' Project future incidence
#'
#' This function simulates future incidence based on past incidence data, a
#' selection of plausible reproduction numbers (R), and the distribution of the
#' serial interval (time from primary onset to secondary onset).
#'
#' @export
#'
#' @author Pierre Nouvellet (original model), Thibaut Jombart (bulk of the
#'   code), Sangeeta Bhatia (Negative Binomial model)
#'
#' @param x An \code{incidence} object containing daily incidence; other time
#'   intervals will trigger an error.
#'
#' @param R A vector of numbers representing plausible reproduction numbers; for
#'   instance, these can be samples from a posterior distribution using the
#'   `earlyR` or `EpiEstim` packages. If `time_change` is provided, then it must
#'   be a `vector` (for fixed values of R per time window) or a `list` of
#'   vectors (for separate distributions of R per time window), with one element
#'   more than the number of dates in `time_change`.
#'
#' @param si A function computing the serial interval, or a `numeric`
#'   vector providing its mass function. For functions, we strongly recommend
#'   using the RECON package \code{distcrete} to obtain such distribution (see
#'   example).
#'
#' @param n_sim The number of epicurves to simulate. Defaults to 100.
#'
#' @param n_days The number of days to run simulations for. Defaults to 14.
#'
#' @param R_fix_within A logical indicating if R should be fixed within
#'     simulations (but still varying across simulations). If \code{FALSE}, R is
#'     drawn for every simulation and every time step. Fixing values within
#'     simulations favours more extreme predictions (see details)
#'
#' @param model Distribution to be used for projections. Must be one of
#' "poisson" or "negbin" (negative binomial process). Defaults to poisson
#'
#' @param size size parameter of negative binomial distribition. Ignored if
#' model is poisson
#'
#' @param time_change an optional vector of times at which the simulations
#'   should use a different sample of reproduction numbers, provided in days
#'   into the simulation (so that day '1' is the first day after the input
#'   `incidence` object); if provided, `n` dates in `time_change` will produce
#'   `n+1` time windows, in which case `R` should be a list of vectors of `n+1`
#'   `R` values, one per each time window.
#'
#' @details The decision to fix R values within simulations
#'     (\code{R_fix_within}) reflects two alternative views of the uncertainty
#'     associated with R. When drawing R values at random from the provided
#'     sample, (\code{R_fix_within} set to \code{FALSE}), it is assumed that R
#'     varies naturally, and can be treated as a random variable with a given
#'     distribution. When fixing values within simulations (\code{R_fix_within}
#'     set to \code{TRUE}), R is treated as a fixed parameter, and the
#'     uncertainty is merely a consequence of the estimation of R. In other
#'     words, the first view is rather Bayesian, while the second is more
#'     frequentist.
#'
#'
#' @examples
#'
#' ## example using simulated Ebola outbreak
#' if (require(outbreaks) &&
#'     require(distcrete) &&
#'     require(incidence) &&
#'     require(magrittr)) {
#'
#' si <- distcrete("gamma", interval = 1L,
#'                  shape = 0.37,
#'                  scale = 41.4, w = 0)
#'
#' i <- incidence(ebola_sim$linelist$date_of_onset)
#' plot(i)
#'
#'
#' ## projections after the first 100 days, over 60 days, fixed R to 2.1
#'
#' set.seed(1)
#' proj_1 <- project(x = i[1:100], R = 2.1, si = si, n_days = 60)
#' plot(proj_1)
#'
#' ## add projections to incidence plot
#' plot(i[1:160]) %>% add_projections(proj_1)
#'
#'
#' ## projections after the first 100 days, over 60 days,
#' ## using a sample of R
#'
#' set.seed(1)
#' R <- rnorm(100, 1.8, 0.2)
#' hist(R, col = "grey", border = "white", main = "Distribution of R")
#' proj_2 <- project(x = i[1:100], R = R, si = si, n_days = 60)
#'
#' ## add projections to incidence plot
#' plot(i[1:160]) %>% add_projections(proj_2)
#'
#'
#' ## same with R constant per simulation (more variability)
#'
#' set.seed(1)
#' proj_3 <- project(x = i[1:100], R = R, si = si, n_days = 60,
#'                   R_fix_within = TRUE)
#'
#' ## add projections to incidence plot
#' plot(i[1:160]) %>% add_projections(proj_3)
#'
#'
#' ## time-varying R, 2 periods, R is 2.1 then 0.5
#' set.seed(1)
#' proj_4 <- project(i,
#'                   R = c(2.1, 0.5),
#'                   si = si,
#'                   n_days = 60,
#'                   time_change = 40,
#'                   n_sim = 100)
#' plot(proj_4)
#'
#' 
#' ## time-varying R, 2 periods, separate distributions of R for each period
#' set.seed(1)
#' R_period_1 <- runif(100, min = 1.1, max = 3)
#' R_period_2 <- runif(100, min = 0.6, max = .9)
#' 
#' proj_5 <- project(i,
#'                   R = list(R_period_1, R_period_2),
#'                   si = si,
#'                   n_days = 60,
#'                   time_change = 20,
#'                   n_sim = 100)
#' plot(proj_5)
#' 
#' }
#'

project <- function(x, R, si, n_sim = 100, n_days = 7,
                    R_fix_within = FALSE,
                    model = c("poisson", "negbin"),
                    size = 0.03,
                    time_change = NULL) {

  ## Various checks on inputs

  model <- match.arg(model)

  if (!inherits(x, "incidence")) {
    msg <- "x is not an incidence object"
    stop(msg)
  }

  if (as.integer(mean(incidence::get_interval(x))) != 1L) {
    msg <- sprintf(
        "daily incidence needed, but interval is %d days",
        as.integer(mean(incidence::get_interval(x)))
    )
    stop(msg)
  }

  if (ncol(incidence::get_counts(x)) > 1L) {
    msg <- sprintf("cannot use multiple groups in incidence object")
    stop(msg)
  }

  n_time_periods <- 1 # default value, erased if `time_change` provided
  
  if (!is.null(time_change)) {
    if (!is.numeric(time_change)) {
      msg <- sprintf("`time_change` must be `numeric`, but is a `%s`",
                     paste(class(time_change), collapse = ", "))
      stop(msg)
    }

    n_time_periods <- length(time_change) + 1

    if (!is.vector(R)) {
      msg <- sprintf("`R` must be a `vector` or a `list` if `time_change` provided; it is a `%s`",
                     paste(class(R), collapse = ", "))
      stop(msg)
    }

    if (length(R) != n_time_periods) {
      msg <- sprintf("`R` must be a `list` of size %d to match %d time changes; found %d",
                     n_time_periods,
                     n_time_periods - 1,
                     length(R))
      stop(msg)
    }
  }
  
  assert_R(R)


  ## useful variables
  n_dates_x <- nrow(incidence::get_counts(x))
  t_max <- n_days + n_dates_x - 1

  if (inherits(si, "distcrete")) {
    if (as.integer(si$interval) != 1L) {
      msg <- sprintf(
        "interval used in si is not 1 day, but %d)",
        si$interval
      )
      stop(msg)
    }

    ws <- rev(si$d(0:t_max))
  } else {
    si <- si / sum(si)
    si <- c(si, rep(0, t_max))
    ws <- rev(si)
  }


  if (is.null(time_change)) {
    time_change <- Inf
  }


  ## Computation of projections: we use the basic branching process with a
  ## Poisson likelihood, identical to the one used for estimating R0 in EpiEstim
  ## and earlyR. The force of infection on a given day is the sum of individual
  ## forces of infection. The invididual force of infection is computed as the
  ## R0 multiplied by the pmf of the serial interval for the corresponding day:

  ## lambda_{i,t} = R0 w(t - t_i)

  ## where 'w' is the PMF of the serial interval and 't_i' is the date of
  ## onset of case 'i'.


  ## initial conditions
  I0 <- matrix(incidence::get_counts(x), nrow = n_dates_x, ncol = n_sim)

  ## projection
  out <- rbind(I0, matrix(0, n_days, n_sim))
  t_start <- n_dates_x + 1
  t_stop <- t_max + 1
  t_sim <- seq(
    from = t_start,
    to = t_stop,
    by = 1L
  )

  ## time_change is provided in relative dates, i.e. date 1 is the first day of
  ## the simulation, but really is max(x$dates) + 1
  time_change <- t_start + time_change - 1

  ## handling time periods: to cover the more generic cases when `R` can change
  ## over different time periods, we treat all simulations like having time
  ## periods, with `R` being a list of vectors, one for each time period. If
  ## there are no changes, we just consider this is a single time period, so put
  ## `R` in a list of length 1. If there are `n` changes and the user provided a
  ## vector for R of length `n + 1`, we assume the `R` is constant per time
  ## period and input is silently converted to a list of length `n + 1`.

  time_period <- 1L
  
  if (!is.list(R)) { # i.e. R is a vector and needs conversion to a list
    if (n_time_periods > 1L) {  # several time periods
      R <- as.list(R)
     } else {  # a single time period
       R <- list(R)
     }
  }
  

  ## On the drawing of R values: either these are constant within simulations,
  ## so drawn once for all simulations, or they need drawing at every time step
  ## for every simulations.

  ## On the handling of reporting: reporting first affects the force of
  ## infection lambda, with the underlying assumption that the true epicurve
  ## multiplied by the (constant) reporting results in the observed one. Then,
  ## the true incidence (true_I) is determined using this lambda (Poisson
  ## process) and we apply effects sampling to this true incidence to get the
  ## projected one, using a Binomial sampling.

  if (R_fix_within) {
    R_time_period <- R[[time_period]]
    current_R <- sample_(R_time_period, n_sim, replace = TRUE)
  }

  for (i in t_sim) {
    ## update the time period if needed
    if (i %in% time_change) {
      time_period <- time_period + 1
    }
     
    if (!R_fix_within) {
    R_time_period <- R[[time_period]]
      current_R <- sample_(R_time_period, n_sim, replace = TRUE)
    }
    lambda <- utils::tail(ws, i) %*% out[seq_len(i), , drop = FALSE]
    ## lambda <- lambda / reporting
    if (model == "poisson") {
      out[i, ] <- stats::rpois(n_sim, current_R * lambda)
    } else {
      ## If mu = 0, then it doesn't matter what the size value is,
      ## rnbinom will output 0s (mu = 0 => p =1).
      ## mu will be 0 if lambda is 0. But that will make size 0 which
      ## will make rnbinom spit NAs. Workaround is: if lambda is 0
      ## set size to a non-trivial value.
      size_adj <- lambda * size
      idx <- which(lambda == 0)
      size_adj[idx] <- 1
      out[i, ] <- stats::rnbinom(n_sim, size = size_adj, mu = current_R * lambda)
    }
    ## out[i,] <- stats::rbinom(ncol(out), true_I, prob = reporting)
  }


  ## shape output: 'projections' objects are basically matrices of predicted
  ## incidence, with dates in rows and simulations in columns. Dates are
  ## stored as attributes of the object, in a format similar to that of the
  ## original dates in the 'incidence' object. We also store the original
  ## 'incidence' object in the attributes.

  out <- out[(n_dates_x + 1):(n_dates_x + n_days), , drop = FALSE]

  dates <- utils::tail(x$dates, 1) + seq_len(nrow(out))

  build_projections(out, dates, FALSE)
}
