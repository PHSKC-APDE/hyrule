#' Fit a linkage model (screening model + a stacked ensemble
#' @param train data.frame containing the training data
#' @param formula formula. The formula to fit
#' @param ensemble a named list of parsnip model specifications
#' @param bounds numeric. Two numbers (0-1) representing the predicted probability bounds from the screening model that should be fit with the ensemble.
#' Results outside these bounds are considered clear enough (not-)matches to not need further processing.
#' @param stage_one_only logical. Whether to return the stage one results so that models can be custom implemented with the larger tidy models universe
#' @param lasso logical. Whether a standard GLM (F, the default) or a lasso regression (T) should be used as the screening model
#' @param penalty_seq numeric. Vector of numeric values [0-1] denoting possible penalties
#' @importFrom data.table between
#' @importFrom rsample vfold_cv
#' @importFrom recipes recipe
#' @importFrom workflowsets workflow_set option_add workflow_map
#' @importFrom stacks control_stack_grid stacks add_candidates blend_predictions fit_members
#' @importFrom stacks %>%
#' @importFrom butcher butcher
#' @importFrom parsnip logistic_reg fit
#' @importFrom tune select_best tune control_grid tune_grid
#' @importFrom rsample vfold_cv
#' @importFrom yardstick metric_set mn_log_loss
#' @importFrom workflows add_model add_recipe
#' @export
fit_link = function(train, formula, ensemble = default_ensemble(), bounds = c(.001,.999),
                    stage_one_only = FALSE, lasso = F, penalty_seq = seq(.0001, .1, length.out = 200)){

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
  stopifnot('Outcome variable must be a factor with levels 0 and 1' = is.factor(train[[as.character(formula)[[2]]]]))
  stopifnot(all(c(0,1) %in% levels(train[[as.character(formula)[[2]]]])))

  # fit the models
  # start with logistic regression
  if(lasso){
    # Find optimal penalty value
    screen = parsnip::logistic_reg(penalty = tune('penalty'), engine = 'glmnet', mixture = 1)
    screen_wf = workflows::workflow() %>%
      workflows::add_model(screen) %>%
      workflows::add_recipe(recipes::recipe(train, formula))

    penalty_grid = data.frame(penalty = penalty_seq)

    best_pen = screen_wf %>%
      tune::tune_grid(resamples = rsample::vfold_cv(train, v = 5),
                grid = penalty_grid,
                control = tune::control_grid(verbose = F, save_pred = T),
                metrics = yardstick::metric_set(yardstick::mn_log_loss)) %>%
      tune::select_best()


    screen = parsnip::logistic_reg(engine = 'glmnet', mixture = 1, penalty = best_pen$penalty) %>%
      parsnip::fit(data = train, formula = formula)

  }else{
    screen = parsnip::logistic_reg(engine = 'glm') %>% parsnip::fit(data = train, formula = formula)
  }

  screen = butcher::butcher(screen)

  # in sample training predictions
  s1 = predict(screen, train, type = 'prob')[,'.pred_1', drop = T]

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
