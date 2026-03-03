Черновой вариант

Краткая инстркуция:
1)Клонируйте репзиторий в удобное место
git clone https://github.com/Icelikk/tag_writer.git
cd tag_writer

2) Для БД по умолчанию используются следующие значения
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=Guts

3)Запускаете конетйнеры
docker-compose up -d

контейнер dev1_pg (PostgreSQL)
контейнер dev3_dev (среда разработки)
контейнер d2_app (скомпилированное приложение - просто пишет в бд, без всего)

Для проверки работоспособности можно сразу отключить d2-app
docker stop d2_app

Зайти в dev3-dev с помощью

docker exec -it dev3_dev bash

и запустить там auto_test.sh 

./auto_test.sh
Если лог создаётся и пишется, значит програма работает

Второй вариант, при рабочем контейнере d2_app:
зайди в dev
docker-compose exec dev bash 
либо docker exec -it dev2_app bash
И выполнить 2 раза
psql $DATABASE_URL -c "SELECT count(*) FROM aboba;"
Если счетчик растёт - значит программа пишет

