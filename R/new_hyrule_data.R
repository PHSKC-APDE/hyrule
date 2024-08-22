#' Create a new hyrule data object
#' @param src One of a data.frame type object,
#' vector of .parquet file paths, or a DBIConnection object
#' @param table_name when `src` is a DBIConnection, a table name using I or DBI::Id. See dbplyr \href{https://dbplyr.tidyverse.org/reference/tbl.src_dbi.html}{documentation} for more info
#' @param ... arguments passed onto lower level functions for
#' @details stuff
#' @export
new_hyrule_data = function(src, ...){
  UseMethod('new_hyrule_data')
}

#' @rdname new_hyrule_data
#' @export
new_hyrule_data.data.frame = function(src, ...){
  class(src) <- c('hyrule_data', class(src))
  src
}

#' @rdname new_hyrule_data
#' @export
new_hyrule_data.character = function(src, ...){
  r = open_dataset(src, ...)
  class(r) <- c('hyrule_data', class(r))
  r

}

#' @rdname new_hyrule_data
#' @export
new_hyrule_data.Dataset = function(src, ...){
  class(src) <- c('hyrule_data', class(src))
  src
}

#' @rdname new_hyrule_data
#' @export
new_hyrule_data.DBIConnection = function(src, from, ...){
  r = dplyr::tbl(src, from, ...)
  class(r) <- c('hyrule_data', class(r))
  r
}
