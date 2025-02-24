list(
  tar_target(screener, 
  command = fit_screening_model(test_train_split[2], bounds, f))
)
