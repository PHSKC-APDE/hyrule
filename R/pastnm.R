#' Concatenate strings and remove NAs
#' @param ... see paste0
#' @export
pastenm = function(...){

  dots = list(...)
  dots = lapply(dots, function(x){
    x[is.na(x)] = ''
    x
  })

  do.call(paste0, dots)

}
