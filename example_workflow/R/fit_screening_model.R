#' Fit the first stage screening model
#' @param fitmefp file path to parquet file
#' @param bounds numeric bounds to which the ML models will focus
#' @param theform formula for the models
fit_screening_model = function(fitmefp, bounds, theform){
  
  fitme = arrow::read_parquet(fitmefp)
  data.table::setDT(fitme)
  
  l = fit_link(fitme, theform, bounds = bounds, lasso = T, stage_one_only = T)
  
  
}
