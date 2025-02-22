tar_target(preds,
        predict_links(
          pairs = bid_files,
          model = model_path,
          output_folder = outdir,
          data = data,
          loc_history = lh,
          zip_history = zh,
          freq_tab_first_name = freqs[1],
          freq_tab_last_name = freqs[2],
          freq_tab_dob = freqs[3]
        ), 
        pattern = map(bid_files), 
        iteration = 'list', 
        format = 'file')
