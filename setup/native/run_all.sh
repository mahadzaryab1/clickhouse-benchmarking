#!/bin/bash

# Run all native schema benchmark retrieval scripts against ClickHouse
# and report results in a formatted table.
#
# Usage:
#   ./run_all.sh [--host HOST] [--database DB] [--container NAME]
#
# Examples:
#   ./run_all.sh                                    # defaults: container=clickhouse, database=jaeger
#   ./run_all.sh --host 64.181.240.35               # run over SSH
#   ./run_all.sh --container my-clickhouse --database default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../../performance-retrieval-scripts/native-schema"

HOST=""
CONTAINER="clickhouse"
DATABASE="jaeger"

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)       HOST="$2"; shift 2 ;;
        --container)  CONTAINER="$2"; shift 2 ;;
        --database)   DATABASE="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

run_query() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --database=${DATABASE} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

run_query_with_time() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --database=${DATABASE} --time --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>&1
    else
        eval "${cmd}" 2>&1
    fi
}

print_header() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

print_subheader() {
    echo ""
    echo "--- $1 ---"
}

# ──────────────────────────────────────────────────────────────
# 1. Compression Stats
# ──────────────────────────────────────────────────────────────
print_header "COMPRESSION STATS"

print_subheader "Spans Table - Overall"
query=$(cat "${SCRIPTS_DIR}/table_compression_spans")
run_query "${query}" | column -t -s $'\t'

print_subheader "Spans Table - Per Column"
query=$(cat "${SCRIPTS_DIR}/columns_compression_spans")
run_query "${query}" | column -t -s $'\t'

print_subheader "Trace ID Timestamps Table - Overall"
query=$(cat "${SCRIPTS_DIR}/table_compression_trace_id_timestamps")
run_query "${query}" | column -t -s $'\t'

print_subheader "Trace ID Timestamps Table - Per Column"
query=$(cat "${SCRIPTS_DIR}/columns_compression_trace_id_timestamps")
run_query "${query}" | column -t -s $'\t'

# ──────────────────────────────────────────────────────────────
# 2. Insert Performance
# ──────────────────────────────────────────────────────────────
print_header "INSERT PERFORMANCE"

query=$(cat "${SCRIPTS_DIR}/schema_insert")
run_query "${query}" | column -t -s $'\t'

# ──────────────────────────────────────────────────────────────
# 3. Retrieval Performance
# ──────────────────────────────────────────────────────────────
print_header "RETRIEVAL PERFORMANCE"

print_subheader "Retrieve Services"
query=$(cat "${SCRIPTS_DIR}/retrieve_services")
run_query "${query}" | column -t -s $'\t'

print_subheader "Retrieve Operations"
query=$(cat "${SCRIPTS_DIR}/retrieve_operations")
run_query "${query}" | column -t -s $'\t'

print_subheader "Retrieve Spans by Trace ID"
query=$(cat "${SCRIPTS_DIR}/retrieve_spans_by_trace_id")
run_query "${query}" | column -t -s $'\t'

# ──────────────────────────────────────────────────────────────
# 4. Search Performance
# ──────────────────────────────────────────────────────────────
print_header "SEARCH PERFORMANCE"

print_subheader "Search by Service"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_service")
run_query "${query}" | column -t -s $'\t'

print_subheader "Search by Operation"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_operation")
run_query "${query}" | column -t -s $'\t'

print_subheader "Search by Duration"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_duration")
run_query "${query}" | column -t -s $'\t'

print_subheader "Search by Timestamp"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_timestamp")
run_query "${query}" | column -t -s $'\t'

print_subheader "Search by Tag"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_tag")
run_query "${query}" | column -t -s $'\t'

print_subheader "Search by All Filters"
query=$(cat "${SCRIPTS_DIR}/search_spans_by_all")
run_query "${query}" | column -t -s $'\t'

echo ""
echo "============================================================"
echo "  DONE"
echo "============================================================"
