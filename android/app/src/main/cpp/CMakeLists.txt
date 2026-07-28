cmake_minimum_required(VERSION 3.22)
# Only used on aarch64 Linux hosts; see the gate in ../../../build.gradle.kts.
# Skip CMake's try-compile: the NDK's x86_64 clang cannot run on this arm64
# host. No targets are defined, so nothing is ever actually compiled.
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
project(furtive_noop C CXX)
