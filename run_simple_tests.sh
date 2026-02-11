#!/bin/bash

echo "   ЗАПУСК ТЕСТОВ ДЛЯ TagsWriter "
echo ""



EXCEL_FILE="results.csv"
echo "Тест;Тегов;Период(мс);Время(сек);Пакетов;Записей;Время_общее(мс);Скорость(зап/сек);Среднее_время(мс);Превышение;Мин время записи;Макс время записи;Средневадратичное" > $EXCEL_FILE


TESTS=(
    "10000 1000 1800"
    
)

test_num=1

for test in "${TESTS[@]}"; do
    echo "Тест $test_num: $test"
    
    
    read tags period time <<< "$test"
    
    
    LOG_FILE="test_${tags}_${period}_${time}.log"
    
    
    echo "Запуск: ./TagsWriter $tags $period $time"
    ./build/TagsWriter $tags $period $time > "$LOG_FILE" 2>&1
    

    COUNT_TAGS=$(tail -10 "$LOG_FILE" | grep "COUNT_TAGS=" | tail -1 | cut -d'=' -f2)
    PERIOD_MS=$(tail -10 "$LOG_FILE" | grep "PERIOD_MS=" | tail -1 | cut -d'=' -f2)
    WORK_TIME_SEC=$(tail -10 "$LOG_FILE" | grep "WORK_TIME_SEC=" | tail -1 | cut -d'=' -f2)
    TOTAL_PACKETS=$(tail -10 "$LOG_FILE" | grep "TOTAL_PACKETS=" | tail -1 | cut -d'=' -f2)
    TOTAL_RECORDS=$(tail -10 "$LOG_FILE" | grep "TOTAL_RECORDS=" | tail -1 | cut -d'=' -f2)
    TOTAL_TIME_MS=$(tail -10 "$LOG_FILE" | grep "TOTAL_TIME_MS=" | tail -1 | cut -d'=' -f2)
    TIME_MAX=$(tail -10 "$LOG_FILE"| grep "TIME_MAX=" | tail -1| cut -d'=' -f2)
    TIME_MIN=$(tail -10 "$LOG_FILE"| grep "TIME_MIN=" | tail -1| cut -d'=' -f2)
    TIME_STDDEV=$(tail -10 "$LOG_FILE"| grep "TIME_STDDEV" | tail -1| cut -d'=' -f2)
    AVG_TIME=$(grep "TIME_AVG=" "$LOG_FILE" | tail -1 | cut -d'=' -f2)

    if [[ -n "$WORK_TIME_SEC" && "$WORK_TIME_SEC" -gt 0 ]]; then
        SPEED=$((TOTAL_RECORDS / WORK_TIME_SEC))
    else
        SPEED=0
    fi
   
 
    
    
    if [[ $AVG_TIME -gt $period ]]; then
        EXCEED="ДА (+$((AVG_TIME - period))мс)"
    else
        EXCEED="НЕТ"
    fi
    
 
    echo "$test_num;$tags;$period;$WORK_TIME_SEC;$TOTAL_PACKETS;$TOTAL_RECORDS;$TOTAL_TIME_MS;$SPEED;$AVG_TIME;$EXCEED;$TIME_MIN;$TIME_MAX;$TIME_STDDEV" >> $EXCEL_FILE
    
    echo "  Успешно! Пакетов: $TOTAL_PACKETS, Скорость: $SPEED зап/сек"
    echo ""
    
    sleep 1
    test_num=$((test_num + 1))
done

echo "ТЕСТЫ ЗАВЕРШЕНЫ "
