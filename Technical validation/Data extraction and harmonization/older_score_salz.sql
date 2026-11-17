-- criteria
-- age > 65
-- first icu admission
-- los icu day >= 1d


--                   Part 1. cohort information                    --

-- --------------------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_cohort_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_cohort_salz as

with older_study_cohort_salz as (
    select icud.patientid, icud.hadm_id
    , icud.gender
    , case when icud.weight < 20 then null
    when icud.weight > 400 then null
    else icud.weight end as weight
    , case when icud.height < 50 then null
    when icud.height > 300 then null
    else icud.height end as height
    , icud.bmi, icud.age
    , icud.admissionyear as anchor_year_group
    , icud.los_hospital_day
    , case when round(icud.icu_admit_hr/24,2) < 0 then 0 else round(icu_admit_hr/24,2) end as pre_icu_los_day 
    , icud.icudaysofstay as los_icu_day
    , 'white' as ethnicity
    , icud.saps3
    , case when icud.surgicaladmissiontype = 'Urgent Surgery' then 'EMERGENCY'
    else 'ELECTIVE' end as admission_type
    , case when icud.surgicaladmissiontype in ('Unknown', 'Elective Surgery') then 1 else 0 end as electivesurgery
    , case when icud.hospitalunit = 'INIC' then '9 bed intermediate care ward'
    when icud.hospitalunit = 'CWIN' then '14 bed intensive care ward'
    when icud.hospitalunit = 'INBD' then '9 bed intensive care ward'
    when icud.hospitalunit = 'INID' then '9 bed mixed ward (intermediate care, non-invasive-ventilation possible)'
    else null end as first_careunit
    , 0 as admittime
    , cs.timeofstay as dischtime
    , expa.icuoffset as intime
    , round((expa.icudaysofstay * 24*3600 + expa.icuoffset)) as outtime
    , cs.Offsetofdeath as deathtime
    , case when icud.hospitaldischargetype = 'Deceased' then 1 
    when cs.Offsetofdeath <= cs.timeofstay + 24*3600 then 1
    else 0 end as death_hosp
    , ROUND((cs.Offsetofdeath - expa.icuoffset)/3600) as deathtime_icu_hour
    , case when cs.Offsetofdeath is not null and (cs.Offsetofdeath - expa.icuoffset) <= 1*24*3600 then 1
    when cs.Offsetofdeath is not null and (cs.Offsetofdeath - expa.icuoffset) > 1*24*3600 then 0
    else 0 end as flag
    , round((sp.sepsis3_onset - expa.icuoffset)/3600,2) as sepsis_icu_hr

    from icustay_detail icud
    left join cases cs
    on icud.hadm_id = cs.caseid
    LEFT JOIN export_add as expa 
    on icud.hadm_id = expa.caseid
    left join sepsis3 sp
    on icud.hadm_id = sp.hadm_id
    where icud.age >= 65
    and icud.icudaysofstay > 1    
)

, vital_gcs_uo_info as (
    select sc.hadm_id, gcs_min
    , round(vital.heart_rate_mean,1) as heart_rate_mean
    , round(vital.mbp_mean,1) as mbp_mean
    , round(vital.sbp_mean,1) as sbp_mean
    , round(vital.resp_rate_mean,1) as resp_rate_mean
    , round(vital.temperature_mean,1) as temperature_mean
    , vital.spo2_min
    , case when uo.urineoutput < 0 then 0 else uo.urineoutput end as urineoutput
    from older_study_cohort_salz sc
    left join first_day_gcs gcs
    on sc.hadm_id = gcs.hadm_id
    left join first_day_vitalsign vital
    on sc.hadm_id = vital.hadm_id
    left join first_day_urine_output uo
    on sc.hadm_id = uo.hadm_id    
)

-- apsiii, sofa, saps, oasis, cci_score
, score_info as (
  select sc.hadm_id, ap.apsiii, ap.apsiii_prob
  , oa.oasis, oa.oasis_prob
  , sp.sapsii as saps,  sp.sapsii_prob as saps_prob
  , sf.sofa, 1 / (1 + exp(- (-3.3890 + 0.2439*(sf.sofa) ))) as sofa_prob
  , cci.charlson_comorbidity_index as cci_score
  from older_study_cohort_salz sc 
  left join apsiii ap 
  on sc.hadm_id = ap.hadm_id
  left join oasis oa 
  on sc.hadm_id = oa.hadm_id
  left join sapsii sp 
  on sc.hadm_id = sp.hadm_id
  left join (
    select hadm_id, hr, sofa_24hours as sofa
    , ROW_NUMBER()
    over (partition by hadm_id order by hr desc) as flag
    from qivoted_sofa
    where hr <= 23 and hr >= 0
  ) sf
  on sc.hadm_id = sf.hadm_id
  and sf.flag = 1
  left join (
    select hadm_id, max(charlson_comorbidity_index) as charlson_comorbidity_index
    from charlson_comorbidity_index
    group by hadm_id
  ) cci 
  on sc.hadm_id = cci.hadm_id
)

, exclude_id_vt_info as (
  select hadm_id
  from (
      select hadm_id
      , case when heart_rate_mean > 0 then 0 else 1 end as hr_flag
      , case when mbp_mean > 0 then 0 else 1 end as mbp_flag
      , case when resp_rate_mean > 0 then 0 else 1 end as rr_flag
      , case when gcs_min > 0 then 0 else 1 end as gcs_flag
      , case when temperature_mean > 0 then 0 else 1 end as t_flag
      , case when spo2_min > 0 then 0 else 1 end as spo2_flag
      , case when sbp_mean > 0 then 0 else 1 end as sbp_flag    
      from vital_gcs_uo_info
  ) aa
  where (hr_flag + mbp_flag + rr_flag + gcs_flag + t_flag + spo2_flag + sbp_flag) > 0
)

select sc.*
, apsiii, apsiii_prob, oasis, oasis_prob, saps, saps_prob, sofa, sofa_prob, cci_score
from older_study_cohort_salz sc
left join score_info si
on sc.hadm_id = si.hadm_id
where flag = 0
and sc.hadm_id not in (select hadm_id from exclude_id_vt_info)
order by sc.hadm_id;



--                   Part 2. vital sign information                    --

-- ------------------------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_vt_uo_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_vt_uo_salz as

with study_cohort as (
	select *
	from older_study_cohort_salz
)

, cohort_time_0 as
(
  select hadm_id, intime
  , generate_series(
    0, 
    ceil(los_icu_day * 24)
    ) as hr	
  from study_cohort
)

, cohort_time as (
	select hadm_id, hr, (intime + hr*3600) as charttime
	from cohort_time_0
)

, vital_signs_info_0 as (
  select sc.hadm_id, ceil((vt.charttime - sc.intime)/3600) as hr  
  , vt.heart_rate
  , coalesce(vt.sbp, vt.sbp_ni) as sbp 
  , coalesce(vt.mbp, vt.mbp_ni) as mbp
  , vt.resp_rate, vt.temperature, vt.spo2
  from vitalsign vt
  inner join study_cohort sc 
  on sc.hadm_id = vt.hadm_id
  and (vt.charttime - sc.intime) >= 0
)

, vital_signs_info as (
	select hadm_id, hr
	, round(avg(heart_rate)) as heart_rate
	, round(avg(sbp)) as sbp
	, round(avg(mbp)) as mbp
	, round(avg(resp_rate)) as resp_rate
	, round(avg(temperature),2) as temperature
	, round(avg(spo2)) as spo2
	from vital_signs_info_0
	group by hadm_id, hr					
)

, uo_info_0 as (
	SELECT sc.hadm_id, ceil((uo.charttime - sc.intime)/3600) as hr
  	, uo.urineoutput 
	FROM urine_output uo 
	inner join study_cohort sc 
  on sc.hadm_id = uo.hadm_id
  and (uo.charttime - sc.intime) >= 0
)

, uo_info as (
	select hadm_id, hr, sum(urineoutput) as urineoutput
	from uo_info_0
	group by hadm_id, hr
)

, vital_uo_use_0 as (
    select ct.hadm_id, ct.hr
    , heart_rate, sbp, mbp, resp_rate, temperature, spo2
    , case when u.urineoutput > 0 then u.urineoutput else 0 end as urineoutput
    from cohort_time ct 
    left join vital_signs_info v 
    on ct.hadm_id = v.hadm_id
    and ct.hr = v.hr
    left join uo_info u 
    on ct.hadm_id = u.hadm_id
    and ct.hr = u.hr
)

, vital_uo_use as (
  select hadm_id
      , round(avg(heart_rate), 1) as heart_rate_mean
      , round(avg(mbp), 1) as mbp_mean
      , round(avg(sbp), 1) as sbp_mean
      , round(avg(resp_rate), 1) as resp_rate_mean
      , round(avg(temperature), 1) as temperature_mean
      , sum(case when urineoutput < 0 then 0 else urineoutput end) as urineoutput
      , min(spo2) as spo2_min      
  from vital_uo_use_0
  where hr >= 1 and hr <= 24
  group by hadm_id
)

, gcs_use as (
  select sc.hadm_id, vt.gcs as gcs_min
  from gcs vt
  inner join study_cohort sc 
  on sc.hadm_id = vt.hadm_id  
)

select sc.hadm_id, heart_rate_mean, mbp_mean, sbp_mean, spo2_min
, resp_rate_mean, temperature_mean, gcs_min, urineoutput
from older_study_cohort_salz sc
left join vital_uo_use vt
on sc.hadm_id = vt.hadm_id
left join gcs_use g
on sc.hadm_id = g.hadm_id
order by sc.hadm_id;



--                   Part 3. lab information                    --

-- ------------------------------------------------------------ --

DROP MATERIALIZED VIEW IF EXISTS older_study_lab_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_lab_salz as

with study_cohort as (
	select *
	from older_study_cohort_salz
)

, cohort_time_0 as
(
  select hadm_id, intime
  , generate_series(
    0, 
    ceil(los_icu_day * 24)
    ) as hr	
  from study_cohort
)

, cohort_time as (
	select hadm_id, hr, (intime + hr*3600) as charttime
	from cohort_time_0
)

, bg_info_0 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, po2 as pao2, pco2 as paco2, coalesce(fio2_chartevents, fio2) as fio2
	, pao2fio2ratio, ph, baseexcess, bicarbonate
	, hematocrit, hemoglobin, chloride, calcium
	, potassium, sodium, lactate, glucose
	from bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id
)

, bg_info_1 as (
	select hadm_id, hr
	, max(pao2) as pao2, max(paco2) as paco2
	, max(fio2) as fio2, max(pao2fio2ratio) as pao2fio2ratio
	, max(ph) as ph, max(baseexcess) as baseexcess
	, max(bicarbonate) as bicarbonate, max(hematocrit) as hematocrit
	, max(hemoglobin) as hemoglobin, max(chloride) as chloride
	, max(calcium) as calcium, max(potassium) as potassium
	, max(sodium) as sodium, max(lactate) as lactate
	, max(glucose) as glucose
	from bg_info_0
	group by hadm_id, hr
)

, bg_info as (
  select b1.hadm_id, b1.hr, pao2, paco2, fio2
  , ph, baseexcess, bicarbonate, hematocrit, hemoglobin
  , chloride, calcium, potassium, sodium, lactate, glucose
  , pao2fio2ratio_vent
  , case when pao2fio2ratio_vent is null then pao2fio2ratio else null end as pao2fio2ratio_novent
  from bg_info_1 b1
  left join (
    select bg.hadm_id, bg.hr
    , pao2fio2ratio as pao2fio2ratio_vent
    from bg_info_1 bg
    inner join ventilation vt
    on bg.hadm_id = vt.hadm_id
    where bg.hr >= vt.starttime and bg.hr <= vt.endtime
  ) pa
  on b1.hadm_id = pa.hadm_id
  and b1.hr = pa.hr
)

, lab_info_00 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, wbc, lymphocytes, neutrophils
	from blood_differential bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id	
)

, lab_info_0 as (
	select hadm_id, hr
	, max(wbc) as wbc, max(lymphocytes) as lymphocytes
	, max(neutrophils) as neutrophils
	from lab_info_00
	group by hadm_id, hr 
) 

, lab_info_10 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, albumin, creatinine, bun
	from chemistry bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id	
)

, lab_info_1 as (
	select hadm_id, hr
	, max(albumin) as albumin, max(creatinine) as creatinine
	, max(bun) as bun
	from lab_info_10
	group by hadm_id, hr 
) 

, lab_info_20 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, fibrinogen, pt
	, ptt, inr
	from coagulation bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id	
)

, lab_info_2 as (
	select hadm_id, hr
	, max(fibrinogen) as fibrinogen, max(pt) as pt
	, max(ptt) as ptt, max(inr) as inr
	from lab_info_20
	group by hadm_id, hr 
) 

, lab_info_30 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, platelet
	from complete_blood_count bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id	
)

, lab_info_3 as (
	select hadm_id, hr
	, max(platelet) as platelet
	from lab_info_30
	group by hadm_id, hr 
) 

, lab_info_40 as (
	select bg.hadm_id, ceil((charttime - sc.intime)/3600) as hr
	, alt, alp as alkaline_phosphatase
	, ast, bilirubin_total as bilirubin
	from enzyme bg
	inner join study_cohort sc 
	on bg.hadm_id = sc.hadm_id	
)

, lab_info_4 as (
	select hadm_id, hr
	, max(alt) as alt
	, max(alkaline_phosphatase) as alkaline_phosphatase
	, max(ast) as ast
	, max(bilirubin) as bilirubin	
	from lab_info_40
	group by hadm_id, hr 
)

, lab_info_50 as (
	select le.caseid as hadm_id
	, ceil((le.offset - sc.intime)/3600) as hr
	, le.laboratoryvalue AS val
	, case 
	when le.laboratoryid IN (481) then 'troponin'
	when le.laboratoryid IN (468) then 'magnesium'
	when le.laboratoryid IN (571) then 'bnp'
	when le.laboratoryid in (672) then 'aniongap'
	else null end as label
	from laboratory le
	inner join study_cohort sc 
	on le.caseid = sc.hadm_id 
	where le.laboratoryid in (481, 468, 571, 672) 
)

, lab_info_5 as (
	select hadm_id, hr
	, max(case when label = 'troponin' then val else null end) as troponin
	, max(case when label = 'magnesium' then val else null end) as magnesium
	, max(case when label = 'bnp' then val else null end) as bnp
	, max(case when label = 'aniongap' then val else null end) as aniongap
	from lab_info_50
	group by hadm_id, hr
)

, lab_info_use as (
  select ct.hadm_id, ct.hr
  , albumin, aniongap, bicarbonate
  , bun, calcium, chloride, creatinine, glucose, sodium
  , potassium, fibrinogen, inr, pt, ptt, hematocrit
  , hemoglobin, platelet, wbc, alt, ast, bilirubin 				
  , pao2, paco2, fio2, pao2fio2ratio_novent, pao2fio2ratio_vent
  , ph, baseexcess, lactate
  , troponin, magnesium, bnp
  , lymphocytes, neutrophils, alkaline_phosphatase as alp
  from cohort_time ct
  left join bg_info bi
  on ct.hadm_id = bi.hadm_id
  and ct.hr = bi.hr
  left join lab_info_0 lab0
  on ct.hadm_id = lab0.hadm_id
  and ct.hr = lab0.hr
  left join lab_info_1 lab1
  on ct.hadm_id = lab1.hadm_id
  and ct.hr = lab1.hr
  left join lab_info_2 lab2
  on ct.hadm_id = lab2.hadm_id
  and ct.hr = lab2.hr
  left join lab_info_3 lab3
  on ct.hadm_id = lab3.hadm_id
  and ct.hr = lab3.hr
  left join lab_info_4 lab4
  on ct.hadm_id = lab4.hadm_id
  and ct.hr = lab4.hr
  left join lab_info_5 lab5
  on ct.hadm_id = lab5.hadm_id
  and ct.hr = lab5.hr
)

select sc.hadm_id
, max(creatinine) as creatinine_max, max(bilirubin) as bilirubin_max
, min(platelet) as platelet_min, max(bun) as bun_max
, max(wbc) as wbc_max, max(glucose) as glucose_max
, max(hematocrit) as hematocrit_max, max(potassium) as potassium_max, max(sodium) as sodium_max
, min(bicarbonate) as bicarbonate_min, max(bicarbonate) as bicarbonate_max
, min(pao2fio2ratio_novent) as pao2fio2ratio_novent
, min(pao2fio2ratio_vent) as pao2fio2ratio_vent
, min(albumin) as albumin_min, max(alt) as alt_max
, max(ast) as ast_max, max(alp) as alp_max
, max(pt) as pt_max, max(ptt) as ptt_max
, min(inr) as inr_min, min(hemoglobin) as hemoglobin_min
, min(chloride) as chloride_min, min(pao2) as pao2_min
, max(paco2) as paco2_max, max(lactate) as lactate_max
, min(baseexcess) as baseexcess_min, max(fio2) as fio2_max
, max(troponin) as troponin_max, max(lymphocytes) as lymphocytes_max
, min(lymphocytes) as lymphocytes_min, min(neutrophils) as neutrophils_min
, max(magnesium) as magnesium_max, min(fibrinogen) as fibrinogen_min
, max(bnp) as bnp_max, max(aniongap) as aniongap_max
from older_study_cohort_salz sc
left join lab_info_use lab
on sc.hadm_id = lab.hadm_id
and hr>= 1 and hr<= 24
group by sc.hadm_id
order by sc.hadm_id;



--                   Part 4. treatment information                    --

-- ------------------------------------------------------------------ --
DROP MATERIALIZED VIEW IF EXISTS older_study_tr_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_tr_salz as

with study_cohort as (
	select *, intime as icu_admission_time, outtime as icu_discharge_time
	from older_study_cohort_salz
)

, cohort_time_0 as
(
  select hadm_id, icu_admission_time
  , generate_series(
    0, 
    ceil((icu_discharge_time - icu_admission_time)/60.0/60.0)
    ) as hr
		
  from study_cohort
)

, cohort_time as (
	select hadm_id, hr, (icu_admission_time + hr*3600) as charttime
	from cohort_time_0
)

, treatment_all_0 as (
	select dob.hadm_id, floor((starttime - icu_admission_time)/60.0/60.0) as starttime_hr
	, ceil((endtime - icu_admission_time)/60.0/60.0) as endtime_hr
	, 'dobutamine' as label
	from dobutamine dob 
	inner join study_cohort ct
	on dob.hadm_id = ct.hadm_id
	where vaso_amount > 0 
	union all
	select dob.hadm_id, floor((starttime - icu_admission_time)/60.0/60.0) as starttime_hr
	, ceil((endtime - icu_admission_time)/60.0/60.0) as endtime_hr
	, 'dopamine' as label
	from dopamine dob 
	inner join study_cohort ct
	on dob.hadm_id = ct.hadm_id
	where vaso_amount > 0
	union all
	select dob.hadm_id, floor((starttime - icu_admission_time)/60.0/60.0) as starttime_hr
	, ceil((endtime - icu_admission_time)/60.0/60.0) as endtime_hr
	, 'epinephrine' as label
	from epinephrine dob 
	inner join study_cohort ct
	on dob.hadm_id = ct.hadm_id
	where vaso_amount > 0
	union all
	select dob.hadm_id, floor((starttime - icu_admission_time)/60.0/60.0) as starttime_hr
	, ceil((endtime - icu_admission_time)/60.0/60.0) as endtime_hr
	, 'norepinephrine' as label
	from norepinephrine dob 
	inner join study_cohort ct
	on dob.hadm_id = ct.hadm_id
	where vaso_amount > 0
	union all
	select dob.hadm_id, starttime as starttime_hr
	, endtime as endtime_hr
	, 'ventilation' as label
	from ventilation dob 
	inner join study_cohort ct
	on dob.hadm_id = ct.hadm_id		
)

, treatment_all as (
	select distinct *
	from (
		select hadm_id, label
		, generate_series(
			starttime_hr, 
			endtime_hr
		) as hr 
		from treatment_all_0
	) aa
)

, treatment_info_need as (
  select ct.hadm_id
  , max(case when label = 'dobutamine' and ct.hadm_id = ta.hadm_id and ct.hr = ta.hr then 1 else 0 end) as dobutamine
  , max(case when label = 'dopamine' and ct.hadm_id = ta.hadm_id and ct.hr = ta.hr then 1 else 0 end) as dopamine
  , max(case when label = 'epinephrine' and ct.hadm_id = ta.hadm_id and ct.hr = ta.hr then 1 else 0 end) as epinephrine
  , max(case when label = 'norepinephrine' and ct.hadm_id = ta.hadm_id and ct.hr = ta.hr then 1 else 0 end) as norepinephrine
  , max(case when label = 'ventilation' and ct.hadm_id = ta.hadm_id and ct.hr = ta.hr then 1 else 0 end) as ventilation

  from cohort_time ct
  left join treatment_all ta
  on ct.hadm_id = ta.hadm_id
  and ct.hr = ta.hr
  where ct.hr >= 1 and ct.hr <= 24
  group by ct.hadm_id
)

select sc.hadm_id
, case when dobutamine is not null then dobutamine else 0 end as dobutamine
, case when dopamine is not null then dopamine else 0 end as dopamine
, case when epinephrine is not null then epinephrine else 0 end as epinephrine
, case when norepinephrine is not null then norepinephrine else 0 end as norepinephrine
, case when ventilation is not null then ventilation else 0 end as vent
, 0 as code_status, 0 as code_status_eva_flag
from older_study_cohort_salz sc
left join treatment_info_need ti
on sc.hadm_id = ti.hadm_id
order by sc.hadm_id;



--                   Part 5. activity information                    --

-- ----------------------------------------------------------------- --

DROP MATERIALIZED VIEW IF EXISTS older_study_activity_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_activity_salz as


select hadm_id, 0 as activity_stand
, 0 as activity_sit, 0 as activity_bed
, 0 as activity_eva_flag
, 0 as fall_risk
, 0 as fall_risk_eva_flag
from older_study_cohort_salz
order by hadm_id;



--                        Merge                          --

-- ----------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_salz CASCADE;
CREATE MATERIALIZED VIEW older_study_salz as

select sc.patientid, sc.hadm_id 
, first_careunit, los_icu_day
, los_hospital_day
, death_hosp
, deathtime_icu_hour
, pre_icu_los_day
, admission_type, ethnicity, anchor_year_group
, case when gender = 'male' then 'M' else 'F' end as gender, age
, height, weight, bmi
, electivesurgery
, vent
, creatinine_max, bilirubin_max, platelet_min
, bun_max, wbc_max, glucose_max, hematocrit_max
, potassium_max, sodium_max
, bicarbonate_min, bicarbonate_max
, pao2fio2ratio_novent, pao2fio2ratio_vent, albumin_min
, alt_max, ast_max, alp_max, pt_max, ptt_max, inr_min
, chloride_min
, pao2_min, paco2_max, lactate_max, baseexcess_min, fio2_max
, troponin_max, lymphocytes_max, lymphocytes_min, neutrophils_min
, magnesium_max, fibrinogen_min, bnp_max, aniongap_max

, gcs_min
, urineoutput, spo2_min, heart_rate_mean
, mbp_mean, sbp_mean, resp_rate_mean, temperature_mean

, norepinephrine
, epinephrine
, dopamine
, dobutamine

, activity_stand
, activity_sit
, activity_bed
, activity_eva_flag

, apsiii, apsiii_prob, oasis, oasis_prob, saps, saps_prob, sofa, sofa_prob, cci_score

, code_status
, code_status_eva_flag
from older_study_cohort_salz sc
left join older_study_lab_salz lab
on sc.hadm_id = lab.hadm_id
left join older_study_vt_uo_salz vt
on sc.hadm_id = vt.hadm_id
left join older_study_tr_salz tr
on sc.hadm_id = tr.hadm_id
left join older_study_activity_salz ac
on sc.hadm_id = ac.hadm_id
order by sc.hadm_id;



--                        final output                       --

-- --------------------------------------------------------- --
with cohort_info as (
  select hadm_id, ROW_NUMBER() OVER (ORDER BY hadm_id) as id
  from older_study_salz
)

select ci.id, patientid
, first_careunit, los_icu_day
, los_hospital_day, death_hosp, deathtime_icu_hour, pre_icu_los_day
, admission_type, ethnicity, anchor_year_group
, gender, age, height, weight, bmi
, electivesurgery, vent
, creatinine_max, bilirubin_max, platelet_min
, bun_max, wbc_max, glucose_max, hematocrit_max
, potassium_max, sodium_max
, bicarbonate_min, bicarbonate_max
, pao2fio2ratio_novent, pao2fio2ratio_vent, albumin_min
, alt_max, ast_max, alp_max, pt_max, ptt_max, inr_min, chloride_min
, pao2_min, paco2_max, lactate_max, baseexcess_min, fio2_max
, troponin_max, lymphocytes_max, lymphocytes_min, neutrophils_min
, magnesium_max, fibrinogen_min, bnp_max, aniongap_max
, gcs_min, urineoutput, spo2_min, heart_rate_mean
, mbp_mean, sbp_mean, resp_rate_mean, temperature_mean
, norepinephrine, epinephrine, dopamine, dobutamine
, activity_stand, activity_sit, activity_bed, activity_eva_flag
, apsiii, apsiii_prob, oasis, oasis_prob, saps, saps_prob, sofa, sofa_prob, cci_score
, code_status, code_status_eva_flag
from cohort_info ci
inner join older_study_salz sc
on ci.hadm_id = sc.hadm_id
order by ci.id;