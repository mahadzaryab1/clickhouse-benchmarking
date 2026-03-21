-- Experiment 2: Cleanup - drop the index table and materialized views
DROP VIEW IF EXISTS link_attribute_index_mv;
DROP VIEW IF EXISTS event_attribute_index_mv;
DROP VIEW IF EXISTS span_attribute_index_mv;
DROP TABLE IF EXISTS span_attribute_index;
