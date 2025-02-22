list(
tarchetypes::tar_combine(
    model,
    submods,
    command = create_stacked_model(
      !!!.x,
      mnames = s_params$nm,
      screener = screener,
      bounds = bounds
    )
  ),
  tar_target(model_path,
  {
    saveRDS(model, file.path(outdir, 'model.rds'))
    file.path(outdir, 'model.rds')
  },
  format = 'file')
)
