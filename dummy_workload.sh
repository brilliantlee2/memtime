#!/usr/bin/env bash
set -euo pipefail

DUR_SEC=600          # 总运行时长：10分钟
GROW_SEC=240         # 前 4 分钟增长内存（你可以改）
STEP_MB=10           # 每次增长 10MB
STEP_INTERVAL=1      # 每 1 秒增长一次

# 子进程：持续分配一点内存 + 持续占用少量 CPU，直到 10 分钟结束
(
  python - <<PY
import time, math

dur = ${DUR_SEC}
grow = ${GROW_SEC}
step_mb = ${STEP_MB}
interval = ${STEP_INTERVAL}

t0 = time.time()
buf = []

# 先增长内存 grow 秒：每 interval 秒追加 step_mb MB
while time.time() - t0 < grow:
    buf.append(b"x" * (step_mb * 1024 * 1024))
    # 顺便做点轻量 CPU，避免完全 sleep
    for i in range(20000):
        math.sqrt(i + 1)
    time.sleep(interval)

# 后面保持到 dur 秒结束：不再增长内存，只做轻量 CPU + sleep
while time.time() - t0 < dur:
    for i in range(30000):
        math.sqrt(i + 1)
    time.sleep(0.2)
PY
) &

child=$!

# 主进程：做点计算并等待到 10 分钟结束
python - <<PY
import time, math

dur = ${DUR_SEC}
t0 = time.time()
x = 0.0

while time.time() - t0 < dur:
    for i in range(80000):
        x += math.sqrt(i + 1)
    time.sleep(0.05)

print("dummy done", x)
PY

wait "$child"