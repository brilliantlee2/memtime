# memtime — Monitor RSS memory over time (Linux)

`memtime` is a tiny, dependency-light toolkit to **monitor a command’s total RSS memory usage over time** (including its child processes), record it to CSV, and **plot a memory-vs-time curve**.

It’s designed for quick profiling on Linux servers/HPC nodes when you want:
- **Total runtime**
- **Memory (RSS) trend vs time**
- Minimal setup and easy reproducibility

---

## What it does

When you run:

```bash
./memtime.sh <name_prefix> <interval_min> <command...>
