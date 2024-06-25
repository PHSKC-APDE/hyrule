#' Predicting with a hyrule_link
#' @param object hyrule_link object
#' @param new_data data.frame data containing variables to predict on
#' @param members logical. Whether predictions from the ensemble members should be returned
#' @param opts list. Option arguments to be passed on to predict.model_stack which passes it on to the prediction routines of the underlying ensemble
#' @param ... not implemented
#' @details predict.hyrule_link always requests "prob" type from predict.model_stack
#' @export
#' @importFrom stats predict
#' @exportS3Method stats::predict hyrule_link
predict.hyrule_link = function(object, new_data, members = F, opts = list(), ...){ # type = 'prob',

  stopifnot(is.data.frame(new_data))
  stopifnot(is.logical(members))

  # make predictions for the screening model
  if(!is.null(object$screen)){
    s1 = predict(object$screen, new_data, type = 'prob')[,'.pred_1', drop = T]
    good_rows = which(!is.na(s1) & data.table::between(s1, object$bounds[1], object$bounds[2]))
  }else{
    s1 = rep(NA_real_, nrow(new_data))
    good_rows = seq_len(nrow(new_data))
  }

  if(any(good_rows)){

    if(inherits(object$stack, 'model_stack')){
      stk = predict(object$stack, new_data[good_rows,],
                    type = 'prob', members = members, opts = opts)
    }else{
      stk = predict(object$stack, new_data[good_rows,],
                    type = 'prob', opts = opts)
    }


    # keep only prediction of match
    stk = stk[, grep('.pred_1', names(stk),value = T)]
    names(stk)[1] <- 'ens'
    names(stk) <- gsub('.pred_1_', '', names(stk), fixed = T)

    res = data.table::data.table(screen = s1)
    res[, rowid := .I]
    stk$rowid = good_rows
    res = merge(res, stk, all.x = T, by = 'rowid')
    res[, final := screen]
    res[!is.na(ens), final := ens]
    res[, rowid := NULL]
  }else{
    res = data.table(screen = s1, ens = NA_real_, final = s1)

    if(members){
      for(m in names(object$stack$member_fits)){
        res[, (m) := NA_real_]
      }
    }

  }

  data.table::setDF(res)

  res

}
