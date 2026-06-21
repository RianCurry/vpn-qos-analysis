#!/bin/bash

set +e

# =========================
# LOAD KONFIGURASI
# =========================
if [ ! -f config.env ]; then
    echo "[ERROR] File config.env tidak ditemukan!"
    exit 1
fi
source config.env

# =========================
# CEK VARIABEL YANG DIBUTUHKAN
# =========================
REQUIRED_VARS=("P_LIGHT" "DURATION_LIGHT" "P_MEDIUM" "DURATION_MEDIUM" 
               "P_HEAVY" "DURATION_HEAVY" "ITER" "PING_COUNT" "MTR_COUNT" 
               "SAMPLE_INTERVAL")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "[ERROR] Variabel $var tidak didefinisikan di config.env"
        exit 1
    fi
done

# =========================
# CEK KEBERADAAN collect_pi_metrics.sh
# =========================
SAMPLER_SCRIPT="./collect_pi_metrics.sh"
if [ ! -f "$SAMPLER_SCRIPT" ]; then
    echo "[ERROR] $SAMPLER_SCRIPT tidak ditemukan!"
    echo "Pastikan file tersebut berada di direktori yang sama dengan skrip ini."
    exit 1
fi
if [ ! -x "$SAMPLER_SCRIPT" ]; then
    echo "[INFO] Memberikan izin eksekusi pada $SAMPLER_SCRIPT"
    chmod +x "$SAMPLER_SCRIPT"
fi

# =========================
# BUAT DIREKTORI
# =========================
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

    # Matikan sampler jika masih berjalan
    if [ -n "$SAMPLER_PID" ]; then
        echo "[CLEANUP] Menghentikan sampler (PID $SAMPLER_PID)"
        kill "$SAMPLER_PID" 2>/dev/null
        wait "$SAMPLER_PID" 2>/dev/null
    fi

    # Matikan proses lain yang mungkin tersisa
    pkill -f iperf3 2>/dev/null
    pkill -f "mtr " 2>/dev/null
    pkill -f "ping " 2>/dev/null
    pkill -f collect_pi_metrics.sh 2>/dev/null

    echo "Cleanup selesai."
    exit 1
}

trap cleanup SIGINT SIGTERM

# =========================
# CEK KONEKTIVITAS TARGET
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
# FUNGSI UTAMA TEST
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
            # =========================
            SYS_OUT="results/$MODE/$LEVEL/sys_$i.csv"
            echo "[SAMPLER] Memulai pengumpulan metrik ke $SYS_OUT (interval ${SAMPLE_INTERVAL}s)"

            # Jalankan sampler dengan sudo jika diperlukan (vcgencmd butuh root)
            # Jika tidak ingin sudo, hapus 'sudo' dan pastikan user punya akses.
            sudo "$SAMPLER_SCRIPT" "$SYS_OUT" "$SAMPLE_INTERVAL" &
            SAMPLER_PID=$!
            echo "[SAMPLER] PID = $SAMPLER_PID"

            # =========================
            # IPERF3 (dengan timeout)
            # =========================
            echo "[i] iperf3 start"
            IPERF_TIMEOUT=$((D + 30))

            timeout -k 5 "$IPERF_TIMEOUT" \
            iperf3 -c "$TARGET" -P "$P" -t "$D" --json \
            > "results/$MODE/$LEVEL/iperf_$i.json"

            if [ $? -ne 0 ]; then
                echo "[WARN] iperf gagal, mencoba ulang..."
                sleep 3
                timeout -k 5 "$IPERF_TIMEOUT" \
                iperf3 -c "$TARGET" -P "$P" -t "$D" --json \
                > "results/$MODE/$LEVEL/iperf_${i}_retry.json"
            fi

            # =========================
            # HENTIKAN SAMPLER
            # =========================
            if [ -n "$SAMPLER_PID" ]; then
                echo "[SAMPLER] Menghentikan sampler (PID $SAMPLER_PID)"
                kill "$SAMPLER_PID" 2>/dev/null
                wait "$SAMPLER_PID" 2>/dev/null
                SAMPLER_PID=""
            fi

            # =========================
            # PING
            # =========================
            echo "[i] ping start"
            PING_TIMEOUT=$((PING_COUNT + 15))
            timeout -k 3 -s INT "$PING_TIMEOUT" \
            ping -c "$PING_COUNT" -W 2 "$TARGET" \
            > "results/$MODE/$LEVEL/ping_$i.txt"

            # =========================
            # MTR
            # =========================
            echo "[i] mtr start"
            MTR_TIMEOUT=$((MTR_COUNT + 20))
            timeout -k 3 -s INT "$MTR_TIMEOUT" \
            mtr -r -c "$MTR_COUNT" "$TARGET" \
            > "results/$MODE/$LEVEL/mtr_$i.txt"

            # =========================
            # JEDA ANTAR PENGULANGAN
            # =========================
            sleep 2
        done
    done
}

# =========================
# MENU PILIHAN MODE
# =========================
echo ""
echo "Select mode:"
echo "1) Baseline (LAN)"
echo "2) WireGuard"
echo "3) OpenVPN"
read -r MODE

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
