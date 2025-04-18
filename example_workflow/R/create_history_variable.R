#' Create a location history variable
#' @param input a file path (or paths) to a parquet file(s) or a function that returns a data frame
#' @param output_file file path to a .parquet file where the cleaned data will be saved. If NULL, the results are returned as a data frame
#' @param id_cols character. Columns in input (or its result) that group records within a history together. Usually it is the unique ID of the source
#' @param geom character. Column in input that points to a geometry column (e.g. something the sf package can deal with)
#' @param X character. Numeric column in input with the longitude information for a row
#' @param Y character. Numeric column in input with the latitude information for a row
#' @param ... arguments passed to input (when input is a function)
#' @details
#' This function:
#' 1) Loads data from the source specified by input
#' 2) Does some light standardization of inputs
#' 3) Exports a dataset to a parquet file that is long on id_cols and location history
#'
#' Note: Only one of (geom) and (X, Y, and crs) should be specified
#'
create_location_history = function(input, output_file = NULL, id_cols, geom = NULL, X, Y, ...){
  # Load data ----
  if(is.character(input) && all(file.exists(input))){
    d = rbindlist(lapply(input, arrow::read_parquet))
  }else if (is.function(input)){
    d = input(...)
  }else if(is.data.frame(input)){
    d = data.table(input) # copy input -- that's probably ok
  }
  setDT(d)

  #Note: the first section here (when geom is not null) is not tested
  if(!is.null(geom)){
    if(!missing(X) | !missing(Y)) stop('X and Y are specified along with geom. Only one set should be specified')

    ans = na.omit(d[, .SD, .SDcol = c(id_cols, geom)])

    ans = cbind(ans[, .SD, .SDcol = c(id_cols)], st_coordinates(ans[[geom]]))

  }else if(!missing(X) && !missing(Y)){
    ans = na.omit(d[, .SD, .SDcols = c(id_cols, 'X', 'Y')])

  }else{
    stop('X and Y OR geom must be specified')
  }

  if(!is.null(output_file)){
    arrow::write_parquet(ans, output_file)
    return(output_file)
  }else{
    return(ans)
  }

}

#' Create a history variable
#' @param input a file path (or paths) to a parquet file(s) or a function that returns a data frame
#' @param output_file file path to a .parquet file where the cleaned data will be saved. If NULL, the results are returned as a data frame
#' @param id_cols character. Columns in input (or its result) that group records within a history together. Usually it is the unique ID of the source
#' @param variable character. Column in input that specifying the variable to be turned into a history/list
#' @param clean_function function. Function to be applied to `variable` to clean/format it
#' @param ... arguments passed to input (when input is a function)
#' @details
#' This function:
#' 1) Loads data from the source specified by input
#' 2) Does some light standardization of inputs
#' 3) Exports a dataset to a parquet file that is long on id_cols and location history
#'
#' Note: Only one of (geom) and (X, Y, and crs) should be specified
#'
create_history_variable = function(input, output_file = NULL, id_cols, variable, clean_function = NULL, ...){
  # Load data ----
  if(is.character(input) && all(file.exists(input))){
    d = rbindlist(lapply(input, arrow::read_parquet))
  }else if (is.function(input)){
    d = input(...)
  }else if(is.data.frame(input)){
    d = data.table(input) # copy input -- that's probably ok
  }else{
    stop('Invalid `input`')
  }
  setDT(d)

  d = d[, .SD, .SDcols = c(id_cols, variable)]

  if(!missing(clean_function)) d[, (variable) := clean_function(get(variable))]

  d = na.omit(d)
  if(!is.null(output_file)){
    arrow::write_parquet(d, output_file)
    return(output_file)
  }else{
    return(d)
  }

}
