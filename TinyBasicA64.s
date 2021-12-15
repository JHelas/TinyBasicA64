// TinyBasicA64.s
//
// A Z1013 TinyBASIC compatible interpreter for aarch64 / ARMV8 linux systems
//
// NTHelas (c) 2021
//
// Free software for education and private use
//

/* Issues:
	- Break in List during SAVE possible
	- Write errors during save not handled
*/

/* Register usage

	x15 Byte from source code
	x20 Source code - pointer to input line or program memory
	x21 Result of functions
	x24 Format length for PRINT
	x27 Pointer to current source line (after line number)
	x28 TOP
	x29 Copy of SP at program start
*/


.macro call function
	str	x30, [sp, -16]!
	bl	\function
	ldr	x30, [sp], 16
.endm

.macro callr xn:req
	str	x30, [sp, -16]!
	blr	\xn
	ldr	x30, [sp], 16
.endm

.macro push rn:req
	str	\rn, [sp, -16]!
.endm

.macro pop rn:req
	ldr	\rn, [sp], 16
.endm


		.global _start

		// System calls
		.equ	IOCTL,		29
		.equ	OPEN,		56
		.equ	CLOSE,		57
		.equ	READ,		63
		.equ	WRITE,		64
		.equ	EXIT,		93
		.equ	TIME,		113
		.equ	SIGNAL,		134
		.equ	RANDOM,		278

		// Constants for system calls
		.equ	STDIN,		0
		.equ	STDOUT,		1
		.equ	AT_FDCWD,	-100
		.equ	CLOCK_THREAD_CPUTIME_ID, 3
		.equ	SIGINT,		2
		.equ	TCGETS,		0x5401
		.equ	TCSETS,		0x5402
		.equ	FIONREAD,	0x541B
		.equ	ICANON,		2
		.equ	ECHO,		8

		.equ	O_WRITE,	1
		.equ	O_CREAT,	0100
		.equ	O_EXCL,		0200
		.equ	O_TRUNC,	01000

		.equ	WFLAGS,		01101	// O_WRITE | O_CREATE | O_TRUNC

		// Configuration parameters
		.equ	LINE_LENGTH,	128	// Length of input line
		.equ	WORK_LENGTH,	32	// Internal buffer for itoa()
		.equ	VECTOR_SIZE,	128	// Count of @() variables
		.equ	STMT_DELIM,	';'	// Statement delimiter
		.equ	GOSUB_MARK,	'G'
		.equ	FOR_MARK,	'F'

TOP		.req	x28
STACK_COUNTER	.req	v11
STRING_LENGTH	.req	v12

///////////////////////////////////////////////////////////

.data

.align 2

BOOT_MSG:	.ascii	"\nTINY BASIC A64 V1.00"
NEW_LINE:	.ascii	"\n"
BOOT_M_LEN		= . - BOOT_MSG
PROMPT:		.ascii	"READY\n"
PROMPT1:	.ascii	">"
E_WHAT:		.ascii	"WHAT?\n"
E_HOW:		.ascii	"HOW?\n"
E_SORRY:	.ascii	"SORRY\n"

// Orders for direct mode only
OrderList:
		.quad	CmdLIST
		.asciz	"LIST"
		.quad	CmdRUN
		.asciz	"RUN"
		.quad	CmdNEW
		.asciz	"NEW"
		.quad	CmdBYE
		.asciz	"BYE"

.ifdef EXTENSIONS

		.quad	ErrSORRY
		.asciz	"END"		// Change size of used memory - not supported

.endif
		.quad	CmdSAVE
		.asciz	"SAVE"
		.quad	CmdLOAD
		.asciz	"LOAD"

// Commands for direct and run mode
CommandList:
		.quad	CmdLET
		.asciz	"LET"
		.quad	CmdIF
		.asciz	"IF"
		.quad	CmdGOTO
		.asciz	"GOTO"
		.quad	CmdGOSUB
		.asciz	"GOSUB"
		.quad	CmdRETURN
		.asciz	"RETURN"
		.quad	CmdNEXT
		.asciz	"NEXT"
		.quad	CmdREM
		.asciz	"REM"
		.quad	CmdFOR
		.asciz	"FOR"
		.quad	CmdINPUT
		.asciz	"INPUT"
		.quad	CmdPRINT
		.asciz	"PRINT"
		.quad	CmdSTOP
		.asciz	"STOP"
		.quad	CmdOUTCHAR
		.asciz	"OUTCHAR"

.ifdef EXTENSIONS

		.quad	O_DOLLAR
		.asciz	"O$"
		.quad	I_DOLLAR
		.asciz	"I$"
		.quad	CmdTAB
		.asciz	"TAB"
		.quad	CmdBYTE
		.asciz	"BYTE"
		.quad	CmdWord
		.asciz	"WORD"

.endif

		.quad	CmdLET
		.asciz	""

ForToList:
		.quad	ForTO
		.asciz	"TO"
		.quad	ErrWHAT
		.asciz	""

ForStepList:
		.quad	ForSTEP
		.asciz	"STEP"
		.quad	ForDefaultStep
		.asciz	""

// List of functions
FunctionList:
		.quad	FctRND
		.asciz	"RND"
		.quad	FctABS
		.asciz	"ABS"
		.quad	FctSIZE
		.asciz	"SIZE"
		.quad	FctTOP
		.asciz	"TOP"
		.quad	FctINCHAR
		.asciz	"INCHAR"

.ifdef EXTENSIONS

		.quad	FctHEX
		.asciz	"HEX"
		.quad	FctLEN
		.asciz	"LEN"

.endif

		.quad	EvalExpr31
		.asciz	""

// List of logical operators
Operators:
		.quad	op_eq
		.asciz	"="
		.quad	op_ne
		.asciz	"#"
		.quad	op_ge
		.asciz	">="
		.quad	op_gt
		.asciz	">"
		.quad	op_le
		.asciz	"<="
		.quad	op_lt
		.asciz	"<"
		.quad	_return
		.asciz	""

.ifdef BENCH
RUNTIME_MSG:	.ascii "\nRUNTIME: "
RUNTIME_MSG_END	= .
UNIT_MSG:	.ascii " SECONDS\n"
UNIT_MSG_END	= .
.endif

///////////////////////////////////////////////////////////

.bss
.align 2

LineBuff:	.space	LINE_LENGTH
WorkBuff:	.space	WORK_LENGTH
WorkBEnd	= .
VarBuff:	.space	26 * 8
VectBuff:	.space	VECTOR_SIZE * 8
BreakFlag:	.space	8
ProgBuff:	.space	8 * 1024 - LINE_LENGTH - WORK_LENGTH - 26 * 8 - VECTOR_SIZE * 8 - 1 * 8
ProgBEnd	= .

// Struct termios
TermIOS_0:	.space 12
c_lflag:	.space 52
TermIOS_1:	.space 64


///////////////////////////////////////////////////////////

.text


///////////////////////////////////////////////////////////
// Skip blanks in source
//
// Return: w15 current char (not a blank)
//
SkipBlanks:
	sub	x20, x20, 1
SkipBlanks1:
	ldrb	w15, [x20, 1]!
	cmp	w15, 0x20
	beq	SkipBlanks1
	ret


///////////////////////////////////////////////////////////
// Check if a number can be read from source
//
// Return x21 - Number - 0
//
// Used: x15, x16, x17, x18
//
TestNumber:
	call	SkipBlanks
TestNumber1:
	mov	x21, 0
	mov	x16, 10
	mov	x17, 0x39
	ldrb	w15, [x20]
TestNumber2:
	cmp	w15, 0x30		// x10 > 0x30 AND
	ccmp	w15, w17, 0, ge		// x10 > 0x39 return
	bgt	_return
	and	x15, x15, 0xF		// x15 - 0x30
	smulh	x18, x21, x16
	mul	x21, x21, x16		// x21 = x21 * 10
	cmp	x18, x21, ASR #63	// Overflow ?
	bne	ErrHOW
	adds	x21, x21, x15		// x21 += number
	bvs	ErrHOW			// Overflow ?
	ldrb	w15, [x20, 1]!
	b	TestNumber2		// Next


///////////////////////////////////////////////////////////
// Test for a string
//
// w15 - first char x20 points to
//
// Return:
//	x0 - 0 - no string, 1 - string found
//	x1 - Pointer to string, maybe of length 0
//	x2 - String length
//
TestString0:
	call	SkipBlanks
TestString:
	mov	x0, 0
	mov	x2, 0
TestString1:
	cmp	w15, 0x0A
	beq	_return
	cmp	w15, '"'
	bne	TestString3
	add	x20, x20, 1
	mov	x1, x20
	mov	x0, 1
TestString2:
	ldrb	w15, [x20]
	cmp	w15, 0x0A
	beq	_return
	add	x20, x20, 1
	cmp	w15, '"'
	beq	_return
	add	x2, x2, 1
	b	TestString2

TestString3:
	cmp	w15, '\''
	bne	_return
	add	x20, x20, 1
	mov	x1, x20
	mov	x0, 1
TestString4:
	ldrb	w15, [x20]
	cmp	w15, 0x0A
	beq	_return
	add	x20, x20, 1
	cmp	w15, '\''
	beq	_return
	add	x2, x2, 1
	b	TestString4


///////////////////////////////////////////////////////////
// Read variable name
//
// w15 - Varname
//
// Return:
//	x20 - Points to source after varname
//	x25 - Pointer to var
//
// Used: x15, x25
//
GetVarAddress:
	add	x20, x20, 1
	cmp	w15, '@'
	beq	GetVectorAddress
	sub	x15, x15, 'A'
	ccmp	w15, 'Z' - 'A', 0, gt
	bgt	ErrWHAT
	adr	x25, VarBuff
	add	x25, x25, x15, lsl #3
	ret

GetVectorAddress:
	call	ReadFunctionValue
	cmp	x21, VECTOR_SIZE
	ccmp	x21, xzr, 10, lt
	blt	ErrSORRY
	adr	x22, VectBuff
	add	x22, x22, x21, lsl #3
	ret


///////////////////////////////////////////////////////////
// Errors
//
ErrWHAT0:
	sub	x20, x20, 1
ErrWHAT:
	mov	x0, STDOUT
	adr	x1, E_WHAT
	mov	x2, 6			// Length
	mov	x8, WRITE
	svc	0

ErrExt:					// In run mode print line with '?' on error
	cbz	x27, WarmStart
					// Print line number
	ldur	x21, [x27, -8]
	mov	x24, 4
	call	PrintNumber
					// Print space
	mov	x0, STDOUT
	adr	x1, BOOT_MSG + 5	// Blank
	mov	x2,  1			// Length
	svc	0
					// Print code before error
	subs	x2, x20, x27		// Length
	cbz	x2, ErrExt1
	mov	x0, STDOUT
	mov	x1, x27
	svc	0

ErrExt1:				// Print'?'
	mov	x0, STDOUT
	adr	x1, E_HOW + 3		// Question mark
	mov	x2, 1			// Length
	svc	0
					// Print code after error
	mov	x0, STDOUT
	mov	x1, x20
	mov	x2, 0			// Length
ErrExt2:				// Find eol
	ldrb	w16, [x20], 1
	cmp	w16, 0xA
	add	x2, x2, 1
	bne	ErrExt2
ErrExt3:
	svc	0
	b	WarmStart

ErrHOW:
	mov	x0, STDOUT
	adr	x1, E_HOW
	mov	x2, 5			// Length
	mov	x8, WRITE
	svc	0
	b	ErrExt

ErrIO:					// Close file
	mov	x0, x10			// fd
	mov	x8, CLOSE
	svc 0
ErrSORRY:
	mov	x0, STDOUT
	adr	x1, E_SORRY
	mov	x2, 6			// Length
	mov	x8, WRITE
	b	ErrExt3


///////////////////////////////////////////////////////////
// Print a char
//
// x10 fd
// x21 char
//
PrintChar:
	adr	x1, WorkBuff
	strb	w21, [x1]
	mov	x2, 1
	b	PrintNumber4


///////////////////////////////////////////////////////////
// Print formated number
//
// x10 - fd
// x21 - number
// x24 - count of chars
//
// Used: x12, x13, x14, x22
//
PrintNumber:
	adr	x1, WorkBEnd
	mov	x2, 0
	mov	x11, 10
	mov	x14, 0
	cmp	x21, 0
	bpl	PrintNumber1
	neg	x21, x21
	mov	x14, 1			// Remember '-'
PrintNumber1:
	udiv	x12, x21, x11		// x12 = val / 10
	msub	x13, x12, x11, x21	// x13 = x21 - x12 * x11(10)
	add	x13, x13, 0x30
	strb	w13, [x1, -1]!		// Store byte as ascii
	add	x2, x2, 1
	mov	x21, x12
	cbnz	x21, PrintNumber1
	cbz	x14, PrintNumber2
	mov	w13, '-'
	strb	w13, [x1, -1]!		// Store byte as ascii
	add	x2, x2, 1
PrintNumber2:
	mov	w13, ' '
	subs	x22, x24, x2
	cmp	x22, 0
	ble	PrintNumber4
PrintNumber3:
	strb	w13, [x1, -1]!		// Store byte as ascii
	add	x2, x2, 1
	sub	x22, x22, 1
	cbnz	x22, PrintNumber3
PrintNumber4:
	mov	x0, x10
	mov	x8, WRITE
	svc	0
	ret


///////////////////////////////////////////////////////////
// List source code
//
// x10 fd
//
List:
	cmp	x20, TOP		// TOP reached ?
	bge	_return
	adr	x8, BreakFlag
	ldr	x9, [x8]
	cbnz	x9, _return		// CTRL+C pressed ?
					// List one line
	ldr	x21, [x20], 8
	mov	x24, 4
	call	PrintNumber
					// Print space
	mov	x21, ' '
	call	PrintChar
					// Print code
	mov	x0, x10
	mov	x1, x20
	mov	x2,  0			// Length
	mov	x8, WRITE
List2:					// Find eol
	ldrb	w15, [x20], 1
	cmp	w15, 0xA
	add	x2, x2, 1
	bne	List2
	svc	0
	sub	x23, x23, 1		// Max count of lines reached ?
	cbz	x23, _return
	b	List


///////////////////////////////////////////////////////////
// Load program from disc
//
// x1 - Pointer to filename
//
// Used: x10 (fd), x13, x14, x15
//
LoadFile:				// Open file
	mov	x0, AT_FDCWD		// dfd
	mov	x2, 0			// Flags: O_RDONLY
	mov	x3, 0			// Mode: ignored
	mov	x8, OPEN		// openat
	svc	0
	cmp	x0, 0
	blt	ErrSORRY
	adr	TOP, ProgBuff		// NEW
	mov	x10, x0			// Save fd
	mov	x14, 0
LoadFile1:				// Read (again)
	adr	x1, LineBuff
	mov	x2, LINE_LENGTH
	cbz	x14, LoadFile3
	sub	x2, x2, x14
	mov	x0, x14
					// Move non dispatched bytes to begin of buffer
LoadFile2:
	sub	x0, x0, 1
	ldrb	w15, [x20], 1
	strb	w15, [x1], 1
	cbnz	x0, LoadFile2
LoadFile3:
	mov	x0, x10
	mov	x8, READ
	svc	0
	cmp	x0, 0
	blt	ErrIO
	beq	CloseFile
					// Find nl
	adr	x13, LineBuff
	add	x0, x0, x14
LoadFile4:
	mov	x20, x13
	mov	x14, x0
LoadFile5:
	cbz	x0, LoadFile1
	sub	x0, x0, 1
	ldrb	w15, [x13], 1
	cmp	w15, 0x0A
	bne	LoadFile5
					// Store line
	bl	TestNumber		// Line number ?
	cbz	x21, LoadFile4
	bl	DeleteLine
	bl	SkipBlanks
	cmp	w15, 0x0A
	beq	LoadFile4
	sub	x16, x13, x20		// Calc size of code
	call	StoreLine
	b	LoadFile4


///////////////////////////////////////////////////////////
// Close file
//
// x10 fd
//
CloseFile:
	mov	x0, x10			// fd
	mov	x8, CLOSE
	svc	0
	b	WarmStart


///////////////////////////////////////////////////////////
// Signal handler for SIGINT
//
SignalHandler:
	adr	x8, BreakFlag
	mov	x9, 1
	str	x9, [x8]
	ret


///////////////////////////////////////////////////////////
// Switch echo on or off
//
EchoOn:
	adr	x2, TermIOS_1
	b	Echo

EchoOff:
	adr	x2, TermIOS_0
Echo:
	mov	x0, STDIN
	mov	x1, TCSETS
	mov	x8, IOCTL
	svc	0
	ret


///////////////////////////////////////////////////////////
// Main
//
_start:
					// Install signal handler
	adr	x1, LineBuff
	adr	x0, SignalHandler
	str	x0, [x1]
	mov	x0, SIGINT
	mov	x2, 0
	mov	x3, 8
	mov	x8, SIGNAL
	svc	0
					// Read current termios
	mov	x0, STDOUT
	mov	x1, TCGETS
	adr	x2, TermIOS_1
	mov	x8, IOCTL
	svc	0
					// Read current termios
	mov	x0, STDOUT
	adr	x2, TermIOS_0
	svc	0
					// Reset icanon and echo
	adr	x0, c_lflag
	ldrb	w1, [x0]
	mov	w2, ~(ICANON | ECHO)
	and	w1, w1, w2
	strb	w1, [x0]
					// Say hello to the user
	adr	TOP, ProgBuff		// New()
	mov	x0, STDOUT
	adr	x1, BOOT_MSG
	mov	x2, BOOT_M_LEN		// Length
	mov	x8, WRITE
	svc	0
					// Load program by program arg
	ldp	x10, x11, [SP], 16
	mov	x29, SP
	cmp	x10, 2
	blt	WarmStart
	ldp	x1, x13, [SP], 16
	mov	x29, SP
	call	LoadFile
WarmStart:
	mov	sp, x29			// Reset SP
	mov	x10, STDOUT

.ifdef BENCH
	cbz	x27, PrtRuntime3
	mov	x0, STDOUT
	adr	x1, RUNTIME_MSG
	mov	x2, RUNTIME_MSG_END - RUNTIME_MSG	// Length
	mov	x8, WRITE
	svc	0
	mov	x0, CLOCK_THREAD_CPUTIME_ID
	adr	x1, LineBuff
	mov	x8, TIME
	svc	0
	mov	x15, v0.D[0]
	mov	x16, v0.D[1]
	ldr	x17, [x1], 8
	ldr	x18, [x1]
	sub	x21, x17, x15
	sub	x19, x18, x16
	cmp	x19, 0
	csneg	x19, x19, x19, ge
	bge	PrtRuntime1
	sub	x21, x21, 1
PrtRuntime1:
	mov	x24, 1
	call	PrintNumber
					// Print '.'
	mov	x21, '.'
	call	PrintChar
	mov	x18, 1000
	sdiv	x19, x19, x18
	sdiv	x19, x19, x18
	mov	x18, 10
	sdiv	x19, x19, x18
	cmp	x19, 10
	bge	PrtRuntime2
	mov	x21, '0'
	call	PrintChar
PrtRuntime2:
	mov	x21, x19
	call	PrintNumber
	mov	x0, STDOUT
	adr	x1, UNIT_MSG
	mov	x2, UNIT_MSG_END - UNIT_MSG	// Length
	svc	0
PrtRuntime3:
.endif

	mov	x27, 0			// Direct mode
	mov	x0, x10
	adr	x1, PROMPT
	mov	x2, 6			// Length
	mov	x8, WRITE
	svc	0
					// Main loop
Main1:
	mov	STACK_COUNTER.D[0], xzr
	bl	EchoOn
					// Printe '>'
	mov	x21, '>'
	call	PrintChar
					// Input line
	mov	x0, STDIN
	adr	x1, LineBuff
	mov	x2, LINE_LENGTH		// Length
	mov	x8, READ
	svc	0
					// Dispatch line
	adr	x20, LineBuff
	bl	TestNumber		// Line number ?
	cbz	x21, Main2
	bl	DeleteLine
	bl	SkipBlanks
	cmp	w15, 0x0A
	beq	Main1
	sub	x16, x20, x1		// Length of line number in ASCII
	sub	x16, x0, x16		// x16 := src length
	bl	StoreLine		// Yes -> LineEnd ?
	b	Main1

Main2:					// No line number
	adr	x8, BreakFlag
	str	xzr, [x8]		// Reset break flag
	bl	EchoOff
	bl	SkipBlanks
	cmp	w15, 0x0A		// Empty line ?
	beq	WarmStart		// Yes
	adr	x18, OrderList
	bl	ExecLine		// Exec direct
	b	WarmStart


///////////////////////////////////////////////////////////
// Find a codeword in list
//
// Compare src with list entry - maybe shortened by '.'
//
// x18 Table of codewords and pointers
//
// Used: x15-x19
//
FindFunction:
	mov	x17, x20		// Save for restore
FindFunction0:
	ldr	x19, [x18], 8
FindFunction1:
	ldrb	w16, [x18], 1
	cbz	w16, FindFunction3	// End of codeword -> found
	ldrb	w15, [x20], 1
	cmp	w15, w16
	beq	FindFunction1
	cmp	w15, '.'		// Shortcut used ?
	beq	FindFunction3
	mov	x20, x17		// Restore source pointer
FindFunction2:				// Find end of codeword
	ldrb	w16, [x18], 1
	cbnz	w16, FindFunction2
	b	FindFunction0

FindFunction3:
	br	x19			// Jump to function


///////////////////////////////////////////////////////////
// Exec line
//
// x18 table of codewords and pointers - or use ExecLine1
// x20 source (after line number)
//
ExecLine0:
	call	SkipBlanks
	cmp	w15, 0x0A
	beq	ExecLine2
ExecLine1:
	adr	x18, CommandList
ExecLine:
	call	FindFunction
	call	SkipBlanks
	cmp	w15, STMT_DELIM
	cinc	x20, x20, eq
	beq	ExecLine0
	cmp	w15, 0x0A
	bne	ErrWHAT
ExecLine2:
	add	x20, x20, 1
	ret


///////////////////////////////////////////////////////////
// LIST
//
CmdLIST:
	bl	TestNumber
	bl	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	mov	x10, STDOUT
	adr	x20, ProgBuff
	mov	x23, 0
	cbz	x21, CmdLIST1
	mov	x23, 20
	bl	FindLine
CmdLIST1:
	bl	List
	b	WarmStart


///////////////////////////////////////////////////////////
// RUN
//
CmdRUN:
	bl	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	adr	x20, ProgBuff

.ifdef BENCH
	mov	x0, CLOCK_THREAD_CPUTIME_ID
	adr	x1, LineBuff
	mov	x8, TIME
	svc	0
	ld1	{ v0.16B }, [x1]
.endif

CmdRUN0:
	cmp	x20, TOP		// TOP ?
	bge	WarmStart
	add	x20, x20, 8		// Jump over line number
CmdRUN1:
	adr	x8, BreakFlag
	ldr	x9, [x8]
	cbnz	x9, WarmStart		// CTRL+C pressed ?
	mov	x27, x20		// Save start of line for error message
CmdRUN2:
	bl	ExecLine1		// Execute the line
	b	CmdRUN0


///////////////////////////////////////////////////////////
// NEW
//
// "Delete" the program
//
CmdNEW:
	bl	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	adr	TOP, ProgBuff
	b	WarmStart


///////////////////////////////////////////////////////////
// BYE
//
// Leave the interpreter
//
CmdBYE:
	bl	EchoOn
	mov	x0, 0			// Return code
	mov	x8, EXIT
	svc	0			// Call service to exit


///////////////////////////////////////////////////////////
// SAVE
//
CmdSAVE:				// Get filename
	bl	TestString0
	cbz	x2, ErrWHAT
	bl	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	add	x16, x1, x2
	strb	wzr, [x16]
					// Open file
	mov	x0, AT_FDCWD		// dfd
	mov	x2, WFLAGS		// flags
	mov	x3, 0640		// mode
	mov	x8, OPEN		// openat
	svc	0
	cmp	x0, 0
	blt	ErrSORRY
	mov	x10, x0			// Save fd
	mov	x23, 0			// List all
	adr	x20, ProgBuff
	bl	List
	b	CloseFile


///////////////////////////////////////////////////////////
// LOAD
//
CmdLOAD:
	// Get filename
	bl	TestString0
	cbz	x2, ErrWHAT
	bl	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	add	x16, x1, x2
	strb	wzr, [x16]
	bl	LoadFile
	b	WarmStart


///////////////////////////////////////////////////////////
// LET
//
CmdLET:					// Read var name
	call	SkipBlanks
	call	GetVarAddress		// x25 := address
CmdLET1:				// Skip blanks
	ldrb	w15, [x20], 1
	cmp	w15, 0x20
	beq	CmdLET1
					// Read '='
	cmp	w15, '='
	bne	ErrWHAT0
	call	EvalExpr0
	str	x21, [x25]		// Store value in var
	ret


///////////////////////////////////////////////////////////
// IF
//
CmdIF:
	call	EvalExpr0
	cbz	x21, CmdREM
	ldr	x30, [sp], 16		// Cleanup ret
	b	ExecLine1


///////////////////////////////////////////////////////////
// GOTO
//
CmdGOTO:
	call	EvalExpr0
	call	SkipBlanks
	cmp	w15, 0x0a
	bne	ErrWHAT
	call	FindLineExact
	ldr	x30, [sp], 16
	b	CmdRUN1


///////////////////////////////////////////////////////////
// GOSUB
//
CmdGOSUB:
	call	EvalExpr0
	stp	x27, x20, [sp, -16]!	// Save line pointer and position in line
	call	FindLineExact
	mov	x21, GOSUB_MARK
	push	x21			// Save mark
	call	IncStackCounter
	b	CmdRUN2


///////////////////////////////////////////////////////////
// RETURN
//
CmdRETURN:
	call	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	add	sp, sp, 16		// Dismiss return address
	mov	x8, STACK_COUNTER.D[0]
	cbz	x8, ErrWHAT
	sub	x8, x8, 1
	mov	STACK_COUNTER.D[0], x8
	pop	x21			// Restore mark
	cmp	x21, GOSUB_MARK
	bne	ErrWHAT
	ldp	x27, x20, [sp], 16	// Restore line pointer and position in line
	ret


///////////////////////////////////////////////////////////
// REM
//
CmdREM:
	ldrb	w15, [x20], 1
	cmp	w15, 0x0A
	bne	CmdREM
	sub	x20, x20, 1
	ret


///////////////////////////////////////////////////////////
// FOR TO NEXT
//
CmdFOR:
	call	SkipBlanks
	call	CmdLET			// x25 - pointer to var
	mov	x4, x25
	adr	x18, ForToList
	b	FindFunction

ForTO:
	call	SkipBlanks
	mov	x2, x20			// Save address of TO expression
	call	EvalExpr0
	adr	x18, ForStepList
	b	FindFunction

ForSTEP:
	call	SkipBlanks
	mov	x3, x20			// Save address of STEP expression
	call	EvalExpr0
	b	ForDefaultStep1

ForDefaultStep:
	mov	x3, 0
ForDefaultStep1:
	mov	x5, FOR_MARK
	pop	x6			// Save return
	stp	x27, x20, [sp, -16]!	// Line pointer and position in line
	stp	x2, x3, [sp, -16]!	// TO and STEP
	stp	x5, x4, [sp, -16]!	// Var and MARK
	push	x6
IncStackCounter:
	mov	x8, STACK_COUNTER.D[0]
	add	x8, x8, 1
	cmp	x8, 4096		// Limit count of FOR and GOSUB
	beq	ErrSORRY
	mov	STACK_COUNTER.D[0], x8
	ret


///////////////////////////////////////////////////////////
// NEXT
//
CmdNEXT:
	call	SkipBlanks		// Get Var
	call	GetVarAddress		// x25 := address, x20 after var name
	sub	x11, x20, 1		// Save for 'leave' case
	mov	x12, x27
	mov	x9, STACK_COUNTER.D[0]
CmdNEXT1:
	cbz	x9, ErrWHAT
	mov	STACK_COUNTER.D[0], X9
	ldp	x5, x4, [sp, 16]	// Restore mark and var
	cmp	x5, FOR_MARK
	bne	ErrWHAT
	cmp	x4, x25
	beq	CmdNEXT2
	pop	x7			// Wrong FOR
	str	x7, [sp, 32]!
	sub	x9, x9, 1
	bne	CmdNEXT1

CmdNEXT2:				// FOR data found
	ldp	x20, x3, [sp, 32]	// STEP and TO
	ldp	x27, x1, [sp, 48]	// Line data
	call	EvalExpr0
	ldr	x24, [x4]
	cmp	x24, x21		// Last loop ?
	cset	x6, eq			// Mark for later use
	cbz	x3, CmdNEXT8		// Default step ?
	mov	x20, x3			// Run STEP
	call	EvalExpr0		//  and
CmdNEXT5:
	add	x21, x24, x21		//  add to var
	str	x21, [x4]		//  store it
	cbnz	x6, CmdNEXT9
	mov	STACK_COUNTER.D[0], x9
	adr	x8, BreakFlag
	ldr	x9, [x8]
	cbnz	x9, WarmStart		// CTRL+C pressed ?
	ret

CmdNEXT6:				// Cleanup GOSUB data
	cmp	x5, GOSUB_MARK
	bne	ErrWHAT
	add	sp, sp, 16
	sub	x9, x9, 1
	b	CmdNEXT1

CmdNEXT8:
	mov	x21, 1
	b	CmdNEXT5

CmdNEXT9:				// Go on after NEXT x
	add	x20, x11, 1
	mov	x27, x12
	pop	x7
	str	x7, [sp, 32]!
	sub	x9, x9, 1
	mov	STACK_COUNTER.D[0], x9
	ret


///////////////////////////////////////////////////////////
// INPUT
//
CmdINPUT0:
	add	x20, x20, 1
CmdINPUT:
	call	TestString0
	cbz	x0, CmdINPUT2		// Not a string
	cbz	x2, CmdINPUT7		// Nothing to print
	mov	x0, 1
	mov	x8, WRITE
	svc	0
	b	CmdINPUT7

CmdINPUT2:
	mov	x1, x20
	call	GetVarAddress		// x25 := address
	mov	x0, STDOUT
	sub	x2, x20, x1		// Length
	mov	x8, WRITE
	svc	0
	mov	x21, ':'
	call	PrintChar
					// Read
	call	EchoOn
	mov	x0, STDIN
	adr	x1, WorkBuff
	mov	x2, WORK_LENGTH
	mov	x8, READ
	svc	0
					// Convert
	push	x20
	mov	x20, x1
	call SkipBlanks
	mov	x1, 1
	cmp	x15, '-'
	cneg	x1, x1, eq
	cinc	x20, x20, le
	call TestNumber
	mul	x21, x21, x1
	str	x21, [x25]
	pop	x20
CmdINPUT7:
	call	SkipBlanks
	cmp	w15, ','
	beq	CmdINPUT0
	cmp	w15, STMT_DELIM
	ccmp	w15, 0x0A, 4, ne
	bne	ErrWHAT
	b	EchoOff


///////////////////////////////////////////////////////////
// PRINT
//
// x20 - source
//
// Used: x15, x24
//
CmdPRINT:
	mov	x24, 6
	call	SkipBlanks
	cmp	w15, ','
	beq	ErrWHAT
	cmp	w15, STMT_DELIM
	ccmp	w15, 0x0A, 4, ne
	beq	CmdPRINT7
CmdPRINT1:				// Statement end ?
					// Format option ? # - max 129
	cmp	w15, '#'
	bne	CmdPRINT2
	add	x20, x20, 1
	call	EvalExpr0
	cmp	x21, 129
	csel	x24, x21, xzr, lt
	b	CmdPRINT4

CmdPRINT2:
	// String ?
	call	TestString
	cbz	x0, CmdPRINT3		// Not a string
	cbz	x2, CmdPRINT4		// Length of 0 - nothing to print
	mov	x0, STDOUT
	mov	x8, WRITE
	svc	0
	b	CmdPRINT4

CmdPRINT3:				// Expression ?
	call	EvalExpr0
	call	PrintNumber
CmdPRINT4:				// Comma or statement end ?
	call	SkipBlanks
	cmp	w15, ','
	bne	CmdPRINT6
CmdPRINT5:
	ldrb	w15, [x20, 1]!
	cmp	w15, 0x20
	beq	CmdPRINT5
	cmp	w15, STMT_DELIM
	ccmp	w15, 0x0A, 4, ne
	beq	_return
	b	CmdPRINT1

CmdPRINT6:
	cmp	w15, STMT_DELIM
	ccmp	w15, 0x0A, 4, ne
	bne	ErrWHAT
CmdPRINT7:				// Out NL if needed
	adr	x1, NEW_LINE
	mov	x2, 1			// Length
CmdPRINT8:
	mov	x0, STDOUT
	mov	x8, WRITE
	svc	0
	ret


///////////////////////////////////////////////////////////
// STOP
//
CmdSTOP:
	call	SkipBlanks
	cmp	w15, 0x0A
	bne	ErrWHAT
	b	WarmStart


///////////////////////////////////////////////////////////
// OUTCHAR (value) | value
//
// Print value as char
//
CmdOUTCHAR:
	call	SkipBlanks
	cmp	w15, '('
	beq	CmdOUTCHAR1
	call	EvalExpr0
	and	x21, x21, 255
	b	PrintChar

CmdOUTCHAR1:
	call	ReadFunctionValue1
	and	x21, x21, 255
	b	PrintChar


///////////////////////////////////////////////////////////
// Read (<expr>)
//
ReadFunctionValue:
	call	SkipBlanks
	cmp	w15, '('
	bne	ErrWHAT
ReadFunctionValue1:
	add	x20, x20, 1
	call	EvalExpr0
	cmp	w15, ')'
	bne	ErrWHAT
	add	x20, x20, 1
	ret


///////////////////////////////////////////////////////////
// O$(x)
//
// Output a string
//
// Used: x15, x16, x17
//
.ifdef EXTENSIONS

O_DOLLAR:
	call	ReadFunctionValue
	adr	x16, LineBuff
	adr	x17, ProgBEnd
	add	x16, x16, x21
	cmp	x16, TOP
	blt	ErrSORRY
	mov	x1, x16
	mov	x2, -1
O_DOLLAR1:
	add	x2, x2, 1
	cmp	x16, x17
	bge	CmdPRINT8
	ldrb	w15, [x16], 1
	cbnz	w15, O_DOLLAR1
	b	CmdPRINT8


///////////////////////////////////////////////////////////
// I$(x)
//
// Input a string
//
// Used: x15, x16, x17,
I_DOLLAR:
	call	ReadFunctionValue
					// Read
	call	EchoOn
	mov	x0, STDIN
	adr	x1, WorkBuff
	mov	x2, WORK_LENGTH
	mov	x8, READ
	svc	0
	cmp	x0, 0
	bmi	I_DOLLAR2
	adr	x15, LineBuff
	adr	x16, ProgBEnd
	add	x15, x15, x21		// Destination
	add	x17, x15, x0		// End
	cmp	x15, TOP
	ccmp	x17, x16, 0, ge
	bgt	ErrSORRY
	sub	x0, x0, 1
	mov	STRING_LENGTH.D[0], x0
I_DOLLAR1:
	ldrb	w16, [x1], 1
	strb	w16, [x15], 1
	sub	x0, x0, 1
	cbnz	x0, I_DOLLAR1
	strb	wzr, [x15]
I_DOLLAR2:
	call	EchoOff
	ret


///////////////////////////////////////////////////////////
// TAB(value)
//
// Used: x21, x23
//
CmdTAB:
	call	ReadFunctionValue
	mov	x23, x21
	mov	x21, 0x20
CmdTAB1:
	cbz	x23, _return
	call	PrintChar
	sub	x23, x23, 1
	b	CmdTAB1


///////////////////////////////////////////////////////////
// BYTE(value)
//
// Print the value hexadecimal formated (XX)
//
// Used: x15, x23
//
CmdBYTE:
	call	ReadFunctionValue
	mov	x23, x21
	lsr	x21, x21, 4
	call	PrtHex
	mov	x21, x23
	b	PrtHex

PrtHex:
	and	x21, x21, 0x0F
	add	x21, x21, 0x30
	cmp	x21, 0x3A
	blt	PrtHex1
	add	x21, x21, 0x07
PrtHex1:
	b	PrintChar


///////////////////////////////////////////////////////////
// WORD(value)
//
// Print the value hexadecimal formated (XXXX)
//
// Used: x15, x23
//
CmdWord:
	call	ReadFunctionValue
	mov	x23, x21
	lsr	x21, x21, 12
	call	PrtHex
	mov	x21, x23
	lsr	x21, x21, 8
	call	PrtHex
	mov	x21, x23
	lsr	x21, x21, 4
	call	PrtHex
	mov	x21, x23
	b	PrtHex

.endif


///////////////////////////////////////////////////////////
// Store input in ProgBuffer
//
// x16 -
// x19 - Pointer to destination position in ProgBuff
// x20 - Pointer to code (in input buffer)
// x21 - line number
//
// Used: x15, x17, x18
//
StoreLine:				// Check available space in ProgBuff
	add	x16, x16, 8		// Add size of (binary) line number
	adr	x17, ProgBEnd
	sub	x17, x17, TOP
	cmp	x16, x17
	bgt	ErrSORRY		// Out of memory
					// Make space
	add	TOP, TOP, x16
	mov	x17, TOP
	add	x18, x19, x16
	sub	x16, x17, x16
StoreLine1:
	cmp	x17, x18
	ble	StoreLine2
	ldrb	w15, [x16, -1]!
	strb	w15, [x17, -1]!
	b	StoreLine1

StoreLine2:				// Copy line number
	str	x21, [x19], 8
StoreLine3:				// Copy code
	ldrb	w15, [x20], 1
	strb	w15, [x19], 1
	cmp	w15, 0x0A
	bne	StoreLine3
	ret


///////////////////////////////////////////////////////////
// Delete a code line from ProgBuffer
//
// x21 - line number
//
// Return x19 Pointer to store position
//
// Used: x15, x16, x17
//
//
DeleteLine:
	push	x20
	call	FindLine
	mov	x19, x20		// Store for later use
	cmp	x20, TOP		// TOP ?
	bge	DeleteLine4
	mov	x16, x20
	ldr	x17, [x20], 8
	cmp	x21, x17		// Line number found ?
	bne	DeleteLine4		// No -> return
					// Find next statement
DeleteLine1:
	ldrb	w15, [x20], 1
	cmp	w15, 0xA
	bne	DeleteLine1
					// Do while TOP is not reached
DeleteLine2:
	cmp	x20, TOP
	beq	DeleteLine3
	ldrb	w15, [x20], 1
	strb	w15, [x16], 1
	b	DeleteLine2

DeleteLine3:
	mov	TOP, x16
DeleteLine4:
	pop	x20
_return:
	ret


///////////////////////////////////////////////////////////
// Find a code line by line number
//
// Used by DeleteLine, LIST x
//
// x21 line number
//
// Return: x20 - pointer to line with line number or
//		next greater line number (or TOP)
//
// Used: x15, x16
//
FindLine:
	adr	x20, ProgBuff
FindLine1:
	cmp	x20, TOP		// TOP reached ?
	bge	_return
	ldr	x16, [x20]
	cmp	x21, x16
	ble	_return
	add	x20, x20, 8
FindLine2:
	ldrb	w15, [x20], 1
	cmp	w15, 0xA
	bne	FindLine2
	b	FindLine1


///////////////////////////////////////////////////////////
// Find a code line by line number - exact mode
//
// Used by GOTO, GOSUB
//
// x21 line number
//
// Return:
//	x17 - pointer to old position in current line
//	x20 - pointer to line with line number
//
// Used: x15, x16, x17
//
FindLineExact:
	mov	x17, x20
	mov	x20, x27
	cbz	x20, FindLineExact0
	ldr	x16, [x20, -8]!		// Current line number
	cmp	x21, x16
	bgt	FindLineExact1
FindLineExact0:
	adr	x20, ProgBuff		// Search from start
FindLineExact1:
	cmp	x20, TOP		// TOP reached ?
	bge	FindLineExactErr
	ldr	x16, [x20], 8
	cmp	x21, x16
	blt	FindLineExactErr
	csel	x27, x20, x27, eq
	beq	_return
FindLineExact2:				// Search EOL
	ldrb	w15, [x20], 1
	cmp	w15, 0xA
	bne	FindLineExact2
	b	FindLineExact1

FindLineExactErr:
	mov	x20, x17
	b	ErrHOW


///////////////////////////////////////////////////////////
// Evaluate expression
//
// Return x21 - value
//
// Used: x16, x17, x18, x19, x22
//
EvalExpr0:
	mov	x21, 0
	call	EvalExpr1
					// Read logical operator
	adr	x18, Operators
	b	FindFunction

EvalExpr1:
	call	SkipBlanks
	cmp	w15, '-'		// Unary
	bne	EvalExpr11
	call	EvalExpr2
	neg	x21, x21
	b	EvalExpr13

EvalExpr11:
	cmp	w15, '+'		// Unary
	beq	EvalExpr12
	sub	x20, x20, 1
EvalExpr12:
	call	EvalExpr2
EvalExpr13:				// Subtraction ?
	call	SkipBlanks
	cmp	w15, '-'
	bne	EvalExpr14
	push	x21
	call	EvalExpr2
	neg	x21, x21
	b	EvalExpr15

EvalExpr14:				// Addition ?
	cmp	w15, '+'
	bne	_return			// No ? -> ret
	push	x21
	call	EvalExpr2
EvalExpr15:
	pop	x16
	adds	x21, x16, x21
	bvs	ErrHOW
	b	EvalExpr13


EvalExpr2:
	mov	x21, 0
	call	EvalExpr3
EvalExpr21:				// Multiplication ?
	call	SkipBlanks
	cmp	w15, '*'
	bne	EvalExpr22
	push	x21
	call	EvalExpr3
	pop	x16
	smulh	x17, x16, x21
	mul	x21, x16, x21
	cmp	x17, x21, ASR #63
	bne	ErrHOW
	b	EvalExpr21

EvalExpr22:				// Division ?
	cmp	w15, '/'
	bne	_return			// Possible: Jump to '%' function
	push	x21
	call	EvalExpr3
	cbz	x21, ErrHOW		// Division by zero ?
	pop	x16
	sdiv	x21, x16, x21
	b	EvalExpr21


EvalExpr3:				// Is it a number ?
	ldrb	w15, [x20, 1]!
	cmp	w15, ' '
	beq	EvalExpr3
	mov	x19, x20
	call	TestNumber1
	cmp	x19, x20		// Anything read ?
	bne	_return			// Yes
					// Is it a function ?
	adr	x18, FunctionList
	b	FindFunction

EvalExpr31:				// Is it a var ?
	ldrb	w15, [x20]
	cmp	w15, '@'
	beq	EvalExpr32
	blt	EvalExpr33
	cmp	w15, 'Z'
	bgt	EvalExpr33
	add	x20, x20, 1
	sub	x15, x15, 'A'
	adr	x16, VarBuff
	add	x16, x16, x15, lsl #3
	ldr	x21, [x16]		// Load Var to x21
	ret

EvalExpr32:				// @(x)
	add	x20, x20, 1
	call	ReadFunctionValue
	cmp	x21, VECTOR_SIZE
	ccmp	x21, xzr, 10, lt
	blt	ErrSORRY
	adr	x16, VectBuff
	add	x16, x16, x21, lsl #3
	ldr	x21, [x16]		// Load Var to x21
	ret

EvalExpr33:				// Is ist char 'x' ?
	cmp	w15, '\''
	bne	EvalExpr34
	ldrb	w21, [x20, 1]!
	ldrb	w15, [x20, 1]!
	cmp	w15, '\''
	bne	ErrWHAT
	add	x20, x20, 1
	ret

EvalExpr34:				// Is it a '(' ?
	cmp	w15, '('
	bne	ErrWHAT
	add	x20, x20, 1
	call	EvalExpr0
	cmp	w15, ')'
	bne	ErrWHAT
	add	x20, x20, 1
	ret


///////////////////////////////////////////////////////////
// RND(expr)
//
// Return: x21 random value between 1 and function param (inclusive)
//
FctRND:
	call	ReadFunctionValue
	adr	x0, WorkBuff
	mov	x1, 8			// Length
	mov	x2, 0			// Flags
	mov	x8, RANDOM
	svc	0
	adr	x0, WorkBuff
	ldr	x0, [x0]
	udiv	x1, x0, x21
	msub	x21, x1, x21, x0	// x21 = <rnd> - val * (<rnd> / val)
	add	x21, x21, 1
	ret


///////////////////////////////////////////////////////////
// ABS
//
// Return: x21 absulute value
//
FctABS:
	call	ReadFunctionValue
	cmp	x21, 0
	csneg	x21, x21, x21, ge
	ret


///////////////////////////////////////////////////////////
// SIZE
//
// Return: x21 Free bytes in program memory
//
FctSIZE:
	adr	x15, ProgBEnd
	sub	x21, x15, TOP
	ret


///////////////////////////////////////////////////////////
// INCHAR
//
// Read a char nonblocking from stdin
//
// Return: x21 read char if any or 0
//
FctINCHAR:				// Check if something is available
	mov	x21, 0
	mov	x0, STDIN
	mov	x1, FIONREAD
	adr	x2, WorkBuff
	mov	x8, IOCTL
	svc	0
	cbnz	x0, ErrSORRY		// Call OK ?
	ldr	x1, [x2]
	cbz	x1, _return		// Nothing to read
	mov	x1, x2			// Buffer
	mov	x2, 1			// Length
	mov	x8, READ
	svc	0
	ldr	x21, [x1]
	ret


///////////////////////////////////////////////////////////
// HEX(AB)
//
// Return: x21 Convert hex chars to value
//
.ifdef EXTENSIONS

FctHEX:
	call	SkipBlanks
	cmp	w15, '('
	bne	ErrWHAT
	mov	x21, 0
	add	x20, x20, 1
	call	SkipBlanks
FctHEX1:				// A-F ?
	ldrb	w15, [x20], 1
	cmp	w15, 'F'
	bgt	FctHEX3
	cmp	w15, 'A'
	blt	FctHEX2
	sub	w15, w15, 0x37
	orr	x21, x15, x21, lsl 4
	b	FctHEX1

FctHEX2:				// 0-9 ?
	cmp	w15, '9'
	bgt	FctHEX3
	cmp	w15, '0'
	blt	FctHEX3
	sub	w15, w15, 0x30
	orr	x21, x15, x21, lsl 4
	b	FctHEX1

FctHEX3:
	sub	x20, x20, 1
FctHEX4:
	ldrb	w15, [x20], 1
	cmp	w15, 0x20
	beq	FctHEX4
	cmp	w15, ')'
	bne	ErrWHAT0
	ret


///////////////////////////////////////////////////////////
// LEN
//
// Return: x21 Length of last used string
//
FctLEN:
	mov	x21, STRING_LENGTH.D[0]
	ret

.endif


///////////////////////////////////////////////////////////
// TOP
//
// Return: x21 First free position in memory behind basic program
//
FctTOP:
	adr	x22, LineBuff
	sub	x21, TOP, x22
	ret


///////////////////////////////////////////////////////////
// Logical operators
//
// Return: x21 - 0 false / 1 true
//
// Used: x22
//
LoadTerm:
	push	x21
	call	EvalExpr1
	pop	x22
	cmp	x22, x21
	ret

op_eq:
	call	LoadTerm
	cset	x21, eq
	ret

op_ne:
	call	LoadTerm
	cset	x21, ne
	ret

op_ge:
	call	LoadTerm
	cset	x21, ge
	ret

op_gt:
	call	LoadTerm
	cset	x21, gt
	ret

op_le:
	call	LoadTerm
	cset	x21, le
	ret

op_lt:
	call	LoadTerm
	cset	x21, lt
	ret
