SELECT
    l.trace_id,
    min(t.start) AS start,
    max(t.end) AS end
FROM (
    SELECT DISTINCT
        s.trace_id
    FROM spans s
    WHERE 1=1
        AND (
            arrayExists((key, value) -> key = '${ATTR_KEY}' AND value = '${ATTR_VAL}', s.str_attributes.key, s.str_attributes.value)
            OR arrayExists((key, value) -> key = '${ATTR_KEY}' AND value = '${ATTR_VAL}', s.resource_str_attributes.key, s.resource_str_attributes.value)
            OR arrayExists((key, value) -> key = '${ATTR_KEY}' AND value = '${ATTR_VAL}', s.scope_str_attributes.key, s.scope_str_attributes.value)
            OR arrayExists(x -> arrayExists((key, value) -> key = '${ATTR_KEY}' AND value = '${ATTR_VAL}', x.str_attributes.key, x.str_attributes.value), s.events)
            OR arrayExists(x -> arrayExists((key, value) -> key = '${ATTR_KEY}' AND value = '${ATTR_VAL}', x.str_attributes.key, x.str_attributes.value), s.links)
        )
    LIMIT 1000
) l
LEFT JOIN trace_id_timestamps t ON l.trace_id = t.trace_id
GROUP BY l.trace_id
