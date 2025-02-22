list(
  # Create frequency tables
  tar_target(
    freqs,
    create_frequency_table(
      tables = list(data),
      columns = c('first_name_noblank', 'last_name_noblank', 'dob_clean'),
      output_folder = outdir
    ), format = 'file'
  )
)
