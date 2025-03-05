list(
  # Load, clean, and save datasets
  tar_target(data, init_data(
    c(input_1, input_2), 
    file.path(outdir, 'data.parquet')), format = 'file')
)
