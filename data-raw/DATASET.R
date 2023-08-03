## Use the psuedo people package to generate some test data
library('reticulate')
library('data.table')
library('sf')
psp = import('pseudopeople')

# Load the config file for the decennial census
config <-psp$get_config('decennial_census')
def_config = config
# get the default dataset
default = psp$generate_decennial_census(seed = 1L)

# change how the error is

config$row_noise$omit_row$row_probability <- .04
config$column_noise$first_name$make_typos$cell_probability <- .1
config$column_noise$last_name$make_typos$cell_probability <- .1
config$column_noise$last_name$use_fake_name = 0L


con3 = list(decennial_census =
              list(row_noise = list(omit_row = list(row_probability = .04)),
                   column_noise = list(first_name = list(make_typos = list(cell_probability = .1)),
                                       last_name = list(make_typos = list(cell_probability = .1)))))

uno = psp$generate_decennial_census(seed = 1L, config = con3) # file.path(getwd(), 'data-raw/psp_config.yml')
dos = psp$generate_decennial_census(seed = 100L, config = con3)
setDT(uno); setDT(dos);
uno = uno[, lapply(uno, unlist)]
dos = dos[, lapply(dos, unlist)]

# fix NaNs
for(col in names(uno)){
  if(inherits(uno[[col]], 'character')){
    uno[get(col) == 'NaN', (col) := NA_character_]
  }
}
# fix NaNs
for(col in names(dos)){
  if(inherits(dos[[col]], 'character')){
    dos[get(col) == 'NaN', (col) := NA_character_]
  }
}

fake_one = uno
fake_two = dos

fake_one[, date_of_birth := as.Date(date_of_birth, '%m/%d/%Y')]
fake_two[, date_of_birth := as.Date(date_of_birth, '%m/%d/%Y')]


# Make a location history
peeps = data.table(simulant_id = unique(fake_one[, simulant_id], fake_two[, simulant_id]))
## create a starting area -- in North Carolina for fun
nc <- st_read(system.file("shape/nc.shp", package="sf"))
nc$fakepop = floor(nc$BIR79/sum(nc$BIR79) * nrow(peeps))
start = st_sample(nc, nc$fakepop)
start = st_sf(id = sample(peeps$simulant_id, length(start)), geom = start, sf_column_name = 'geom')

# four sets of 20 % change over
chng = lapply(1:4, function(x){
  # give 20 percent a new address
  scnd = st_sample(nc, floor(.2 * nrow(start)))
  scnd = st_sf(id = sample(start$id, length(scnd)), geom = scnd, sf_column_name = 'geom')
  scnd
})

lh1 = rbind(subset(start, !id %in% chng[[1]][['id']]), # same base, change 20%
            chng[[1]],
            chng[[2]])
lh1 = split(lh1,f = lh1$id)
lh1 = lapply(lh1, function(x){
  x$time = seq_len(nrow(x))
  x
})
lh1 = rbindlist(lh1)
lh1 = st_sf(lh1)

lh2 = rbind(subset(start, !id %in% chng[[3]][['id']]), # same base, change 20%
            chng[[3]],
            chng[[4]])
lh2 = split(lh2,f = lh2$id)
lh2 = lapply(lh2, function(x){
  x$time = seq_len(nrow(x))
  x
})
lh2 = st_sf(rbindlist(lh2))

setnames(lh1, 'id', 'simulant_id')
setnames(lh2, 'id', 'simulant_id')

location_history_one = lh1
location_history_two = lh2

# create ZIP code
nc$zip = nc$CNTY_ID + 10000
zip1 = setDT(st_drop_geometry(st_join(subset(lh1, time == 1), nc[, 'zip']))[, c('simulant_id', 'zip')])
zip2 = setDT(st_drop_geometry(st_join(subset(lh2, time == 1), nc[, 'zip']))[, c('simulant_id', 'zip')])

fake_one = merge(fake_one, zip1, by = 'simulant_id')
fake_two = merge(fake_two, zip2, by = 'simulant_id')

# Make phone history
peeps[, nnums := sample(1:3, .N, T)]
peeps[, start := floor(runif(.N,0, 10000))]

permute1 = peeps[nnums>1, ifelse(sample(0:1, .N, T, c(.1,.9)), 0, floor(runif(.N,0,100)))]
permute2 = peeps[nnums>2, ifelse(sample(0:1, .N, T, c(.1,.9)), 0, floor(runif(.N,0,100)))]

phs = lapply(0:1, function(x){
  p = copy(peeps)

  # if x == 1, permute 10 percent of the starting phones
  p[, phone1 := start]
  if(x==1) p[, phone1 := ifelse(sample(0:1, .N, T, c(.1,.9)), start, start + floor(runif(.N,0,100)))]
  p[nnums>1, phone2 := phone1 + permute1]
  p[nnums>2, phone3 := phone2 + permute2]
  p = melt(p[, .(simulant_id, phone1, phone2, phone3)], id.vars = 'simulant_id')
  p = p[!is.na(value)]
  p[, value := value + 1000000000]

})

phone_history_one = phs[[1]]
phone_history_two = phs[[2]]

# Save results

# Fake data
usethis::use_data(fake_one, overwrite = TRUE)
fake_one = fake_one
setnames(fake_one, 'simulant_id', 'id1')
saveRDS(fake_one, 'data-raw/fake_one.rds')
usethis::use_data(fake_two, overwrite = TRUE)
setnames(fake_two, 'simulant_id', 'id2')
saveRDS(fake_two, 'data-raw/fake_two.rds')

# Location history
usethis::use_data(location_history_one, overwrite = TRUE)
setnames(location_history_one, 'simulant_id', 'id1')
saveRDS(location_history_one, 'data-raw/location_history_one.rds')

usethis::use_data(location_history_two, overwrite = TRUE)
setnames(location_history_two, 'simulant_id', 'id2')
saveRDS(location_history_two, 'data-raw/location_history_two.rds')

# phone history
usethis::use_data(phone_history_one, overwrite = TRUE)
setnames(phone_history_one, 'simulant_id', 'id1')
saveRDS(phone_history_one, 'data-raw/phone_history_one.rds')

usethis::use_data(phone_history_two, overwrite = TRUE)
setnames(phone_history_two, 'simulant_id', 'id2')
saveRDS(phone_history_two, 'data-raw/phone_history_two.rds')



# Make a dataset of potential pairs for matchmaker
# this is probably a stupid way to do this
pairs = CJ(id1 = fake_one[, id1], id2 = fake_two[, id2])
pairs[, same := id1 == id2]
notmatch = pairs[same == F][sample(seq_len(.N), 100)]
match = pairs[same == T][sample(seq_len(.N), 25)]
rm(pairs)
pairs = rbind(match, notmatch)
pairs[, truth := as.integer(same)]
pairs[, same := NULL]
usethis::use_data(pairs, overwrite = T)
saveRDS(pairs, 'data-raw/pairs.rds')





