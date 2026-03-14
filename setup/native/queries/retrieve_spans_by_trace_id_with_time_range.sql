SELECT * FROM spans s WHERE s.trace_id = '${TRACE_ID}' AND s.start_time >= '${TRACE_TIME_MIN}' AND s.start_time <= '${TRACE_TIME_MAX}'
