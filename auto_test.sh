#!/bin/bash

PERIODS=(100 80 60 40 20)
TAGS_LIST=(100 1000 2000 3000 4000 5000 10000)
DURATION=60        
THRESHOLD=10
DB_NAME="Guts"
DB_USER="postgres"
DB_PASS="mark28102003"
DB_HOST="localhost"

opt_results="optimization_results.csv"
echo "period_ms,max_tags,size_bytes" > "$opt_results"
all_results="results.csv"
echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,table_size_bytes,exceed_count" > "$all_results"


for period in "${PERIODS[@]}"; do
    echo "Тестирование периода $period мс"
    max_success=0   
    success_found=false

    for tags in "${TAGS_LIST[@]}"; do
        echo "  Запуск с размером пакета $tags"
        
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "TRUNCATE TABLE aboba;" 2>&1 > /dev/null
        if [ $? -ne 0 ]; then
            echo "    Ошибка очистки БД"
            continue
        fi

        > TagsWriter.log

        log_file="test_p${period}_t${tags}.log"
        

        timeout $((DURATION + 10)) ./build/TagsWriter "$tags" "$period" "$DURATION" > "$log_file" 2>&1
        exit_code=$?
        
        if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then
            echo "    Ошибка выполнения (код $exit_code), может программа уже упала :) "
            break
        fi
        
        exceed_count=$(grep -c "Превышение времени на" TagsWriter.log)
        echo "    Превышений: $exceed_count"
        
        size_bytes=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT pg_total_relation_size('aboba');" 2>/dev/null)
       
        echo "TABLE_SIZE=$size_bytes">>"$log_file"

        count_tags=$(grep -oP 'COUNT_TAGS=\K\d+' "$log_file" | head -1)
        period_ms=$(grep -oP 'PERIOD_MS=\K\d+' "$log_file" | head -1)
        work_time_sec=$(grep -oP 'WORK_TIME_SEC=\K\d+' "$log_file" | head -1)
        total_packets=$(grep -oP 'TOTAL_PACKETS=\K\d+' "$log_file" | head -1)
        total_records=$(grep -oP 'TOTAL_RECORDS=\K\d+' "$log_file" | head -1)
        total_time_ms=$(grep -oP 'TOTAL_TIME_MS=\K\d+' "$log_file" | head -1)
        time_min=$(grep -oP 'TIME_MIN=\K\d+' "$log_file" | head -1)
        time_max=$(grep -oP 'TIME_MAX=\K\d+' "$log_file" | head -1)
        time_avg=$(grep -oP 'TIME_AVG=\K[\d.]+' "$log_file" | head -1)
        time_stddev=$(grep -oP 'TIME_STDDEV=\K[\d.]+' "$log_file" | head -1)

        echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$size_bytes,$exceed_count" >> "$all_results"

        if [ -s TagsWriter.log ]; then
    
            percentiles_file="percentiles_p${period}_t${tags}.txt"
            ./percentiles.sh TagsWriter.log > "$percentiles_file"
        fi
        if [ "$exceed_count" -gt "$THRESHOLD" ]; then
            echo "    Порог превышен "
            break
        else
            max_success=$tags
            success_found=true
        fi
    done

    #size_bytes=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT pg_total_relation_size('aboba');" 2>/dev/null)

    if [ "$success_found" = true ]; then
        echo "Для периода $period максимальный проходной размер: $max_success"
        echo "$period,$max_success,$size_bytes" >> "$opt_results"
    else
        echo "Для периода $period нет успешных тестов "
        echo "$period,0,$size_bytes" >> "$opt_results"
    fi
done

echo "Готово." 