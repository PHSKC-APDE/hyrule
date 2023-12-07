#' Create a new hyrule_link object
#' @param screen a screening model of class model_fit (usually from fit_link), or alternatively, NULL for no screener
#' @param stack a stacked ensemble
#' @param bounds two item numeric vector indicatoring the bounds of where stack is relevant
#' @param butcher logical. Whether the data, env, and fitted values of stack should be axed
#' @export
#' @importFrom butcher axe_env axe_fitted axe_data
new_hyrule_link = function(screen, stack, bounds, butcher = T){

  stopifnot(is.null(screen) || inherits(screen, 'model_fit'))
  stopifnot(is.numeric(bounds))
  stopifnot(all(bounds<1 & bounds>0))
  stopifnot(bounds[1]<bounds[2])

  # to do: add a stack validation

  if(butcher) stack = butcher::axe_env(butcher::axe_data(butcher::axe_fitted(stack)))

  obj = list(screen = screen, stack = stack, bounds = bounds)
  class(obj) <- c('hyrule_link')
  obj
}
