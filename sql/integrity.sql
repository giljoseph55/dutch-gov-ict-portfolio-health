-- Integrity checks. Each row: check name, number of violations. HARD checks must all be 0.
-- (load.py runs this file and stops if any hard check is not 0.)
SELECT 'hard: sqlite integrity_check = ok' AS check_name, (SELECT COUNT(*) FROM pragma_integrity_check WHERE integrity_check <> 'ok') AS violations
UNION ALL SELECT 'hard: foreign key violations', (SELECT COUNT(*) FROM pragma_foreign_key_check)
UNION ALL SELECT 'hard: project without any cost report', COUNT(*) FROM project p WHERE NOT EXISTS (SELECT 1 FROM cost_report r WHERE r.project_id = p.project_id)
UNION ALL SELECT 'hard: negative cost total, or component below -0.05m', COUNT(*) FROM cost_report WHERE MIN(est_total_m, act_total_m) < 0 OR MIN(est_internal_m, est_external_m, est_other_m, act_internal_m, act_external_m, act_other_m) < -0.05
UNION ALL SELECT 'hard: estimate total <> sum of its parts (tolerance 0.06m)', COUNT(*) FROM cost_report WHERE ABS(est_total_m - (est_internal_m + est_external_m + est_other_m)) > 0.06
UNION ALL SELECT 'hard: actual total <> sum of its parts (tolerance 0.06m)', COUNT(*) FROM cost_report WHERE ABS(act_total_m - (act_internal_m + act_external_m + act_other_m)) > 0.06
UNION ALL SELECT 'hard: invalid ISO date (start, as-of, report, est. end)',
       (SELECT COUNT(*) FROM project WHERE date(start_date) IS NOT start_date OR date(as_of_date) IS NOT as_of_date)
     + (SELECT COUNT(*) FROM cost_report WHERE date(report_date) IS NOT report_date OR (est_end_date IS NOT NULL AND date(est_end_date) IS NOT est_end_date))
UNION ALL SELECT 'hard: seq not contiguous 1..n per project', COUNT(*) FROM (SELECT project_id FROM cost_report GROUP BY project_id HAVING MIN(seq) <> 1 OR MAX(seq) <> COUNT(*))
UNION ALL SELECT 'hard: report_date goes backwards with seq', COUNT(*) FROM cost_report a JOIN cost_report b ON a.project_id = b.project_id AND b.seq = a.seq + 1 WHERE b.report_date < a.report_date
UNION ALL SELECT 'hard: replan_reason on a non-Herijking report', COUNT(*) FROM replan_reason x JOIN cost_report r USING (report_id) WHERE r.action_nl <> 'Herijking'
-- Informational (known source-data quirks; documented, not errors in the load):
UNION ALL SELECT 'info: reports with a component between -0.05m and 0 (rounding artefact, e.g. Praeventis 2024-06-25)', COUNT(*) FROM cost_report WHERE MIN(est_internal_m, est_external_m, est_other_m, act_internal_m, act_external_m, act_other_m) < 0 AND MIN(est_internal_m, est_external_m, est_other_m, act_internal_m, act_external_m, act_other_m) >= -0.05
UNION ALL SELECT 'info: projects with no Initieel report', COUNT(*) FROM project p WHERE NOT EXISTS (SELECT 1 FROM cost_report r WHERE r.project_id = p.project_id AND r.action_nl = 'Initieel')
UNION ALL SELECT 'info: projects whose first Initieel report is not their first report (baseline comes later)', COUNT(*) FROM v_baseline WHERE base_seq > 1
UNION ALL SELECT 'info: projects with more than one Initieel report', COUNT(*) FROM (SELECT project_id FROM cost_report WHERE action_nl = 'Initieel' GROUP BY project_id HAVING COUNT(*) > 1)
UNION ALL SELECT 'info: reports with est_total_m = 0', COUNT(*) FROM cost_report WHERE est_total_m = 0
UNION ALL SELECT 'info: reports with missing est_end_date', COUNT(*) FROM cost_report WHERE est_end_date IS NULL
UNION ALL SELECT 'info: first report dated before project start_date', COUNT(*) FROM project p JOIN cost_report r ON r.project_id = p.project_id AND r.seq = 1 WHERE r.report_date < p.start_date
UNION ALL SELECT 'info: reports dated after the download date (2026-10-20)', COUNT(*) FROM cost_report WHERE report_date > '2026-10-20'
UNION ALL SELECT 'info: duplicate project names', COUNT(*) FROM (SELECT name FROM project GROUP BY name HAVING COUNT(*) > 1);
