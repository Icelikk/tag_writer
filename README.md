# PostgreSQL Tag Writer Benchmark

Контейнеризированный стенд для нагрузочного тестирования PostgreSQL при потоковой записи данных.

**Требования:** Docker Engine ≥ 20.10, Docker Compose ≥ 2.0, Git.

```bash
git clone https://github.com/Icelikk/tag_writer.git
cd tag_writer
docker-compose up -d --build
docker stop d2_app 
```
d2_app сразу начинает писать в PG при запуске,поэтому лучше его остановить, если вы хотите зайти в dev3_dev

Подключитесь к контейнеру и запустите тест:

```bash
docker exec -it dev3_dev bash
cd /app

./auto_test.sh              # полный цикл тестирования
```

Результаты сохраняются в папке `/app` внутри контейнера в виде CSV-файлов.

---

## ⚠️ Важно при использовании нескольких проектов

Если на этом же сервере запущен другой проект — у него может быть свой контейнер `postgres` на порту `5432`. При попытке поднять этот проект получишь ошибку конфликта портов или имён контейнеров.

**Перед запуском остановите старый проект:**

```bash
cd /путь/к/другому/проекту
docker-compose down
```

**Если нужно запустить оба проекта одновременно** — измените порт PostgreSQL в `docker-compose.yml`:

```yaml
db:
  ports:
    - "5433:5432"   # внешний порт 5433, внутренний остаётся 5432
```

И имя контейнера:

```yaml
db:
  container_name: dev1_pg_tagwriter   # уникальное имя
```

> Внутри контейнеров общение идёт по внутренним именам сервисов (`db`), так что менять строки подключения в коде не нужно.

---

1. **TagsWriter** — генерирует пакеты данных и записывает в PostgreSQL через `pqxx::stream_to` 
2. **auto_test.sh** — цикл тестов по всем периодам и размерам пакетов, собирает метрики, очищает таблицу между тестами
3. **percentiles.sh** — анализирует лог и вычисляет процентильное распределение задержек (P5, P10, P25, P50, P75, P90, P95)
4. **d2_app** — контейнер для непрерывной записи

---

## Структура проекта

```
.
├── dockerfile.dev            # Образ для разработки 
├── dockerfile.app            # Образ для app
├── docker-compose.yml        
├── CMakeLists.txt            
├── src/
│   └── test_connection.cpp   # Исходник TagsWriter
├── auto_test.sh              # Скрипт автоматического тестирования
├── percentiles.sh            # Анализ процентилей из лога
└── init.sql                  # Инициализация схемы (таблица aboba, индексы)
```

> Бинарник `TagsWriter` собирается при сборке образа и кладётся в `/usr/local/bin/`.

---

## Параметры тестирования

Все параметры задаются в `auto_test.sh`:

| Параметр     | Описание                                          | Значение по умолчанию |
|--------------|---------------------------------------------------|-----------------------|
| `PERIODS`    | Период, с которым программа записывает пакеты данных                       | `(100 80 60 40 20)`   |
| `TAGS_LIST`  | Размеры пакетов (количество записей за цикл)      | `(100 1000 2000 3000 4000 5000 10000)` |
| `DURATION`   | Длительность одного теста (сек)                   | `60`                  |
| `THRESHOLD`  | Допустимое количество превышений периода          | `10`                  |

В `run_simple_tests.sh`:

| Параметр     | Описание                                          |
|--------------|---------------------------------------------------|
| `TESTS`      | Массив тестов в формате `"tags period time"`     |

Пример: `"5000 100 300"` — 5000 записей в пакете, период 100 мс, длительность 300 сек.

---

## Выходные данные

После запуска в `/app` появятся:

| Файл                             | Содержимое                                                                                           |
|----------------------------------|------------------------------------------------------------------------------------------------------|
| `results.csv`                    | Детальная статистика по каждому прогону: период, размер пакета, задержки, превышения, размер таблицы |
| `optimization_results.csv`       | Максимальный проходной размер пакета для каждого периода                                             |
| `percentiles_p{period}_t{tags}.txt` | Процентильное распределение задержек для конкретного теста                                        |
| `TagsWriter.log`                 | Лог записи (plog, уровень debug)                                                                     |
| `test_p{period}_t{tags}.log`     | Stdout каждого теста (финальные метрики)                                                             |

Пример строки в `results.csv`:

```
period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,table_size_bytes,exceed_count
100,1000,60,598,598000,60012,15,89,24.3,8.7,52428800,3
```

Пример вывода `percentiles.sh`:

```
Всего пакетов: 598
Минимальное:   15 мс
Максимальное:  89 мс
Среднее:       24.30 мс

Процентили:
P5:  18 мс
P10: 19 мс
P25: 21 мс
P50: 23 мс
P75: 26 мс
P90: 31 мс
P95: 38 мс
```

---

## Управление контейнерами

**Первый запуск / пересборка образа:**

```bash
docker-compose down
docker-compose up -d --build
```

**Подключение к контейнеру разработки:**

```bash
docker exec -it dev3_dev bash
```

**Просмотр логов:**

```bash
docker-compose logs -f dev
docker-compose logs -f app
```

**Очистка таблицы вручную:**

```bash
docker exec -it dev3_dev psql -h db -U postgres -d Guts -c "TRUNCATE TABLE aboba;"
```

**Проверка размера таблицы:**

```bash
docker exec -it dev3_dev psql -h db -U postgres -d Guts -c "SELECT pg_size_pretty(pg_total_relation_size('aboba'));"
```

## Особенности реализации


```sql
CREATE UNLOGGED TABLE aboba (
    id int2 NOT NULL,
    q int2 NOT NULL,
    v float4 NOT NULL,
    t int8 NOT NULL
) WITH (fillfactor = 95);

CREATE INDEX idx_aboba_id ON aboba USING btree (id);
CREATE INDEX idx_aboba_t_brin ON aboba USING brin (t) WITH (pages_per_range = 32);
```

- **UNLOGGED** — не пишется в WAL, быстрее вставка 
- **fillfactor = 95** — резервирует 5% места на странице для обновлений
- **BRIN индекс на timestamp** — компактный индекс для монотонно растущих данных

### Механизм записи

```cpp
pqxx::stream_to stream(transaction, "aboba");
for (int i = 0; i < count_tags; i++) {
    stream << std::make_tuple(id, q, v, timestamp);
}
stream.complete();
transaction.commit();
```

Использует протокол `COPY` — самый быстрый способ массовой вставки в PostgreSQL.
