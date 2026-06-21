#!/bin/bash
 
set +e
 
source config.env
 
mkdir -p results/{baseline,wireguard,openvpn}
mkdir -p logs
 
timestamp=$(date +"%Y%m%d_%H%M%S")
log_file="logs/run_$timestamp.log"
 
exec > >(tee -a "$log_file") 2>&1
 
SAMPLER_PID=""
 
# =========================
# CLEAN EXIT HANDLER
# =========================
cleanup() {
    echo ""
    echo "=============================="
    echo "STOP DETECTED - CLEANING UP"
    echo "=============================="
 
    [ -n "$SAMPLER_PID" ] && kill "$SAMPLER_PID" 2>/dev/null
 
    pkill -f iperf3 2>/dev/null
    pkill -f "mtr " 2>/dev/null
    pkill -f "ping " 2>/dev/null
    pkill -f collect_pi_metrics.sh 2>/dev/null
 
    exit 1
}
 
trap cleanup SIGINT SIGTERM
 
# =========================
# CHECK SERVER CONNECTIVITY
# =========================
check_host() {
    TARGET=$1
    echo "[CHECK] Testing connectivity to $TARGET"
 
    ping -c 2 -W 2 "$TARGET" > /dev/null
 
    if [ $? -ne 0 ]; then
        echo "[ERROR] Target $TARGET unreachable!"
        echo "Abort test for this mode."
        return 1
    fi
 
    return 0
}
 
# =========================
# SAFE RUN FUNCTION
# =========================
run_test () {
    MODE=$1
    TARGET=$2
 
    echo ""
    echo "######################################"
    echo "MODE: $MODE"
    echo "TARGET: $TARGET"
    echo "######################################"
 
    check_host "$TARGET"
    if [ $? -ne 0 ]; then
        echo "[SKIP] $MODE skipped due to unreachable target"
        return
    fi
 
    for LEVEL in light medium heavy
    do
        case $LEVEL in
            light)
                P=$P_LIGHT
                D=$DURATION_LIGHT
                ;;
            medium)
                P=$P_MEDIUM
                D=$DURATION_MEDIUM
                ;;
            heavy)
                P=$P_HEAVY
                D=$DURATION_HEAVY
                ;;
        esac
 
        mkdir -p "results/$MODE/$LEVEL"
 
        for i in $(seq 1 $ITER)
        do
            echo ""
            echo ">>> [$MODE][$LEVEL] RUN $i"
 
            # =========================
            # RESOURCE SAMPLER
            # Starts right before the load test and is stopped right after,
            # so CPU/RAM/Temp are sampled DURING the actual throughput test
            # rather than drifting in an unrelated background log.
            # =========================
            SYS_OUT="results/$MODE/$LEVEL/sys_$i.csv"
            ./collect_pi_metrics.sh "$SYS_OUT" "$SAMPLE_INTERVAL" &
            SAMPLER_PID=$!
 
            # =========================
            # IPERF3 (SAFE + TIMEOUT)
            # =========================
            echo "[i] iperf3 start"
 
            IPERF_TIMEOUT=$((D + 30))
 
            timeout -k 5 "$IPERF_TIMEOUT" \
            iperf3 -c "$TARGET" -P "$P" -t "$D" --json \
            > "results/$MODE/$LEVEL/iperf_$i.json"
 
            if [ $? -ne 0 ]; then
                echo "[WARN] iperf failed, retry..."
 
                sleep 3
 
                timeout -k 5 "$IPERF_TIMEOUT" \
                iperf3 -c "$TARGET" -P "$P" -t "$D" --json \
                > "results/$MODE/$LEVEL/iperf_${i}_retry.json"
            fi
 
            # Load test is over, stop sampling.
            kill "$SAMPLER_PID" 2>/dev/null
            wait "$SAMPLER_PID" 2>/dev/null
            SAMPLER_PID=""
 
            # =========================
            # PING (SAFE)
            # Timeout now scales with PING_COUNT instead of a fixed 10s, so
            # ping actually gets to send all PING_COUNT packets and print its
            # "rtt min/avg/max" + "packet loss" summary line - that line is
            # the only thing the parser can read latency/loss from.
            # -s INT makes the fallback kill send SIGINT (like Ctrl-C)
            # instead of SIGTERM, so even if the timeout IS hit, ping still
            # prints stats for whatever it managed to send instead of dying
            # silently.
            # =========================
            echo "[i] ping start"
 
            PING_TIMEOUT=$((PING_COUNT + 15))
 
            timeout -k 3 -s INT "$PING_TIMEOUT" \
            ping -c "$PING_COUNT" -W 2 "$TARGET" \
            > "results/$MODE/$LEVEL/ping_$i.txt"
 
            # =========================
            # MTR (SAFE)
            # mtr -r (report mode) only writes output once ALL cycles are
            # done - it can't print early. Timeout now scales with
            # MTR_COUNT plus headroom, instead of a fixed 20s that was
            # killing it before a single report was ever written.
            # =========================
            echo "[i] mtr start"
 
            MTR_TIMEOUT=$((MTR_COUNT + 20))
 
            timeout -k 3 -s INT "$MTR_TIMEOUT" \
            mtr -r -c "$MTR_COUNT" "$TARGET" \
            > "results/$MODE/$LEVEL/mtr_$i.txt"
 
            # =========================
            # GAP
            # =========================
            sleep 2
        done
    done
}
 
# =========================
# MENU
# =========================
echo ""
echo "Select mode:"
echo "1) Baseline (LAN)"
echo "2) WireGuard"
echo "3) OpenVPN"
read MODE
 
case $MODE in
    1)
        run_test baseline 192.168.11.106
        ;;
    2)
        run_test wireguard 10.10.10.1
        ;;
    3)
        run_test openvpn 10.8.0.1
        ;;
    *)
        echo "Invalid option"
        ;;
esac
 
echo ""
echo "======================================"
echo "TEST COMPLETED"
echo "LOG: $log_file"
echo "======================================"
 
