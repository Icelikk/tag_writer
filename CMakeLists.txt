cmake_minimum_required(VERSION 3.16)
project(TagsWriter LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")

include(FetchContent)
FetchContent_Declare(
    plog
    GIT_REPOSITORY https://github.com/SergiusTheBest/plog
    GIT_TAG 1.1.10
)
FetchContent_MakeAvailable(plog)

add_executable(tag_writer src/test_connection.cpp)

target_link_libraries(tag_writer PRIVATE plog::plog pqxx pq)

target_compile_options(tag_writer PRIVATE -Wno-deprecated-declarations)