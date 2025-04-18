#' A function to convert pairs from source id to hash id
#' @param pairs a data.frame with the columns (id1, id2, pair)
#' @param ... data frames for do the source id to hash conversion
convert_sid_to_hid = function(pairs, ..., output_file){
  dots = list(...)

  dots = rbindlist(dots)
  dots = unique(dots[, .(source_id, clean_hash)])

  pairs[id1>id2, c('id1' ,'id2') := list(id2, id1)]
  pairs = pairs[, .(pair = first(pair)), .(id1, id2)]

  ans = merge(pairs, dots[, .(source_id, hid1 = clean_hash)], all.x = T, by.x = 'id1', by.y = 'source_id')
  ans = merge(ans, dots[, .(source_id, hid2 = clean_hash)], all.x = T, by.x = 'id2', by.y = 'source_id')

  # Remove stuff when hash id is the same
  ans = ans[hid1 != hid2] # This drops a lot of rows and reflects how the shortcuts used to make fake (training) data may not reflect real world data
  ans[hid1>hid2, c('hid1', 'hid2') := list(hid2, hid1)]
  ans = unique(ans[, .(hid1, hid2, pair)])
  # r = ans[, .N, .(id1, id2)][N ==1,]
  # ans = merge(ans, r, by = c('id1', 'id2'))
  ans = ans[, .(id1 = hid1, id2 = hid2, pair)]

  if(!is.null(output_file)){
    arrow::write_parquet(ans, output_file)

    output_file
  }else{
    return(ans)
  }

}
