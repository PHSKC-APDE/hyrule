import pandas as pd
import pseudopeople as pp

config = {
    'decennial_census': {
        'column_noise': {
            'first_name': {
                'use_nickname': {
                    'cell_probability': .1
                },
                'use_fake_name':{
                    'cell_probability': .05
                },
                'make_typos':{
                    'cell_probability': .25
                }

            },
            'last_name': {
                'make_typos':{
                    'cell_probability': .25
                },
                'use_fake_name':{
                    'cell_probability': .25
                },

            },
            'date_of_birth': {
                'write_wrong_digits':{
                    'cell_probability': .2
                }
            },
            'street_name': {
                'make_typos':{
                    'cell_probability': .15
                }
            }
        }
    }
}

wic1 = pp.generate_decennial_census(config=config, seed = 1)
wic2 = pp.generate_decennial_census(config=config, seed = 2)
wic1.to_parquet('fake_one.parquet')
wic2.to_parquet('fake_two.parquet')
