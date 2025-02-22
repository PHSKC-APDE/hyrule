svm = parsnip::svm_linear(
  mode = 'classification', 
  engine = 'kernlab', 
  cost = tune())
rf = parsnip::rand_forest(
  mode = 'classification',
  trees = tune(),
  mtry = tune())
xg = parsnip::set_engine(
  parsnip::boost_tree(
    mode = 'classification',
    tree_depth = tune(),
    mtry = tune(), 
    trees = tune(),
    learn_rate = tune()),
  'xgboost', 
  objective = 'binary:logistic')

s_params = tibble::tribble(~NAME, ~MODEL,
                           'svm', quote(svm)
                           ,'rf', quote(rf)
                           ,'xg', quote(xg)
)
s_params$TUNER = 'bayes'
s_params$nm = s_params$NAME

  

