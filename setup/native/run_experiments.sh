#!/bin/bash
# Attribute Search Optimization Benchmarks
# Run this script on the Oracle Cloud VM where ClickHouse is running.
#
# Usage: ./run_experiments.sh [database]
#   database: ClickHouse database name (default: jaeger)

set -euo pipefail

DB="${1:-jaeger}"
RUNS=3
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CH="clickhouse-client -d $DB"

echo "=== Attribute Search Optimization Experiments ==="
echo "Database: $DB"
echo "Runs per query: $RUNS"
echo ""

# -------------------------------------------------------
# Step 0: Discover actual values from the dataset
# -------------------------------------------------------
echo "--- Discovering values from dataset ---"

SERVICE=$($CH -q "SELECT name FROM services LIMIT 1" | head -1)
echo "Service: $SERVICE"

OPERATION=$($CH -q "SELECT name FROM operations WHERE service_name = '$SERVICE' LIMIT 1" | head -1)
echo "Operation: $OPERATION"

# Get an attribute key/value that actually exists in str_attributes
ATTR_ROW=$($CH -q "SELECT str_attributes.key[1], str_attributes.value[1] FROM spans WHERE length(str_attributes.key) > 0 LIMIT 1" --format=TSV | head -1)
ATTR_KEY=$(echo "$ATTR_ROW" | cut -f1)
ATTR_VAL=$(echo "$ATTR_ROW" | cut -f2)
echo "Attribute: $ATTR_KEY = $ATTR_VAL"

TIME_RANGE=$($CH -q "SELECT min(start_time), max(start_time) FROM spans" --format=TSV | head -1)
TIME_MIN=$(echo "$TIME_RANGE" | cut -f1)
TIME_MAX=$(echo "$TIME_RANGE" | cut -f2)
echo "Time range: $TIME_MIN .. $TIME_MAX"

DURATION_RANGE=$($CH -q "SELECT quantile(0.25)(duration), quantile(0.75)(duration) FROM spans" --format=TSV | head -1)
DURATION_MIN=$(echo "$DURATION_RANGE" | cut -f1 | cut -d. -f1)
DURATION_MAX=$(echo "$DURATION_RANGE" | cut -f2 | cut -d. -f1)
echo "Duration range: $DURATION_MIN .. $DURATION_MAX"

echo ""

# Helper: substitute variables in a SQL template
substitute() {
    sed \
        -e "s|\${ATTR_KEY}|$ATTR_KEY|g" \
        -e "s|\${ATTR_VAL}|$ATTR_VAL|g" \
        -e "s|\${SERVICE}|$SERVICE|g" \
        -e "s|\${OPERATION}|$OPERATION|g" \
        -e "s|\${DURATION_MIN}|$DURATION_MIN|g" \
        -e "s|\${DURATION_MAX}|$DURATION_MAX|g" \
        -e "s|\${TIME_MIN}|$TIME_MIN|g" \
        -e "s|\${TIME_MAX}|$TIME_MAX|g" \
        "$1"
}

# Helper: drop caches between experiments for fair comparison
drop_caches() {
    $CH -q "SYSTEM DROP MARK CACHE"
    $CH -q "SYSTEM DROP UNCOMPRESSED CACHE"
}

# -------------------------------------------------------
# Step 1: Bloom Filter Effectiveness
# -------------------------------------------------------
echo "========================================"
echo "  EXPERIMENT 1: Bloom Filter Check"
echo "========================================"
echo ""

# Clear query log
$CH -q "SYSTEM FLUSH LOGS"
$CH -q "TRUNCATE TABLE system.query_log"
sleep 1

echo "Running attribute search WITH bloom filters ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/experiments/exp1_bloom_enabled.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

echo "Running attribute search WITHOUT bloom filters ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/experiments/exp1_bloom_disabled.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

$CH -q "SYSTEM FLUSH LOGS"
sleep 1

echo ""
echo "--- Experiment 1 Results ---"
$CH < "$SCRIPT_DIR/experiments/exp1_retrieve_results.sql" --format=PrettyCompact
echo ""

# -------------------------------------------------------
# Step 2: Inverted Index Table
# -------------------------------------------------------
echo "========================================"
echo "  EXPERIMENT 2: Inverted Index Table"
echo "========================================"
echo ""

echo "Creating index table and materialized views..."
$CH < "$SCRIPT_DIR/experiments/exp2_create_index.sql"
echo "Done."

echo "Backfilling index from existing spans (this may take a while)..."
$CH < "$SCRIPT_DIR/experiments/exp2_backfill_index.sql" --format=PrettyCompact
echo "Backfill complete."
echo ""

# Clear query log
$CH -q "SYSTEM FLUSH LOGS"
$CH -q "TRUNCATE TABLE system.query_log"
sleep 1

echo "Running attribute-only search via INDEX ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/experiments/exp2_search_via_index.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

echo "Running search-all via INDEX ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/experiments/exp2_search_all_via_index.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

echo "Running BASELINE attribute-only search via arrayExists ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/queries/search_by_attribute.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

echo "Running BASELINE search-all via arrayExists ($RUNS runs)..."
for i in $(seq 1 $RUNS); do
    drop_caches
    substitute "$SCRIPT_DIR/queries/search_by_all.sql" | $CH > /dev/null
    echo "  Run $i complete"
done

$CH -q "SYSTEM FLUSH LOGS"
sleep 1

echo ""
echo "--- Experiment 2 Results ---"
$CH < "$SCRIPT_DIR/experiments/exp2_retrieve_results.sql" --format=PrettyCompact
echo ""

# -------------------------------------------------------
# Index table storage overhead
# -------------------------------------------------------
echo "--- Index Table Storage Overhead ---"
$CH -q "
SELECT
    formatReadableSize(sum(bytes_on_disk)) AS size_on_disk,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts
WHERE table = 'span_attribute_index' AND active
" --format=PrettyCompact

echo ""

# -------------------------------------------------------
# Cleanup prompt
# -------------------------------------------------------
echo "========================================"
echo "  Experiments complete!"
echo "========================================"
echo ""
echo "The span_attribute_index table is still present."
echo "To clean up, run:"
echo "  $CH < $SCRIPT_DIR/experiments/exp2_cleanup.sql"
