tar_target(fixed, 
             fixed_links(
               data = data,
               model_path = model_path,
               fixed_vars = c('source_system', 'source_id'),
               id_col = 'clean_hash',
               output_file = file.path(outdir, 'fixed_links.parquet')
             ), format = 'file'
           )
