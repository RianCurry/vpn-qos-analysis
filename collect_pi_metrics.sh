#!/bin/bash

OUTPUT="$1"
INTERVAL="$2"

if [ -z "$OUTPUT" ] || [ -z "$INTERVAL" ]; then
    echo "Usage: $0 <output_file> <interval_sec>"
    exit 1
fi

# Tulis header
echo "timestamp,cpu_percent,ram_used_mb,temp_c" > "$OUTPUT"

# Fungsi untuk mendapatkan CPU usage (%) dengan 2 desimal dari /proc/stat
get_cpu() {
    # Baca /proc/stat baris pertama (cpu total)
    local stat1=$(cat /proc/stat | head -1)
    # Ambil nilai user, nice, system, idle, iowait, irq, softirq, steal
    local user=$(echo $stat1 | awk '{print $2}')
    local nice=$(echo $stat1 | awk '{print $3}')
    local system=$(echo $stat1 | awk '{print $4}')
    local idle=$(echo $stat1 | awk '{print $5}')
    local iowait=$(echo $stat1 | awk '{print $6}')
    local irq=$(echo $stat1 | awk '{print $7}')
    local softirq=$(echo $stat1 | awk '{print $8}')
    local steal=$(echo $stat1 | awk '{print $9}')
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local idle_all=$((idle + iowait))
    # Sleep sebentar untuk mendapatkan delta
    sleep $INTERVAL
    local stat2=$(cat /proc/stat | head -1)
    local user2=$(echo $stat2 | awk '{print $2}')
    local nice2=$(echo $stat2 | awk '{print $3}')
    local system2=$(echo $stat2 | awk '{print $4}')
    local idle2=$(echo $stat2 | awk '{print $5}')
    local iowait2=$(echo $stat2 | awk '{print $6}')
    local irq2=$(echo $stat2 | awk '{print $7}')
    local softirq2=$(echo $stat2 | awk '{print $8}')
    local steal2=$(echo $stat2 | awk '{print $9}')
    local total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
    local idle_all2=$((idle2 + iowait2))
    local delta_total=$((total2 - total))
    local delta_idle=$((idle_all2 - idle_all))
    # Persentase penggunaan = (delta_total - delta_idle) * 100 / delta_total
    if [ $delta_total -eq 0 ]; then
        echo "0.00"
    else
        usage=$(echo "scale=2; ($delta_total - $delta_idle) * 100 / $delta_total" | bc)
        echo "$usage"
    fi
}

# Fungsi untuk mendapatkan RAM used (MB) dengan 2 desimal dari /proc/meminfo
get_ram() {
    local total=$(grep MemTotal /proc/meminfo | awk '{print $2}')  # dalam kB
    local available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')  # dalam kB
    local used=$((total - available))  # dalam kB
    # Konversi ke MB dengan 2 desimal
    echo "scale=2; $used / 1024" | bc
}

# Fungsi untuk mendapatkan suhu dengan 2 desimal
get_temp() {
    local temp=""
    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.2f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    if [ -z "$temp" ] || [ "$temp" = "0.00" ]; then
        raw=$(/usr/bin/vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 | cut -d"'" -f1)
        if [ -n "$raw" ] && [ "$raw" != "0.0" ]; then
            temp=$(printf "%.2f" "$raw" 2>/dev/null)
        fi
    fi
    echo "${temp:-0.00}"
}

# Loop utama
while true; do
    # Ambil timestamp
    ts=$(date +%s)
    # Dapatkan CPU (fungsi ini sudah sleep di dalamnya, jadi total sleep = INTERVAL)
    cpu=$(get_cpu)
    # Dapatkan RAM
    ram=$(get_ram)
    # Dapatkan suhu
    temp=$(get_temp)
    # Tulis ke file
    echo "$ts,$cpu,$ram,$temp" >> "$OUTPUT"
    # Karena get_cpu sudah sleep, tidak perlu sleep lagi; tapi kita perlu memastikan interval total tepat.
    # Jika get_cpu menggunakan sleep $INTERVAL, maka total waktu per iterasi = INTERVAL + overhead.
    # Untuk presisi, kita bisa mengatur sleep tambahan jika perlu, tapi di sini kita biarkan.
done