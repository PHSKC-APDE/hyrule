list(
  tar_target(
    blocks,
    make_block(
      q = qgrid,
      data = data,
      id_col = 'clean_hash',
      deduplicate = FALSE,
      output_folder = outdir
    ),
    pattern = map(qgrid),
    format = 'file'
  ),
  tar_target(
    bids,
    compile_blocks(
      blocks = blocks,
      output_folder = outdir,
      chk_size = 10000
    ),
    format = 'file'
  ),
  tar_target(bid_files, bids)
)
