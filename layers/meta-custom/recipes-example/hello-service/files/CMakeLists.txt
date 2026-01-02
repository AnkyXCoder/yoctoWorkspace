cmake_minimum_required(VERSION 3.10)

project(hello-service LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(hello-service hello.cpp)

install(TARGETS hello-service
        RUNTIME DESTINATION bin)
