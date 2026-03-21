#!/bin/bash

# Attribute Search Optimization Experiments
#
# Tests whether bloom filter indexes help attribute search,
# and whether an inverted index table improves performance.
#
# Follows the same conventions as run_benchmarks.sh:
# runs from your local machine, executes queries over SSH.
#
# Usage:
#   ./run_experiments.sh [--host HOST] [--container NAME] [--database DB] [--runs N]
#
# Examples:
#   ./run_experiments.sh --host "opc@64.181.240.35" --runs 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="${SCRIPT_DIR}/experiments"
QUERIES_DIR="${SCRIPT_DIR}/queries"

HOST=""
CONTAINER="clickhouse"
DATABASE="jaeger"
RUNS=3

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)       HOST="$2"; shift 2 ;;
        --container)  CONTAINER="$2"; shift 2 ;;
        --database)   DATABASE="$2"; shift 2 ;;
        --runs)       RUNS="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# Helpers (same pattern as run_benchmarks.sh)
# ──────────────────────────────────────────────────────────────

run_query() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --password password --database=${DATABASE} --time --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>&1
    else
        eval "${cmd}" 2>&1
    fi
}

run_query_silent() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --password password --database=${DATABASE} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

run_query_format() {
    local query="$1"
    local format="$2"
    local cmd="docker exec ${CONTAINER} clickhouse-client --password password --database=${DATABASE} --format=${format} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

run_substituted_query_silent() {
    local file="$1"
    local query
    query=$(envsubst < "${file}")
    run_query_silent "${query}"
}

drop_caches() {
    run_query_silent "SYSTEM DROP MARK CACHE"
    run_query_silent "SYSTEM DROP UNCOMPRESSED CACHE"
}

print_header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

# ──────────────────────────────────────────────────────────────
# Discover sample values
# ──────────────────────────────────────────────────────────────
print_header "DISCOVERING SAMPLE VALUES"

echo "Fetching a sample service name..."
export SERVICE=$(run_query_silent "SELECT name FROM services LIMIT 1")
echo "  SERVICE:      ${SERVICE}"

echo "Fetching a sample operation name..."
export OPERATION=$(run_query_silent "SELECT name FROM operations WHERE service_name = '${SERVICE}' LIMIT 1")
echo "  OPERATION:    ${OPERATION}"

echo "Fetching time range..."
export TIME_MIN=$(run_query_silent "SELECT min(start_time) FROM spans")
export TIME_MAX=$(run_query_silent "SELECT max(start_time) FROM spans")
echo "  TIME_MIN:     ${TIME_MIN}"
echo "  TIME_MAX:     ${TIME_MAX}"

echo "Fetching duration range..."
DURATION_STATS=$(run_query_silent "SELECT min(duration), max(duration) FROM spans WHERE duration > 0")
export DURATION_MIN=$(echo "${DURATION_STATS}" | cut -f1)
export DURATION_MAX=$(echo "${DURATION_STATS}" | cut -f2)
echo "  DURATION_MIN: ${DURATION_MIN}"
echo "  DURATION_MAX: ${DURATION_MAX}"

echo "Fetching a sample attribute key-value..."
ATTR_KV=$(run_query_silent "SELECT key, value FROM (SELECT str_attributes.key AS key, str_attributes.value AS value FROM spans LIMIT 1) ARRAY JOIN key, value LIMIT 1")
export ATTR_KEY=$(echo "${ATTR_KV}" | cut -f1)
export ATTR_VAL=$(echo "${ATTR_KV}" | cut -f2)
echo "  ATTR_KEY:     ${ATTR_KEY}"
echo "  ATTR_VAL:     ${ATTR_VAL}"

echo "Fetching total span count..."
TOTAL_SPANS=$(run_query_silent "SELECT count() FROM spans")
echo "  TOTAL_SPANS:  ${TOTAL_SPANS}"

# ──────────────────────────────────────────────────────────────
# EXPERIMENT 1: Bloom Filter Effectiveness
# ──────────────────────────────────────────────────────────────
print_header "EXPERIMENT 1: BLOOM FILTER CHECK"

echo "Clearing query log..."
run_query_silent "SYSTEM FLUSH LOGS"
run_query_silent "TRUNCATE TABLE system.query_log"
sleep 1

echo "Running attribute search WITH bloom filters (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${EXPERIMENTS_DIR}/exp1_bloom_enabled.sql"
    echo "  Run ${i} complete"
done

echo "Running attribute search WITHOUT bloom filters (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${EXPERIMENTS_DIR}/exp1_bloom_disabled.sql"
    echo "  Run ${i} complete"
done

run_query_silent "SYSTEM FLUSH LOGS"
sleep 1

echo ""
echo "--- Experiment 1 Results ---"
EXP1_RESULTS=$(cat "${EXPERIMENTS_DIR}/exp1_retrieve_results.sql")
run_query_format "${EXP1_RESULTS}" "PrettyCompact"

# ──────────────────────────────────────────────────────────────
# EXPERIMENT 2: Inverted Index Table
# ──────────────────────────────────────────────────────────────
print_header "EXPERIMENT 2: INVERTED INDEX TABLE"

echo "Creating index table and materialized views..."
# Run each statement in the create file separately
while IFS='' read -r -d ';' statement; do
    statement=$(echo "${statement}" | sed '/^--/d' | tr '\n' ' ' | xargs)
    if [[ -n "${statement}" ]]; then
        run_query_silent "${statement}"
    fi
done < "${EXPERIMENTS_DIR}/exp2_create_index.sql"
echo "Done."

echo "Backfilling index from existing spans (this may take a while)..."
while IFS='' read -r -d ';' statement; do
    statement=$(echo "${statement}" | sed '/^--/d' | tr '\n' ' ' | xargs)
    if [[ -n "${statement}" ]]; then
        run_query_format "${statement}" "PrettyCompact"
    fi
done < "${EXPERIMENTS_DIR}/exp2_backfill_index.sql"
echo "Backfill complete."

echo ""
echo "Clearing query log..."
run_query_silent "SYSTEM FLUSH LOGS"
run_query_silent "TRUNCATE TABLE system.query_log"
sleep 1

echo "Running attribute-only search via INDEX (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${EXPERIMENTS_DIR}/exp2_search_via_index.sql"
    echo "  Run ${i} complete"
done

echo "Running search-all via INDEX (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${EXPERIMENTS_DIR}/exp2_search_all_via_index.sql"
    echo "  Run ${i} complete"
done

echo "Running BASELINE attribute-only search via arrayExists (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${QUERIES_DIR}/search_by_attribute.sql"
    echo "  Run ${i} complete"
done

echo "Running BASELINE search-all via arrayExists (${RUNS} runs)..."
for i in $(seq 1 "${RUNS}"); do
    drop_caches
    run_substituted_query_silent "${QUERIES_DIR}/search_by_all.sql"
    echo "  Run ${i} complete"
done

run_query_silent "SYSTEM FLUSH LOGS"
sleep 1

echo ""
echo "--- Experiment 2 Results ---"
EXP2_RESULTS=$(cat "${EXPERIMENTS_DIR}/exp2_retrieve_results.sql")
run_query_format "${EXP2_RESULTS}" "PrettyCompact"

echo ""
echo "--- Index Table Storage Overhead ---"
run_query_format "SELECT formatReadableSize(sum(bytes_on_disk)) AS size_on_disk, formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed, formatReadableSize(sum(data_compressed_bytes)) AS compressed, round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio FROM system.parts WHERE table = 'span_attribute_index' AND active" "PrettyCompact"

print_header "EXPERIMENTS COMPLETE"
echo ""
echo "The span_attribute_index table is still present."
echo "To clean up, run the exp2_cleanup.sql statements manually."
