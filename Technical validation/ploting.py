import os


import pandas as pd
import joypy.joyplot
import seaborn as sns
import matplotlib.pyplot as plt


plt.rcParams['font.family'] = 'Times New Roman'

from matplotlib import rcParams
from sklearn.preprocessing import StandardScaler, MinMaxScaler


def plot_ridge_plot(data, column):
    """
    ridge plot
    data: data dictionary
    column: 
    """
    
    selected_columns = [column, 'dataset']
    datas = []
    for name, df in data.items():
        df['dataset'] = name
        print(name)
        datas.append(df[selected_columns])


    # 合并所有筛选后的数据集
    datas = pd.concat(datas, ignore_index=True, axis=0)
    # print(datas)


    
    color = ['#F49E39', '#E7483D', '#918AC2', '#8FC751', '#5b52b1']
    overlap = 0
    ax, fig = joypy.joyplot(datas,
                            column=column,
                            by='dataset',
                            legend=False,
                            overlap=overlap,
                            grid=False,
                            hist=False,
                            color=color,
                            fade=False,  
                            linecolor='grey',
                            alpha=0.8,
                            xlabelsize=12,
                            ylabelsize=12,
                            figsize=(4, 4),
                            title=column,
                            )
    plt.show()
    plt.close()


def plot_box_plot(data, column):
    """
        data: data dictionary
        column_name: 
    """
   
    selected_columns = [column, 'dataset']
    datas = []
    for name, df in data.items():
        df['dataset'] = name
        datas.append(df[selected_columns])

        datas = pd.concat(datas, ignore_index=True, axis=0)

    
    datasets_name = data.keys()

    
    plot_data = [datas[datas['dataset'] == d][column] for d in datasets_name]

    
    fig, ax = plt.subplots(figsize=(4, 4))

     parts = ax.boxplot(plot_data, widths=0.5, patch_artist=True, showfliers=False,
                       meanline=False, showmeans=False, medianprops=dict(color='grey', linewidth=1))
    
    colors = ['#F49E39', '#E7483D', '#918AC2', '#8FC751', '#5b52b1']
    
    for pc, color in zip(parts['boxes'], colors):
        pc.set_color(color)
        pc.set_alpha(0.8)

    
    ax.set_xticks(np.arange(1, len(datasets_name) + 1))
    ax.set_xticklabels(datasets_name, rotation=0, fontsize=12)
    ax.set_ylabel(column, fontsize=12)

    
    plt.show()

if __name__ == '__main__':
    mimic_path = mimic_path
    eicu_path = eicu_path
    salz_path = salz_path
    zhejiang_path = zhejiang_path

    data_mimic = pd.read_csv(mimic_path, encoding='utf-8')
    data_eicu = pd.read_csv(eicu_path, encoding='utf-8')
    data_ams = pd.read_csv(ams_path, encoding='utf-8')
    data_salz = pd.read_csv(salz_path, encoding='utf-8')
    data_zhejiang = pd.read_csv(zhejiang_path, encoding='utf-8')

    vital_signals = ['spo2_min', 'heart_rate_mean', 'mbp_mean', 'sbp_mean', 'resp_rate_mean',
                    'temperature_mean', 'gcs_min']
    
    labs = ['lactate_max', 'creatinine_max', 'bilirubin_max', 'platelet_min', 'wbc_max', 'bicarbonate_min']
   
    data_mimic = data_mimic[labs]
    data_eicu = data_eicu[labs]
    data_ams = data_ams[labs]
    data_salz = data_salz[labs]
    data_zhejiang = data_zhejiang[labs]

    
    data_mimic = data_mimic.fillna(data_mimic.mean())
    data_eicu = data_eicu.fillna(data_eicu.mean())
    data_ams = data_ams.fillna(data_ams.mean())
    data_salz = data_salz.fillna(data_salz.mean())
    data_zhejiang = data_zhejiang.fillna(data_zhejiang.mean())
    
    data = {'a-mimic': data_mimic, 'b-eicu': data_eicu, 'c-ams': data_ams, 'salz': data_salz, 'zhejiang': data_zhejiang}
    print(data.keys())

    for column in labs:
        
        plot_ridge_plot(data, column)
        plot_box_plot(data, column)