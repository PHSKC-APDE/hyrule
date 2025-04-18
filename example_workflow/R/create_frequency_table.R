#' Generate a frequency table for a given column
#' @param tables file path to parquet files contained the data (and columns) to compute frequencies for
#' @param columns character. Columns in tables to create frequencies for
#' @param output_folder directory path to save results
#' @details
#' This function uses a temporary (in memory)duckdb and parquet files to compute the frequency of values within selected columns
#'
#' @return file paths, one per column. This function also saves data to output_folder
#'
create_frequency_table = function(tables, columns, output_folder){
  ddb = dbConnect(duckdb())
  on.exit({
    DBI::dbDisconnect(ddb, shutdown = TRUE)
  })
  stopifnot(is.list(tables))

  ans = lapply(columns, function(nm){

    col = DBI::Id(column = nm)
    dtab = lapply(tables, function(d){
      dt = parquet_to_ddb(d)
      glue::glue_sql('select {`col`} from {dt}', .con = ddb)
    })
    dtab = glue::glue_sql_collapse(dtab, ' union all ')
    q = glue::glue_sql('select count(*) as N, {`col`} from ({`dtab`}) as d group by {`col`}', .con = ddb)
    r = setDT(dbGetQuery(ddb, q))
    r[, paste0(nm, '_freq') := round((N-min(N)) / (max(N) - min(N)),4)]

    if(!is.null(output_folder)){
      out = file.path(output_folder, paste0(nm, '_freq', '.parquet'))
      arrow::write_parquet(r, out)
      return(out)
    }else{
      return(r)
    }



  })

  return(unlist(ans))
}
