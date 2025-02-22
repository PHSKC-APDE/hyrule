## Use the psuedo people package to generate some test data
library('data.table')
library('sf')
library('arrow')

target_overlap = .1

uno = read_parquet('data-raw/create_fake_data/fake_one.parquet')
dos = read_parquet('data-raw/create_fake_data/fake_two.parquet')

setDT(uno); setDT(dos);

# Limit columns
uno = uno[, .(simulant_id, first_name, middle_initial, last_name, sex, date_of_birth, street_number, street_name, unit_number)]
dos = dos[, .(simulant_id, first_name, middle_initial, last_name, sex, date_of_birth, street_number, street_name, unit_number)]

# Choose the matches
init_mtch = intersect(uno$simulant_id, dos$simulant_id)
mtch = sample(init_mtch, target_overlap * length(init_mtch))

# Reduce overlap
droppers = setdiff(init_mtch, mtch)
drop_split = sample(1:2, length(droppers), replace = T)

uno = uno[simulant_id %in% c(mtch, droppers[drop_split == 1])]
dos = dos[simulant_id %in% c(mtch, droppers[drop_split == 2])]

# Create fake location info
## Using fake north carolina
uniq_locs = unique(rbind(uno, dos)[!is.na(street_number) & !is.na(street_name), .(street_number, street_name)])
uniq_locs[, id := .I]
nc <- st_read(system.file("shape/nc.shp", package="sf"))
nc = st_transform(nc, crs = 32119) # project/convert to meters
pts = st_sample(nc,size = nrow(uniq_locs))
pts = st_sf(id = seq_len(length(pts)), 'geom' = pts, sf_column_name = 'geom')

pts = st_join(pts, nc[, 'FIPS'])

## Pretend county fips is ZIP  code
names(pts) <- c('id', 'zip_code', 'geom')
uniq_locs = cbind(uniq_locs, st_coordinates(pts))
uniq_locs$zip_code = pts$zip_code

## Randomly drop some locations
### Drop 10% of XY and 5% (5 * .5) of ZIP code
uniq_locs = uniq_locs[sample(seq_len(.N), floor(.N * .1)), c('X', 'Y') := NA ]
zipna = sample(uniq_locs[is.na(X), id], size = floor(.5 * nrow(uniq_locs[is.na(X)])))
uniq_locs[zipna, zip_code := NA]


uno = merge(uno, uniq_locs, all.x = T, by = c('street_number', 'street_name'))
dos = merge(dos, uniq_locs, all.x = T, by = c('street_number', 'street_name'))

uno[, id := NULL]
dos[, id := NULL]

setnames(uno, 'simulant_id', 'source_id')
setnames(dos, 'simulant_id', 'source_id')


fake_one = uno
fake_one[, source_system := 'System 1']
fake_two = dos
fake_two[, source_system := 'System 2']

# # clean up names and stuff
# setnames(fake_one, 'simulant_id', 'id1')
# setnames(fake_two, 'simulant_id', 'id2')

# Save results
usethis::use_data(fake_one, overwrite = TRUE)
arrow::write_parquet(fake_one, 'data-raw/fake_one.parquet')
usethis::use_data(fake_two, overwrite = TRUE)
arrow::write_parquet(fake_two, 'data-raw/fake_two.parquet')

# Make some training data
mp = sample(mtch, 400)
nop_1 = sample(fake_one$source_id, 225)
nop_2 = sample(fake_two$source_id, 225)

train = rbind(
  data.table(id1 = mp, id2 = mp, pair = 1),
  data.table(id1 = nop_1, id2 = nop_2, pair = as.numeric(nop_1 == nop_2))
)

#Randomly permute a few
permute_me = sample(seq_len(train[,.N]), 20)
train[permute_me, pair := sample(0:1, .N, T)]

usethis::use_data(train, overwrite = TRUE)
arrow::write_parquet(train, 'data-raw/train.parquet')


# # Make a dataset of potential pairs for matchmaker
# # this is probably a stupid way to do this
# pairs = CJ(id1 = fake_one[, id1], id2 = fake_two[, id2])
# pairs[, same := id1 == id2]
# notmatch = pairs[same == F][sample(seq_len(.N), 100)]
# match = pairs[same == T][sample(seq_len(.N), 25)]
# rm(pairs)
# pairs = rbind(match, notmatch)
# pairs[, truth := as.integer(same)]
# pairs[, same := NULL]
# usethis::use_data(pairs, overwrite = T)
# saveRDS(pairs, 'data-raw/pairs.rds')
#




