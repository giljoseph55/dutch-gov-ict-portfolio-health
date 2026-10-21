-- Every number in the README comes from one of these queries. Run them all with:  python3 -I src/run_queries.py
-- Format: a "-- Qn:" title line, "-- HOW TO EXPLAIN:" notes, optional "-- PARAMS:" (run once per value), then ONE statement.
-- Definitions (baseline, latest, cost sample, schedule sample, RAG) are in sql/views.sql.
-- Money is EUR millions. "Cost growth" = latest estimate vs the first (initial) estimate in the dashboard.
-- Money columns keep the source's 2-decimal precision: SQLite versions differ in how ROUND() treats exact half-way
-- values (3.37 rounds 71.85 to 71.9, 3.45 to 71.8), and results must not depend on the SQLite version.

-- Q1: Which projects are in the analysis? (the funnel from 516 to the samples the percentages are based on)
-- HOW TO EXPLAIN: "Not every project can be measured. Cancelled ones have no outcome, some have no initial plan on record, and tiny or zero baselines make percentages meaningless. Every later percentage says which sample it uses."
SELECT '1 projects in the dataset' AS step, COUNT(*) AS n FROM project
UNION ALL SELECT '2 with an initial-plan report',                                  COUNT(*) FROM v_drift WHERE base_date IS NOT NULL
UNION ALL SELECT '3 ...and not cancelled / not yet started',                       COUNT(*) FROM v_drift WHERE base_date IS NOT NULL AND in_scope = 1
UNION ALL SELECT '4 COST sample: ...and initial estimate >= EUR 1m',               COUNT(*) FROM v_drift WHERE cost_ok = 1
UNION ALL SELECT '5 SCHEDULE sample: ...both end dates, >= 90 days planned',       COUNT(*) FROM v_drift WHERE sched_ok = 1;

-- Q2: Headline cost drift - how many projects are above their first cost estimate, and by how much?
-- HOW TO EXPLAIN: "For each project: (latest estimate - first estimate) / first estimate. Then count how many are above 0%, 10%, 25%. The total row adds up euros: sum of first estimates vs sum of latest estimates. The last two columns show how much one project (the biggest) drives the total."
WITH s AS (SELECT * FROM v_drift WHERE cost_ok = 1),
r AS (SELECT cost_growth_pct v, ROW_NUMBER() OVER (ORDER BY cost_growth_pct) rn, COUNT(*) OVER () n FROM s)
SELECT COUNT(*)                                                      AS n_projects,
       SUM(cost_growth_pct > 0)                                      AS n_above_0pct,
       ROUND(100.0 * SUM(cost_growth_pct > 0)  / COUNT(*), 1)        AS pct_above_0,
       ROUND(100.0 * SUM(cost_growth_pct > 10) / COUNT(*), 1)        AS pct_above_10,
       ROUND(100.0 * SUM(cost_growth_pct > 25) / COUNT(*), 1)        AS pct_above_25,
       ROUND(100.0 * SUM(cost_growth_pct < 0)  / COUNT(*), 1)        AS pct_below_0,
       (SELECT ROUND(AVG(v), 1) FROM r WHERE rn IN ((n + 1) / 2, (n + 2) / 2)) AS median_growth_pct,
       ROUND(SUM(base_cost_m), 0)                                    AS first_estimates_m,
       ROUND(SUM(latest_cost_m), 0)                                  AS latest_estimates_m,
       ROUND(SUM(cost_growth_m), 0)                                  AS total_growth_m,
       ROUND(100.0 * SUM(cost_growth_m) / SUM(base_cost_m), 1)       AS total_growth_pct,
       ROUND(MAX(cost_growth_m), 0)                                  AS largest_single_growth_m,
       ROUND(SUM(cost_growth_m) - MAX(cost_growth_m), 0)             AS growth_excl_largest_m
FROM s;

-- Q3: Headline schedule drift - how many projects have a later estimated end date than their first estimate?
-- HOW TO EXPLAIN: "slip = latest estimated end date minus first estimated end date, in days. Counted against 90 days (a quarter) and 365 days (a year). Only estimates exist, not realised end dates, so this is slip of the forecast. Many end dates are entered as 31 December (see Q10), so read slip at year/quarter precision: the median of exactly 365 days means 'about a year', not a measured day count."
WITH s AS (SELECT *, ROUND(slip_days) AS sd, 100.0 * slip_days / planned_days AS slip_pct FROM v_drift WHERE sched_ok = 1),
r  AS (SELECT sd v, ROW_NUMBER() OVER (ORDER BY sd) rn, COUNT(*) OVER () n FROM s),
rp AS (SELECT slip_pct v, ROW_NUMBER() OVER (ORDER BY slip_pct) rn, COUNT(*) OVER () n FROM s)
SELECT COUNT(*)                                          AS n_projects,
       ROUND(100.0 * SUM(sd > 0)   / COUNT(*), 1)        AS pct_later_than_first,
       ROUND(100.0 * SUM(sd > 90)  / COUNT(*), 1)        AS pct_slip_over_90d,
       ROUND(100.0 * SUM(sd > 365) / COUNT(*), 1)        AS pct_slip_over_365d,
       ROUND(100.0 * SUM(sd < 0)   / COUNT(*), 1)        AS pct_earlier_than_first,
       (SELECT AVG(v) FROM r  WHERE rn IN ((n + 1) / 2, (n + 2) / 2)) AS median_slip_days,
       (SELECT ROUND(AVG(v), 1) FROM rp WHERE rn IN ((n + 1) / 2, (n + 2) / 2)) AS median_slip_pct_of_planned_duration
FROM s;

-- Q4: Top 10 at-risk projects: still running (in progress or under reorientation), RAG = Red, ranked by euro growth.
-- HOW TO EXPLAIN: "At risk = still active AND Red (cost > +25% or end date > 12 months later than first estimate). Ranked by euros added to the estimate, because a PMO cares first where the money is. These are outside-view flags from public data, not a judgement on the teams."
SELECT name, ministry, status_en AS status, ROUND(base_cost_m, 2) AS first_est_m, ROUND(latest_cost_m, 2) AS latest_est_m,
       ROUND(cost_growth_m, 2) AS growth_m, ROUND(cost_growth_pct, 0) AS growth_pct,
       CAST(ROUND(slip_days) AS INTEGER) AS slip_days, replans_total, rag,
       (SELECT as_of_date FROM project p WHERE p.project_id = v_rag.project_id) AS status_date
FROM v_rag
WHERE status_nl IN ('In uitvoering', 'In heroriëntatie') AND cost_ok = 1 AND rag = 'Red'
ORDER BY cost_growth_m DESC
LIMIT 10;

-- Q5: Drift by group. One table per grouping dimension (the same statement is run for each value below).
-- PARAMS: dim = ministry | size_band | replans_y1_group | replans_total_group | method_class | ict_activity | start_cohort | status
-- HOW TO EXPLAIN: "Same measures as Q2/Q3, cut by one property at a time. n_cost is the group size - read small groups (n under 15) as anecdotes, not rates. One property at a time ignores overlap: big projects are also the ones with more re-plans, so none of this separates cause from correlation. n_cost and n_sched are different populations: the schedule sample also holds projects with a first estimate under EUR 1m (band '<EUR 1m') or without usable cost data."
WITH d AS (SELECT x.bucket, x.ord, v.* FROM v_dims x JOIN v_drift v USING (project_id) WHERE x.dim = :dim),
cr AS (SELECT bucket, cost_growth_pct v, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY cost_growth_pct) rn,
              COUNT(*) OVER (PARTITION BY bucket) n FROM d WHERE cost_ok = 1),
cm AS (SELECT bucket, AVG(v) med FROM cr WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY bucket),
sr AS (SELECT bucket, ROUND(slip_days) v, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY ROUND(slip_days)) rn,
              COUNT(*) OVER (PARTITION BY bucket) n FROM d WHERE sched_ok = 1),
sm AS (SELECT bucket, AVG(v) med FROM sr WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY bucket)
SELECT d.bucket,
       SUM(d.cost_ok)                                                                       AS n_cost,
       ROUND(cm.med, 1)                                                                     AS median_cost_growth_pct,
       ROUND(100.0 * SUM(CASE WHEN d.cost_ok = 1 AND d.cost_growth_pct > 25 THEN 1 ELSE 0 END) / NULLIF(SUM(d.cost_ok), 0), 1) AS pct_cost_over_25,
       ROUND(SUM(CASE WHEN d.cost_ok = 1 THEN d.cost_growth_m END), 2)                      AS growth_m,
       ROUND(100.0 * SUM(CASE WHEN d.cost_ok = 1 THEN d.cost_growth_m END) / SUM(CASE WHEN d.cost_ok = 1 THEN d.base_cost_m END), 1) AS growth_pct_of_first_est,
       SUM(d.sched_ok)                                                                      AS n_sched,
       sm.med                                                                               AS median_slip_days,
       ROUND(100.0 * SUM(CASE WHEN d.sched_ok = 1 AND ROUND(d.slip_days) > 365 THEN 1 ELSE 0 END) / NULLIF(SUM(d.sched_ok), 0), 1) AS pct_slip_over_365
FROM d LEFT JOIN cm ON cm.bucket = d.bucket LEFT JOIN sm ON sm.bucket = d.bucket
GROUP BY d.bucket
ORDER BY MIN(d.ord), d.bucket;

-- Q6: Do cost drift and schedule drift travel together?
-- HOW TO EXPLAIN: "A 2x2: cost above +25% or not, end date more than 12 months later or not, for projects in both samples. If the diagonal cells dominate, they travel together."
SELECT CASE WHEN cost_growth_pct > 25 THEN 'cost > +25%' ELSE 'cost <= +25%' END AS cost_band,
       CASE WHEN ROUND(slip_days) > 365 THEN 'end > 12 months later' ELSE 'end <= 12 months later' END AS schedule_band,
       COUNT(*) AS n_projects
FROM v_drift WHERE cost_ok = 1 AND sched_ok = 1
GROUP BY 1, 2 ORDER BY 1, 2;

-- Q7: RAG distribution (my thresholds: Red = cost > +25% or end > 12 months later; Amber = > +10% or > 3 months).
-- HOW TO EXPLAIN: "A portfolio status split. The thresholds are a PMO-style convention I chose and state openly; change them in sql/views.sql and every number moves with them."
SELECT status_en AS status, rag, COUNT(*) AS n_projects
FROM v_rag WHERE in_scope = 1 AND rag <> 'n/a'
GROUP BY status_en, rag
ORDER BY status_en, CASE rag WHEN 'Red' THEN 1 WHEN 'Amber' THEN 2 ELSE 3 END;

-- Q8: Why do projects re-plan? (reasons stated on re-plan reports; a report can list several)
-- HOW TO EXPLAIN: "A re-plan is a formal reset of the plan. The dashboard lets the project state one or more reasons. This counts the stated reasons, so the shares add to more than 100%. The reasons are self-reported."
SELECT rr.reason_en AS reason, COUNT(*) AS n_reports,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT report_id) FROM replan_reason), 1) AS pct_of_re_plans_with_a_reason
FROM replan_reason x JOIN reason_ref rr USING (reason_nl)
GROUP BY rr.reason_en ORDER BY n_reports DESC;

-- Q9: Completed projects - does the picture change if we use ACTUAL spend instead of the final ESTIMATE?
-- HOW TO EXPLAIN: "For finished projects the dashboard also reports what was actually spent. Most finish within 5% of their last estimate, but some come in under it. Measuring against actual spend lowers the overrun shares a little; it does not change the direction. I report both so nobody can say I picked the worse number."
WITH s AS (SELECT *, ROUND(spent_m - base_cost_m, 2) AS spend_growth_m FROM v_drift WHERE cost_ok = 1 AND status_nl = 'Afgerond')
SELECT COUNT(*)                                                                   AS n_completed,
       ROUND(100.0 * SUM(cost_growth_pct > 0)  / COUNT(*), 1)                     AS final_est_pct_above_0,
       ROUND(100.0 * SUM(cost_growth_pct > 25) / COUNT(*), 1)                     AS final_est_pct_above_25,
       ROUND(100.0 * SUM(spend_growth_m > 0) / COUNT(*), 1)                       AS actual_spend_pct_above_0,
       ROUND(100.0 * SUM(100.0 * spend_growth_m / base_cost_m > 25) / COUNT(*), 1) AS actual_spend_pct_above_25,
       SUM(spent_m < 0.95 * latest_cost_m)                                        AS n_spent_over_5pct_under_final_est,
       SUM(spent_m > 1.05 * latest_cost_m)                                        AS n_spent_over_5pct_above_final_est,
       ROUND(SUM(latest_cost_m), 0)                                               AS final_estimates_m,
       ROUND(SUM(spent_m), 0)                                                     AS actual_spend_m
FROM s;

-- Q10: How precise are the end dates? (share entered as 31 December, i.e. at year level)
-- HOW TO EXPLAIN: "Almost half of all estimated end dates in the data are 31 December. That means many projects plan at year level, so schedule slip moves in big steps. That is why I talk about 'more than 12 months late' rather than exact day counts."
SELECT 'all cost reports with an end date' AS scope, COUNT(est_end_date) AS n_dates,
       SUM(substr(est_end_date, 6) = '12-31') AS n_on_31_dec,
       ROUND(100.0 * SUM(substr(est_end_date, 6) = '12-31') / COUNT(est_end_date), 1) AS pct_on_31_dec
FROM cost_report
UNION ALL
SELECT 'schedule sample: first and latest end dates', 2 * COUNT(*),
       SUM(substr(base_end, 6) = '12-31') + SUM(substr(latest_end, 6) = '12-31'),
       ROUND(100.0 * (SUM(substr(base_end, 6) = '12-31') + SUM(substr(latest_end, 6) = '12-31')) / (2 * COUNT(*)), 1)
FROM v_drift WHERE sched_ok = 1;

-- Q11: Is a first-year re-plan an early warning? Cost growth AFTER the first 12 months, by number of first-year re-plans.
-- HOW TO EXPLAIN: "A re-plan in year one already contains some cost growth, so comparing total growth would be circular. Here I take each project's estimate at the 12-month mark and measure only what happens after that. If projects that re-planned early keep growing faster afterwards, the early re-plan is a real warning sign. I repeat it inside size bands, because size could drive both."
WITH g AS (SELECT * FROM v_after_year_one)
SELECT grp AS size_band, replans_y1_group, n, pct_later_growth_over_0, pct_later_growth_over_25 FROM (
    SELECT 0 AS o, 'all sizes' AS grp, replans_y1_group, COUNT(*) AS n,
           ROUND(100.0 * SUM(later_growth_pct > 0) / COUNT(*), 1)  AS pct_later_growth_over_0,
           ROUND(100.0 * SUM(later_growth_pct > 25) / COUNT(*), 1) AS pct_later_growth_over_25
    FROM g GROUP BY replans_y1_group
    UNION ALL
    SELECT CASE size_band WHEN 'EUR 1-5m' THEN 1 WHEN 'EUR 5-20m' THEN 2 WHEN 'EUR 20-100m' THEN 3 ELSE 4 END, size_band, replans_y1_group, COUNT(*),
           ROUND(100.0 * SUM(later_growth_pct > 0) / COUNT(*), 1), ROUND(100.0 * SUM(later_growth_pct > 25) / COUNT(*), 1)
    FROM g GROUP BY size_band, replans_y1_group
) ORDER BY o, replans_y1_group;

-- Q12: At-risk totals (the numbers behind the PMO report's top risks).
-- HOW TO EXPLAIN: "All running Red projects, then the ten largest by euros added, and how many of those ten slipped five years or more."
WITH a AS (SELECT * FROM v_rag WHERE status_nl IN ('In uitvoering', 'In heroriëntatie') AND cost_ok = 1 AND rag = 'Red'),
t AS (SELECT * FROM a ORDER BY cost_growth_m DESC LIMIT 10)
SELECT (SELECT COUNT(*) FROM a)                                   AS n_running_red_in_cost_sample,
       (SELECT ROUND(SUM(cost_growth_m), 0) FROM a)               AS growth_all_running_red_m,
       (SELECT ROUND(SUM(cost_growth_m), 1) FROM t)               AS growth_top10_m,
       (SELECT SUM(ROUND(slip_days) >= 1826) FROM t)              AS top10_slipped_5y_or_more,
       (SELECT ROUND(100.0 * SUM(cost_growth_m) / (SELECT SUM(cost_growth_m) FROM v_drift WHERE cost_ok = 1), 1) FROM t) AS top10_pct_of_portfolio_growth;

-- Q13: Time coverage of the cost sample (behind the README limitations). Data end = the download date, 2026-10-20.
-- HOW TO EXPLAIN: "The first estimates go back two decades, so the euros mix price levels. Projects whose first plan is less than a year before the download can't have a full first year yet, so their first-year re-plans are undercounted. A few reports carry dates after the download - a data-entry quirk."
SELECT MIN(base_date)                                                        AS earliest_first_estimate,
       MAX(base_date)                                                        AS latest_first_estimate,
       SUM(julianday('2026-10-20') - julianday(base_date) < 365)             AS n_first_plan_under_12m_before_download,
       (SELECT COUNT(*) FROM cost_report WHERE report_date > '2026-10-20')   AS n_reports_dated_after_download
FROM v_drift WHERE cost_ok = 1;
