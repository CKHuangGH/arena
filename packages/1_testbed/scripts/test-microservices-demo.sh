#!/bin/bash
set -euo pipefail

# -------- Preflight --------
for bin in kubectl curl jq awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing dependency: $bin" >&2; exit 1; }
done

# -------- Config --------
LOAD_LEVELS=("low" "mid" "high")
USERS=(3 6 12)
RATE=(1 2 4)

TEST_DURATION=60    # seconds per test
NUM_TESTS=3
RESULTS_DIR="./results"
mkdir -p "$RESULTS_DIR"

PROM_URL="http://localhost:9090"   # adjust if remote

# -------- Helpers --------
# Instant query at a specific timestamp (single value per series)
query_prometheus_instant() {
  local query="$1"      # PromQL
  local eval_time="$2"  # epoch seconds
  local output_file="$3"

  echo "metric,instance,node,namespace,pod,container,mode,value" > "$output_file"

  resp=$(
    curl -s -G "${PROM_URL}/api/v1/query" \
      --data-urlencode "query=${query}" \
      --data-urlencode "time=${eval_time}"
  )

  if ! echo "$resp" | jq -e '.status=="success"' >/dev/null 2>&1; then
    echo "WARN: instant query failed: $query" >&2
    return
  fi

  echo "$resp" | jq -r '
    .data.result[]? as $s
    | [
        ($s.metric.__name__ // ""),
        ($s.metric.instance // ""),
        ($s.metric.node // ""),
        ($s.metric.namespace // ""),
        ($s.metric.pod // ""),
        ($s.metric.container // ""),
        ($s.metric.mode // ""),
        ($s.value[1] | tonumber)
      ]
    | @csv
  ' >> "$output_file"
}

# Average last column across multiple CSVs, grouping by the first 7 columns
average_metric_across_tests() {
  local pattern="$1"      # e.g. results/low_node_cpu_pct_test*.csv
  local out_file="$2"     # e.g. results/low_node_cpu_pct_avg.csv

  # shell glob might expand to itself if no files; guard by listing first
  shopt -s nullglob
  local files=( $pattern )
  shopt -u nullglob
  if (( ${#files[@]} == 0 )); then
    echo "metric,instance,node,namespace,pod,container,mode,avg_value" > "$out_file"
    return
  fi

  awk -F, '
    BEGIN { OFS="," }
    FNR==1 { next }  # skip headers in each file
    {
      key = $1 OFS $2 OFS $3 OFS $4 OFS $5 OFS $6 OFS $7
      gsub(/"/, "", key)
      val = $8
      gsub(/"/, "", val)
      sum[key] += val; cnt[key] += 1
    }
    END {
      print "metric,instance,node,namespace,pod,container,mode,avg_value"
      for (k in sum) {
        printf "%s,%.10f\n", k, sum[k]/cnt[k]
      }
    }
  ' "${files[@]}" > "$out_file"
}

save_cluster_status() {
  local outdir="$1"
  mkdir -p "$outdir"
  kubectl get nodes -o wide > "$outdir/nodes.txt"
  kubectl describe nodes > "$outdir/nodes_describe.txt"
  kubectl get pods -A -o wide > "$outdir/pods.txt"
  kubectl top nodes > "$outdir/top_nodes.txt" 2>/dev/null || true
  kubectl top pods -A > "$outdir/top_pods.txt" 2>/dev/null || true
}

# -------- PromQL (use [WIN] placeholder for the test-duration window) --------
KEYS=(
  node_cpu_pct
  pod_cpu_pct
  node_mem_pct
  pod_mem_pct
)

QUERIES=(
  '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[WIN])) * 100)'
  '100 * sum by (namespace, pod) ( rate(container_cpu_usage_seconds_total{container!="", image!=""}[WIN]) )'
  '100 * ( 1 - avg_over_time(node_memory_MemAvailable_bytes{job="node-exporter"}[WIN]) / avg_over_time(node_memory_MemTotal_bytes{job="node-exporter"}[WIN]) )'
  '100 * sum by (namespace, pod) ( avg_over_time(container_memory_usage_bytes{container!="", image!=""}[WIN]) ) / sum by (namespace, pod) ( kube_pod_container_resource_limits{resource="memory", unit="byte"} )'
)

# -------- Test Runner --------
run_test() {
  local load="$1"
  local users rate

  # Map load -> USERS/RATE
  for idx in "${!LOAD_LEVELS[@]}"; do
    if [[ "${LOAD_LEVELS[$idx]}" == "$load" ]]; then
      users=${USERS[$idx]}
      rate=${RATE[$idx]}
      break
    fi
  done

  local result_file="$RESULTS_DIR/${load}_rps.txt"
  : > "$result_file"

  echo "==> Running tests for load: $load (USERS=$users RATE=$rate)"

  for i in $(seq 1 "$NUM_TESTS"); do
    echo "-- Test #$i --"

    # Apply new env and restart Deployment
    kubectl set env deployment/loadgenerator USERS="$users" RATE="$rate" >/dev/null
    kubectl rollout restart deployment/loadgenerator >/dev/null
    kubectl rollout status deployment/loadgenerator --timeout=120s

    # Get the new pod and ensure it's Ready before timing
    local POD=""
    until POD="$(kubectl get pod -l app=loadgenerator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"; do
      sleep 1
    done
    kubectl wait --for=condition=ready "pod/${POD}" --timeout=60s

    # (optional) show the env inside the container for sanity
    echo "Loadgen env:" $(kubectl exec "$POD" -- env | egrep '^(USERS|RATE)=' | xargs)

    # Small warm-up
    sleep 5
    local start_ts end_ts
    start_ts=$(date +%s)

    echo "Running load for ${TEST_DURATION}s..."
    sleep "$TEST_DURATION"

    end_ts=$(date +%s)

    # RPS from THIS pod’s logs
    local metric
    metric=$(kubectl logs "$POD" --since=2m \
      | grep "Aggregated" | tail -1 | awk '{print $(NF-1)}' || true)
    [[ -z "${metric:-}" ]] && metric=0
    echo "$metric" >> "$result_file"

    # Save cluster status for this run
    save_cluster_status "$RESULTS_DIR/status_${load}_test${i}"

    # Build window token once per test
    local window_secs=$(( end_ts - start_ts ))
    (( window_secs < 10 )) && window_secs=10
    local window="${window_secs}s"

    # Export each metric exactly at end_ts (uses [WIN] inside the query)
    for idx in "${!KEYS[@]}"; do
      local key="${KEYS[$idx]}"
      local q="${QUERIES[$idx]}"

      # Replace any of [WIN]/[2m]/[1m] with the actual window
      q="${q//\[WIN]/[${window}]}"
      q="${q//\[2m]/[${window}]}"
      q="${q//\[1m]/[${window}]}"

      local csv="$RESULTS_DIR/${load}_${key}_test${i}.csv"
      echo "Exporting $key -> $csv   at t=end (${end_ts}) window=${window}"
      echo "$q" >> "$RESULTS_DIR/debug_queries.log"
      query_prometheus_instant "$q" "$end_ts" "$csv"
    done
  done

  echo "Completed load: $load (RPS samples in $result_file)"

  # After all tests for this load, write per-metric averages across tests
  for idx in "${!KEYS[@]}"; do
    local key="${KEYS[$idx]}"
    local pattern="$RESULTS_DIR/${load}_${key}_test*.csv"
    local out="$RESULTS_DIR/${load}_${key}_avg.csv"
    echo "Averaging ${pattern} -> ${out}"
    average_metric_across_tests "$pattern" "$out"
  done
}

analyze_results() {
  local load="$1"
  local file="$RESULTS_DIR/${load}_rps.txt"
  echo "Analyzing RPS for load: $load"

  if [[ ! -s "$file" ]]; then
    echo "Average RPS (trimmed): 0"
    return
  fi

  # Sort and compute trimmed mean (drop 2 min & 2 max if >4 samples)
  local avg
  avg=$(sort -n "$file" | awk '
    { v[NR]=$1 }
    END {
      n=NR
      start=1; end=n
      if (n>4) { start=3; end=n-2 }
      sum=0; count=0
      for (i=start; i<=end; i++) { sum+=v[i]; count++ }
      if (count>0) printf "%.6f", sum/count; else print 0
    }')

  echo "Average RPS (trimmed): $avg"
}

# -------- Main --------
for load in "${LOAD_LEVELS[@]}"; do
  run_test "$load"
  analyze_results "$load"
done

echo "All done. CSVs in $RESULTS_DIR"
