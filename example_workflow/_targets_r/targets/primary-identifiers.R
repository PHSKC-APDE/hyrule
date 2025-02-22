list(
  # file paths to data
  tarchetypes::tar_files_input(input_1, '../data-raw/fake_one.parquet'),
  tarchetypes::tar_files_input(input_2, '../data-raw/fake_two.parquet'),
  
  # Load, clean, and save datasets
  tar_target(data, init_data(c(input_1, input_2), file.path(outdir, 'data.parquet')), format = 'file')


)
