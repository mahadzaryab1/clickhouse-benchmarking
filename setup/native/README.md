# Native Schema Setup

## Hardware

Oracle Cloud VM.Standard2.4 (4 OCPUs Intel Xeon Platinum 8167M, 60 GB RAM)

## Benchmark Workflow

### 0. Setup

SSH onto the remote machine and start ClickHouse and Jaeger:

```bash
ssh opc@64.181.240.35

# Start ClickHouse
docker run -d -p 8123:8123 -p 9000:9000 --name clickhouse \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=password \
  clickhouse/clickhouse-server

# Create the jaeger database
docker exec clickhouse clickhouse-client --password password \
  --query="CREATE DATABASE IF NOT EXISTS jaeger"

# Build and run Jaeger (schema tables are created automatically on startup)
cd jaeger/
go build -o ./jaeger ./cmd/jaeger/
./jaeger --config cmd/jaeger/config-clickhouse.yaml
```

Leave Jaeger running in this session. The remaining steps run from your local machine.

### 1. Populate Data

Use `run_tracegen.sh` to generate trace data. Each trace has 10 spans (1 parent + 9 children), each child span has 11 attributes with 97 distinct keys and 1000 distinct values.

| Dataset | Traces | Spans |
| --- | --- | --- |
| 1M | 100,000 | 1,000,000 |
| 10M | 1,000,000 | 10,000,000 |
| 100M | 10,000,000 | 100,000,000 |
| 1B | 100,000,000 | 1,000,000,000 |

```bash
# 100K traces (1M spans), single day
./run_tracegen.sh --host "opc@64.181.240.35" --traces 100000

# 1M traces (10M spans) spread across 5 days
./run_tracegen.sh --host "opc@64.181.240.35" --traces 1000000 --days 5
```

For multi-day mode (`--days > 1`), the script temporarily sets the system clock back on the remote host before each batch of tracegen, so ClickHouse writes spans with past timestamps into separate date partitions. Time is restored via NTP (chrony) after the run completes (or on failure via a trap).

**Parameters:**

- `--traces N` — total number of traces to generate (default: 100000). Each trace = 10 spans.
- `--days D` — number of days to spread data across (default: 1). Traces are split evenly across days.

### 2. Run Benchmarks

Use `run_benchmarks.sh` to execute the benchmark queries. It auto-discovers sample values (trace ID, service name, operation, time range, duration range, attribute key/value) from the data and substitutes them into the `.sql` query templates using `envsubst`. Each query is run N times (default: 3) and results are logged in ClickHouse's `system.query_log`.

```bash
./run_benchmarks.sh --host "opc@64.181.240.35" --runs 3
```

### 3. Retrieve Results

Use `run_all.sh` to query `system.query_log` and produce a formatted report of all benchmark results, including compression stats, insert performance, retrieval times, and search times:

```bash
./run_all.sh --host "opc@64.181.240.35"
```

### 4. Clean Up

Run `cleanup.sql` to truncate all data tables and clear the query log before the next benchmark run:

```bash
docker exec clickhouse clickhouse-client --database=jaeger --multiquery < cleanup.sql
```
