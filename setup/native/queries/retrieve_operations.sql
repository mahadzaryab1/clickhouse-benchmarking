SELECT
    name,
    span_kind
FROM
    operations
WHERE
    service_name = '${SERVICE}'
GROUP BY name, span_kind
