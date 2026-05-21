#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
RESULTS_DIR="$PROJECT_ROOT/results"
BIN="$BUILD_DIR/tag_writer"

mkdir -p "$RESULTS_DIR"

PERIODS=(100 80 60 40 20)
TAGS_LIST=(100 1000 2000 3000 4000 5000 10000)
DURATION=5
THRESHOLD=10

DB_NAME="Guts"
DB_USER="postgres"
DB_PASS="postgres"
DB_HOST="db"

opt_results="$RESULTS_DIR/optimization_results.csv"
all_results="$RESULTS_DIR/results.csv"

echo "period_ms,max_tags,size_bytes" > "$opt_results"
echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,gen_min,gen_max,gen_avg,gen_stddev,insert_min,insert_max,insert_avg,insert_stddev,total_insert_ms,table_size_bytes,exceed_count,p5,p10,p25,p50,p75,p90,p95" > "$all_results"

calculate_percentiles() {
    local logfile="$1"
    if [ ! -f "$logfile" ]; then
        echo "0 0 0 0 0 0 0"
        return
    fi
    grep -oP 'Пакетная вставка за\s+\K\d+' "$logfile" 2>/dev/null | sort -n | awk '{arr[NR]=$1} function get_p(p, idx) {idx=int(NR*p/100)+1; if(idx>NR)idx=NR; if(idx<1)idx=1; return arr[idx]} END {if(NR==0){print "0 0 0 0 0 0 0";exit} printf "%d %d %d %d %d %d %d", get_p(5),get_p(10),get_p(25),get_p(50),get_p(75),get_p(90),get_p(95)}'
}

for period in "${PERIODS[@]}"; do
    echo "Тестирование периода $period мс"
    max_success=0
    success_found=false

    for tags in "${TAGS_LIST[@]}"; do
        echo "  Запуск с размером пакета $tags"

        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
            -c "TRUNCATE TABLE guts;" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "  Ошибка очистки БД, пропускаем"
            continue
        fi

        > "$PROJECT_ROOT/TagsWriter.log"

        log_file="$RESULTS_DIR/test_p${period}_t${tags}.log"

        timeout $((DURATION + 10)) "$BIN" "$tags" "$period" "$DURATION" > "$log_file" 2>&1
        exit_code=$?

        if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then
            echo "  Ошибка выполнения, код: $exit_code"
            break
        fi

        exceed_count=$(grep -c "Превышение времени на" "$PROJECT_ROOT/TagsWriter.log" 2>/dev/null)
        exceed_count=${exceed_count:-0}
        echo "  Превышений: $exceed_count"

        size_bytes=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
            -t -A -c "SELECT pg_total_relation_size('guts');" 2>/dev/null)
        size_bytes=${size_bytes:-0}
        echo "TABLE_SIZE=$size_bytes" >> "$log_file"

        total_packets=$(grep -oP 'TOTAL_PACKETS=\K\d+' "$log_file" | head -1)
        total_records=$(grep -oP 'TOTAL_RECORDS=\K\d+' "$log_file" | head -1)
        total_time_ms=$(grep -oP 'TOTAL_TIME_MS=\K\d+' "$log_file" | head -1)
        time_min=$(grep -oP 'TIME_MIN=\K\d+' "$log_file" | head -1)
        time_max=$(grep -oP 'TIME_MAX=\K\d+' "$log_file" | head -1)
        time_avg=$(grep -oP 'TIME_AVG=\K[\d.]+' "$log_file" | head -1)
        time_stddev=$(grep -oP 'TIME_STDDEV=\K[\d.]+' "$log_file" | head -1)
        gen_min=$(grep -oP 'GEN_TIME_MIN=\K\d+' "$log_file" | head -1)
        gen_max=$(grep -oP 'GEN_TIME_MAX=\K\d+' "$log_file" | head -1)
        gen_avg=$(grep -oP 'GEN_TIME_AVG=\K[\d.]+' "$log_file" | head -1)
        gen_stddev=$(grep -oP 'GEN_TIME_STDDEV=\K[\d.]+' "$log_file" | head -1)
        insert_min=$(grep -oP 'INSERT_TIME_MIN=\K\d+' "$log_file" | head -1)
        insert_max=$(grep -oP 'INSERT_TIME_MAX=\K\d+' "$log_file" | head -1)
        insert_avg=$(grep -oP 'INSERT_TIME_AVG=\K[\d.]+' "$log_file" | head -1)
        insert_stddev=$(grep -oP 'INSERT_TIME_STDDEV=\K[\d.]+' "$log_file" | head -1)
        total_insert_ms=$(grep -oP 'TOTAL_INSERT_MS=\K\d+' "$log_file" | head -1)

        read p5 p10 p25 p50 p75 p90 p95 <<< $(calculate_percentiles "$PROJECT_ROOT/TagsWriter.log")
        echo "  Процентили: P5=$p5 P10=$p10 P25=$p25 P50=$p50 P75=$p75 P90=$p90 P95=$p95"

        row="$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms"
        row="$row,$time_min,$time_max,$time_avg,$time_stddev"
        row="$row,$gen_min,$gen_max,$gen_avg,$gen_stddev"
        row="$row,$insert_min,$insert_max,$insert_avg,$insert_stddev,$total_insert_ms"
        row="$row,$size_bytes,$exceed_count"
        row="$row,$p5,$p10,$p25,$p50,$p75,$p90,$p95"
        echo "$row" >> "$all_results"

        if [ "$exceed_count" -gt "$THRESHOLD" ]; then
            echo "  Порог превышен, остановка для периода $period"
            break
        else
            max_success=$tags
            success_found=true
        fi
    done

    if [ "$success_found" = true ]; then
        echo "Период $period: максимальный проходной размер $max_success"
        echo "$period,$max_success,$size_bytes" >> "$opt_results"
    else
        echo "Период $period: нет успешных тестов"
        echo "$period,0,0" >> "$opt_results"
    fi
done

echo "Готово. Результаты в $RESULTS_DIR"