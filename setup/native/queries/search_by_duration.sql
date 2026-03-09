SELECT
    l.trace_id,
    t.start,
    t.end
FROM (
    SELECT DISTINCT
        s.trace_id
    FROM spans s
    WHERE 1=1
        AND s.duration >= ${DURATION_MIN}
        AND s.duration <= ${DURATION_MAX}
    LIMIT 20
) l
LEFT JOIN trace_id_timestamps t ON l.trace_id = t.trace_id
