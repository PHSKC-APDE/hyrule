#' Predict links
#' @param pairs
#' @param model
#' @param output_folder
#' @param data file path to a parquet file containing the data
#' @param loc_history file path to location history file
#' @param zip_history file path to zip history parquet file
#' @param freq_tab_first_name file path to frequency table for first names parquet file
#' @param freq_tab_last_name file path to frequency table for last names parquet file
#' @param freq_tab_dob file path to frequency table for dob parquet file
predict_links = function(pairs, model, output_folder, data, loc_history, zip_history, freq_tab_first_name, freq_tab_last_name, freq_tab_dob){

  ddb = DBI::dbConnect(duckdb::duckdb())
  loadspatial(ddb)

  if(is.character(model)){
    if(file.exists(model)){
      model = readRDS(model)
    } else {
      stop('goofy things')
    }
  }
  if(!is.data.frame(pairs) && is.list(pairs) && length(pairs) == 1) pairs = pairs[[1]]
  mmf = make_model_frame(
    pairs = pairs,
    data = data,
    lh = loc_history,
    zh = zip_history,
    ft_first = freq_tab_first_name,
    ft_last = freq_tab_last_name,
    ft_dob = freq_tab_dob
  )

  predme = dbGetQuery(ddb, mmf) # glue::glue_sql('SET threads TO 1; {mmf}', .con = ddb)
  setDT(predme)
  vvv = broom::tidy(model[[1]])$term
  vvv = vvv[-1]
  for(v in vvv){
    if(!v %in% names(predme)) predme[, (v) := 0]
  }
  preds = predict(model, predme, members = T)

  ### Filter ones that are too low ----
  preds = cbind(predme[, .(id1, id2)], round(preds,3))
  preds = preds[final >.05]

  if(!is.null(output_folder)){
    ootf = file.path(output_folder, paste0('preds_', basename(pairs)))
    arrow::write_parquet(preds, ootf)
    return(ootf)
  }else{
    return(preds)
  }

}
