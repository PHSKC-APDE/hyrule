#' Create a new hyrule_link object
#' @param screen a glm screen model from fit_link
#' @param stack a stacked ensemble
#' @param bounds two item numberic vector indicatoring the bounds of where stack is relevant
#' @export
new_hyrule_link = function(screen, stack, bounds){

  stopifnot(inherits(screen, 'model_fit')) # fit by parsnip logistic regression
  stopifnot(is.numeric(bounds))
  stopifnot(all(bounds<1 & bounds>0))
  stopifnot(bounds[1]<bounds[2])

  # to do: add a stack validation

  obj = list(screen = screen, stack = stack, bounds = bounds)
  class(obj) <- c('hyrule_link')
  obj
}
