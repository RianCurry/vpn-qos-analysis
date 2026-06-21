#!/bin/bash

OUTPUT="$1"
INTERVAL="$2"

if [ -z "$OUTPUT" ] || [ -z "$INTERVAL" ]; then
    echo "Usage: $0 <output_file> <interval_sec>"
    exit 1
fi

# Tulis header
echo "timestamp,cpu_percent,ram_used_mb,temp_c" > "$OUTPUT"

# Fungsi mendapatkan CPU usage (%) dengan 2 desimal
get_cpu() {
    # Metode 1: top (format umum)
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if [ -n "$cpu" ]; then
        printf "%.2f" "$cpu"
        return
    fi
    # Metode 2: vmstat (jika top gagal)
    cpu=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
    if [ -n "$cpu" ]; then
        printf "%.2f" "$cpu"
        return
    fi
    # Metode 3: /proc/stat (paling akurat)
    local cpu_line=$(grep '^cpu ' /proc/stat)
    if [ -n "$cpu_line" ]; then
        # Hitung idle total dari /proc/stat
        local user nice system idle iowait irq softirq steal guest guest_nice
        read -r _ user nice system idle iowait irq softirq steal guest guest_nice <<< "$cpu_line"
        local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        local usage=$(echo "scale=2; (1 - $idle / $total) * 100" | bc)
        printf "%.2f" "$usage"
        return
    fi
    echo "0.00"
}

# Fungsi mendapatkan RAM used (MB) dengan 2 desimal
get_ram() {
    local ram=$(free -m | awk '/Mem:/ {print $3}')
    if [ -n "$ram" ]; then
        printf "%.2f" "$ram"
        return
    fi
    # Fallback: /proc/meminfo
    local total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    local avail=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    if [ -n "$total" ] && [ -n "$avail" ]; then
        local used=$(( (total - avail) / 1024 )) # konversi ke MB (kira-kira)
        printf "%.2f" "$used"
        return
    fi
    echo "0.00"
}

# Fungsi mendapatkan suhu (°C) dengan 2 desimal
get_temp() {
    local temp=""
    # Prioritas: /sys/class/thermal/thermal_zone0/temp
    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(awk '{printf "%.2f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    fi
    # Fallback: vcgencmd (Raspberry Pi)
    if [ -z "$temp" ] || [ "$temp" = "0.00" ]; then
        local raw=$(/usr/bin/vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 | cut -d"'" -f1)
        if [ -n "$raw" ] && [ "$raw" != "0.0" ]; then
            temp=$(printf "%.2f" "$raw")
        fi
    fi
    # Jika semua gagal
    echo "${temp:-0.00}"
}

while true; do
    CPU=$(get_cpu)
    RAM=$(get_ram)
    TEMP=$(get_temp)
    echo "$(date +%s),$CPU,$RAM,$TEMP" >> "$OUTPUT"
    sleep "$INTERVAL"
done