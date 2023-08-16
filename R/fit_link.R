#' Fit a linkage model (screening model + a stacked ensemble
#' @param train data.frame containing the training data
#' @param formula formula. The formula to fit
#' @param ensemble a named list of parsnip model specifications
#' @param bounds numeric. Two numbers (0-1) representing the predicted probability bounds from the screening model that should be fit with the ensemble.
#' Results outside these bounds are considered clear enough (not-)matches to not need further processing.
#' @param stage_one_only logical. Whether to return the stage one results so that models can be custom implemented with the larger tidy models universe
#' @importFrom data.table between
#' @importFrom rsample vfold_cv
#' @importFrom recipes recipe
#' @importFrom workflowsets workflow_set option_add workflow_map
#' @importFrom stacks control_stack_grid stacks add_candidates blend_predictions fit_members
#' @importFrom stacks %>%
#' @importFrom butcher butcher
#' @importFrom stats glm
#' @export
fit_link = function(train, formula, ensemble = default_ensemble(), bounds = c(.001,.999), stage_one_only = FALSE){

  stopifnot(is.data.frame(train))
  stopifnot(inherits(formula, 'formula'))
  stopifnot(is.numeric(bounds))
  stopifnot(all(bounds<1 & bounds>0))
  stopifnot(bounds[1]<bounds[2])
  if(!stage_one_only){
    modspec = sapply(ensemble, function(x) inherits(x, 'model_spec'))
    stopifnot('Ensemble must be a list of parsnip models and inhereit model_spec' = all(modspec))
    mtypes = sapply(ensemble, function(x) x$mode == 'classification')
    stopifnot('Only classification type models allowed at the moment.
            Contact maintainer if you have a regression need' = all(mtypes))
  }
  stopifnot('Outcome variable must be a factor with levels 0 and 1' = is.factor(train[[as.character(theform)[[2]]]]))
  stopifnot(all(c(0,1) %in% levels(train[[as.character(theform)[[2]]]])))

  # fit the models
  # start with logistic regression
  screen = stats::glm(formula, family = 'binomial', data = train)
  screen = butcher::butcher(screen)

  # in sample training predictions
  s1 = predict(screen, train, type = 'response')

  if(stage_one_only){
    return(list(screen = screen, bounds = bounds, i = data.table::between(s1, bounds[1], bounds[2])))
  }

  trainsub = train[data.table::between(s1, bounds[1], bounds[2])]

  folds = rsample::vfold_cv(trainsub, v = 5)

  link_rec = recipes::recipe(trainsub, formula = formula)

  wrk = workflowsets::workflow_set(preproc = list(data =link_rec),
                                   models = ensemble) %>%
    workflowsets::option_add(control = stacks::control_stack_grid()) %>%
    workflowsets::workflow_map(fn = 'fit_resamples', resamples = folds)

  # make the stack
  stk = stacks::stacks() %>% add_candidates(wrk)

  res = stk %>% blend_predictions() %>% fit_members()

  return(new_hyrule_link(screen, res, bounds))

}

#' default ensemble of ML models for linkage
#' @export
#' @importFrom parsnip rand_forest boost_tree svm_linear set_engine
#' @importFrom stacks %>%
default_ensemble = function(){
  # Build a tiny models stack
  list(rf = parsnip::rand_forest(mode = 'classification', trees = 1000),
       xg = parsnip::boost_tree(mode = 'classification') %>% set_engine('xgboost', objective = 'binary:logistic'),
       svm = parsnip::svm_linear(mode = 'classification', engine = 'kernlab'))
}
