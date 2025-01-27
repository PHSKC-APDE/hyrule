list(
  # file paths to data
  tarchetypes::tar_files_input(input_1, '../data-raw/fake_one.parquet'),
  tarchetypes::tar_files_input(input_2, '../data-raw/fake_two.parquet'),
  
  # Load, clean, and save datasets
  tar_target(data_1, init_data(input_1, file.path(outdir, 'd1.parquet')), format = 'file'),
  
  # Specify second dataset for link only example
  tar_target(data_2, init_data(input_2, file.path(outdir, 'd2.parquet')), format = 'file'),

  # if this is a linkdedupe situation, you'd probably want to do the following instead of : 
  # tar_target(data_2, data_1, format = 'file)
  
  # Create frequency tables
  tar_target(freqs, create_frequency_table(tables = list(data_1, data_2),
                                           columns = c('first_name_noblank', 'last_name_noblank', 'dob_clean'), 
                                           output_folder = outdir))

)
