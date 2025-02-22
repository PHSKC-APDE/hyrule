
list(
  tar_target(
    train_test_data, 
    compile_training_data(
        input = train_input,
        output_file = file.path(outdir, 'train_and_test.parquet'),
        formula = f,
        data = data,
        loc_history = lh,
        zip_history = zh,
        freq_tab_first_name = freqs[1],
        freq_tab_last_name = freqs[2],
        freq_tab_dob = freqs[3]
      )
    )
  )

