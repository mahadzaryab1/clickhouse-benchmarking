TRUNCATE TABLE spans;
TRUNCATE TABLE services;
TRUNCATE TABLE operations;
TRUNCATE TABLE trace_id_timestamps;
TRUNCATE TABLE attribute_metadata;

-- Clear the query log so retrieval scripts only report results from the current run.
SYSTEM FLUSH LOGS;
TRUNCATE TABLE system.query_log;
