list(
  # Note: This step is mostly just so the example(s) can run
  tar_target(train_input,
             convert_sid_to_hid(
               pairs = hyrule::train, 
               arrow::read_parquet(data),
               output_file = file.path(outdir, 'training.parquet')
               ), format = 'file'
             )
  
  # usually something like the following is better
  #tarchetypes::tar_files_input(train_input,'FILEPATHS to training data goes here'))
)



