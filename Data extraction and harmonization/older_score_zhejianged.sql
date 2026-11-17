-- criteria
-- age >= 65
-- first icu admission
-- los icu day >= 1d

--                   Part 1. cohort information                    --

-- --------------------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_cohort_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_cohort_zhejiang as


with admission_type_info_0 as (
    SELECT patient_sn, hospital_id, transferfrom_dept_eng
    , ROW_NUMBER() OVER (PARTITION BY patient_sn, hospital_id ORDER BY transferuut_datetime) as rn
    FROM "hospitaltransfer"
)

, urgent_info_0 as (
    select distinct patient_sn, hospital_id
    from admission_type_info_0
    where rn = 1
    and (
        transferfrom_dept_eng ilike '%surgery%'
        or transferfrom_dept_eng ilike '%critical%'
        or transferfrom_dept_eng ilike '%icu%'
        or transferfrom_dept_eng ilike '%emergency%'
    )
)

, urgent_info as (
    select *
    from urgent_info_0
    union
    select patient_sn, hospital_id
    from firstnote
    where firstnote_desc like '%突发%'
)

, ed_surgery_0 as (
    select co.patient_sn, co.hospital_id, (sg_time - ed_time) as time_diff 
    from (
        select distinct patient_sn, hospital_id
        from hospitaltransfer
        where transferfrom_dept_eng ilike 'emergency'
        or transferfrom_dept_eng ilike 'surgery'
    ) co
    left join (
        select patient_sn, hospital_id, min(transferuut_datetime) as ed_time
        from hospitaltransfer
        where transferfrom_dept_eng ilike 'emergency'
        group by patient_sn, hospital_id       
    ) ed
    on co.patient_sn = ed.patient_sn
    and co.hospital_id = ed.hospital_id
    left join (
        select patient_sn, hospital_id, min(transferuut_datetime) as sg_time
        from hospitaltransfer
        where transferfrom_dept_eng ilike 'surgery'
        group by patient_sn, hospital_id       
    ) sg
    on co.patient_sn = sg.patient_sn
    and co.hospital_id = sg.hospital_id        
)

, ed_surgery as (
    select patient_sn, hospital_id
    from ed_surgery_0
    where time_diff >= 0
)

, surgery_info as (
    select sy.patient_sn, sy.hospital_id
    , min(case when sy.patient_sn = fn.patient_sn and sy.hospital_id = fn.hospital_id then 0 else 1 end) as surgery_type -- 0: non-elective surgery
    from surgerytab sy
    left join ed_surgery fn
    on sy.patient_sn = fn.patient_sn
    and sy.hospital_id = fn.hospital_id
		group by sy.patient_sn, sy.hospital_id
)

, older_study_cohort_zhejiang as (
	select cs.patient_sn, cs.hospital_id, age, age_cut
    , case when sex = 'Female' then 'F' else 'M' end as gender
    , case when height < 50 then null
	when height > 300 then null else height end as height
	, case when weight < 20 then null
	when weight > 400 then null else weight end as weight
	, (case when weight > 0 and height > 0 then round((weight/(0.0001*height*height)),1) else null end) as bmi
	, death_hosp
	, 0 as admittime
	, intime as icu_admittime
	, outtime as dis_icu	
	, los_hospital_days as los_hospital_day 
	, los_icu_days as los_icu_day
	, round(intime, 3) as pre_icu_los_day	
	, case when death_hosp = 1 then round(24*(los_hospital_days - intime)) ELSE NULL end as deathtime_icu_hour
	, 'ICU' as first_careunit
	, case when cs.patient_sn = ad.patient_sn and cs.hospital_id = ad.hospital_id then 'URGENT' else 'ELECTIVE' end as admission_type
    , case when cs.patient_sn = sg.patient_sn and cs.hospital_id = sg.hospital_id and sg.surgery_type = 1 then 1 else 0 end as electivesurgery	
	from icustay_detail cs	
	left join urgent_info ad 
	on cs.patient_sn = ad.patient_sn
    and cs.hospital_id = ad.hospital_id
    left join surgery_info sg
    on cs.patient_sn = sg.patient_sn
    and cs.hospital_id = sg.hospital_id
	where (
        age_cut in ('(70,80]', '(80,90]', '(90,150]')
        or age >= 65
    )
	and los_icu_days > 1
    and los_hospital_days > 1
)

, vital_gcs_uo_info as (
    select sc.patient_sn, sc.hospital_id, gcs_min
    , round(vital.heart_rate_mean,1) as heart_rate_mean
    , round(vital.mbp_mean,1) as mbp_mean
    , round(vital.sbp_mean,1) as sbp_mean
    , round(vital.resp_rate_mean,1) as resp_rate_mean
    , round(vital.temperature_mean,1) as temperature_mean
    , vital.spo2_min
    , case when uo.urineoutput < 0 then 0 else uo.urineoutput end as urineoutput
    from older_study_cohort_zhejiang sc
    left join first_day_gcs gcs
    on sc.patient_sn = gcs.patient_sn
    and sc.hospital_id = gcs.hospital_id
    left join first_day_vitalsign vital
    on sc.patient_sn = vital.patient_sn
    and sc.hospital_id = vital.hospital_id
    left join first_day_urine_output uo
    on sc.patient_sn = uo.patient_sn
    and sc.hospital_id = uo.hospital_id    
)

, score_info as (
  select sc.patient_sn, sc.hospital_id
  , sf.sofa, 1 / (1 + exp(- (-3.3890 + 0.2439*(sf.sofa) ))) as sofa_prob
  , sap.sapsii as saps, sapsii_prob as saps_prob
  , cci.charlson_comorbidity_index as cci_score
  , oa.oasis, oa.oasis_prob
  from older_study_cohort_zhejiang sc 
  left join sofa sf
  on sc.patient_sn = sf.patient_sn
  and sc.hospital_id = sf.hospital_id
  left join sapsii sap 
  on sc.patient_sn = sap.patient_sn
  and sc.hospital_id = sap.hospital_id 
  left join (
    select patient_sn, hospital_id, max(charlson_comorbidity_index) as charlson_comorbidity_index
    from charlson_comorbidity_index
    group by patient_sn, hospital_id
  ) cci 
  on sc.patient_sn = cci.patient_sn
  and sc.hospital_id = cci.hospital_id
  left join oasis oa
  on sc.patient_sn = oa.patient_sn
  and sc.hospital_id = oa.hospital_id
)

, exclude_id_vt_info as (
  select patient_sn, hospital_id
  from (
      select patient_sn, hospital_id
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
, sofa, sofa_prob, saps, saps_prob, cci_score, oasis, oasis_prob
from older_study_cohort_zhejiang sc
left join score_info si
on sc.patient_sn = si.patient_sn
and sc.hospital_id = si.hospital_id
where sc.patient_sn not in (select patient_sn from exclude_id_vt_info)
order by sc.patient_sn;


--                   Part 2. vital sign information                    --

-- ------------------------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_vt_uo_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_vt_uo_zhejiang as

with study_cohort as (
	select *
	from older_study_cohort_zhejiang
)

, cohort_time as
(
  select patient_sn, hospital_id, icu_admittime
  , generate_series(
    0, 
	ceil((dis_icu - icu_admittime)*24)::INTEGER
    ) as hr
		
  from study_cohort
)

, vital_info_0 as (
	select vt.patient_sn, vt.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, heart_rate, COALESCE(sbp, sbp_ni) as sbp, COALESCE(dbp, dbp_ni) as dbp
	, resp_rate, spo2, temperature, cvp
	from vitalsign_cal vt
	inner join study_cohort sc 
	on vt.patient_sn = sc.patient_sn
    and vt.hospital_id = sc.hospital_id
)

, vital_info as (
	select patient_sn, hospital_id, hr
	, round(avg(heart_rate),1) as heart_rate
	, round(avg(sbp),1) as sbp
	, round(avg(case when sbp > 0 and dbp > 0 then ((sbp+2*dbp)/3) else null end),1) as mbp
	, round(avg(resp_rate),1) as resp_rate
	, round(avg(spo2)) as spo2
	, round(avg(temperature),1) as temperature
    , round(avg(cvp),1) as cvp
	from vital_info_0
	group by patient_sn, hospital_id, hr
)

, uo_info_0 as (
	select uo.patient_sn, uo.hospital_id, ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr, urineoutput
	from urine_output uo
	inner join study_cohort sc 
	on uo.patient_sn = sc.patient_sn
    and uo.hospital_id = sc.hospital_id	
)

, uo_info as (
	select patient_sn, hospital_id, hr, sum(urineoutput) as urineoutput
	from uo_info_0
	group by patient_sn, hospital_id, hr
)

, vital_uo_use_0 as (
    select ct.patient_sn, ct.hospital_id, ct.hr
    , heart_rate, resp_rate, sbp, mbp, temperature, spo2, urineoutput, cvp
    from cohort_time ct
    left join vital_info vt
    on ct.patient_sn = vt.patient_sn
    and ct.hospital_id = vt.hospital_id
    and ct.hr = vt.hr
    left join uo_info uo
    on ct.patient_sn = uo.patient_sn
    and ct.hospital_id = uo.hospital_id
    and ct.hr = uo.hr
    where ct.hr >= 1 and ct.hr <= 24
)

, vital_uo_use as (
  select patient_sn, hospital_id
      , round(avg(heart_rate), 1) as heart_rate_mean
      , round(avg(mbp), 1) as mbp_mean
      , round(avg(sbp), 1) as sbp_mean
      , round(avg(resp_rate), 1) as resp_rate_mean
      , round(avg(temperature), 1) as temperature_mean
      , sum(case when urineoutput < 0 then 0 else urineoutput end) as urineoutput
      , min(spo2) as spo2_min      
  from vital_uo_use_0
  group by patient_sn, hospital_id
)

, gcs_use as (
    select patient_sn, hospital_id, min(gcs_min) as gcs_min
    from first_day_gcs
    group by patient_sn, hospital_id
)

select sc.patient_sn, sc.hospital_id
, heart_rate_mean, mbp_mean, sbp_mean, spo2_min
, resp_rate_mean, temperature_mean, gcs_min, coalesce(vt.urineoutput, fuo.urineoutput) as urineoutput
from older_study_cohort_zhejiang sc
left join vital_uo_use vt
on sc.patient_sn = vt.patient_sn
and sc.hospital_id = vt.hospital_id
left join first_day_urine_output fuo
on sc.patient_sn = fuo.patient_sn
and sc.hospital_id = fuo.hospital_id
left join gcs_use g
on sc.patient_sn = g.patient_sn
and sc.hospital_id = g.hospital_id
order by sc.patient_sn, sc.hospital_id;


--                   Part 3. lab information                    --

-- ------------------------------------------------------------ --
DROP MATERIALIZED VIEW IF EXISTS older_study_lab_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_lab_zhejiang as

with study_cohort as (
	select *
	from older_study_cohort_zhejiang
)

, cohort_time as
(
  select patient_sn, hospital_id, icu_admittime
  , generate_series(
    0, 
	ceil((dis_icu - icu_admittime)*24)::INTEGER
    ) as hr
		
  from study_cohort
)

, bg_info_0 as (
	select sc.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, po2 as pao2, pco2 as paco2, fio2
	, ph, baseexcess, bicarbonate
	, hematocrit, hemoglobin, chloride, calcium
	, potassium, sodium, lactate, glucose
	from bg
	inner join study_cohort sc 
	on bg.patient_sn = sc.patient_sn
    and bg.hospital_id = sc.hospital_id
)

, bg_info_1 as (
	select *, case when pao2 > 0 and fio2 > 0 then ROUND(100*pao2/fio2, 1) else null end as pao2fio2ratio
	from (
		select patient_sn, hospital_id, hr
		, max(pao2) as pao2, max(paco2) as paco2
		, max(fio2) as fio2 
		, max(ph) as ph, max(baseexcess) as baseexcess
		, max(bicarbonate) as bicarbonate, max(hematocrit) as hematocrit
		, max(hemoglobin) as hemoglobin, max(chloride) as chloride
		, max(calcium) as calcium, max(potassium) as potassium
		, max(sodium) as sodium, max(lactate) as lactate
		, max(glucose) as glucose
		from bg_info_0
		group by patient_sn, hospital_id, hr
	) aa
)

, bg_info as (
    select b1.patient_sn, b1.hospital_id, b1.hr
    , pao2, paco2, fio2
	, ph, baseexcess, bicarbonate
	, hematocrit, hemoglobin, chloride, calcium
	, potassium, sodium, lactate, glucose
    from bg_info_1 b1
)

, lab_info_00 as (
	select bg.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, wbc, lymphocytes, neutrophils
	from blood_differential bg
	inner join study_cohort sc 
	on bg.patient_sn = sc.patient_sn
    and bg.hospital_id = sc.hospital_id	
)

, lab_info_0 as (
	select patient_sn, hospital_id, hr
	, max(wbc) as wbc, max(lymphocytes) as lymphocytes
	, max(neutrophils) as neutrophils
	from lab_info_00
	group by patient_sn, hospital_id, hr 
) 

, lab_info_10 as (
	select bg.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, albumin, creatinine, bun, aniongap
	from chemistry bg
	inner join study_cohort sc 
	on bg.patient_sn = sc.patient_sn
    and bg.hospital_id = sc.hospital_id	
)

, lab_info_1 as (
	select patient_sn, hospital_id, hr
	, max(albumin) as albumin, max(creatinine) as creatinine
	, max(bun) as bun, max(aniongap) as aniongap
	from lab_info_10
	group by patient_sn, hospital_id, hr 
) 

, lab_info_20 as (
	select bg.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, pt, ptt, inr
	from coagulation bg
	inner join study_cohort sc 
	on bg.patient_sn = sc.patient_sn
    and bg.hospital_id = sc.hospital_id	
)

, lab_info_2 as (
	select patient_sn, hospital_id, hr
	, max(pt) as pt, max(ptt) as ptt, max(inr) as inr
	from lab_info_20
	group by patient_sn, hospital_id, hr 
) 

, lab_info_30 as (
	select BG.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, platelet
	from complete_blood_count bg
	inner join study_cohort sc 
	on bg.patient_sn = sc.patient_sn
    AND bg.hospital_id = sc.hospital_id	
)

, lab_info_3 as (
	select patient_sn, hospital_id, hr
	, max(platelet) as platelet
	from lab_info_30
	group by patient_sn, hospital_id, hr 
) 

, lab_info_40 as (
	select bg.patient_sn, bg.hospital_id
    , ceil((charttime - sc.icu_admittime)*24)::INTEGER as hr
	, alt, alp as alkaline_phosphatase
	, ast, bilirubin_total as bilirubin
	from enzyme bg
	inner join study_cohort sc
    on bg.patient_sn = sc.patient_sn
	and bg.hospital_id = sc.hospital_id	
)

, lab_info_4 as (
	select patient_sn, hospital_id, hr
	, max(alt) as alt
	, max(alkaline_phosphatase) as alkaline_phosphatase
	, max(ast) as ast
	, max(bilirubin) as bilirubin	
	from lab_info_40
	group by patient_sn, hospital_id, hr 
)

, lab_info_use as (
    select ct.patient_sn, ct.hospital_id, ct.hr
    , pao2, paco2, fio2
    , ph, baseexcess, bicarbonate, hematocrit
    , hemoglobin, chloride, calcium, potassium
    , sodium, lactate, glucose
    , wbc, lymphocytes, neutrophils
    , albumin, creatinine, bun, pt
    , ptt, inr
    , platelet
    , alt, alkaline_phosphatase, ast, bilirubin, aniongap
    from cohort_time ct
    left join bg_info bi
    on ct.hospital_id = bi.hospital_id
    and ct.hr = bi.hr
    left join lab_info_0 lab0
    on ct.patient_sn = lab0.patient_sn
    and ct.hospital_id = lab0.hospital_id
    and ct.hr = lab0.hr
    left join lab_info_1 lab1
    on ct.patient_sn = lab1.patient_sn
    and ct.hospital_id = lab1.hospital_id
    and ct.hr = lab1.hr
    left join lab_info_2 lab2
    on ct.patient_sn = lab2.patient_sn
    and ct.hospital_id = lab2.hospital_id
    and ct.hr = lab2.hr
    left join lab_info_3 lab3
    on ct.patient_sn = lab3.patient_sn
    and ct.hospital_id = lab3.hospital_id
    and ct.hr = lab3.hr
    left join lab_info_4 lab4
    on ct.patient_sn = lab4.patient_sn
    and ct.hospital_id = lab4.hospital_id
    and ct.hr = lab4.hr
)

, pafi10 as
(
  -- join blood gas to ventilation durations to determine if patient was vent
  select bg.patient_sn, bg.hospital_id, bg.charttime
  , po2, fio2
  , case when vd.patient_sn is not null and vd.hospital_id is not null then 1 else 0 end as isvent
  from bg
  inner join icustay_detail icud
  on icud.patient_sn = bg.patient_sn
  and bg.hospital_id = icud.hospital_id
  left join (
    select icud.patient_sn, icud.hospital_id
    from ventilation vt
    inner join icustay_detail icud
    on vt.patient_sn = icud.patient_sn
    and vt.event_datetime >= icud.intime
    and vt.event_datetime < icud.intime + 1 
  ) vd
  on bg.patient_sn = vd.patient_sn
  and bg.hospital_id = vd.hospital_id
  
  where bg.charttime >= icud.intime - 0.25
  and bg.charttime < icud.intime + 1
  order by bg.patient_sn, bg.hospital_id, bg.charttime
)

, pafi1 as (
    select patient_sn, hospital_id, min(po2) as pao2, max(fio2) as fio2
    , max(isvent) as isvent
    from pafi10
    group by patient_sn, hospital_id
)

, pafi2 as
(
  -- because pafi has an interaction between vent/PaO2:FiO2, we need two columns for the score
  -- it can happen that the lowest unventilated PaO2/FiO2 is 68, but the lowest ventilated PaO2/FiO2 is 120
  -- in this case, the SOFA score is 3, *not* 4.
  select patient_sn, hospital_id
  , min(case when isvent = 0 then pao2/(0.01*fio2) else null end) as pao2fio2ratio_novent
  , min(case when isvent = 1 then pao2/(0.01*fio2) else null end) as pao2fio2ratio_vent
  from pafi1
  group by patient_sn, hospital_id
)

, lab_need_info as (
    select sc.patient_sn, sc.hospital_id
    , max(creatinine) as creatinine_max, max(bilirubin) as bilirubin_max
    , min(platelet) as platelet_min, max(bun) as bun_max
    , max(wbc) as wbc_max, max(glucose) as glucose_max
    , max(hematocrit) as hematocrit_max, max(potassium) as potassium_max, max(sodium) as sodium_max
    , min(bicarbonate) as bicarbonate_min, max(bicarbonate) as bicarbonate_max
    --, min(pao2fio2ratio_novent) as pao2fio2ratio_novent
    --, min(pao2fio2ratio_vent) as pao2fio2ratio_vent
    , min(albumin) as albumin_min, max(alt) as alt_max
    , max(ast) as ast_max
    , max(alkaline_phosphatase) as alp_max

    , max(pt) as pt_max, max(ptt) as ptt_max
    , min(inr) as inr_min, min(hemoglobin) as hemoglobin_min
    , min(chloride) as chloride_min, min(pao2) as pao2_min
    , max(paco2) as paco2_max, max(lactate) as lactate_max
    , min(baseexcess) as baseexcess_min, max(fio2) as fio2_max
    , max(lymphocytes) as lymphocytes_max
    , min(lymphocytes) as lymphocytes_min, min(neutrophils) as neutrophils_min
    , max(aniongap) as aniongap_max
    from older_study_cohort_zhejiang sc
    left join lab_info_use lab
    on sc.patient_sn = lab.patient_sn
    and sc.hospital_id = lab.hospital_id
    and hr>= 1 and hr<= 24
    group by sc.patient_sn, sc.hospital_id
    order by sc.patient_sn, sc.hospital_id
)


select lni.*, pf.pao2fio2ratio_novent, pf.pao2fio2ratio_vent
from lab_need_info lni
left join pafi2 pf
on lni.patient_sn = pf.patient_sn
and lni.hospital_id = pf.hospital_id
order by lni.patient_sn, lni.hospital_id;



--                   Part 4. treatment information                    --

-- ------------------------------------------------------------------ --
DROP MATERIALIZED VIEW IF EXISTS older_study_tr_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_tr_zhejiang as

with study_cohort as (
	select *
	from older_study_cohort_zhejiang
)

, cohort_time as
(
  select patient_sn, hospital_id, icu_admittime
  , generate_series(
    0, 
	ceil((dis_icu - icu_admittime)*24)::INTEGER
    ) as hr
		
  from study_cohort
)

, dobutamine_info as (
	select dob.patient_sn, dob.hospital_id
	, ct.hr
	, max(case when ceil((dob.charttime - ct.icu_admittime)*24)::INTEGER = ct.hr then 1
	else 0 end) as dobutamine 
	from dobutamine dob 
	inner join cohort_time ct
	on dob.patient_sn = ct.patient_sn
    and dob.hospital_id = ct.hospital_id
	where dob.vaso_rate > 0
    and ct.hr >= 1 and ct.hr <= 24
	group by dob.patient_sn, dob.hospital_id, ct.hr
)

, dopamine_info as (
	select dob.patient_sn, dob.hospital_id
	, ct.hr
	, max(case when ceil((dob.charttime - ct.icu_admittime)*24)::INTEGER = ct.hr then 1
	else 0 end) as dopamine 
	from dopamine dob 
	inner join cohort_time ct
	on dob.patient_sn = ct.patient_sn
    and dob.hospital_id = ct.hospital_id
	where dob.vaso_rate > 0
    and ct.hr >= 1 and ct.hr <= 24
	group by dob.patient_sn, dob.hospital_id, ct.hr
)

, epinephrine_info as (
	select dob.patient_sn, dob.hospital_id
	, ct.hr
	, max(case when ceil((dob.charttime - ct.icu_admittime)*24)::INTEGER = ct.hr then 1
	else 0 end) as epinephrine 
	from epinephrine dob 
	inner join cohort_time ct
	on dob.patient_sn = ct.patient_sn
    and dob.hospital_id = ct.hospital_id
	where dob.vaso_rate > 0
    and ct.hr >= 1 and ct.hr <= 24
	group by dob.patient_sn, dob.hospital_id, ct.hr
)

, norepinephrine_info as (
	select dob.patient_sn, dob.hospital_id
	, ct.hr
	, max(case when ceil((dob.charttime - ct.icu_admittime)*24)::INTEGER = ct.hr then 1
	else 0 end) as norepinephrine 
	from norepinephrine dob 
	inner join cohort_time ct
	on dob.patient_sn = ct.patient_sn
    and dob.hospital_id = ct.hospital_id
	where dob.vaso_rate > 0
    and ct.hr >= 1 and ct.hr <= 24
	group by dob.patient_sn, dob.hospital_id, ct.hr
)

, vent_info as (
	select ct.patient_sn, ct.hospital_id, ct.hr
	, max(case when ceil((vt.event_datetime - ct.icu_admittime)*24)::INTEGER = ct.hr then 1
	else 0 end) as ventilation
	from (
		select distinct patient_sn, hospital_id, event_datetime
		from ventilation
	) vt
	inner join cohort_time ct
	on vt.patient_sn = ct.patient_sn
	and vt.hospital_id = ct.hospital_id
    and ct.hr >= 1 and ct.hr <= 24
	group by ct.patient_sn, ct.hospital_id, ct.hr
)

, treatment_info_need as (
    select ct.patient_sn, ct.hospital_id, ct.hr
    , case when dob.dobutamine = 1 then 1 else 0 end as dobutamine
    , case when dop.dopamine = 1 then 1 else 0 end as dopamine
    , case when ep.epinephrine = 1 then 1 else 0 end as epinephrine
    , case when nop.norepinephrine = 1 then 1 else 0 end as norepinephrine
    , case when vt.ventilation = 1 then 1 else 0 end as ventilation

    from cohort_time ct
    left join dobutamine_info dob
    on ct.patient_sn = dob.patient_sn
    and ct.hospital_id = dob.hospital_id
    and ct.hr = dob.hr
    left join dopamine_info dop
    on ct.patient_sn = dop.patient_sn
    and ct.hospital_id = dop.hospital_id
    and ct.hr = dop.hr
    left join epinephrine_info ep
    on ct.patient_sn = ep.patient_sn
    and ct.hospital_id = ep.hospital_id
    and ct.hr = ep.hr
    left join norepinephrine_info nop
    on ct.patient_sn = nop.patient_sn
    and ct.hospital_id = nop.hospital_id
    and ct.hr = nop.hr
    left join vent_info vt
    on ct.patient_sn = vt.patient_sn
    and ct.hospital_id = vt.hospital_id
    and ct.hr = vt.hr
    where ct.hr >= 1 and ct.hr <= 24
)

select sc.patient_sn, sc.hospital_id
, max(case when dobutamine is not null then dobutamine else 0 end) as dobutamine
, max(case when dopamine is not null then dopamine else 0 end) as dopamine
, max(case when epinephrine is not null then epinephrine else 0 end) as epinephrine
, max(case when norepinephrine is not null then norepinephrine else 0 end) as norepinephrine
, max(case when ventilation is not null then ventilation else 0 end) as vent
, 0 as code_status, 0 as code_status_eva_flag
from older_study_cohort_zhejiang sc
left join treatment_info_need ti
on sc.patient_sn = ti.patient_sn
and sc.hospital_id = ti.hospital_id
group by sc.patient_sn, sc.hospital_id
order by sc.patient_sn, sc.hospital_id;




DROP MATERIALIZED VIEW IF EXISTS older_study_activity_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_activity_zhejiang as

with activity_info_0 as (
    select patient_sn, hospital_id, event_datetime
    , case 
    when nursingevent_val like '%站%' then 2
    when nursingevent_val like '%立%' then 2
    when nursingevent_val like '%外出%' then 2
    when nursingevent_val like '%高压氧%' then 2
    when nursingevent_val like '%坐%' then 1
    else 0 end as activity
    from nursingchart_vitalsign
    where nursingevent_item = '体位+CPT'
)

, activity_info as (
    select ac.patient_sn, ac.hospital_id, max(activity) as activity
    from activity_info_0 ac
    inner join icustay_detail icud
    on ac.patient_sn = icud.patient_sn
    and ac.hospital_id = icud.hospital_id
    and ac.event_datetime >= icud.intime - 0.25
    and ac.event_datetime < icud.intime + 1
    group by ac.patient_sn, ac.hospital_id
)

select ai.patient_sn, sc.hospital_id
, case when activity = 2 then 1 else 0 end as activity_stand
, case when activity = 1 then 1 else 0 end as activity_sit
, case when activity = 0 or activity is null then 1 else 0 end as activity_bed
, case when sc.hospital_id = ai1.hospital_id then 1 else 0 end as activity_eva_flag
, 0 as fall_risk
, 0 as fall_risk_eva_flag
from older_study_cohort_zhejiang sc
left join activity_info ai
on ai.patient_sn = sc.patient_sn
and sc.hospital_id = ai.hospital_id
left join (
    select distinct patient_sn, hospital_id 
    from nursingchart_vitalsign
) ai1
on sc.patient_sn = ai1.patient_sn
and sc.hospital_id = ai1.hospital_id
order by ai.patient_sn, sc.hospital_id;



--                        Merge                          --

-- ----------------------------------------------------- --
DROP MATERIALIZED VIEW IF EXISTS older_study_zhejiang CASCADE;
CREATE MATERIALIZED VIEW older_study_zhejiang as

select sc.patient_sn, sc.hospital_id 
, first_careunit, los_icu_day
, los_hospital_day
, death_hosp
, deathtime_icu_hour
, pre_icu_los_day
, admission_type, 'asian' as ethnicity
, '2019-2022' as anchor_year_group
, gender, age, age_cut
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
, lymphocytes_max, lymphocytes_min, neutrophils_min
, aniongap_max

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

, sofa, sofa_prob, saps, saps_prob, cci_score, oasis, oasis_prob

, code_status
, code_status_eva_flag
from older_study_cohort_zhejiang sc
left join older_study_lab_zhejiang lab
on sc.patient_sn = lab.patient_sn
and sc.hospital_id = lab.hospital_id
left join older_study_vt_uo_zhejiang vt
on sc.patient_sn = vt.patient_sn
and sc.hospital_id = vt.hospital_id
left join older_study_tr_zhejiang tr
on sc.patient_sn = tr.patient_sn
and sc.hospital_id = tr.hospital_id
left join older_study_activity_zhejiang ac
on sc.patient_sn = ac.patient_sn
and sc.hospital_id = ac.hospital_id
order by sc.patient_sn, sc.hospital_id;


--                        final output                       --

-- --------------------------------------------------------- --

select ROW_NUMBER() OVER () as id
, first_careunit, los_icu_day
, los_hospital_day, death_hosp, deathtime_icu_hour, pre_icu_los_day
, admission_type, ethnicity, anchor_year_group
, gender, age, age_cut, height, weight, bmi
, electivesurgery, vent
, creatinine_max, bilirubin_max, platelet_min
, bun_max, wbc_max, glucose_max, hematocrit_max
, potassium_max, sodium_max
, bicarbonate_min, bicarbonate_max
, pao2fio2ratio_novent, pao2fio2ratio_vent, albumin_min
, alt_max, ast_max, alp_max, pt_max, ptt_max, inr_min, chloride_min
, pao2_min, paco2_max, lactate_max, baseexcess_min, fio2_max
, null as troponin_max, lymphocytes_max, lymphocytes_min, neutrophils_min
, null as magnesium_max, null as fibrinogen_min, null as bnp_max, aniongap_max
, gcs_min, urineoutput, spo2_min, heart_rate_mean
, mbp_mean, sbp_mean, resp_rate_mean, temperature_mean
, norepinephrine, epinephrine, dopamine, dobutamine
, activity_stand, activity_sit, activity_bed, activity_eva_flag
, sofa, sofa_prob, saps, saps_prob, cci_score, oasis, oasis_prob
, code_status, code_status_eva_flag
from older_study_zhejiang sc
order by patient_sn, hospital_id;
