import pandas as pd


def death_label(data):
    """
    data
    """
    data['survival_time'] = data['deathtime_icu_hour']/24
    data[f'survival_time_28d'] = data['survival_time'].apply(lambda x: min(x, 28) if pd.notnull(x) else 28)

    data[f'death_28d'] = (data['survival_time'] <= 28).astype(int)
    data[f'death_28d'].fillna(0, inplace=True)
    return data


if __name__ == '__main__':
    mimic_path = mimic_path
    eicu_path = eicu_path
    ams_path = ams_path
    salz_path =salz_path
    zhejiang_path =zhejiang_path

    data_mimic = pd.read_csv(mimic_path, encoding='utf-8')
    data_eicu = pd.read_csv(eicu_path, encoding='utf-8')
    data_ams = pd.read_csv(ams_path, encoding='utf-8')
    data_salz = pd.read_csv(salz_path, encoding='utf-8')
    data_zhejiang = pd.read_csv(zhejiang_path, encoding='utf-8')
    
    data = {'mimic': data_mimic, 'eicu': data_eicu, 'ams': data_ams, 'salz': data_salz, 'zhejiang': data_zhejiang}
    for name, df in data.items():
        df = death_label(df)