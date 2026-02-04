#!/bin/bash

echo "   ЗАПУСК ТЕСТОВ ДЛЯ TagsWriter "
echo ""



EXCEL_FILE="results.csv"
echo "Тест;Тегов;Период(мс);Время(сек);Пакетов;Записей;Время_общее(мс);Скорость(зап/сек);Среднее_время(мс);Превышение" > $EXCEL_FILE


TESTS=(
    "1000 100 0"
    "500 100 5" 
    "1000 100 5"
    "1000 200 5"
    "5000 500 10"
    "10000 1000 15"
    
)

test_num=1

for test in "${TESTS[@]}"; do
    echo "Тест $test_num: $test"
    
    
    read tags period time <<< "$test"
    
    
    LOG_FILE="test_${tags}_${period}_${time}.log"
    
    
    echo "Запуск: ./build/TagsWriter $tags $period $time"
    ./build/TagsWriter $tags $period $time > "$LOG_FILE" 2>&1
    

    COUNT_TAGS=$(tail -10 "$LOG_FILE" | grep "COUNT_TAGS=" | tail -1 | cut -d'=' -f2)
    PERIOD_MS=$(tail -10 "$LOG_FILE" | grep "PERIOD_MS=" | tail -1 | cut -d'=' -f2)
    WORK_TIME_SEC=$(tail -10 "$LOG_FILE" | grep "WORK_TIME_SEC=" | tail -1 | cut -d'=' -f2)
    TOTAL_PACKETS=$(tail -10 "$LOG_FILE" | grep "TOTAL_PACKETS=" | tail -1 | cut -d'=' -f2)
    TOTAL_RECORDS=$(tail -10 "$LOG_FILE" | grep "TOTAL_RECORDS=" | tail -1 | cut -d'=' -f2)
    TOTAL_TIME_MS=$(tail -10 "$LOG_FILE" | grep "TOTAL_TIME_MS=" | tail -1 | cut -d'=' -f2)
    
    
    if [[ -n "$WORK_TIME_SEC" && "$WORK_TIME_SEC" -gt 0 ]]; then
        SPEED=$((TOTAL_RECORDS / WORK_TIME_SEC))
    else
        SPEED=0
    fi
   
    if [[ -n "$TOTAL_PACKETS" && "$TOTAL_PACKETS" -gt 0 ]]; then
        AVG_TIME=$((TOTAL_TIME_MS / TOTAL_PACKETS))
    else
        AVG_TIME=0
    fi
    
    
    if [[ $AVG_TIME -gt $period ]]; then
        EXCEED="ДА (+$((AVG_TIME - period))мс)"
    else
        EXCEED="НЕТ"
    fi
    
 
    echo "$test_num;$tags;$period;$WORK_TIME_SEC;$TOTAL_PACKETS;$TOTAL_RECORDS;$TOTAL_TIME_MS;$SPEED;$AVG_TIME;$EXCEED" >> $EXCEL_FILE
    
    echo "  Успешно! Пакетов: $TOTAL_PACKETS, Скорость: $SPEED зап/сек"
    echo ""
    
    sleep 1
    test_num=$((test_num + 1))
done

echo "ТЕСТЫ ЗАВЕРШЕНЫ "
