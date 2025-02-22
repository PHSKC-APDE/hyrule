#' linkages that are a-priori decided

fixed_links = function(data, model_path, fixed_vars = c('source_system', 'source_id'), id_col = 'clean_hash', output_file){
  ddb = DBI::dbConnect(duckdb::duckdb())

  if(is.character(model_path)){
    if(file.exists(model_path)){
      model_path = readRDS(model_path)
    } else {
      stop('goofy things')
    }
  }
  dtab = data
  cols = lapply(c(id_col, fixed_vars), function(x) DBI::Id(column = x))
  lid = DBI::Id(schema = 'l', column = paste0(id_col))
  rid = DBI::Id(schema = 'r', column = paste0(id_col))
  fixins = setDT(dbGetQuery(ddb,
                            glue::glue_sql('
                 with d as (select distinct {`cols`*} from {`dtab`})

                 select {`lid`} as id1, {`rid`} as id2
                 from d as l
                 inner join d as r on (
                 l.source_system = r.source_system AND
                 l.source_id = r.source_id AND
                 {`lid`} < {`rid`});

                 ',.con = ddb)))

  # Keep only where there are more than 1 id per fixed
  fixins[, screen := 1]
  addme = broom::tidy(model_path$stack$coefs)
  setDT(addme)
  if(nrow(addme)>0){
    smodel_path = addme[estimate != 0 & term != '(Intercept)', gsub('.pred_1_', '', term, fixed = T)]
  }else{
    smodel_path = NULL
  }
  # cvars = c('missing_ssn', 'missing_zip', 'missing_ah')
  fixins[, c('ens', smodel_path) := NA_real_]
  fixins[, final := 1]
  fixins[id1>id2, c('id1', 'id2') := list(id2, id1)]

  arrow::write_parquet(fixins, output_file)

  output_file
}
