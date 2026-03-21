-- Experiment 2: Create inverted index table and materialized views
-- This table denormalizes attribute key-value pairs for fast lookups

CREATE TABLE IF NOT EXISTS span_attribute_index (
    attribute_key String,
    attribute_value String,
    trace_id String,
    start_time DateTime64(9)
) ENGINE = MergeTree
PARTITION BY toDate(start_time)
ORDER BY (attribute_key, attribute_value, trace_id);

-- Materialized view: index span, resource, and scope level attributes
CREATE MATERIALIZED VIEW IF NOT EXISTS span_attribute_index_mv TO span_attribute_index AS
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

-- Materialized view: index event-level attributes
CREATE MATERIALIZED VIEW IF NOT EXISTS event_attribute_index_mv TO span_attribute_index AS
SELECT
    tp.1 AS attribute_key,
    tp.2 AS attribute_value,
    trace_id,
    start_time
FROM spans
ARRAY JOIN events AS e
ARRAY JOIN arrayConcat(
    arrayZip(e.str_attributes.key, e.str_attributes.value),
    arrayZip(e.int_attributes.key, arrayMap(v -> toString(v), e.int_attributes.value)),
    arrayZip(e.double_attributes.key, arrayMap(v -> toString(v), e.double_attributes.value)),
    arrayZip(e.bool_attributes.key, arrayMap(v -> toString(v), e.bool_attributes.value)),
    arrayZip(e.complex_attributes.key, e.complex_attributes.value)
) AS tp;

-- Materialized view: index link-level attributes
CREATE MATERIALIZED VIEW IF NOT EXISTS link_attribute_index_mv TO span_attribute_index AS
SELECT
    tp.1 AS attribute_key,
    tp.2 AS attribute_value,
    trace_id,
    start_time
FROM spans
ARRAY JOIN links AS l
ARRAY JOIN arrayConcat(
    arrayZip(l.str_attributes.key, l.str_attributes.value),
    arrayZip(l.int_attributes.key, arrayMap(v -> toString(v), l.int_attributes.value)),
    arrayZip(l.double_attributes.key, arrayMap(v -> toString(v), l.double_attributes.value)),
    arrayZip(l.bool_attributes.key, arrayMap(v -> toString(v), l.bool_attributes.value)),
    arrayZip(l.complex_attributes.key, l.complex_attributes.value)
) AS tp;
