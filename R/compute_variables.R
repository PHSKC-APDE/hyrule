#' Create variables for linkage
#' @param input data.table of pairs from two datasets prepped with prep_data_for_linkage
#' @param sex logical. Should sex/gender based variables be computed?
#' @export
compute_variables = function(input, sex = F){
  # Hamming distance
  ham = function(x,y) stringdist(as.character(x), as.character(y), 'hamming')

  # Hamming distance of DOB
  input[, dob_ham := ham(dob1, dob2)]
  input[, mis_dob := as.integer(is.na(dob_ham))]
  input[, mean_dob_ham := mean(dob_ham, na.rm= T)]
  input[mis_dob == 1, dob_ham := mean_dob_ham]

  # do the sex designations disagree
  if(sex){
    input[, sex_disagree := as.integer(sex1 != sex2)]
    input[is.na(sex_disagree), sex_disagree := 0]
  }

  # first name distances
  ## cosine bigram
  input[!is.na(fn1) & !is.na(fn2),
        fn_cos2 := stringdist(fn1, fn2,method = 'cosine',
                              q = ifelse(nchar(fn1) <2 | nchar(fn2) <2,1,2))]
  input[is.na(fn_cos2), fn_cos2 := 1]

  ## jaro-winkler
  input[!is.na(fn1) & !is.na(fn2),
        fn_jw := stringdist(fn1, fn2,method = 'jw', p = .1)]
  input[is.na(fn_jw), fn_jw := 1]

  ## soundex
  input[!is.na(fn1) & !is.na(fn2),
        fn_sx := stringdist(fn1,fn2, method = 'soundex')]
  input[is.na(fn_sx), fn_sx := 1]

  # last name differences
  ## cosine bigram
  input[!is.na(ln1) & !is.na(ln2),
        ln_cos2 := stringdist(ln1, ln2,method = 'cosine',
                              q = ifelse(nchar(ln1) <2 | nchar(ln2) <2,1,2))]
  input[is.na(ln_cos2), ln_cos2 := 1]

  ## jaro-winkler
  input[!is.na(ln1) & !is.na(ln2),
        ln_jw := stringdist(ln1, ln2,method = 'jw', p = .1)]
  input[is.na(ln_jw), ln_jw := 1]

  ## soundex
  input[!is.na(ln1) & !is.na(ln2),
        ln_sx := stringdist(ln1,ln2, method = 'soundex')]
  input[is.na(ln_sx), ln_sx := 1]

  # combined name trigram cosine
  input[, cn1 := paste0(fn1,ln1)]
  input[, cn2 := paste0(fn2, ln2)]
  input[!is.na(cn1) | !is.na(cn2),
        cn_cos := stringdist(cn1, cn2, 'cosine', q = 3 )]
  input[is.na(cn_cos), cn_cos := 1]

  # flags for identical daymonth
  input[, daymonth := as.integer(mday(dob1) == mday(dob2) & month(dob1) == month(dob2))]
  input[is.na(daymonth), daymonth := 0]

  return(input)
}
