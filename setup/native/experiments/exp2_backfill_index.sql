-- Experiment 2: Backfill the index table from existing spans data
-- NOTE: The materialized views only capture NEW inserts.
-- This INSERT backfills all existing data into the index.

INSERT INTO span_attribute_index
SELECT
    tp.1 AS attribute_key,
    tp.2 AS attribute_value,
    trace_id,
    start_time
FROM (
    SELECT
        arrayJoin(arrayConcat(
            arrayZip(str_attributes.key, str_attributes.value),
            arrayZip(resource_str_attributes.key, resource_str_attributes.value),
            arrayZip(scope_str_attributes.key, scope_str_attributes.value),
            arrayZip(int_attributes.key, arrayMap(v -> toString(v), int_attributes.value)),
            arrayZip(resource_int_attributes.key, arrayMap(v -> toString(v), resource_int_attributes.value)),
            arrayZip(scope_int_attributes.key, arrayMap(v -> toString(v), scope_int_attributes.value)),
            arrayZip(double_attributes.key, arrayMap(v -> toString(v), double_attributes.value)),
            arrayZip(resource_double_attributes.key, arrayMap(v -> toString(v), resource_double_attributes.value)),
            arrayZip(scope_double_attributes.key, arrayMap(v -> toString(v), scope_double_attributes.value)),
            arrayZip(bool_attributes.key, arrayMap(v -> toString(v), bool_attributes.value)),
            arrayZip(resource_bool_attributes.key, arrayMap(v -> toString(v), resource_bool_attributes.value)),
            arrayZip(scope_bool_attributes.key, arrayMap(v -> toString(v), scope_bool_attributes.value)),
            arrayZip(complex_attributes.key, complex_attributes.value),
            arrayZip(resource_complex_attributes.key, resource_complex_attributes.value),
            arrayZip(scope_complex_attributes.key, scope_complex_attributes.value)
        )) AS tp,
        trace_id,
        start_time
    FROM spans
);

-- Verify the backfill
SELECT
    count() AS total_rows,
    uniq(attribute_key) AS distinct_keys,
    uniq(trace_id) AS distinct_traces
FROM span_attribute_index;

-- Check index table compression
SELECT
    formatReadableSize(sum(bytes_on_disk)) AS total_size_on_disk,
    formatReadableSize(sum(data_uncompressed_bytes)) AS total_data_uncompressed_size,
    formatReadableSize(sum(data_compressed_bytes)) AS total_data_compressed_size,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 3) AS compression_ratio
FROM system.parts
WHERE table = 'span_attribute_index' AND active;
