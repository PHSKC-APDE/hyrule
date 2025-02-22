list(
  tar_target(
    training_hash,
    rlang::hash(arrow::read_parquet(train_test_data))
  ),
  
  tar_target(test_train_split, 
             split_tt(hash = training_hash, 
                      training_data = train_test_data, 
                      fraction = .15, 
                      train_of = file.path(outdir, 'train.parquet'), 
                      test_of = file.path(outdir, 'test.parquet'))
             , format = 'file')
  
)
