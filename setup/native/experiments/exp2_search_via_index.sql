-- Experiment 2: Search by attribute using the inverted index table
-- Run this 3 times to get averaged results

SELECT
    l.trace_id,
    min(t.start) AS start,
    max(t.end) AS end
FROM (
    SELECT DISTINCT trace_id
    FROM span_attribute_index
    WHERE attribute_key = '${ATTR_KEY}'
        AND attribute_value = '${ATTR_VAL}'
    LIMIT 1000
) l
LEFT JOIN trace_id_timestamps t ON l.trace_id = t.trace_id
GROUP BY l.trace_id;
