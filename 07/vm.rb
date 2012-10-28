#!/Users/cjpa/.rvm/rubies/ruby-1.9.2-p320/bin/ruby

#
# The Parser reads lines and decomposes them into their separate elements
# In a second phase, we translate the current record into ASM
# 
# Some notes about the translation to assember:
# . we leave all used memory dirty. this means that parts of the stack might contain values which aren't 
#   valid anymore. But we don't care since they will be overwritten anyway next time something gets pushed.
#   Same goes for temporary memory-registers we use in calculations (notably R13-15)
#
require 'pp'

class Parser 
  # Constants
  C_PUSH        = 1
  C_POP         = 2
  C_LABEL       = 3
  C_GOTO        = 4
  C_IF          = 5
  C_FUNCTION    = 6
  C_RETURN      = 7
  C_CALL        = 8
  C_ARITHMETIC  = 9
  
  COMMANDS = {
    "push"  => {"type" => C_PUSH, "args" => 2, "asm" => :push},
    "pop"   => {"type" => C_POP, "args" => 2, "asm" => :pop},
    "add"   => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :add},
    "sub"   => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :sub},
    "and"   => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :andf},
    "or"    => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :orf},
    "eq"    => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :eq},
    "lt"    => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :lt},
    "gt"    => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :gt},
    "not"   => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :notf},
    "neg"   => {"type" => C_ARITHMETIC, "args" => 0, "asm" => :neg}
  }
  
  attr_reader :command, :args, :filename, :linenumber, :commandinfo
  
  def error(msg)
    puts "#{@filename}:#{@linenumber}: #{msg}"
    exit
  end
  
  def initialize(current_filename, line, linenumber)
    line.strip!
    parts = line.split #split by spaces
    @command = parts[0]
    @filename = current_filename
    @linenumber = linenumber
    
    # Check if we recognise the command
    if not COMMANDS.has_key?(@command)
      error "Command not found: #{@command}"
    else
      @commandinfo = COMMANDS[@command]
    end
    
    
    # Hold the arguments to the command
    if (parts.length() -1 > @commandinfo["args"])
      error "Too many arguments: #{(parts.length - 1).to_s} (expected: #{@commandinfo["args"].to_s})" 
    else 
      @args = parts.drop(1)
    end
  end

  def push 
    segment = @args[0]
    index   = @args[1]
    
    case segment.to_s
    when "constant"
      asm  = "@#{index.to_s}\n"
      asm += "D=A\n"
      asm += "@SP\n"
      asm += "A=M\n"
      asm += "M=D\n"
    when "local"
      asm = push_helper("LCL")
    when "argument"
      asm = push_helper("ARG")
    when "that"
      asm = push_helper("THAT")
    when "this"
      asm = push_helper("THIS")
    when "static"
      address = index.to_i + 16 # 16 = base of static-segment 
      asm  = "@#{address.to_s}\n"
      asm += "D=M\n"  
      asm += "@SP\n"
      asm += "A=M\n"
      asm += "M=D\n"
    when "pointer"
      address = index.to_i + 3 # 3 = base of pointer-segment
      asm  = "@#{address.to_s}\n"
      asm += "D=M\n"  
      asm += "@SP\n"
      asm += "A=M\n"
      asm += "M=D\n"
    when "temp"
      address = index.to_i + 5 # 5 = base of temp-segment
      asm  = "@#{address.to_s}\n"
      asm += "D=M\n"  
      asm += "@SP\n"
      asm += "A=M\n"
      asm += "M=D\n"

    else 
      error "push: Wrong segment defined: #{segment.to_s}"
    end
    
    asm += spinc
    return asm
  end
  
  def pop
    segment = @args[0]
    index   = @args[1].to_i
    
    case segment.to_s
    when "local"
      asm = pop_helper("LCL")
    when "argument"
      asm = pop_helper("ARG")
    when "that"
      asm = pop_helper("THAT")
    when "this"
      asm = pop_helper("THIS")    
    when "static"
      address = index.to_i + 16 # 16 = base of static-segment 
      asm  = "@SP\n"
      asm += "A=M-1\n"
      asm += "D=M\n"  # D contains value of SP-1 register
      asm += "@#{address.to_s}\n"
      asm += "M=D\n"  
    when "pointer"
      address = index + 3 # 3 = base of pointer-segment
      asm  = "@SP\n"
      asm += "A=M-1\n"
      asm += "D=M\n"  # D contains value of SP-1 register
      asm += "@#{address.to_s}\n"
      asm += "M=D\n"  
    when "temp"
      address = index + 5 # 5 = base of temp-segment
      asm  = "@SP\n"
      asm += "A=M-1\n"
      asm += "D=M\n"  # D contains value of SP-1 register
      asm += "@#{address.to_s}\n"
      asm += "M=D\n"  
    else
      error "pop: Wrong segment defined: #{segment.to_s}"
    end
    
    asm += spdec
    return asm
  end

  def add
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "M=M+D\n"
    asm += spdec
    
    return asm
  end

  def sub
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "M=M-D\n"   # only this is different from sum
    asm += spdec
    
    return asm
  end

  def eq
    # first we sub
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "D=M-D\n"   # only this is different from sum
    
    # Now we compare
    asm += "@eq#{@filename}.#{@linenumber}\n"
    asm += "D;JEQ\n"
    
    # NOT EQUAL: store 0 in stack (0 means: FALSE)
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=0\n"
    asm += "@eq#{@filename}.#{@linenumber}.done\n"
    asm += "0;JMP\n"
    
    # EQUAL: store -1 in stack (-1 means: TRUE)
    asm += "(eq#{@filename}.#{@linenumber})\n"
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=-1\n"
    asm += "(eq#{@filename}.#{@linenumber}.done)\n"
    asm += spdec
    
    return asm
  end

  def gt
    # first we sub
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "D=M-D\n"   # only this is different from sum
    
    # Now we compare
    asm += "@gt#{@filename}.#{@linenumber}\n"
    asm += "D;JGT\n"
    
    # NOT EQUAL: store 0 in stack (0 means: FALSE)
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=0\n"
    asm += "@gt#{@filename}.#{@linenumber}.done\n"
    asm += "0;JMP\n"
    
    # EQUAL: store -1 in stack (-1 means: TRUE)
    asm += "(gt#{@filename}.#{@linenumber})\n"
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=-1\n"
    asm += "(gt#{@filename}.#{@linenumber}.done)\n"
    asm += spdec
    
    return asm
  end

  def lt
    # first we sub
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "D=M-D\n"   # only this is different from sum
    
    # Now we compare
    asm += "@lt#{@filename}.#{@linenumber}\n"
    asm += "D;JLT\n"
    
    # NOT EQUAL: store 0 in stack (0 means: FALSE)
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=0\n"
    asm += "@lt#{@filename}.#{@linenumber}.done\n"
    asm += "0;JMP\n"
    
    # EQUAL: store -1 in stack (-1 means: TRUE)
    asm += "(lt#{@filename}.#{@linenumber})\n"
    asm += "@R13\n"
    asm += "A=M\n"
    asm += "M=-1\n"
    asm += "(lt#{@filename}.#{@linenumber}.done)\n"
    asm += spdec
    
    return asm
  end

  def andf
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "M=M&D\n"   # only this is different from sum
    asm += spdec
    
    return asm
  end

  def orf
    asm  = "@SP\n"
    asm += "A=M\n"    # A holds pointer to next stack item
    asm += "D=A-1\n"  # D holds pointer to last inserted stack item 
    asm += "@R14\n"
    asm += "M=D\n"    # R14 holds pointer to last inserted stack item (arg2)
    asm += "@R13\n"
    asm += "M=D-1\n"  # R13 holds pointer to second last inserted stack item (arg1)
    asm += "@R14\n"
    asm += "A=M\n"
    asm += "D=M\n"   
    asm += "@R13\n" 
    asm += "A=M\n"
    asm += "M=M|D\n"   # only this is different from sum
    asm += spdec

    return asm
  end

  def notf
    asm  = "@SP\n"
    asm += "A=M-1\n"
    asm += "M=!M\n"
    
    return asm
  end
  
  def neg
    asm  = "@SP\n"
    asm += "A=M-1\n"
    asm += "M=-M\n"
    
    return asm
  end


  # helper function: increase Stack Pointer by 1
  def spinc
     asm  = "@SP\n"
     asm += "M=M+1\n" 
     return asm
  end

  # helper function: Decrease Stack Pointer by 1  
  def spdec
     asm  = "@SP\n"
     asm += "M=M-1\n"  
     return asm
  end
  
  def push_helper(registername)
    index = @args[1].to_i

    asm  = "@#{registername}\n"
    asm += "D=M\n"  # D contains contents of LCL-register (=points to base-address of local-segment)
    asm += "@#{index.to_s}\n"
    asm += "A=A+D\n"
    asm += "D=M\n"  # Now D contains contents of LCL+index register
    asm += "@SP\n"
    asm += "A=M\n"
    asm += "M=D\n"

    return asm
  end
  
  def pop_helper(registername)
    index = @args[1].to_i

    asm  = "@SP\n"
    asm += "A=M-1\n"
    asm += "D=M\n"  # D contains value of SP-1 register
    asm += "@R13\n"
    asm += "M=D\n"  # value to pop sits in R13 now
    asm += "@"+registername+"\n"
    asm += "D=M\n"  # D contains contents of LCL/ARG/...-register (=points to base-address of segment)
    asm += "@#{index.to_s}\n"
    asm += "D=A+D\n"
    asm += "@R14\n" # address to LCL+index sits in R14
    asm += "M=D\n"
    asm += "@R13\n" # Get value again
    asm += "D=M\n"
    asm += "@R14\n" # push value in LCL+index register
    asm += "A=M\n"
    asm += "M=D\n"
    
    return asm
  end
end


# main loop
filename = ARGV[0]
files = [] # hold all the files we need to process
linecounter = 0 
parseobjects = [] # holds all the Parser-objects

if File.file? filename
  files.push filename
end

if File.directory? filename
  files = Dir[filename+'/*.vm']
end

while fn=files.pop
  f = File.open(fn)
  while not f.eof? do
    linecounter += 1
    line = f.readline

    # Remove whitespace from string
    line.strip!

    # Remove comments
    line.gsub!(/\/\/.*/, "")

    if not line.empty?
      # do your thing here
      parseobject = Parser.new(fn, line, linecounter)
      parseobjects.push(parseobject)
    end
  end
  
  parseobjects.each {|p|
    puts p.method(p.commandinfo["asm"]).call
  }
  #pp parseobjects
end
