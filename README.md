# TinyBasicA64
TinyBasic interpreter for aarch64 / ARM V8 linux systems

- adapted from TinyBASIC of Z1013 (my first computer) which was based on PATB by Li-Chen Wang
- interpreter written in 100% assembler for compact code
- all values are 64bit signed (like the original version the lowest negative number (here -9223372036854775808) could not be converted
- abbrevation of keywords by '.' is supported
- concatenation of statements with ';' is supported
- RUN and LIST can be broken with control+c
- some commands and functions marked as optional could be activated by compiler parameter
- the program assumes a 8KByte RAM machine with more than 6KBytes memory free for program (the stack memory not in count)
- basic lines are stored with <8_byte_binary_line_number>text<NL> in memory
- for general documentation please use the net
