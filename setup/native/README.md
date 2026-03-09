# Native Schema Setup

## Hardware

Oracle Cloud VM.Standard2.4 (4 OCPUs Intel Xeon Platinum 8167M, 60 GB RAM)

## ClickHouse

Docker command:
```
docker run -d -p 8123:8123 -p 9000:9000 --name clickhouse \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=password \
  clickhouse/clickhouse-server
```

Create the `jaeger` database:
```
docker exec clickhouse clickhouse-client --password password --query="CREATE DATABASE IF NOT EXISTS jaeger"
```

The schema tables are automatically created by Jaeger on startup. See `schema/native/` for the DDL.

## Jaeger

Build and run with the ClickHouse config:
```
cd jaeger/
go build -o ./jaeger ./cmd/jaeger/
./jaeger --config cmd/jaeger/config-clickhouse.yaml
```

The `config-clickhouse.yaml` configures the ClickHouse storage backend with the native schema.

## Tracegen

Generate load using Jaeger's built-in tracegen:
```
docker run --network host jaegertracing/jaeger-tracegen \
  -traces 1500000 \
  -spans 10 \
  -services 2 \
  -trace-exporter otlp-grpc
```

Each trace has 11 spans (1 parent + 10 children), each child span has 11 attributes with 97 distinct keys and 1000 distinct values.

## Measuring Insert Throughput

To measure insert throughput, run tracegen for a fixed duration (e.g., 5 minutes) and then count the inserted spans:
```
./run_tracegen.sh --host "opc@64.181.240.35" --duration 300
```

This runs tracegen for the specified duration, waits for it to finish, then queries the span count and reports the throughput (spans/sec).
