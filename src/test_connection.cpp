#include <iostream>
#include <chrono>
#include <pqxx/pqxx>
#include <random>
#include <plog/Log.h>
#include <plog/Initializers/RollingFileInitializer.h>
#include <tuple>
#include <thread>
#include <cstdint>
#include <cmath>
#include <vector>

int main(int argc, char* argv[]) {
    plog::init(plog::debug, "/app/TagsWriter.log");

    std::string conn_info =
        "host=db "
        "dbname=Guts "
        "user=postgres "
        "password=postgres";

    int period_ms  = 100;
    int count_tags = 1000;
    int work_time  = 0;

    if (argc >= 2) count_tags = std::stoi(argv[1]);
    if (argc >= 3) period_ms  = std::stoi(argv[2]);
    if (argc >= 4) work_time  = std::stoi(argv[3]);

    PLOGI << "Записей в пакете: " << count_tags;
    PLOGI << "Период цикла = "    << period_ms  << " мс";
    PLOGI << "Время работы = "    << work_time  << " с";

    int64_t gen_min = 10000, gen_max = 0;
    double  gen_total = 0,   gen_sum_sq = 0;

    int64_t insert_min = 10000, insert_max = 0;
    double  insert_total = 0,   insert_sum_sq = 0;

    int64_t total_min = 10000, total_max = 0;
    double  total_time = 0,    total_sum_sq = 0;

    int packet_number      = 0;
    int reconnect_attempt  = 0;
    const int MAX_RECONNECT = 5;
    bool connected         = false;

    auto program_start = std::chrono::steady_clock::now();

    std::random_device rd;
    std::mt19937 gen_rng(rd());
    std::uniform_int_distribution<int16_t> dis_i(1, 20000);
    std::uniform_real_distribution<float>  dis_r(1.0f, 1000.0f);

    std::vector<std::tuple<uint32_t, int16_t, float, int64_t>> buffer;

    while (!connected && reconnect_attempt < MAX_RECONNECT) {
        try {
            PLOGI << "Попытка подключения к БД " << (reconnect_attempt + 1);
            pqxx::connection db(conn_info);

            if (!db.is_open()) {
                PLOGE << "Не удалось открыть соединение";
                reconnect_attempt++;
                continue;
            }

            PLOGI << "Успешное подключение к " << db.dbname();

            while (true) {

                if (work_time > 0) {
                    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                        std::chrono::steady_clock::now() - program_start).count();
                    if (elapsed >= work_time) break;
                }

                packet_number++;
                PLOGI << "Пакет номер " << packet_number;

                auto packet_start = std::chrono::steady_clock::now();

                auto now = std::chrono::system_clock::now();
                int64_t timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                    now.time_since_epoch()).count();

                auto gen_start = std::chrono::steady_clock::now();

                buffer.clear();
                buffer.reserve(count_tags);
                for (int i = 0; i < count_tags; ++i) {
                    uint32_t id = static_cast<uint32_t>(
                        (packet_number * count_tags + i) % 32768);
                    int16_t  q  = dis_i(gen_rng);
                    float    v  = dis_r(gen_rng);
                    buffer.emplace_back(id, q, v, timestamp);
                }

                auto gen_dur = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - gen_start).count();

                PLOGI << "Генерация данных за " << gen_dur << " мс";

                if (gen_dur < gen_min) gen_min = gen_dur;
                if (gen_dur > gen_max) gen_max = gen_dur;
                gen_total  += gen_dur;
                gen_sum_sq += static_cast<double>(gen_dur) * gen_dur;

                auto insert_start = std::chrono::steady_clock::now();

                bool   insert_ok    = false;
                int    insert_retry = 0;
                const int MAX_RETRY = 3;

                while (!insert_ok && insert_retry < MAX_RETRY) {
                    try {
                        pqxx::work txn(db);
                        pqxx::stream_to stream(txn, "Guts");

                        for (const auto& row : buffer) {
                            stream << row;
                        }

                        stream.complete();
                        txn.commit();
                        insert_ok = true;

                    } catch (const pqxx::broken_connection& e) {
                        insert_retry++;
                        PLOGW << "Обрыв соединения при вставке. Попытка "
                              << insert_retry << ": " << e.what();

                        if (insert_retry < MAX_RETRY) {
                            std::this_thread::sleep_for(std::chrono::seconds(1));
                            try {
                                db = pqxx::connection(conn_info);
                                if (db.is_open()) PLOGI << "Переподключение успешно";
                            } catch (const pqxx::broken_connection& e2) {
                                PLOGW << "Не удалось переподключиться: " << e2.what();
                            }
                        }
                    }
                }

                if (!insert_ok) {
                    PLOGE << "Не удалось вставить пакет после " << MAX_RETRY << " попыток";
                    break;
                }

                auto insert_dur = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - insert_start).count();

                PLOGI << "Пакетная вставка за " << insert_dur << " мс";

                if (insert_dur < insert_min) insert_min = insert_dur;
                if (insert_dur > insert_max) insert_max = insert_dur;
                insert_total  += insert_dur;
                insert_sum_sq += static_cast<double>(insert_dur) * insert_dur;

                auto total_dur = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - packet_start).count();

                PLOGI << "Пакет записан за " << total_dur << " мс";

                if (total_dur < total_min) total_min = total_dur;
                if (total_dur > total_max) total_max = total_dur;
                total_time   += total_dur;
                total_sum_sq += static_cast<double>(total_dur) * total_dur;

                if (total_dur < period_ms) {
                    PLOGD << "Ждем " << (period_ms - total_dur) << " мс";
                    std::this_thread::sleep_for(
                        std::chrono::milliseconds(period_ms - total_dur));
                } else {
                    PLOGW << "Превышение времени на " << (total_dur - period_ms) << " мс";
                }
            }

            connected = true;

        } catch (const pqxx::broken_connection& e) {
            reconnect_attempt++;
            PLOGE << "Ошибка подключения номер: " << reconnect_attempt;
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }

        if (!connected && reconnect_attempt < MAX_RECONNECT) {
            PLOGI << "Повторная попытка через 2 секунды...";
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }

    if (!connected) {
        PLOGE << "Не удалось подключиться к БД после " << MAX_RECONNECT << " попыток";
        return 1;
    }

    double gen_avg = 0, gen_stddev = 0;
    if (packet_number > 0) {
        gen_avg = gen_total / packet_number;
        double variance = (gen_sum_sq / packet_number) - (gen_avg * gen_avg);
        gen_stddev = (variance > 0) ? std::sqrt(variance) : 0.0;
    }

    double insert_avg = 0, insert_stddev = 0;
    if (packet_number > 0) {
        insert_avg = insert_total / packet_number;
        double variance = (insert_sum_sq / packet_number) - (insert_avg * insert_avg);
        insert_stddev = (variance > 0) ? std::sqrt(variance) : 0.0;
    }

    double total_avg = 0, total_stddev = 0;
    if (packet_number > 0) {
        total_avg = total_time / packet_number;
        double variance = (total_sum_sq / packet_number) - (total_avg * total_avg);
        total_stddev = (variance > 0) ? std::sqrt(variance) : 0.0;
    }

    auto program_end = std::chrono::steady_clock::now();
    auto run_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        program_end - program_start).count();

    std::cout << "COUNT_TAGS="    << count_tags                    << "\n";
    std::cout << "PERIOD_MS="     << period_ms                     << "\n";
    std::cout << "WORK_TIME_SEC=" << work_time                     << "\n";
    std::cout << "TOTAL_PACKETS=" << packet_number                 << "\n";
    std::cout << "TOTAL_RECORDS=" << (packet_number * count_tags)  << "\n";
    std::cout << "TOTAL_TIME_MS=" << run_ms                        << "\n";

    std::cout << "TIME_MIN="    << total_min    << "\n";
    std::cout << "TIME_MAX="    << total_max    << "\n";
    std::cout << "TIME_AVG="    << total_avg    << "\n";
    std::cout << "TIME_STDDEV=" << total_stddev << "\n";

    std::cout << "GEN_TIME_MIN="    << gen_min    << "\n";
    std::cout << "GEN_TIME_MAX="    << gen_max    << "\n";
    std::cout << "GEN_TIME_AVG="    << gen_avg    << "\n";
    std::cout << "GEN_TIME_STDDEV=" << gen_stddev << "\n";
        // Время вставки в постгрес
    std::cout << "INSERT_TIME_MIN="    << insert_min    << "\n";
    std::cout << "INSERT_TIME_MAX="    << insert_max    << "\n";
    std::cout << "INSERT_TIME_AVG="    << insert_avg    << "\n";
    std::cout << "INSERT_TIME_STDDEV=" << insert_stddev << "\n";
        //Время вставки за весь прогон
    std::cout << "TOTAL_INSERT_MS=" << static_cast<int64_t>(insert_total) << "\n";

    return 0;
}