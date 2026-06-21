#!/bin/bash
# run_server_test.sh - Jalankan di ThinkPad untuk menguji Pi sebagai server VPN
# Mode: baseline (LAN), wireguard, openvpn (semua otomatis)
set +e

# =========================
# LOAD KONFIGURASI
# =========================
if [ ! -f config.env ]; then
    echo "[ERROR] config.env tidak ditemukan!"
    exit 1
fi
source config.env

# =========================
# KONFIGURASI
# =========================
PI_USER=${PI_USER:-raspian}
PI_IP=${PI_IP:-192.168.11.106}
SAMPLER_SCRIPT=${SAMPLER_SCRIPT_PATH:-./collect_pi_metrics.sh}
RESULTS_BASE="./results"
BASELINE_IP=${BASELINE_IP:-192.168.11.106}
WIREGUARD_IP=${WIREGUARD_IP:-10.10.10.1}
OPENVPN_IP=${OPENVPN_IP:-10.8.0.1}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-2}

# =========================
# SSH & SCP DENGAN SSH-PASS (sekali)
# =========================
if ! command -v sshpass &> /dev/null; then
    echo "[INFO] Menginstall sshpass..."
    sudo apt update && sudo apt install -y sshpass
fi

if [ -z "$SSH_PASS" ]; then
    echo -n "Masukkan password SSH untuk $PI_USER@$PI_IP: "
    read -s SSH_PASS
    echo ""
fi

pi_ssh() {
    sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 "$PI_USER@$PI_IP" "$@"
}

pi_scp() {
    sshpass -p "$SSH_PASS" scp -o ConnectTimeout=5 "$@"
}

# =========================
# FUNGSI MENUNGGU FILE
# =========================
wait_for_file() {
    local FILE=$1
    local MAX_WAIT=10
    local WAIT_COUNT=0
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        if pi_ssh "[ -f $FILE ] && [ -s $FILE ]" 2>/dev/null; then
            return 0
        fi
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    return 1
}

# =========================
# CEK TARGET
# =========================
check_target() {
    local TARGET=$1
    echo "[CHECK] Testing connectivity to $TARGET"
    ping -c 2 -W 2 "$TARGET" > /dev/null
    return $?
}

# =========================
# FUNGSI RUN MODE
# =========================
run_mode() {
    local MODE=$1
    local TARGET=$2
    local MODE_DIR="$RESULTS_BASE/server_${MODE}"
    mkdir -p "$MODE_DIR"

    echo ""
    echo "##########################################"
    echo "MODE: $MODE (target: $TARGET)"
    echo "##########################################"

    check_target "$TARGET" || {
        echo "[SKIP] $MODE skipped due to unreachable target"
        return
    }

    LEVELS="light medium heavy"
    [ "${ENABLE_LONG_TEST:-no}" = "yes" ] && LEVELS="$LEVELS long"

    for LEVEL in $LEVELS; do
        case $LEVEL in
            light)  P=$P_LIGHT; D=$DURATION_LIGHT ;;
            medium) P=$P_MEDIUM; D=$DURATION_MEDIUM ;;
            heavy)  P=$P_HEAVY; D=$DURATION_HEAVY ;;
            long)   P=${P_LONG:-1}; D=${DURATION_LONG:-3600} ;;
        esac

        RESULT_DIR="$MODE_DIR/$LEVEL"
        mkdir -p "$RESULT_DIR"
        PI_RESULT_DIR="/home/$PI_USER/results/server_${MODE}/$LEVEL"
        pi_ssh "mkdir -p $PI_RESULT_DIR"

        echo ""
        echo ">>> LEVEL: $LEVEL (durasi ${D}s, paralel $P)"

        for i in $(seq 1 "$ITER"); do
            echo ""
            echo "  RUN $i / $ITER"

            SYS_FILE="$PI_RESULT_DIR/sys_$i.csv"

            # 1. Start sampler
            echo "    [SAMPLER] Memulai di Pi: $SYS_FILE"
            pi_ssh "nohup $SAMPLER_SCRIPT $SYS_FILE $SAMPLE_INTERVAL > /dev/null 2>&1 &"
            sleep 2

            # Tunggu file CSV
            if ! wait_for_file "$SYS_FILE"; then
                echo "    [WARN] File CSV tidak muncul, sampler mungkin gagal"
            fi

            # 2. Iperf3
            UDP_OPT=""
            [ "${UDP_TEST:-no}" = "yes" ] && UDP_OPT="-u -b ${UDP_BANDWIDTH:-100M}"
            echo "    [IPERF3] Menjalankan iperf3 (${D}s, $P streams)"
            IPERF_TIMEOUT=$((D + 30))
            timeout -k 5 "$IPERF_TIMEOUT" \
                iperf3 -c "$TARGET" -P "$P" -t "$D" $UDP_OPT --json -4 > "$RESULT_DIR/iperf_$i.json"
            if [ $? -ne 0 ]; then
                echo "    [WARN] iperf3 gagal, retry..."
                sleep 3
                timeout -k 5 "$IPERF_TIMEOUT" \
                    iperf3 -c "$TARGET" -P "$P" -t "$D" $UDP_OPT --json -4 > "$RESULT_DIR/iperf_${i}_retry.json"
            fi

            # 3. Stop sampler
            echo "    [SAMPLER] Menghentikan sampler di Pi"
            pi_ssh "pkill -f collect_pi_metrics.sh" || true
            sleep 1

            # 4. Copy CSV
            echo "    [COPY] Menyalin $SYS_FILE ke $RESULT_DIR/"
            if pi_scp "$PI_USER@$PI_IP:$SYS_FILE" "$RESULT_DIR/" 2>/dev/null; then
                echo "    [COPY] Sukses"
            else
                echo "    [WARN] Gagal copy CSV"
            fi

            # 5. HTTP Response
            if [ "${HTTP_TEST:-yes}" = "yes" ]; then
                echo "    [HTTP] Response time test"
                curl -o /dev/null -s -w "%{time_total}\n" https://www.google.com > "$RESULT_DIR/http_response_$i.txt"
            fi

            # 6. Ping
            echo "    [PING] $PING_COUNT paket ke $TARGET"
            PING_TIMEOUT=$((PING_COUNT + 15))
            timeout -k 3 -s INT "$PING_TIMEOUT" \
                ping -c "$PING_COUNT" -W 2 "$TARGET" > "$RESULT_DIR/ping_$i.txt"

            # 7. MTR
            echo "    [MTR] $MTR_COUNT paket ke $TARGET"
            MTR_TIMEOUT=$((MTR_COUNT + 20))
            timeout -k 3 -s INT "$MTR_TIMEOUT" \
                mtr -r -c "$MTR_COUNT" "$TARGET" > "$RESULT_DIR/mtr_$i.txt"

            sleep $SLEEP_BETWEEN
        done
    done
}

# =========================
# EKSEKUSI SEMUA MODE
# =========================
echo ""
echo "=========================================="
echo "MEMULAI PENGUJIAN SERVER UNTUK SEMUA MODE"
echo "=========================================="

# Pastikan iperf3 server di Pi berjalan
pi_ssh "pgrep -x iperf3 > /dev/null || (iperf3 -s -D && echo '[INFO] iperf3 server dimulai')"

run_mode "baseline" "$BASELINE_IP"
run_mode "wireguard" "$WIREGUARD_IP"
run_mode "openvpn" "$OPENVPN_IP"

# Cleanup
pi_ssh "rm -rf /home/$PI_USER/results" || true

echo ""
echo "=========================================="
echo "SEMUA PENGUJIAN SELESAI"
echo "Hasil tersimpan di: $RESULTS_BASE/server_*/"
echo "=========================================="