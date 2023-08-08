#' Predicting with a hyrule_link
#' @param object hyrule_link object
#' @param new_data data.frame data containing variables to predict on
#' @param members logical. Whether predictions from the ensemble members should be returned
#' @param opts list. OPtion arguments to be passed on to predict.model_stack which passes it on to the prediction routines of the underlying ensemble
#' @param ... not implemented
#' @details predict.hyrule_link always requests "prob" type from predict.model_stack
predict.hyrule_link = function(object, new_data, members = F, opts = list(), ...){ # type = 'prob',

  stopifnot(is.data.frame(new_data))
  stopifnot(is.logical(members))

  # make predictions for the screening model
  s1 = predict(object$screen, new_data, type = 'response')
  stk = predict(object$stack, new_data[data.table::between(s1, object$bounds[1], object$bounds[2]),],
                type = 'prob', members = members, opts = opts)

  # keep only prediction of match
  stk = stk[, grep('.pred_1', names(stk),value = T)]
  names(stk)[1] <- 'ens'
  names(stk) <- gsub('.pred_1_data_', '', names(stk), fixed = T)


  res = data.table::data.table(screen = s1)
  res[, rowid := .I]
  stk$rowid = res$rowid[between(s1, object$bounds[1], object$bounds[2]) ]
  res = merge(res, stk, all.x = T, by = 'rowid')
  res[, final := screen]
  res[!is.na(ens), final := ens]
  data.table::setDF(res)

  res



}
