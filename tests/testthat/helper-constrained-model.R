constrained_parameter_model <- function() {
  paste(
    "parameters { simplex[1] fixed; simplex[3] weights; corr_matrix[3] C;",
    "cov_matrix[2] Sigma; cholesky_factor_corr[3] Lcorr;",
    "cholesky_factor_cov[3] Lcov; matrix[2,3] M; vector[1] singleton;",
    "array[2] vector[2] a; real theta; }",
    "transformed parameters { real twice_theta = 2 * theta; }",
    "model { weights ~ dirichlet(rep_vector(1,3)); C ~ lkj_corr(1);",
    "Sigma ~ wishart(3,diag_matrix(rep_vector(1,2))); Lcorr ~ lkj_corr_cholesky(1);",
    "to_vector(Lcov) ~ normal(0,1); to_vector(M) ~ normal(0,1);",
    "singleton ~ normal(0,1); for(i in 1:2) a[i] ~ normal(0,1); theta ~ normal(0,1); }",
    "generated quantities { real prediction = theta; }")
}
