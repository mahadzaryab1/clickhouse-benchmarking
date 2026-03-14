SELECT
    l.trace_id,
    t.start,
    t.end
FROM (
    SELECT DISTINCT
        s.trace_id
    FROM spans s
    WHERE 1=1
        AND s.start_time >= '${TIME_MIN}'
        AND s.start_time <= '${TIME_MAX}'
    LIMIT 1000
) l
LEFT JOIN trace_id_timestamps t ON l.trace_id = t.trace_id
