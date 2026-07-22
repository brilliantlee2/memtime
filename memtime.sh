#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <name_prefix> <interval_min> <command...>"
  echo "Example: $0 debreak 1 conda run -n debreak debreak --bam input.bam ..."
  exit 1
fi

name="$1"; shift
interval="$1"; shift
cmd=("$@")

out_dir="${name}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$out_dir"

csv="$out_dir/memory.csv"
echo "min_since_start,rss_total_gib,pss_total_gib,cgroup_memory_gib,proc_count,physical_metric" > "$csv"

start_epoch=$(date +%s)

("${cmd[@]}") >"$out_dir/stdout.log" 2>"$out_dir/stderr.log" &
root_pid=$!
echo "$root_pid" > "$out_dir/pid"

collect_pids() {
  local root="$1"
  local pids=("$root")
  local changed=1

  while [[ $changed -eq 1 ]]; do
    changed=0
    local current=" ${pids[*]} "
    local kids
    kids=$(pgrep -P "$(IFS=,; echo "${pids[*]}")" 2>/dev/null || true)
    if [[ -n "$kids" ]]; then
      while read -r child; do
        [[ -z "$child" ]] && continue
        if ! [[ "$current" =~ " $child " ]]; then
          pids+=("$child")
          changed=1
        fi
      done <<< "$kids"
    fi
  done

  printf '%s\n' "${pids[@]}"
}

sum_rss_kb() {
  local pids=("$@")
  { ps -o rss= -p "$(IFS=,; echo "${pids[*]}")" 2>/dev/null || true; } \
    | awk '{sum += $1} END {print sum + 0}'
}

# PSS apportions shared pages among the processes that map them, avoiding RSS
# double counting. It is the best process-tree estimate of physical memory use.
sum_pss_kb() {
  local pids=("$@")
  local total=0
  local readable=0
  local process_pid pss

  for process_pid in "${pids[@]}"; do
    [[ -r "/proc/$process_pid/smaps_rollup" ]] || continue
    pss=$(awk '/^Pss:/ {print $2; exit}' "/proc/$process_pid/smaps_rollup" 2>/dev/null || true)
    [[ "$pss" =~ ^[0-9]+$ ]] || continue
    total=$((total + pss))
    readable=$((readable + 1))
  done

  printf '%s %s\n' "$total" "$readable"
}

# A dedicated Slurm/job cgroup provides the kernel-accounted memory charged to
# the whole job. On a shared login/session cgroup this can include other tasks.
read_cgroup_memory_bytes() {
  local process_pid="$1"
  local path value_file

  # cgroup v2
  path=$(awk -F: '$1 == "0" {print $3; exit}' "/proc/$process_pid/cgroup" 2>/dev/null || true)
  if [[ -n "$path" ]]; then
    value_file="/sys/fs/cgroup${path%/}/memory.current"
    [[ -r "$value_file" ]] && cat "$value_file" && return 0
  fi

  # cgroup v1, common on older HPC systems
  path=$(awk -F: '$2 ~ /(^|,)memory(,|$)/ {print $3; exit}' "/proc/$process_pid/cgroup" 2>/dev/null || true)
  if [[ -n "$path" ]]; then
    value_file="/sys/fs/cgroup/memory${path%/}/memory.usage_in_bytes"
    [[ -r "$value_file" ]] && cat "$value_file" && return 0
  fi

  return 1
}

write_top_processes_snapshot() {
  local timestamp_min="$1"; shift
  local pids=("$@")
  local snapshot="$out_dir/top_$(printf '%08.2f' "$timestamp_min" | tr '.' '_').tsv"

  ps -o pid=,ppid=,rss=,%mem=,etime=,comm=,args= \
    -p "$(IFS=,; echo "${pids[*]}")" 2>/dev/null \
    | awk 'BEGIN{OFS="\t"; print "pid","ppid","rss_kb","pct_mem","etime","comm","args"}
      {print $1,$2,$3,$4,$5,$6,substr($0,index($0,$7))}' \
    | sort -t $'\t' -k3,3nr \
    | head -20 > "$snapshot" || true
}

while kill -0 "$root_pid" 2>/dev/null; do
  now_epoch=$(date +%s)
  sec=$((now_epoch - start_epoch))
  min=$(awk -v s="$sec" 'BEGIN {printf "%.2f", s / 60.0}')

  mapfile -t pids < <(collect_pids "$root_pid")
  proc_count="${#pids[@]}"

  rss_kb=$(sum_rss_kb "${pids[@]}")
  rss_gib=$(awk -v x="$rss_kb" 'BEGIN {printf "%.3f", x / 1024 / 1024}')

  read -r pss_kb pss_proc_count < <(sum_pss_kb "${pids[@]}")
  if [[ "$pss_proc_count" -gt 0 ]]; then
    pss_gib=$(awk -v x="$pss_kb" 'BEGIN {printf "%.3f", x / 1024 / 1024}')
    physical_metric="pss_smaps_rollup_${pss_proc_count}_of_${proc_count}"
  else
    pss_gib="NA"
    physical_metric="pss_unavailable"
  fi

  if cgroup_bytes=$(read_cgroup_memory_bytes "$root_pid"); then
    cgroup_gib=$(awk -v x="$cgroup_bytes" 'BEGIN {printf "%.3f", x / 1024 / 1024 / 1024}')
    physical_metric="${physical_metric}+cgroup"
  else
    cgroup_gib="NA"
  fi

  echo "$min,$rss_gib,$pss_gib,$cgroup_gib,$proc_count,$physical_metric" >> "$csv"
  write_top_processes_snapshot "$min" "${pids[@]}"
  sleep "$((interval * 60))"
done

set +e
wait "$root_pid"
rc=$?
set -e

end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
echo "$elapsed" > "$out_dir/elapsed_seconds.txt"
echo "$rc" > "$out_dir/exit_code.txt"

echo "[DONE] exit_code=$rc elapsed=${elapsed}s"
echo "[OUT]  $out_dir"
