-- ------------------------------------------------------------------
-- Title: Systemic inflammatory response syndrome (SIRS) criteria
-- Originally written by: Alistair Johnson
-- Contact: aewj [at] mit [dot] edu
-- ------------------------------------------------------------------

-- This query extracts the Systemic inflammatory response syndrome (SIRS) criteria
-- The criteria quantify the level of inflammatory response of the body
-- The score is calculated at the time of suspected infection.

-- Reference for SIRS:
--    American College of Chest Physicians/Society of Critical Care Medicine Consensus Conference:
--    definitions for sepsis and organ failure and guidelines for the use of innovative therapies in sepsis"
--    Crit. Care Med. 20 (6): 864–74. 1992.
--    doi:10.1097/00003246-199206000-00025. PMID 1597042.

-- Variables used in SIRS:
--  Body temperature (min and max)
--  Heart rate (max)
--  Respiratory rate (max)
--  PaCO2 (min)
--  White blood cell count (min and max)
--  the presence of greater than 10% immature neutrophils (band forms)

DROP MATERIALIZED VIEW IF EXISTS SIRS_si;
CREATE MATERIALIZED VIEW SIRS_si AS
with bg as
(
  -- join blood gas to ventilation durations to determine if patient was vent
  select bg.icustay_id
  , min(pco2) as PaCO2_Min
  from bloodgasarterial_si bg
  where specimen_pred = 'ART'
  group by bg.icustay_id
)
-- Aggregate the components for the score
, scorecomp as
(
select ie.icustay_id
  , v.Tempc_Min
  , v.Tempc_Max
  , v.HeartRate_Max
  , v.RespRate_Max
  , bg.PaCO2_Min
  , l.WBC_min
  , l.WBC_max
  , l.Bands_max

from suspinfect ie
left join bg
 on ie.icustay_id = bg.icustay_id
left join vitals_si v
  on ie.icustay_id = v.icustay_id
left join labs_si l
  on ie.icustay_id = l.icustay_id
)
, scorecalc as
(
  -- Calculate the final score
  -- note that if the underlying data is missing, the component is null
  -- eventually these are treated as 0 (normal), but knowing when data is missing is useful for debugging
  select icustay_id

  , case
      when Tempc_Min < 36.0 then 1
      when Tempc_Max > 38.0 then 1
      when Tempc_min is null then null
      else 0
    end as Temp_score


  , case
      when HeartRate_Max > 90.0  then 1
      when HeartRate_Max is null then null
      else 0
    end as HeartRate_score

  , case
      when RespRate_max > 20.0  then 1
      when PaCO2_Min < 32.0  then 1
      when coalesce(RespRate_max, PaCO2_Min) is null then null
      else 0
    end as Resp_score

  , case
      when WBC_Min <  4.0  then 1
      when WBC_Max > 12.0  then 1
      when Bands_max > 10 then 1-- > 10% immature neurophils (band forms)
      when coalesce(WBC_Min, Bands_max) is null then null
      else 0
    end as WBC_score

  from scorecomp
)
select
  si.icustay_id
  -- Combine all the scores to get SOFA
  -- Impute 0 if the score is missing
  , coalesce(Temp_score,0)
  + coalesce(HeartRate_score,0)
  + coalesce(Resp_score,0)
  + coalesce(WBC_score,0)
    as SIRS
  , Temp_score, HeartRate_score, Resp_score, WBC_score
from suspinfect si
left join scorecalc s
  on si.icustay_id = s.icustay_id
where si.suspected_infection_time is not null
order by si.icustay_id;
