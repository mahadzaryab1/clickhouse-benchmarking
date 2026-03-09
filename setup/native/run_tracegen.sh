#!/bin/bash

# Measure insert throughput by running tracegen for a fixed duration,
# then counting the number of spans inserted.
#
# Prerequisites:
#   - Jaeger must be running with the ClickHouse backend
#   - ClickHouse must be running
#   - Run cleanup.sql first for a clean measurement
#
# Usage:
#   ./run_tracegen.sh [--host HOST] [--container NAME] [--database DB] [--duration SECS]
#
# Examples:
#   ./run_tracegen.sh --duration 300                              # local, 5 minutes
#   ./run_tracegen.sh --host "opc@64.181.240.35" --duration 300   # remote, 5 minutes

set -euo pipefail

HOST=""
CONTAINER="clickhouse"
DATABASE="jaeger"
DURATION=300

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)       HOST="$2"; shift 2 ;;
        --container)  CONTAINER="$2"; shift 2 ;;
        --database)   DATABASE="$2"; shift 2 ;;
        --duration)   DURATION="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

run_remote() {
    local cmd="$1"
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>&1
    else
        eval "${cmd}" 2>&1
    fi
}

run_ch_query() {
    local query="$1"
    local cmd="docker exec ${CONTAINER} clickhouse-client --database=${DATABASE} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

echo "============================================================"
echo "  INSERT THROUGHPUT BENCHMARK"
echo "============================================================"
echo ""
echo "Duration: ${DURATION}s"
echo ""

# Get span count before
BEFORE=$(run_ch_query "SELECT count() FROM spans")
echo "Spans before: ${BEFORE}"

# Run tracegen for the specified duration
echo ""
echo "Starting tracegen for ${DURATION}s..."
START_TIME=$(date +%s)

run_remote "timeout ${DURATION} docker run --rm --network host jaegertracing/jaeger-tracegen \
  -traces 0 \
  -spans 10 \
  -services 2 \
  -trace-exporter otlp-grpc \
  -duration ${DURATION}s || true"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "Tracegen finished after ${ELAPSED}s"
echo ""

# Wait a few seconds for any buffered inserts to flush
echo "Waiting 10s for buffered inserts to flush..."
sleep 10

# Get span count after
AFTER=$(run_ch_query "SELECT count() FROM spans")
echo "Spans after:  ${AFTER}"

# Calculate throughput
INSERTED=$((AFTER - BEFORE))
if [[ ${DURATION} -gt 0 ]]; then
    THROUGHPUT=$((INSERTED / DURATION))
else
    THROUGHPUT=0
fi

echo ""
echo "============================================================"
echo "  RESULTS"
echo "============================================================"
echo "  Spans inserted: ${INSERTED}"
echo "  Duration:       ${DURATION}s"
echo "  Throughput:     ${THROUGHPUT} spans/sec"
echo "============================================================"
