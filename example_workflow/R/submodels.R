#' Make folds
#' @param train file.path to the training data
#' @param screener screening model
make_folds = function(train, screener){
  fitme = arrow::read_parquet(train)
  data.table::setDT(fitme)
  rsample::vfold_cv(fitme[screener$i,], 5)
  
}

#' Fit a submodel
#' @param train file path to training data
#' @param screener screening model
#' @param folds folds from rsample
#' @param m model specification
#' @param theform model formula
#' @param apply_screen logical. Should rows be screened out (by the screening model) be removed from the training dataset for the model
#' @param stacked logical. Is the model going to be part of a stacked ensemble
fit_submodel = function(train, screener, folds, m, theform, apply_screen = T, stacked = TRUE){
  
  tuner = 'bayes'
  trainsub = arrow::read_parquet(train)
  data.table::setDT(trainsub)
  
  if(apply_screen) trainsub = trainsub[screener$i]
  
  vvv = attr(terms(theform), 'term.labels')
  
  
  # recipe
  link_rec = recipes::recipe(trainsub, formula = theform)

  params = extract_parameter_set_dials(m) %>% finalize(trainsub[ ,.SD, .SDcols = vvv])
  
  wf = workflow(link_rec, m)
  
  if(stacked){
    ctrl = control_bayes(save_pred = T, save_workflow = T, event_level = 'second')
  } else{
    ctrl = control_bayes(save_workflow = T)
  }
  
  
  mets = yardstick::metric_set(mn_log_loss, roc_auc, f_meas) #, accuracy 
  
  if(tuner == 'bayes'){
    wf_search = tune::tune_bayes(wf,
                                 resamples = folds,
                                 control = ctrl,
                                 iter = 300,
                                 initial = 30,
                                 metrics = mets,
                                 param_info = params)
  }else if(tuner == 'anneal'){
    wf_search = finetune::tune_sim_anneal(wf,
                                          resamples = folds,
                                          control = finetune::control_sim_anneal(save_pred = T, save_workflow = T, event_level = 'second'),
                                          iter = 100,
                                          initial = 20,
                                          metrics = mets,
                                          param_info = params)
  }else if(tuner == 'race'){
    wf_search = finetune::tune_race_win_loss(wf,
                                          resamples = folds,
                                          control = finetune::control_race(save_pred = T, save_workflow = T, event_level = 'second'),
                                          grid = 30,
                                          metrics = mets,
                                          param_info = params)
  }else(
    stop('Invalid tuner in the bagging area')
  )
  

  if(!stacked) wf_search = fit_best(wf_search)
  
  wf_search = butcher::butcher(wf_search)
  
  
}