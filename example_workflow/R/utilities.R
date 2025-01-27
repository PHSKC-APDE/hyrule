
#' Load the spatial extension within duckdb
#' @param ddb db Connection object
#' @return result of DB call
#' @details
#' This function should be used only for its side effect
#'
loadspatial = function(ddb){
  DBI::dbExecute(ddb, 'install spatial; load spatial;')

}

#' Generate SQL to read parquet files with duckdb
#' @param files parquet file paths#
parquet_to_ddb = function(files){
  ddb = DBI::dbConnect(duckdb::duckdb()) # purely for syntax stuff
  p_files = glue_sql_collapse(paste0("'", files,"'"), sep = ', ')
  pq = glue::glue_sql('read_parquet([{p_files}])', .con = ddb)
  pq

}

#' Load parquet files into a duckdb table
#' @param ddb duckdb database connection
#' @param files parquet files to upload into table
#' @param table database table created via DBI::Id()
#' @return DBI::Id of the destination table
load_parquet_to_ddb_table = function(ddb, files, table){

  parks = parquet_to_ddb(files)
  qry = glue::glue_sql('create or replace table {`table`} as
                       select * from {parks}', .con = ddb)
  DBI::dbExecute(ddb, qry)

  return(table)
}

