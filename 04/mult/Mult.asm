// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Mult.asm

// Multiplies R0 and R1 and stores the result in R2.
// (R0, R1, R2 refer to RAM[0], RAM[1], and RAM[3], respectively.)

// Compute: 5*6, store result in R3
@R2
D=M
@i
M=D
(LOOP)
  // Not condition comes here
  @i
  D=M
  @END
  D;JEQ
  
  // Actual logic comes here
  @R1
  D=M
  @R3
  M=D+M
  @i
  M=M-1
  // Next while...
  @LOOP
  0;JMP   // Got LOOP
(END)
  @END
  0;JMP // Keep jumping back to END
