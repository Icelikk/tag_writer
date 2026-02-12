#!/bin/bash

if [ -z "$1" ]; then
    echo "Ошибка: не указан лог-файл."
    echo "Использование: $0 <лог-файл>"
    exit 1
fi

LOG_FILE="$1"

grep "Пакет записан за" "$LOG_FILE" | awk '{print $9}' | sort -n | awk '
{
    arr[NR] = $1
    sum += $1
}
END {
    if (NR == 0) {
        print "Нет данных о времени пакетов."
        exit
    }
    printf "Всего пакетов: %d\n", NR
    printf "Минимальное:   %d мс\n", arr[1]
    printf "Максимальное:  %d мс\n", arr[NR]
    printf "Среднее:       %.2f мс\n", sum / NR
    printf "\nПроцентили:\n"
    printf "P5:  %d мс\n", arr[int(NR * 0.05) + 1]
    printf "P10: %d мс\n", arr[int(NR * 0.10) + 1]
    printf "P25: %d мс\n", arr[int(NR * 0.25) + 1]
    printf "P50: %d мс\n", arr[int(NR * 0.50) + 1]
    printf "P75: %d мс\n", arr[int(NR * 0.75) + 1]
    printf "P90: %d мс\n", arr[int(NR * 0.90) + 1]
    printf "P95: %d мс\n", arr[int(NR * 0.95) + 1]
}'