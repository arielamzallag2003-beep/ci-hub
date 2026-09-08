CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra

all: app

app: main.cpp
	$(CXX) $(CXXFLAGS) -o app main.cpp

test: app
	./app

clean:
	rm -f app

.PHONY: all test clean
