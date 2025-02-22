list(
  # Prepare the location histories
  tar_target(
    lh,
    create_location_history(
      input = c(input_1, input_2),
      # This changes based on data storage/format
      output_file = file.path(outdir, 'lh.parquet'),
      id_cols = c('source_system', 'source_id'),
      X = 'X',
      Y = 'Y'
    ),
    format = 'file'
  ),
  
  # Prepare ZIP code histories
  tar_target(
    zh,
    create_history_variable(
    input = c(input_1,input_2),
    output_file = file.path(outdir, 'zh.parquet'),
    id_cols = c('source_system', 'source_id'),
    variable = 'zip_code',
    clean_function = clean_zip_code
    ),
    format = 'file'
  )
)
