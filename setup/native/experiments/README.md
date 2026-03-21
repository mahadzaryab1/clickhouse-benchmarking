# Attribute Search Optimization Experiments

These experiments investigate why attribute search on the `spans` table is slow (~2,451 ms)
and test different optimization strategies.

## Prerequisites

- Data already loaded into the `spans` table via the standard native schema setup
- ClickHouse client available (`clickhouse-client`)

## Experiment 1: Verify Bloom Filter Effectiveness

**Goal**: Determine whether the existing bloom filter indexes on `str_attributes.key`/`str_attributes.value` are actually being used.

**Method**: Run the same attribute search query with skip indexes enabled (default) vs disabled.

```bash
# With bloom filters (default)
clickhouse-client --queries-file experiments/exp1_bloom_enabled.sql

# Without bloom filters
clickhouse-client --queries-file experiments/exp1_bloom_disabled.sql

# Retrieve results
clickhouse-client --queries-file experiments/exp1_retrieve_results.sql
```

If both queries show similar `read_rows` and duration, the bloom filters are NOT helping.

## Experiment 2: Test Inverted Index Table

**Goal**: Test whether a materialized inverted index table dramatically improves attribute search.

```bash
# Create the index table and materialized view
clickhouse-client --queries-file experiments/exp2_create_index.sql

# Backfill existing data
clickhouse-client --queries-file experiments/exp2_backfill_index.sql

# Run search using the index
clickhouse-client --queries-file experiments/exp2_search_via_index.sql

# Retrieve results
clickhouse-client --queries-file experiments/exp2_retrieve_results.sql

# Cleanup (optional)
clickhouse-client --queries-file experiments/exp2_cleanup.sql
```

## Experiment 3: Test LowCardinality on Attribute Keys

**Goal**: Test whether `LowCardinality(String)` on attribute keys improves compression and search.

This requires recreating the table, so it should be run on a separate instance or after
backing up data.

## Comparing Results

After running experiments, compare:
- `avg_duration_ms` — query execution time
- `avg_read_rows` — how many rows ClickHouse had to scan
- `avg_read_bytes` — how much data was read
- `avg_memory_usage` — peak memory during query

Lower `read_rows` indicates better index utilization.
