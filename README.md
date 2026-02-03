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

```


## Example: Run monitoring and generate a plot

For example, run:

```bash
./memtime.sh test 1 bash ./dummy_workload.sh
```

You will get an output directory that starts with test and is followed by the current timestamp, for example:

test_YYYYMMDD_HHMMSS/


In that directory, mem_rss.csv records memory usage at each sampling point:
    •   Column 1: time since start (in minutes, min_since_start)
    •   Column 2: total RSS memory usage of the process tree at that time (in GiB, rss_total_gib)

Then run (replace the argument with your actual output directory name):

```
python plot_mem.py "<memtime_output_dir>"
# e.g.:
python plot_mem.py test_YYYYMMDD_HHMMSS
```

This will generate a memory-vs-time plot in the same directory:
```
test_YYYYMMDD_HHMMSS/mem_rss.png

```
You can embed the generated plot in your README like this:

```
![Memory usage plot](test_YYYYMMDD_HHMMSS/mem_rss.png)
```
