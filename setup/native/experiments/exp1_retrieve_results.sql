-- Experiment 1: Retrieve results comparing bloom filter enabled vs disabled
-- Run this after executing both exp1_bloom_enabled.sql and exp1_bloom_disabled.sql (3 times each)

SELECT
    'bloom_enabled' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%SELECT DISTINCT%s.trace_id%FROM spans s%WHERE%arrayExists%str_attributes%'
    AND query NOT LIKE '%use_skip_indexes=0%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

UNION ALL

SELECT
    'bloom_disabled' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%SELECT DISTINCT%s.trace_id%FROM spans s%WHERE%arrayExists%str_attributes%use_skip_indexes=0%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

ORDER BY experiment;
