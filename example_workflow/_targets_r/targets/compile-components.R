tar_target(components, 
           compile_links(
             preds,
             fixed,
             data = data, 
             id_col = 'clean_hash',
             cutpoint = cutme$cutpoint,
             output_folder = outdir
           ), format = 'file')
