-- Analysis views. Every definition below is a choice that changes the numbers; each is explained in the README.
-- Costs are EUR millions. Reported precision is 0.01m, so differences are rounded to 2 decimals to remove float noise.

-- Baseline = the EARLIEST report of type 'Initieel' (initial plan) for the project.
CREATE VIEW v_baseline AS
SELECT r.project_id, r.seq AS base_seq, r.report_date AS base_date,
       r.est_total_m AS base_cost_m, r.est_end_date AS base_end
FROM cost_report r
WHERE r.action_nl = 'Initieel'
  AND r.seq = (SELECT MIN(x.seq) FROM cost_report x WHERE x.project_id = r.project_id AND x.action_nl = 'Initieel');

-- Latest = the LAST report of the project (highest seq).
CREATE VIEW v_latest AS
SELECT r.project_id, r.report_date AS latest_date, r.est_total_m AS latest_cost_m,
       r.est_end_date AS latest_end, r.act_total_m AS spent_m, r.seq AS latest_seq
FROM cost_report r
WHERE r.seq = (SELECT MAX(x.seq) FROM cost_report x WHERE x.project_id = r.project_id);

-- Re-plans ('Herijking') AFTER the baseline: in total, and within 365 days of the baseline report (the "early signal").
CREATE VIEW v_replan_counts AS
SELECT b.project_id,
       (SELECT COUNT(*) FROM cost_report r WHERE r.project_id = b.project_id AND r.action_nl = 'Herijking'
         AND r.seq > b.base_seq) AS replans_total,
       (SELECT COUNT(*) FROM cost_report r WHERE r.project_id = b.project_id AND r.action_nl = 'Herijking'
         AND r.seq > b.base_seq AND julianday(r.report_date) <= julianday(b.base_date) + 365) AS replans_y1
FROM v_baseline b;

-- One row per project with its drift from the first plan.
CREATE VIEW v_drift AS
WITH j AS (
    SELECT p.project_id, p.name, m.name_nl AS ministry, p.status_nl, s.status_en, p.start_date, p.method_class,
           COALESCE(p.ict_activity_nl, 'Not stated') AS ict_activity,
           b.base_date, b.base_cost_m, b.base_end,
           l.latest_date, l.latest_cost_m, l.latest_end, l.spent_m,
           rc.replans_total, rc.replans_y1,
           (SELECT COUNT(*) FROM cost_report r WHERE r.project_id = p.project_id) AS n_reports,
           -- Scope: cancelled / not-started projects have no meaningful outcome to measure drift against.
           CASE WHEN p.status_nl NOT IN ('Geannuleerd', 'Nog niet gestart') THEN 1 ELSE 0 END AS in_scope
    FROM project p
    JOIN ministry m      ON m.ministry_id = p.ministry_id
    JOIN status_ref s    ON s.status_nl = p.status_nl
    LEFT JOIN v_baseline b      ON b.project_id = p.project_id
    LEFT JOIN v_latest l        ON l.project_id = p.project_id
    LEFT JOIN v_replan_counts rc ON rc.project_id = p.project_id
), k AS (
    SELECT j.*,
           -- Cost sample: in scope, has an initial plan, and the initial estimate is at least EUR 1m
           -- (zero / near-zero baselines would give meaningless percentages, e.g. +168,567%).
           CASE WHEN in_scope = 1 AND base_cost_m >= 1.0 THEN 1 ELSE 0 END AS cost_ok,
           julianday(base_end)   - julianday(start_date) AS planned_days,
           julianday(latest_end) - julianday(base_end)   AS slip_days
    FROM j
)
SELECT k.*,
       ROUND(latest_cost_m - base_cost_m, 2)                                    AS cost_growth_m,
       CASE WHEN cost_ok = 1 THEN ROUND(100.0 * ROUND(latest_cost_m - base_cost_m, 2) / base_cost_m, 2) END AS cost_growth_pct,
       -- Schedule sample: in scope, both end dates present, and at least 90 days planned between start date and initial end date.
       CASE WHEN in_scope = 1 AND base_end IS NOT NULL AND latest_end IS NOT NULL AND planned_days >= 90 THEN 1 ELSE 0 END AS sched_ok,
       CASE WHEN base_cost_m <  1   THEN '<EUR 1m'      -- never in the cost sample; appears only in schedule figures
            WHEN base_cost_m <  5   THEN 'EUR 1-5m'
            WHEN base_cost_m < 20   THEN 'EUR 5-20m'
            WHEN base_cost_m < 100  THEN 'EUR 20-100m'
            ELSE 'EUR 100m+' END                                                AS size_band,
       CASE WHEN replans_y1 = 0 THEN '0' WHEN replans_y1 = 1 THEN '1' ELSE '2+' END AS replans_y1_group,
       CASE WHEN replans_total = 0 THEN '0' WHEN replans_total = 1 THEN '1'
            WHEN replans_total <= 3 THEN '2-3' ELSE '4+' END                    AS replans_total_group,
       CASE WHEN substr(start_date,1,4) <= '2012' THEN 'start 2012 or earlier'
            WHEN substr(start_date,1,4) <= '2016' THEN 'start 2013-2016'
            WHEN substr(start_date,1,4) <= '2020' THEN 'start 2017-2020'
            ELSE 'start 2021 or later' END                                      AS start_cohort
FROM k;

-- RAG status (my convention, not an official standard - thresholds are stated in the README):
--   RED   : cost growth > 25%  OR  end date slipped > 365 days
--   AMBER : cost growth > 10%  OR  end date slipped > 90 days
--   GREEN : otherwise;  n/a when neither measure is available.
CREATE VIEW v_rag AS
SELECT d.*,
       CASE WHEN cost_ok = 0 AND sched_ok = 0 THEN 'n/a'
            WHEN (cost_ok = 1 AND cost_growth_pct > 25) OR (sched_ok = 1 AND ROUND(slip_days) > 365) THEN 'Red'
            WHEN (cost_ok = 1 AND cost_growth_pct > 10) OR (sched_ok = 1 AND ROUND(slip_days) >  90) THEN 'Amber'
            ELSE 'Green' END AS rag
FROM v_drift d;

-- Long format used by the "by dimension" query (Q5): one row per project per grouping dimension.
CREATE VIEW v_dims AS
SELECT project_id, 'ministry' AS dim, ministry AS bucket, 0 AS ord FROM v_drift
UNION ALL SELECT project_id, 'ict_activity', ict_activity, 0 FROM v_drift
UNION ALL SELECT project_id, 'size_band', size_band,
       CASE size_band WHEN '<EUR 1m' THEN 0 WHEN 'EUR 1-5m' THEN 1 WHEN 'EUR 5-20m' THEN 2 WHEN 'EUR 20-100m' THEN 3 ELSE 4 END FROM v_drift WHERE base_cost_m IS NOT NULL
UNION ALL SELECT project_id, 'replans_y1_group', replans_y1_group, CASE replans_y1_group WHEN '0' THEN 1 WHEN '1' THEN 2 ELSE 3 END FROM v_drift WHERE replans_y1 IS NOT NULL
UNION ALL SELECT project_id, 'replans_total_group', replans_total_group, CASE replans_total_group WHEN '0' THEN 1 WHEN '1' THEN 2 WHEN '2-3' THEN 3 ELSE 4 END FROM v_drift WHERE replans_total IS NOT NULL
UNION ALL SELECT project_id, 'method_class', method_class, 0 FROM v_drift
UNION ALL SELECT project_id, 'status', status_en, 0 FROM v_drift
UNION ALL SELECT project_id, 'start_cohort', start_cohort,
       CASE start_cohort WHEN 'start 2012 or earlier' THEN 1 WHEN 'start 2013-2016' THEN 2 WHEN 'start 2017-2020' THEN 3 ELSE 4 END FROM v_drift;

-- Growth AFTER the first 12 months (used by Q11 and chart 3). The estimate "at month 12" is the last report on or after
-- the baseline and within 365 days of it. Only projects observed for more than a year after the baseline are included.
CREATE VIEW v_after_year_one AS
WITH m AS (
    SELECT d.project_id, d.replans_y1_group, d.size_band, d.latest_cost_m,
           (SELECT r.est_total_m FROM cost_report r
             WHERE r.project_id = d.project_id AND r.seq >= b.base_seq
               AND julianday(r.report_date) <= julianday(b.base_date) + 365
             ORDER BY r.seq DESC LIMIT 1) AS est_12m_m
    FROM v_drift d JOIN v_baseline b ON b.project_id = d.project_id
    WHERE d.cost_ok = 1 AND julianday(d.latest_date) - julianday(b.base_date) > 365
)
SELECT *, 100.0 * ROUND(latest_cost_m - est_12m_m, 2) / est_12m_m AS later_growth_pct FROM m WHERE est_12m_m >= 1.0;

