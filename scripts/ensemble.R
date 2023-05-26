library('data.table')
library('stringdist')
library('e1071')
library('ranger')
library('xgboost')
library('mgcv')
library('glmnet')

# Code largely adapted from the linkage vignette ----
ntrain = 7500
bounds = c(.01, .99)
theform = ismatch ~ dob_ham + mis_dob  + # sex_disagree
  fn_cos2 + fn_jw + ln_cos2 + ln_jw + cn_cos + daymonth +ln_sx + fn_sx
# Load the data
## keep only a subset of the columns ----
kcols = c('simulant_id', 'first_name', 'middle_initial', 'last_name', 'date_of_birth', 'sex')
d1 = hyrule::fake_one[, .SD, .SDcols = kcols]
d2 = hyrule::fake_two[, .SD, .SDcols = kcols]

d1c = hyrule::prep_data_for_linkage(d1,
                                    first_name = 'first_name',
                                    last_name = 'last_name',
                                    middle_name = 'middle_name',
                                    dob = 'date_of_birth',
                                    zip = NULL) # omitted for now

d2c = hyrule::prep_data_for_linkage(d2,
                                    first_name = 'first_name',
                                    last_name = 'last_name',
                                    middle_name = 'middle_name',
                                    dob = 'date_of_birth',
                                    zip = NULL) # omitted for now

## Add back some relevant variables ----
d1c = cbind(d1[, .(simulant_id, sex)], d1c)
d2c = cbind(d2[, .(simulant_id, sex)], d2c)

## create an id field specific to each dataset ----
d1c[, id := .I]
d2c[, id := .I]

# subset the data bit to create test/train ----
train1 = d1c[, sample(id, ntrain)]
train2 = d2c[, sample(id, ntrain)]

d1train = d1c[id %in% train1]
d2train = d2c[id %in% train2]

# block ----
train = CJ(id1 = d1train[, id], id2 = d2train[, id])
train = merge(train, d1c[, .(id1 = id, dob1 = dob)], by = 'id1')
train = merge(train, d2c[, .(id2 = id, dob2 = dob)], by = 'id2')

## create rows for the conditions ----
find_keepers = function(input){
  input[, samemonth := month(dob1) == month(dob2)]
  input[, sameday := mday(dob1) == mday(dob2)]
  input[, sameyear := year(dob1) == year(dob2)]
  input[, swap := month(dob1) == mday(dob2) | mday(dob1) == month(dob2)]
  input[, keep := (samemonth + sameday + sameyear + swap) >0]

  input[keep == T | is.na(keep), .(id1, id2)]
}
train = find_keepers(train)

# create variables ----
train = merge(train, d1train[, .(sex1 = sex,
                                 fn1 = first_name_noblank,
                                 ln1 = last_name_noblank,
                                 dob1 = dob,
                                 id1 = id)], by = 'id1')
train = merge(train, d2train[, .(sex2 = sex,
                                 fn2 = first_name_noblank,
                                 ln2 = last_name_noblank,
                                 dob2 = dob,
                                 id2 = id)], by = 'id2')

train = hyrule::compute_variables(train)

# make the training dataset ----
train = merge(train, d1train[, .(id1 = id, sid1 = simulant_id)], by = 'id1')
train = merge(train, d2train[, .(id2 = id, sid2 = simulant_id)], by = 'id2')
train[, ismatch := as.integer(sid1==sid2)]

# make the test dataset ----
d1test = d1c[!id %in% train1]
d2test = d2c[!id %in% train2]
test = CJ(id1 = d1test[, id], id2 = d2test[, id])
test = merge(test, d1c[, .(id1 = id, dob1 = dob)], by = 'id1')
test = merge(test, d2c[, .(id2 = id, dob2 = dob)], by = 'id2')
test = find_keepers(test)

test = merge(test, d1test[, .(sex1 = sex,
                              fn1 = first_name_noblank,
                              ln1 = last_name_noblank,
                              dob1 = dob,
                              id1 = id)], by = 'id1')
test = merge(test, d2test[, .(sex2 = sex,
                              fn2 = first_name_noblank,
                              ln2 = last_name_noblank,
                              dob2 = dob,
                              id2 = id)], by = 'id2')
test = hyrule::compute_variables(test)

# "truth"
test = merge(test, d1test[, .(id1 = id, sid1 = simulant_id)], by = 'id1')
test = merge(test, d2test[, .(id2 = id, sid2 = simulant_id)], by = 'id2')
test[, ismatch := as.integer(sid1==sid2)]

# Fit the logistic screening model ----
screen = glm(theform,
             data = train, family = 'binomial')

# Find the pairs to fit the ensemble on ----
screen_preds = predict(screen, train, type ='response')
strain = train[screen_preds >= bounds[1] & screen_preds <= bounds[2]]

## assign to folds --
strain[, fold := sample(1:5,size = .N, replace = T)]

# For each fold, fit on all the other data and predict for the fold ----
# trn: training dataset, fid: fold id, frm: formula
fit_me = function(trn, fid, frm, return_mod = F){

  trn_mat = model.matrix(frm, trn)[, -1]
  trn_sub = trn[fold != fid]
  trn_sub_mat = model.matrix(frm, trn_sub)[, -1]
  pcols = attr(terms(frm), 'term.labels')

  # fit the ensemble
  m1 = svm(frm, data = trn_sub, type ='C-classification')
  m2 = ranger(frm, data = trn_sub, num.trees = 1000)
  m3 = xgboost(data = trn_sub_mat, label = trn_sub$ismatch,
               objective = 'binary:logistic', nrounds = 1000,
               verbose = 0)

  # predictions
  preds = data.table(
    svm = as.numeric(as.character(predict(m1, trn[, .SD, .SDcols = pcols]))),
    rf = predict(m2, trn[, .SD, .SDcols = pcols])$predictions,
    xg = predict(m3, trn_mat)
  )

  setnames(preds, paste0(names(preds), '_', fid))

  if(return_mod){
    return(list(preds, mods = list(svm = m1, rf = m2, xg = xgb.save.raw(m3, raw_format = 'json'))))
  }else{
    return(preds)
  }
}

insamp = fit_me(strain, 0, theform, T)
stackz = lapply(1:5, function(x){
  fit_me(strain, x, theform, x == 0)
})

# Extract the models and organize the results ----
mods = insamp[[2]]
insamp = insamp[[1]]
setnames(insamp, gsub('_0', '_is', names(insamp), fixed = T))
stackz = do.call(cbind, stackz)

## collapse stackz into out of sample by model
stackz[, fold := strain[,fold]]
for(fff in unique(stackz[, fold])){
  stackz[fold == fff, rf_oos := get(paste0('rf_', fff))]
  stackz[fold == fff, svm_oos := get(paste0('svm_', fff))]
  stackz[fold == fff, xg_oos := get(paste0('xg_', fff))]
}
stackz = stackz[, .(rf_oos, svm_oos, xg_oos)]

stackz = cbind(stackz, insamp)

# add to training dataset
strain = cbind(strain, stackz)
strain[, c('rf', 'svm', 'xg') := list(rf_oos, svm_oos, xg_oos)]

# fit the stacker
stacker = glm(ismatch ~ rf + svm + xg, data = strain, family = 'binomial')

# "insamp" preds
strain[, pred1 := predict(stacker, strain, type = 'response')]

# full preds
strain[, c('rf', 'svm', 'xg') := list(rf_is, svm_is, xg_is)]
strain[, pred2 := predict(stacker, strain, type = 'response')]
strain[, stack_bin := round(pred2)]
strain[, .N, keyby = .(ismatch, stack_bin)]

# Apply to test
test[, stage1 := predict(screen, test, type = 'response')]
pcols = names(coef(screen)[-1])

test[stage1 >= bounds[1] & stage1<bounds[2], svm := as.numeric(as.character(predict(mods$svm, .SD))), .SDcols = pcols]
test[stage1 >= bounds[1] & stage1<bounds[2], rf := predict(mods$rf, .SD)$predictions, .SDcols = pcols]
test_mat = model.matrix(theform, test)[, -1]
test[stage1 >= bounds[1] & stage1<bounds[2], xg := predict(xgb.load.raw(mods$xg), test_mat[.I,])]
test[stage1 >= bounds[1] & stage1<bounds[2], final := predict(stacker, .SD, type = 'response')]
test[is.na(final), final := stage1]
test[, final_bin := round(final)]
test[, .N, keyby = .(final_bin, ismatch)]

# save the models
saveRDS(list(stage1 = screen, stage2 = mods, stage3 = stacker), 'mods.rds')
