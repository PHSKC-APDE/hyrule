create_stacked_model = function(..., mnames, screener, singlemod = FALSE, bounds = screener$bounds){
  
  dots = list(...)
  names(dots) = mnames
  
  if(!singlemod){
    dots = do.call(workflowsets::as_workflow_set, dots)
    stk = stacks() %>% add_candidates(dots) %>% 
      blend_predictions() %>% fit_members()
  }else{
    if(length(dots)>1) stop('singlemod option only works with one model')
    stk = dots[[1]]
  }

  mods = hyrule::new_hyrule_link(screener[[1]], stk, bounds)
}
