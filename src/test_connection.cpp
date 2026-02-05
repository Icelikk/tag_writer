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

int main(int argc,char* argv[]) {
     plog::init(plog::debug, "TagsWriter.log");
    std::string conn_info = 
        "host=localhost "
        "dbname=Guts "
        "user=postgres "
        "password=mark28102003";
    int period_ms=100;
    int count_tags=1000;
    int work_time=0;    
    if (argc>=2){
        count_tags=std::stoi(argv[1]);
    }
   if (argc>=3){
    period_ms=std::stoi(argv[2]);
   }
   if (argc>=4){
    work_time=std::stoi(argv[3]);
   }
    bool connect=false;
    int reconnect_attempt=0;
    int  MAX_reconnect_count=5;
    auto programm_start_time=std::chrono::steady_clock::now();
    PLOGI<<"Записей в пакете: "<<count_tags<<std::endl;
    PLOGI<<"Перид цикла = "<<period_ms<<std::endl;
    int packet_number=0;
    int64_t time_min=10000;
    int64_t time_max=0;
    double total_time{0};
    double sum_sqrt{};
    while(!connect && reconnect_attempt<MAX_reconnect_count ){
        try {
            PLOGI<<"Попытка полключения к БД "<<(reconnect_attempt+1);
            pqxx::connection db(conn_info);
                
            if (db.is_open()) {
                PLOGI <<"Усепшное подключение" << db.dbname() << std::endl;
            
                std::random_device rd;
                std::mt19937 gen(rd());
                std::uniform_int_distribution<>dis_i(1,20000);
                std::uniform_real_distribution<>dis_r(1,1000);

                
            
                while(true){
                    if(work_time>0){
                        auto current_time=std::chrono::steady_clock::now();
                        auto elapsed_time=std::chrono::duration_cast<std::chrono::seconds>(current_time-programm_start_time).count();
                        if (elapsed_time>=work_time){
                            break;
                        }
                    }
                    
                    packet_number++;
                    PLOGI<<"Пакет номер "<<packet_number;
                    
                    auto start_time=std::chrono::steady_clock::now();
                    auto now=std::chrono::system_clock::now();
                    auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now.time_since_epoch()  
                    ).count();
                    
                    bool packet=false;
                    int packet_retry_count=0;
                    int MAX_packet_retry=3;
                    
                    while(!packet && packet_retry_count<MAX_packet_retry){
                        try{
                            pqxx::work transaction(db);
                            pqxx::stream_to stream(transaction,"aboba");
                            for(int cycle_count=0;cycle_count<count_tags;cycle_count++){
                                uint32_t id = (packet_number*count_tags+cycle_count) % 32768;
                                int16_t q = dis_i(gen);  
                                float v = dis_r(gen);
                                stream<<std::make_tuple(id,q,v,timestamp);
                            }
                            stream.complete();
                            transaction.commit();
                            packet=true;
                        } catch(const pqxx::broken_connection& e){
                            packet_retry_count++;
                            PLOGW << "Обрыв соединения при выполнении пакета. Попытка " 
                                      << packet_retry_count << ": " << e.what();
                            
                            if (packet_retry_count < MAX_packet_retry) {
                                PLOGI << "Попытка переподключения . . .";
                                std::this_thread::sleep_for(std::chrono::seconds(1));
                                
                                try {
                                    db = pqxx::connection(conn_info);
                                    if (db.is_open()) {
                                        PLOGI << "Переподключение успешно";
                                    }
                                } catch (const pqxx::broken_connection& e2) {
                                    PLOGW << "Не удалось переподключиться: " << e2.what();
                                    continue; 
                                }
                            }
                        }
                    }
                    
                    if (!packet) {
                        PLOGE << "Не удалось выполнить пакет после " << MAX_packet_retry << " попыток";
                        break;
                    }
                    
                    PLOGI<<" Время сейчас:"<<timestamp<<std::endl;
                    auto end_time=std::chrono::steady_clock::now();
                    auto duration=std::chrono::duration_cast<std::chrono::milliseconds>(end_time-start_time).count();
                    PLOGI << " Пакет записан за " << duration << " мс" << std::endl;
                    if (time_min>duration){
                        time_min=duration;
                    }
                    if (time_max<duration){
                        time_max=duration;
                    }
                    total_time+=static_cast<double>(duration);
                    sum_sqrt+=static_cast<double>(duration)*duration;
                    
                    if(duration<period_ms){
                        int sleep_time=period_ms - duration;
                        PLOGD<<"Ждем"<<sleep_time;
                        std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time));
                    }
                    else {
                        int delay=duration-period_ms;
                        PLOGW<<"Превышение времени на "<<delay;
                    }
                }     
                connect=true;    
            } else {
                PLOGE<<"Не удалость октрыть соединение"<<std::endl;
                reconnect_attempt++;
            }
        } catch (const pqxx::broken_connection& e) { 
            reconnect_attempt++;
            PLOGE << "Ошибка подключения номер: " << reconnect_attempt << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        if (reconnect_attempt < MAX_reconnect_count) {
            PLOGI << "Повторная попытка через 2 секунды...";
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }

    if (!connect) {
        PLOGE << "Не удалось подключиться к БД после " << MAX_reconnect_count << " попыток";
        return 1;
    }
    
    auto program_end_time=std::chrono::steady_clock::now();
    auto total_duration=std::chrono::duration_cast<std::chrono::milliseconds>(program_end_time-programm_start_time).count();
    double avg_time=0.0;
    double std_dev=0.0;
    if (packet_number>0){
        avg_time=total_time/packet_number;
        double mean_squared = avg_time * avg_time;
        double sum_squared_mean = sum_sqrt / packet_number;
        double variance = sum_squared_mean - mean_squared;
        if (variance < 0) {
            variance = 0;
        }
        
        std_dev = std::sqrt(variance);
    }

    std::cout << "COUNT_TAGS=" << count_tags << std::endl;
    std::cout << "PERIOD_MS=" << period_ms << std::endl;
    std::cout << "WORK_TIME_SEC=" << work_time << std::endl;
    std::cout << "TOTAL_PACKETS=" << packet_number << std::endl;
    std::cout << "TOTAL_RECORDS=" << (packet_number * count_tags) << std::endl;
    std::cout << "TOTAL_TIME_MS=" << total_duration << std::endl;
    std::cout<<  "TIME_MIN="  << time_min<<std::endl;
    std::cout<<  "TIME_MAX="  <<time_max<<std::endl;
    std::cout << "TIME_STDDEV=" << std_dev << std::endl;
    std::cout << "TIME_AVG=" << avg_time << std::endl;
        return 0;
            
}