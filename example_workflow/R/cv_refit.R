#' Refit a stacker model with crossvalidation 

cv_refit = function(train, model_path, apply_screen, iteration, nfolds = 5, lasso = T){

  i = iteration
  fitme = arrow::read_parquet(train)

  mods = model_path
  if(is.character(mods)){
    if(file.exists(mods)){
      mods = readRDS(mods)
    } else {
      stop('goofy things')
    }
  }
  
  
  vars = setdiff(mods[[2]]$model_defs[[1]]$pre$actions$recipe$recipe$var_info$variable, 'pair')
  if(is.null(vars)) vars = setdiff(mods$stack$pre$actions$recipe$recipe$var_info$variable, 'pair')
  theform = as.formula(paste('pair ~', paste(vars, collapse = '+')))
  
  # refit the model
  refit = function(dat, theform, mods){
    folds = rsample::vfold_cv(dat, 5)
    
    ## Refit the ensemble on the subset of data ---- 
    link_rec = recipes::recipe(dat, formula = theform)
    
    ### Create workflow ----
    if(inherits(mods$stack, 'model_stack')){

      wf_set = do.call(as_workflow_set, mods[[2]]$member_fits)
      wf_trained = workflow_map(wf_set, fn = 'fit_resamples', resamples = folds, control = control_stack_resamples())
      ### Fit ----
      stk = stacks() %>% add_candidates(wf_trained) %>% 
        blend_predictions() %>% fit_members()
    }else{
      stk = fit(mods$stack, data = dat)
    }
    
    stk

  }
  
  fitme[, fold_id := sample(1:nfolds, .N,replace = T)]
  
  ## For 5 folds ----
  r = lapply(unique(fitme[, fold_id]), function(k){
    minid = fitme[fold_id != k]
    scr = fit_link(minid, theform, bounds = mods$bounds, lasso = lasso, stage_one_only = T)
    if(apply_screen && !is.null(mods$screen)){
      sdat = minid[scr$i]
    }else{
      sdat = minid
    }
    m = refit(dat = sdat, theform, mods)
    if(is.null(mods$screen)){
      m = new_hyrule_link(NULL, m, mods$bounds)
      
    }else{
      m = new_hyrule_link(scr[[1]], m, mods$bounds)
      
    }
    oos = predict(m, fitme[fold_id == k])[, 'final']
    obj = data.table(i = i, k = k, final = oos)
    obj = cbind(fitme[fold_id == k, .(id1,id2, pair = as.numeric(as.character(pair)))], obj)
    
    obj
  })
  
  r = rbindlist(r)
  r = merge(r, fitme[, .(id1, id2)], all.x = T)

  r
  
  
}
