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
echo "min_since_start,rss_total_gib,pss_total_gib,proc_count,metric_source" > "$csv"

start_epoch=$(date +%s)

("${cmd[@]}") >"$out_dir/stdout.log" 2>"$out_dir/stderr.log" &
pid=$!
echo "$pid" > "$out_dir/pid"

collect_pids() {
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

  printf '%s\n' "${pids[@]}"
}

sum_rss_kb() {
  local pids=("$@")
  local rss_sum_kb=0
  while read -r rss; do
    [[ -z "$rss" ]] && continue
    rss_sum_kb=$((rss_sum_kb + rss))
  done < <(ps -o rss= -p "$(IFS=,; echo "${pids[*]}")" 2>/dev/null || true)

  echo "$rss_sum_kb"
}

sum_pss_kb_from_smem() {
  local pids=("$@")
  command -v smem >/dev/null 2>&1 || return 1

  local pid_csv
  pid_csv="$(IFS=,; echo "${pids[*]}")"
  smem -c "pid pss" -P "" -p "$pid_csv" 2>/dev/null | awk '
    BEGIN {sum=0}
    NR > 1 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {sum += $2}
    END {print sum + 0}
  '
}

sum_pss_kb_from_smaps() {
  local pids=("$@")
  local pss_sum_kb=0
  local pid
  for pid in "${pids[@]}"; do
    [[ -r "/proc/$pid/smaps_rollup" ]] || continue
    local pss
    pss=$(awk '/^Pss:/ {print $2; exit}' "/proc/$pid/smaps_rollup" 2>/dev/null || true)
    [[ -n "${pss:-}" ]] || continue
    pss_sum_kb=$((pss_sum_kb + pss))
  done
  echo "$pss_sum_kb"
}

write_top_processes_snapshot() {
  local timestamp_min="$1"
  shift
  local pids=("$@")
  local snapshot="$out_dir/top_$(printf '%08.2f' "$timestamp_min" | tr '.' '_').tsv"

  ps -o pid=,ppid=,rss=,%mem=,etime=,comm=,args= -p "$(IFS=,; echo "${pids[*]}")" 2>/dev/null \
    | awk 'BEGIN{OFS="\t"; print "pid","ppid","rss_kb","pct_mem","etime","comm","args"} {print $1,$2,$3,$4,$5,$6,substr($0,index($0,$7))}' \
    | sort -t $'\t' -k3,3nr \
    | head -20 > "$snapshot" || true
}

while kill -0 "$pid" 2>/dev/null; do
  now_epoch=$(date +%s)
  sec=$((now_epoch - start_epoch))
  min=$(awk -v s="$sec" 'BEGIN{printf "%.2f", s/60.0}')

  mapfile -t pids < <(collect_pids "$pid")
  rss_kb=$(sum_rss_kb "${pids[@]}")
  rss_gib=$(awk -v x="$rss_kb" 'BEGIN{printf "%.3f", x/1024.0/1024.0}')
  proc_count="${#pids[@]}"

  pss_kb=""
  metric_source="rss_only"
  if command -v smem >/dev/null 2>&1; then
    pss_kb=$(sum_pss_kb_from_smem "${pids[@]}" || true)
    if [[ -n "${pss_kb:-}" ]]; then
      metric_source="smem_pss"
    fi
  fi
  if [[ -z "${pss_kb:-}" ]]; then
    pss_kb=$(sum_pss_kb_from_smaps "${pids[@]}" || true)
    if [[ -n "${pss_kb:-}" && "${pss_kb:-0}" -gt 0 ]]; then
      metric_source="smaps_rollup_pss"
    else
      pss_kb="$rss_kb"
    fi
  fi
  pss_gib=$(awk -v x="$pss_kb" 'BEGIN{printf "%.3f", x/1024.0/1024.0}')

  echo "$min,$rss_gib,$pss_gib,$proc_count,$metric_source" >> "$csv"
  write_top_processes_snapshot "$min" "${pids[@]}"
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
