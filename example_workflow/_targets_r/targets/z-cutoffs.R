list(
tarchetypes::tar_combine(
    cutme,
    cv_cutoffs,
    command = identify_cutoff(
      !!!.x,
      test = test_train_split[1],
      mods = model_path
    )
  ),
  tar_target(cutme_path,
  {
    saveRDS(cutme, file.path(outdir, 'cutme.rds'))
    file.path(outdir, 'cutme.rds')
  },
  format = 'file')
)
