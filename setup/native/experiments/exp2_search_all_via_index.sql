-- Experiment 2: Search by ALL filters using the inverted index table
-- Run this 3 times to get averaged results
-- Uses the index for attribute filtering, then joins back to spans for other filters

SELECT
    l.trace_id,
    min(t.start) AS start,
    max(t.end) AS end
FROM (
    SELECT DISTINCT
        s.trace_id
    FROM spans s
    WHERE 1=1
        AND s.service_name = '${SERVICE}'
        AND s.name = '${OPERATION}'
        AND s.duration >= ${DURATION_MIN}
        AND s.duration <= ${DURATION_MAX}
        AND s.start_time >= '${TIME_MIN}'
        AND s.start_time <= '${TIME_MAX}'
        AND s.trace_id IN (
            SELECT trace_id
            FROM span_attribute_index
            WHERE attribute_key = '${ATTR_KEY}'
                AND attribute_value = '${ATTR_VAL}'
        )
    LIMIT 1000
) l
LEFT JOIN trace_id_timestamps t ON l.trace_id = t.trace_id
GROUP BY l.trace_id;
