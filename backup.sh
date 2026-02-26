#!/bin/bash

SOURCE_OG="$1"
SOURCE_COP="$2"

echo "Копируем из $SOURCE_OG"
echo " Вставляем в папку $SORCE_COP"

if [ -z "$SOURCE_OG" ]; then
    echo "Нет аргументов на вход!Укажите путь"
    exit 1
fi 

if [ -z "$SOURCE_COP" ]; then
    mkdir -p "$SOURCE_COP"
fi 

result_file="log.csv"
CURRENT_DATE=$(date +%Y-%m-%d)

cp -r "$SOURCE_OG" "$SOURCE_COP"
echo "$CURRENT_DATE" > "$result_file"