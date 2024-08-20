#' Is vector a date
#' @param x vector
#' @export
is.Date <- function(x) inherits(x, 'Date')

#' Clean a vector of names
#' @param x character vector
#' @param bad_names a character vector of names in X to turn to NA
#' @details
#' Does not do splits
#' @export
clean_names = function(x, bad_names = c()){

  y = stringi::stri_trans_general(x, id = 'Latin-ASCII')
  y = trimws(toupper(y))
  # clean up punctuation and digits
  # Remove punctuation and digits
  y = gsub(
    "(?!-)[[:punct:]]|[[:digit:]]",
    "",
    y,
    perl = TRUE
  )

  # Clean up spaces
  y = gsub("  ", " ", y)
  y[y %in% c('1')] <- 'TRUE'
  y = gsub("[[:punct:]]|[[:space:]]", " ", y)

  # clean up JRs and SRs
  y = gsub(' JR$', '', y)
  y = gsub(' III$', '', y)
  y = gsub(' II$', '', y)
  y = gsub(' IV$', '', y)
  y = gsub(' SR$', '', y)

  # More spaces
  y = gsub('\\s{2,}',' ',y)

  # More triming
  y = trimws(y)

  y[y%in%bad_names] <- NA

  y

}

#' Replace NA entries with the other valid entries
#' @param x a vector
#' @export
fillblanks = function(x){
  Nu = length(unique(x))
  aNA = any(is.na(x))
  if(aNA == TRUE & Nu == 2){
    x[] <- unique(na.omit(x))
  }

  x
}

#' Remove spaces from a character
#' @param x character vector
#' @export
remove_spaces = function(x) gsub(' ', '', x, fixed = T)

#' Replace NA with blanks ('')
#' @param x a character vector (or something to be converted to character)
nb = function(x) {
  x = as.character(x)
  x[is.na(x)] <- ''
  x
}

#' Make a row-wise hash from a data.frame (or list)
#' @param x single level list (e.g. data.frame)
#' @export
make_hash = function(x){
  x = lapply(x, nb)
  x$sep = '|'
  openssl::md5(do.call(paste, x))
}

