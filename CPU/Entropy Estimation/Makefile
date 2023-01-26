CPPFLAGS = -Wall -O3 -std=c++11 -lm -w -mcmodel=medium -g
PROGRAMS = main 

all: $(PROGRAMS)

main:main.cpp \
	params.h BOBHash.h \
	ElasticSketch.h BitMatcher.h dms4.h
	g++ -o bitmatcher main.cpp $(CPPFLAGS)

clean:
	rm -f *.o $(PROGRAMS)
