#!/Users/cjpa/.rvm/rubies/ruby-1.9.2-p320/bin/ruby
require 'pp'

class Parser 
  attr_reader :type, :value, :jump, :dest, :comp, :romaddress, :opcodes, :jumpcodes, :destcodes
  attr_writer :romaddress, :value

  def initialize(line)
    @opcodes = {
    "0"   => "101010",
    "1"   => "111111",
    "-1"  => "111010",
    "D"   => "001100",
    "A"   => "110000",
    "!D"  => "001101",
    "!A"  => "110001",
    "-D"  => "001111",
    "-A"  => "110011",
    "D+1" => "011111",
    "A+1" => "110111",
    "D-1" => "001110",
    "A-1" => "110010",
    "D+A" => "000010",
    "A+D" => "000010",
    "D-A" => "010011",
    "A-D" => "000111",
    "D&A" => "000000",
    "D|A" => "010101"
    }

    @jumpcodes = {
    "JGT" => "001",
    "JEQ" => "010",
    "JGE" => "011",
    "JLT" => "100",
    "JNE" => "101",
    "JLE" => "110",
    "JMP" => "111"
    }

    @destcodes = {
    "M"   => "001",
    "D"   => "010",
    "MD"  => "011",
    "DM"  => "011",
    "A"   => "100",
    "AM"  => "101",
    "MA"  => "101",
    "AD"  => "110",
    "DA"  => "110",
    "AMD" => "111"
    }
  
    @type  = "" # can be "comment", "a", "c", "l"
    @value = ""
    @jump  = ""
    @dest  = ""
    @comp  = ""
    @romaddress = "" 

    # Comments 
    if line =~ /^\/\/(.*)$/ 
      @type  = "comment"
      @value = $~.captures[0]
      @value.strip!
    end

    # L pseudo command
    if line =~ /^\((.*)\)$/
      @type = "l"
      @value = $~.captures[0]
      @value.strip!
    end

    # A Instruction
    if line =~ /^@(.*)$/
      @type = "a"
      @value = $~.captures[0]
      @value.strip!
    end 

    # C Instruction: If we still didn't find a type, it must be a C-instruction
    if @type.empty?
      @type = "c"
      # Catch dest
      if line =~ /^(.*)=(.*)$/
        @dest = $~.captures[0]
        @dest.strip!
        rest = $~.captures[1]
      else
        rest = line
      end

      if rest =~ /^(.*);(.*)/
        @comp = $~.captures[0]
        @comp.strip!
        @jump = $~.captures[1]
        @jump.strip!
      else  
        @comp = rest
        @comp.strip!
      end
    end
  end

  # Get the boolean representation of this object
  def getBoolean
    if @type == 'a'
      return getBooleanValue().rjust(16, '0')
    end

    if @type == 'c'
      return '111'+getBooleanComp()+getBooleanDest()+getBooleanJump()
    end

    return ""
  end

  def getBooleanComp
    a = 0
    tmpcomp = @comp
    if @comp =~ /M/
      a = 1
      # replace the M for an A to reuse the opcodes lookup table
      tmpcomp = @comp.gsub(/M/, "A")
    end
    
    return a.to_s+@opcodes[tmpcomp]
  end

  def getBooleanJump
    @jump.strip!
    if @jump.empty?
      return "000"
    else
        return @jumpcodes[@jump.to_s]
    end
  end

  def getBooleanDest
    if @dest.empty?
      return "000"
    else 
      if @dest.length == 3
        return "111"
      end
      
      return @destcodes[@dest]
    end
  end

  def getBooleanValue
    number = Integer(@value)
    return number.to_s(2)
  end
  
  def printnice
    puts @romaddress.to_s+" "+@type.to_s+" "+@value.to_s+" "+@comp.to_s+" "+@dest.to_s+" "+@jump.to_s+"\n"
  end
end




@symbols = {
"SP"      => "0",
"LCL"     => "1",
"ARG"     => "2",
"THIS"    => "3",
"THAT"    => "4",
"R0"      => "0",
"R1"      => "1",
"R2"      => "2",
"R3"      => "3",
"R4"      => "4",
"R5"      => "5",
"R6"      => "6",
"R7"      => "7",
"R8"      => "8",
"R9"      => "9",
"R10"     => "10",
"R11"     => "11",
"R12"     => "12",
"R13"     => "13",
"R14"     => "14",
"R15"     => "15",
"SCREEN"  => "16384",
"KBD"     => "24576"
}

# Global vars
filename = ARGV[0]
startaddress = 16
current_ram_address = startaddress
parseobjects = []
counter = 0
last_l_objects = []

# Main loop
f = File.open(filename)
while not f.eof? do
  line = f.readline
   
  # Remove whitespace from string
  line.strip!

  # Remove comments
  line.gsub!(/\/\/.*/, "")

  if not line.empty?
    parseobject = Parser.new(line)
    # Determine the ROM-address
    if parseobject.type == "l"
      last_l_objects.push(parseobject)
    else 
      if parseobject.type == "a" or parseobject.type == "c"
        parseobject.romaddress = counter
        # Make sure the last (label) has the correct ROM-Address too
        if last_l_objects.length > 0
          last_l_objects.each {|last_l_object| 
            last_l_object.romaddress = counter
            @symbols[last_l_object.value] = counter
          }
          
          last_l_objects = []
        end
        counter += 1 
      end
    end 
    parseobjects.push(parseobject)
  end
end

parseobjects.each {|p|
  # Replace symbols
  if p.type == "a" and @symbols.has_key?(p.value)
    p.value = @symbols[p.value]
  end

  # Ram-Address
  if p.type == "a" and not p.value.to_s =~ /^[0123456789]+$/
    @symbols[p.value] = current_ram_address
    p.value=current_ram_address
    current_ram_address += 1
  end 

  # Get binary and write to stdout
  bool = p.getBoolean
  if bool != ""
    puts bool + "\n"
  end
  #p.printnice
}

#pp @symbols
#pp parseobjects
