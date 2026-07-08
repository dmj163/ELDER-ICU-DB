# ELDER-ICU-DB: A Comprehensive Critical Care Data Resource for International Multicenter Study on Elderly ICU Patients

## Overview
ELDER-ICU-DB is a multinational intensive care dataset specifically designed for elderly patients (≥65 years).

It harmonizes data from five public critical care databases: MIMIC-III, MIMIC-IV, eICU-CRD, SICdb, and ZhejiangProvinceICUdb, spanning 209 clinical sites across the United States, Austria, and China, encompassing 93,654 ICU admissions recorded between 2001 and 2022.

## Data Files
The dataset consists of four CSV files, each corresponding to one source database:

| File | Source Database | Rows | Clinical Sites |
|------|----------------|------|----------------|
| MIMIC.csv | MIMIC-III & MIMIC-IV | 48,708 | 1 (Beth Israel Deaconess Medical Center, USA) |
| eICU-CRD.csv | eICU-CRD | 37,166 | 208 (hospitals across USA) |
| SICdb.csv | SICdb | 6,371 | 1 (Salzburg, Austria) |
| ZhejiangProvinceICU.csv | ZhejiangProvinceICUdb | 1,409 | 1 (Zhejiang, China) |

## Key Variables
- **Demographics**: age, gender, ethnicity, weight, height
- **Admission**: admission type, first care unit, LOS (ICU & hospital)
- **Vital signs**: SpO2, heart rate, blood pressure, respiratory rate, temperature, GCS, urine output
- **Labs**: 27 laboratory variables including creatinine, bilirubin, platelet, troponin, BNP, etc.
- **Blood gas**: PaO2, PaCO2, lactate, FiO2, PaO2/FiO2 ratio
- **Treatments**: mechanical ventilation, vasopressors, code status
- **Geriatric-specific**: physical frailty indicators (stand, sit, bed rest), GNRI
- **Clinical scores**: CCI, OASIS, SAPS II, SOFA
- **Outcomes**: in-hospital mortality, 28-day mortality, survival time

## Access Requirements
Users must be credentialed PhysioNet users and have obtained usage rights for the source databases before applying for access to ELDER-ICU-DB.

## Related Resources
Open-source code for data extraction and survival analysis is available at https://github.com/dmj163/ELDER-ICU-DB.
