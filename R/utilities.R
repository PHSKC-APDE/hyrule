#' Is vector a date
#' @param x vector
#' @export
is.Date <- function(x) inherits(x, 'Date')

#' Clean a vector of names
#' @param x character vector
#' @param type one of 'first' or last
#' @details
#' Does not do splits
#' @export
clean_names = function(x, type = 'first'){

  # convert encoding
  x = iconv(x, 'latin1', 'ASCII//TRANSLIT')

  # Remove punctuation and digits
  x = gsub(
    "(?!-)[[:punct:]]|[[:digit:]]",
    "",
    x,
    perl = TRUE
  )
  x = gsub("  ", " ", x)
  x = gsub("[[:punct:]]|[[:space:]]", " ", x)

  toupper(x)


}
