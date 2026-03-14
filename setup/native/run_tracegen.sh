#!/bin/bash

# Populate ClickHouse with trace data, optionally across multiple days.
#
# For multi-day data, the script sets the system clock back on the remote host
# before each batch of tracegen, then restores it via chrony (NTP) at the end.
# This causes ClickHouse to write spans with timestamps in the past, creating
# data across multiple date partitions.
#
# Prerequisites:
#   - Jaeger must be running with the ClickHouse backend
#   - ClickHouse must be running
#   - Run cleanup.sql first for a clean measurement
#   - For multi-day mode: chronyd must be available on the host
#
# Usage:
#   ./run_tracegen.sh [--host HOST] [--container NAME] [--database DB]
#                     [--traces N] [--days D]
#
# Examples:
#   # 100K traces (1M spans), single day
#   ./run_tracegen.sh --host "opc@64.181.240.35" --traces 100000
#
#   # 1M traces (10M spans) spread across 5 days
#   ./run_tracegen.sh --host "opc@64.181.240.35" --traces 1000000 --days 5

set -euo pipefail

HOST=""
CONTAINER="clickhouse"
DATABASE="jaeger"
TRACES=100000
DAYS=1

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)       HOST="$2"; shift 2 ;;
        --container)  CONTAINER="$2"; shift 2 ;;
        --database)   DATABASE="$2"; shift 2 ;;
        --traces)     TRACES="$2"; shift 2 ;;
        --days)       DAYS="$2"; shift 2 ;;
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
    local cmd="docker exec ${CONTAINER} clickhouse-client --password password --database=${DATABASE} --query=\"${query}\""
    if [[ -n "${HOST}" ]]; then
        ssh "${HOST}" "${cmd}" 2>/dev/null
    else
        eval "${cmd}" 2>/dev/null
    fi
}

set_date() {
    local target_date="$1"
    echo "  Setting system date to: ${target_date}"
    run_remote "sudo timedatectl set-ntp false"
    run_remote "sudo date -s '${target_date}'"
}

restore_time() {
    echo ""
    echo "Restoring system time via NTP..."
    run_remote "sudo timedatectl set-ntp true"
    # Give chrony a moment to sync
    sleep 3
    local current=$(run_remote "date")
    echo "System time restored: ${current}"
}

# Ensure time is restored even if the script fails
trap restore_time EXIT

TRACES_PER_DAY=$(( TRACES / DAYS ))
REMAINDER=$(( TRACES % DAYS ))
TOTAL_SPANS=$(( TRACES * 10 ))

echo "============================================================"
echo "  TRACEGEN DATA POPULATION"
echo "============================================================"
echo ""
echo "  Total traces:     ${TRACES}"
echo "  Spans per trace:  10 (1 parent + 9 children)"
echo "  Total spans:      ${TOTAL_SPANS}"
echo "  Days:             ${DAYS}"
echo "  Traces per day:   ${TRACES_PER_DAY}"
echo ""

BEFORE=$(run_ch_query "SELECT count() FROM spans")
echo "Spans before: ${BEFORE}"
echo ""

OVERALL_START=$(date +%s)

for (( d = DAYS - 1; d >= 0; d-- )); do
    # Calculate traces for this batch (last batch gets remainder)
    BATCH_TRACES=${TRACES_PER_DAY}
    if [[ ${d} -eq 0 ]]; then
        BATCH_TRACES=$(( TRACES_PER_DAY + REMAINDER ))
    fi

    echo "------------------------------------------------------------"
    echo "  Day offset: -${d} days | Traces: ${BATCH_TRACES}"
    echo "------------------------------------------------------------"

    if [[ ${d} -gt 0 ]]; then
        # Set system clock back by d days
        TARGET_DATE=$(date -d "-${d} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                      date -v-${d}d '+%Y-%m-%d %H:%M:%S')
        set_date "${TARGET_DATE}"
    else
        # For the current day, restore real time first
        run_remote "sudo timedatectl set-ntp true"
        sleep 3
        echo "  Using current system time"
    fi

    BATCH_START=$(date +%s)

    run_remote "docker run --rm --network host jaegertracing/jaeger-tracegen \
      -traces ${BATCH_TRACES} \
      -spans 9 \
      -services 2 \
      -trace-exporter otlp-grpc"

    BATCH_END=$(date +%s)
    BATCH_ELAPSED=$(( BATCH_END - BATCH_START ))
    echo "  Batch completed in ${BATCH_ELAPSED}s"
    echo ""
done

# Wait for buffered inserts to flush
echo "Waiting 10s for buffered inserts to flush..."
sleep 10

OVERALL_END=$(date +%s)
OVERALL_ELAPSED=$(( OVERALL_END - OVERALL_START ))

AFTER=$(run_ch_query "SELECT count() FROM spans")
INSERTED=$(( AFTER - BEFORE ))

echo ""
echo "============================================================"
echo "  RESULTS"
echo "============================================================"
echo "  Spans inserted: ${INSERTED}"
echo "  Total time:     ${OVERALL_ELAPSED}s"
echo "  Target total:   ${TOTAL_SPANS}"
echo "============================================================"
echo ""

# Show partition breakdown
echo "Partition breakdown:"
run_ch_query "SELECT partition, sum(rows) AS rows, formatReadableSize(sum(data_compressed_bytes)) AS compressed FROM system.parts WHERE database='${DATABASE}' AND table='spans' AND active GROUP BY partition ORDER BY partition"
