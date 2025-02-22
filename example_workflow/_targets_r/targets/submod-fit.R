submods = list(
  tarchetypes::tar_map(
    values = s_params,
    names = 'nm',
    tar_target(submod,
               fit_submodel(
                 train = test_train_split[2],
                 screener = screener,
                 folds = tfolds,
                 m = MODEL,
                 theform = f,
                 apply_screen = apply_screen
                )
              )
  )
)

