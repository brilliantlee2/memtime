#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <name_prefix> <interval_min> <command...>"
  echo "Example (sample every 1 min): $0 test 1 bash dummy_workload.sh"
  exit 1
fi

name="$1"; shift
interval="$1"; shift
cmd=("$@")

# 输出目录：name_时间
out_dir="${name}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$out_dir"

csv="$out_dir/mem_rss.csv"
echo "min_since_start,rss_total_gib" > "$csv"

start_epoch=$(date +%s)

("${cmd[@]}") >"$out_dir/stdout.log" 2>"$out_dir/stderr.log" &
pid=$!
echo "$pid" > "$out_dir/pid"

sum_rss_kb() {
  local root="$1"
  local pids=("$root")
  local changed=1

  while [[ $changed -eq 1 ]]; do
    changed=0
    local current=" ${pids[*]} "
    local kids
    kids=$(pgrep -P "$(IFS=,; echo "${pids[*]}")" 2>/dev/null || true)
    if [[ -n "${kids}" ]]; then
      while read -r k; do
        [[ -z "$k" ]] && continue
        if ! [[ "$current" =~ " $k " ]]; then
          pids+=("$k")
          changed=1
        fi
      done <<< "$kids"
    fi
  done

  local rss_sum_kb=0
  while read -r rss; do
    [[ -z "$rss" ]] && continue
    rss_sum_kb=$((rss_sum_kb + rss))
  done < <(ps -o rss= -p "$(IFS=,; echo "${pids[*]}")" 2>/dev/null || true)

  echo "$rss_sum_kb"
}

while kill -0 "$pid" 2>/dev/null; do
  now_epoch=$(date +%s)
  sec=$((now_epoch - start_epoch))
  min=$(awk -v s="$sec" 'BEGIN{printf "%.2f", s/60.0}')

  rss_kb=$(sum_rss_kb "$pid")
  rss_gib=$(awk -v x="$rss_kb" 'BEGIN{printf "%.3f", x/1024.0/1024.0}')

  echo "$min,$rss_gib" >> "$csv"
  sleep "$((interval * 60))"
done

set +e
wait "$pid"
rc=$?
set -e

end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))

echo "$elapsed" > "$out_dir/elapsed_seconds.txt"
echo "$rc" > "$out_dir/exit_code.txt"

echo "[DONE] exit_code=$rc  elapsed=${elapsed}s"
echo "[OUT]  $out_dir"