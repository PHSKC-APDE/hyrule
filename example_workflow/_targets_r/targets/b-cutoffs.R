cv_cutoffs = list(
  tarchetypes::tar_map(
    values = cutoff_df,
    names = 'name',
    tar_target(cv_co,
                 cv_refit(
                   train = test_train_split[2],
                   model_path = model_path,
                   apply_screen = apply_screen,
                   iteration = iter,
                   nfolds = 5,
                   lasso = T 
                 ))
  )
)
