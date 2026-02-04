cmake_minimum_required(VERSION 3.10)
project(TagsWriter)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(
    plog
    GIT_REPOSITORY https://github.com/SergiusTheBest/plog
    GIT_TAG        1.1.10
)
FetchContent_MakeAvailable(plog)
add_executable(TagsWriter src/test_connection.cpp)

target_link_libraries(TagsWriter PRIVATE plog::plog pqxx pq)   