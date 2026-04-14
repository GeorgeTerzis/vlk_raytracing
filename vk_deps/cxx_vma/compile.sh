#!/bin/bash


zig c++ -O3 -std=c++23 -fPIC -I./include -c vma.cpp -o vma.o
ar rcs libvma.a vma.o
