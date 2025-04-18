
#' clean a column of ZIP codes
#' @param x vector of zip codes
#'
clean_zip_code = function(x){
  zzz = stringr::str_extract_all(x, "[0-9]+")
  zzz = lapply(zzz, paste, collapse = "")
  zzz = substr(zzz, 1, 5)
  zzz[zzz %in% c('', 'NA')] <- NA

  zzz
}

#' Compute and save zip centriods
#'
#' @param input file.path. File path to an file that sf can read containing ZIP codes and its geometry
#' @param output file.path. File path to a parquet file where the results will be saved
#' @param zip_code_col character. column in input that identifies the ZIP code
format_zip_centers = function(input, output, zip_code_col){
  i = read_sf(input)
  i = i[, zip_code_col]
  ans = st_coordinates(st_centroid(i))
  ans = as.data.table(ans)[, .(X,Y)]
  ans[, zip_code := clean_zip_code(i[[zip_code_col]])]

  if(!is.null(output)){
    arrow::write_parquet(ans, output)
    return(output)
  }else{
    return(ans)
  }

}

