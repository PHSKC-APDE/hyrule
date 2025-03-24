tar_target(components, 
           compile_links(
             preds,
             fixed,
             data = data, 
             id_col = 'clean_hash',
             cutpoint = cutme$cutpoint,
             output_folder = outdir,
             method = 'leiden',
             min_N = 15,
             max_density = .4,
             recursive = FALSE
           ), format = 'file')
