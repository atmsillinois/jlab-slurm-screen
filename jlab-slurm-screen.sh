#!/usr/bin/env bash
# keeling.earth.illinois.edu — Start Jupyter Lab on a Slurm compute node (single SRUN).
# Writes ~/.jlab/<session>_<stamp>.{log,url,port,node,where,tunnel}
# WAITS to print SSH commands + Jupyter URL until NODE and PORT are ready.
#
# KEY=VALUE (any order):
#   hours=2 session=jlab cpus=8 mem=32G partition=seseml jlab_port=8888 [dask_port=8787]
#
# Behavior knobs (env vars):
#   READY_WAIT=0   # seconds to wait here for NODE+PORT; 0 = wait indefinitely (default)
#   PRINT_POLL=1   # polling interval (seconds) while waiting; default 1
#   BASTION=       # optional ProxyJump host, e.g. bastion.illinois.edu (adds -J to OUTER ssh)

set -euo pipefail

# -------- Defaults --------
HOURS="2"; SESSION="jlab"; CPUS="8"; MEM="32G"; PARTITION="seseml"
JPORT="8888"; DPORT=""
READY_WAIT="${READY_WAIT:-0}"
PRINT_POLL="${PRINT_POLL:-1}"

# -------- Parse KEY=VALUE args --------
for arg in "$@"; do
  case "$arg" in
    hours=*)       HOURS="${arg#*=}" ;;
    session=*)     SESSION="${arg#*=}" ;;
    cpus=*)        CPUS="${arg#*=}" ;;
    mem=*)         MEM="${arg#*=}" ;;
    partition=*)   PARTITION="${arg#*=}" ;;
    jlab_port=*)   JPORT="${arg#*=}" ;;
    dask_port=*)   DPORT="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" >&2
       echo "Usage: hours=N session=NAME cpus=N mem=SIZE partition=PART jlab_port=PORT [dask_port=PORT]" >&2
       exit 2 ;;
  esac
done

# ---- Validate hours integer; compute seconds ----
if [[ "$HOURS" =~ ^0*[0-9]+$ ]]; then
  SECS=$((10#$HOURS * 3600))
else
  echo "hours must be an integer (got '$HOURS')" >&2; exit 2
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
JDIR="$HOME/.jlab"; mkdir -p "$JDIR"

LOG="$JDIR/${SESSION}_${STAMP}.log"
URLFILE="$JDIR/${SESSION}_${STAMP}.url"
PORTFILE="$JDIR/${SESSION}_${STAMP}.port"
NODEFILE="$JDIR/${SESSION}_${STAMP}.node"
WHEREFILE="$JDIR/${SESSION}_${STAMP}.where"
TUNNELFILE="$JDIR/${SESSION}_${STAMP}.tunnel"

RUNNER="$JDIR/.runner_${SESSION}_${STAMP}.sh"
WATCHER="$JDIR/.watch_${SESSION}_${STAMP}.sh"

# Fresh files
: >"$URLFILE"; : >"$PORTFILE"; : >"$NODEFILE"; : >"$WHEREFILE"; : >"$TUNNELFILE"

# Head & optional bastion
HEAD="keeling.earth.illinois.edu"
ME_LOCAL="$(whoami)"
BASTION="${BASTION:-}"          # e.g. bastion.illinois.edu
BASTION_OPT=""
[[ -n "$BASTION" ]] && BASTION_OPT="-J $BASTION"

# Avoid colliding screen names
if screen -ls | grep -q "\.${SESSION}[[:space:]]"; then
  echo "A screen named '$SESSION' exists. Use a new name or: screen -S $SESSION -X quit" >&2
  exit 1
fi

echo "[keeling] Slurm: partition=$PARTITION time=${HOURS}h cpus=$CPUS mem=$MEM"
echo "[keeling] Requested Jupyter port: $JPORT  (0 = auto-pick; else retries up to 50)"
echo "[keeling] Dask dashboard port: ${DPORT:-<none>}"
echo "[keeling] Session: $SESSION"
echo "[keeling] Files: log=$LOG url=$URLFILE port=$PORTFILE node=$NODEFILE tunnel=$TUNNELFILE"

# ---------- Runner: executes under screen on keeling ----------
cat > "$RUNNER" <<'RS'
#!/usr/bin/env bash
set -euo pipefail
# env: PARTITION HOURS CPUS MEM JPORT SECS LOG NODEFILE WHEREFILE URLFILE
{
  echo "[keeling] Launching single srun (compute node payload)…"
  srun -p "$PARTITION" \
       --time="${HOURS}:00:00" \
       --cpus-per-task="$CPUS" \
       --mem="$MEM" \
       --exclusive -N1 -n1 \
       --job-name="jlab_${USER}" \
       bash -lc '
         set -euo pipefail
         {
           echo "whoami: $(whoami)"
           echo "hostname: $(hostname)"
           echo "hostname -f: $(hostname -f || true)"
           echo "SLURMD_NODENAME: ${SLURMD_NODENAME:-}"
           echo "SLURM_NODELIST: ${SLURM_NODELIST:-}"
         } | sed "s/^/[where] /" | tee -a "'"$LOG"'" | tee "'"$WHEREFILE"'"

         # Write node only from inside srun (compute node)
         hostname > "'"$NODEFILE"'"

         # Activate Python/Jupyter env (customize as needed)
         module load python/3.11 2>/dev/null || true
         # OR: source ~/mambaforge/etc/profile.d/conda.sh && conda activate myenv

         echo "[compute] Starting Jupyter (timeout '"$SECS"'s) on requested port '"$JPORT"'"
         timeout '"$SECS"' jupyter lab \
           --no-browser \
           --ip=127.0.0.1 \
           --ServerApp.port='"$JPORT"' \
           --ServerApp.port_retries=50 \
           2>&1
       '
} 2>&1 | tee -a "$LOG"
RS
chmod +x "$RUNNER"

# ---------- Watcher: fills URL/PORT/node/tunnel asynchronously ----------
cat > "$WATCHER" <<'WS'
#!/usr/bin/env bash
set -euo pipefail
# env: LOG NODEFILE URLFILE PORTFILE TUNNELFILE JPORT DPORT ME HEAD BASTION_OPT
for i in $(seq 1 7200); do  # up to 2h
  # Grab first Jupyter token URL
  if [[ ! -s "$URLFILE" ]]; then
    grep -Eo "http://127\.0\.0\.1:[0-9]+/[^ ]+" "$LOG" | head -n1 > "$URLFILE" 2>/dev/null || true
  fi
  # Extract actual port from URL
  if [[ -s "$URLFILE" && ! -s "$PORTFILE" ]]; then
    awk -F[/:] '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i-1) ~ /127\.0\.0\.1/) {print $i; exit}}' "$URLFILE" > "$PORTFILE" 2>/dev/null || true
  fi

  # Compute node
  NODE=""
  [[ -s "$NODEFILE" ]] && NODE="$(tr -d '\r\n' < "$NODEFILE")"

  if [[ -n "$NODE" ]]; then
    ACTPORT="$( [[ -s "$PORTFILE" ]] && tr -d "\r\n" < "$PORTFILE" || echo "$JPORT" )"
    # Build two-hop tunnel command:
    # OUTER: local -> head (-L PORT:127.0.0.1:PORT)
    # INNER: head  -> compute (-L PORT:127.0.0.1:PORT)
    if [[ -n "$DPORT" ]]; then
      cat > "$TUNNELFILE" <<EOF
ssh $BASTION_OPT -L ${ACTPORT}:127.0.0.1:${ACTPORT} -L ${DPORT}:127.0.0.1:${DPORT} ${ME}@${HEAD} \
  'ssh -N -L ${ACTPORT}:127.0.0.1:${ACTPORT} -L ${DPORT}:127.0.0.1:${DPORT} ${NODE}'
EOF
    else
      cat > "$TUNNELFILE" <<EOF
ssh $BASTION_OPT -L ${ACTPORT}:127.0.0.1:${ACTPORT} ${ME}@${HEAD} \
  'ssh -N -L ${ACTPORT}:127.0.0.1:${ACTPORT} ${NODE}'
EOF
    fi
    exit 0
  fi
  sleep 1
done
WS
chmod +x "$WATCHER"

# ---------- Export for runner & watcher ----------
export PARTITION HOURS CPUS MEM JPORT SECS LOG NODEFILE WHEREFILE URLFILE
export PORTFILE TUNNELFILE
export ME="$ME_LOCAL"; export HEAD="$HEAD"; export DPORT; export BASTION_OPT

# ---------- Start screen (detached); do NOT block ----------
screen -dmS "$SESSION" bash -lc "$RUNNER"

# ---------- Start watcher (detached) ----------
nohup bash -lc "$WATCHER" >/dev/null 2>&1 & disown || true

echo
echo "=== Launched — waiting for compute node & port to be ready ==="
[[ "$READY_WAIT" != "0" ]] && echo "(Max wait: ${READY_WAIT}s; set READY_WAIT=0 to wait indefinitely.)"
echo "Log: $LOG"
echo

# ---------- WAIT here until both NODE and PORT known, then print commands ----------
start_ts=$(date +%s)
while :; do
  HAVE_NODE=0; HAVE_PORT=0; HAVE_URL=0
  [[ -s "$NODEFILE" ]] && HAVE_NODE=1
  [[ -s "$PORTFILE" ]] && HAVE_PORT=1
  [[ -s "$URLFILE"  ]] && HAVE_URL=1

  if (( HAVE_NODE && HAVE_PORT )); then
    NODE="$(tr -d '\r\n' < "$NODEFILE")"
    PORT="$(tr -d '\r\n' < "$PORTFILE" 2>/dev/null || echo "$JPORT")"

    echo "----- Ready -----"
    echo "Compute node : $NODE"
    echo "Jupyter port : $PORT"
    echo

    echo "# Run on YOUR LAPTOP (macOS/Linux) — two-hop via head -> compute:"
    if [[ -n "$DPORT" ]]; then
      echo "ssh $BASTION_OPT -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} ${ME_LOCAL}@${HEAD} \\"
      echo "  'ssh -N -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} ${NODE}'"
    else
      echo "ssh $BASTION_OPT -L ${PORT}:127.0.0.1:${PORT} ${ME_LOCAL}@${HEAD} \\"
      echo "  'ssh -N -L ${PORT}:127.0.0.1:${PORT} ${NODE}'"
    fi
    echo

    echo "# Run on YOUR LAPTOP (Windows PowerShell) — two-hop via head -> compute:"
    if [[ -n "$DPORT" ]]; then
      if [[ -n "$BASTION" ]]; then
        echo "ssh ${ME_LOCAL}@${HEAD} -J ${BASTION} -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} \"ssh -N -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} ${NODE}\""
      else
        echo "ssh ${ME_LOCAL}@${HEAD} -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} \"ssh -N -L ${PORT}:127.0.0.1:${PORT} -L ${DPORT}:127.0.0.1:${DPORT} ${NODE}\""
      fi
    else
      if [[ -n "$BASTION" ]]; then
        echo "ssh ${ME_LOCAL}@${HEAD} -J ${BASTION} -L ${PORT}:127.0.0.1:${PORT} \"ssh -N -L ${PORT}:127.0.0.1:${PORT} ${NODE}\""
      else
        echo "ssh ${ME_LOCAL}@${HEAD} -L ${PORT}:127.0.0.1:${PORT} \"ssh -N -L ${PORT}:127.0.0.1:${PORT} ${NODE}\""
      fi
    fi
    echo

    if (( HAVE_URL )); then
      echo "# Jupyter URL (with token) — paste into browser or VS Code (Select another kernel, Existing Jupyter Server, paste):"
      cat "$URLFILE"
      echo
    else
      echo "# Jupyter URL not parsed yet; fetch shortly with:"
      echo "ssh ${ME_LOCAL}@${HEAD} 'cat $URLFILE'"
      echo
    fi
    break
  fi

  # Timeout?
  if [[ "$READY_WAIT" != "0" ]]; then
    now=$(date +%s)
    (( now - start_ts >= READY_WAIT )) && {
      echo "Timed out waiting for compute node/port."
      echo "From your laptop, retrieve values with:"
      echo "  ssh ${ME_LOCAL}@${HEAD} 'cat $NODEFILE'   # node"
      echo "  ssh ${ME_LOCAL}@${HEAD} 'cat $PORTFILE'   # port"
      echo "  ssh ${ME_LOCAL}@${HEAD} 'cat $URLFILE'    # URL"
      exit 1
    }
  fi
  sleep "$PRINT_POLL"
done

echo
echo "Attach on keeling:  screen -r $SESSION"
echo "Quit early:         screen -S $SESSION -X quit"
