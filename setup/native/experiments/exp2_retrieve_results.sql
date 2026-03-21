-- Experiment 2: Retrieve results for index-based attribute search
-- Run this after executing exp2_search_via_index.sql and exp2_search_all_via_index.sql (3 times each)

-- Results for attribute-only search via index
SELECT
    'index_attr_only' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%SELECT DISTINCT trace_id%FROM span_attribute_index%WHERE attribute_key%'
    AND query NOT LIKE '%system.query_log%'
    AND query NOT LIKE '%s.service_name%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

UNION ALL

-- Results for search-all via index
SELECT
    'index_all_filters' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%FROM spans s%WHERE%s.service_name%s.trace_id IN%span_attribute_index%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

UNION ALL

-- Baseline: original arrayExists attribute search (from earlier benchmarks)
SELECT
    'baseline_attr_only' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%SELECT DISTINCT%s.trace_id%FROM spans s%WHERE%arrayExists%str_attributes%'
    AND query NOT LIKE '%s.service_name =%'
    AND query NOT LIKE '%use_skip_indexes%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

UNION ALL

-- Baseline: original arrayExists search-all (from earlier benchmarks)
SELECT
    'baseline_all_filters' AS experiment,
    count() AS runs,
    avg(query_duration_ms) AS avg_duration_ms,
    avg(read_rows) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes,
    avg(result_rows) AS avg_result_rows,
    formatReadableSize(avg(memory_usage)) AS avg_memory_usage
FROM system.query_log
WHERE query LIKE '%SELECT DISTINCT%s.trace_id%FROM spans s%WHERE%s.service_name =%AND s.name =%AND%s.duration%AND%s.start_time%AND%arrayExists%str_attributes%'
    AND query NOT LIKE '%system.query_log%'
    AND type = 'QueryFinish'
    AND query_duration_ms != 0

ORDER BY experiment;
