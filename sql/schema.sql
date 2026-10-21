-- Schema for the Rijks ICT-dashboard open dataset (large Dutch central-government ICT projects).
-- One row per project, one row per cost report entry. Costs are EUR millions (see README, "Assumptions").
-- Dutch source terms are kept in *_nl columns; English labels live in the *_ref lookup tables.
PRAGMA foreign_keys = ON;

CREATE TABLE ministry (
    ministry_id INTEGER PRIMARY KEY,
    name_nl     TEXT NOT NULL UNIQUE
);

-- Reference tables: Dutch value -> English label (every value in the data must exist here; load.py fails otherwise)
CREATE TABLE status_ref (status_nl TEXT PRIMARY KEY, status_en TEXT NOT NULL);
CREATE TABLE action_ref (action_nl TEXT PRIMARY KEY, action_en TEXT NOT NULL);
CREATE TABLE reason_ref (reason_nl TEXT PRIMARY KEY, reason_en TEXT NOT NULL);

CREATE TABLE project (
    project_id             INTEGER PRIMARY KEY,   -- 1-based position in the source file (names are not unique: AERIUS appears twice)
    name                   TEXT    NOT NULL,
    ministry_id            INTEGER NOT NULL REFERENCES ministry(ministry_id),
    status_nl              TEXT    NOT NULL REFERENCES status_ref(status_nl),
    as_of_date             TEXT    NOT NULL,      -- "Peildatum": date the status was last reported
    start_date             TEXT    NOT NULL,      -- "Startdatum"
    development_method_raw TEXT,                  -- "Ontwikkelwijze", free text in places
    method_class           TEXT    NOT NULL CHECK (method_class IN
                           ('Agile/DevOps','Waterfall','Mixed','Standard product','Unknown / n.a.')),
    custom_built           TEXT    CHECK (custom_built IN ('Ja','Nee')),   -- "Maatwerk"; NULL when blank
    ict_activity_nl        TEXT                                             -- "Soort ICT-activiteit"; NULL when blank
);

CREATE TABLE cost_report (
    report_id         INTEGER PRIMARY KEY,
    project_id        INTEGER NOT NULL REFERENCES project(project_id),
    seq               INTEGER NOT NULL,           -- order within project: by report date, ties by file position
    report_date       TEXT    NOT NULL,           -- "Datum"
    action_nl         TEXT    NOT NULL REFERENCES action_ref(action_nl),   -- Initieel / Rapportage / Herijking
    est_total_m       REAL    NOT NULL,           -- "Actueel totaal projectkosten (correct)": current estimate of total cost
    est_internal_m    REAL    NOT NULL,
    est_external_m    REAL    NOT NULL,
    est_other_m       REAL    NOT NULL,
    act_total_m       REAL    NOT NULL,           -- "Daadwerkelijk totale projectenkosten (correct)": spent to date
    act_internal_m    REAL    NOT NULL,
    act_external_m    REAL    NOT NULL,
    act_other_m       REAL    NOT NULL,
    est_end_date      TEXT,                       -- "Actueel geschatte einddatum": current estimated end date
    replan_reason_raw TEXT,                       -- "Reden herijking", comma/semicolon separated
    UNIQUE (project_id, seq)
);
CREATE INDEX ix_cost_report_project ON cost_report(project_id, seq);

CREATE TABLE replan_reason (
    report_id INTEGER NOT NULL REFERENCES cost_report(report_id),
    reason_nl TEXT    NOT NULL REFERENCES reason_ref(reason_nl),
    PRIMARY KEY (report_id, reason_nl)
);
