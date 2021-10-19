TinyBasicA64: TinyBasicA64.o
	ld -s -o TinyBasicA64 TinyBasicA64.o

TinyBasicA64.o: TinyBasicA64.s
	as -o TinyBasicA64.o TinyBasicA64.s

clean:
	rm *.o
