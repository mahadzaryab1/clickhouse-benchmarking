#!/bin/bash

# Execute benchmark queries against the native ClickHouse schema.
# Each query is defined in a separate .sql file under queries/.
# Variables like ${SERVICE}, ${TRACE_ID}, etc. are auto-discovered
# from the data and substituted at runtime via envsubst.
#
# Results are logged in system.query_log and can be retrieved
# using ./run_all.sh.
#
# Usage:
#   ./run_benchmarks.sh [--host HOST] [--container NAME] [--database DB] [--runs N]
#
# Examples:
#   ./run_benchmarks.sh                                      # local defaults
#   ./run_benchmarks.sh --host "opc@64.181.240.35" --runs 3  # remote, 3 iterations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

run_query() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --database=${DATABASE} --time --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>&1
    else
        eval "${cmd}" 2>&1
    fi
}

run_query_silent() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --database=${DATABASE} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

print_header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

# ──────────────────────────────────────────────────────────────
# Auto-discover sample values from the data
# ──────────────────────────────────────────────────────────────
print_header "DISCOVERING SAMPLE VALUES"

echo "Fetching a sample trace ID..."
export TRACE_ID=$(run_query_silent "SELECT trace_id FROM spans LIMIT 1")
echo "  TRACE_ID:     ${TRACE_ID}"

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
# Execute each query file
# ──────────────────────────────────────────────────────────────
run_query_file() {
    local file="$1"
    local name
    name=$(basename "${file}" .sql)

    # Read the SQL template and substitute variables
    local query
    query=$(envsubst < "${file}")

    echo ""
    echo "--- ${name} ---"
    run_query "${query}"
}

for i in $(seq 1 "${RUNS}"); do
    print_header "RUN ${i} of ${RUNS}"

    for query_file in "${QUERIES_DIR}"/*.sql; do
        run_query_file "${query_file}"
    done
done

print_header "BENCHMARKS COMPLETE"
echo ""
echo "Results are logged in system.query_log."
echo "Run ./run_all.sh to retrieve and format the results."
