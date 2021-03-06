{{
┌─────────────────────────────────────────────────┐
│ JTAGulator                                      │
│                                                 │
│ Author: Joe Grand                               │                     
│ Copyright (c) 2013 Grand Idea Studio, Inc.      │
│ Web: http://www.grandideastudio.com             │
│                                                 │
│ Distributed under a Creative Commons            │
│ Attribution 3.0 United States license           │
│ http://creativecommons.org/licenses/by/3.0/us/  │
└─────────────────────────────────────────────────┘

Program Description:

The JTAGulator is a tool to assist in identifying on-chip debugging (OCD) and/or
programming connections from test points, vias, or component pads on a target
piece of hardware.

Refer to the project page for more details:

http://www.jtagulator.com

Each interface object contains the low-level routines and operational details
for that particular on-chip debugging interface. This keeps the main JTAGulator
object a bit cleaner. 

Command listing is available in the DAT section at the end of this file.

}}


CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000           ' 5 MHz clock * 16x PLL = 80 MHz system clock speed 
  _stack   = 100                 ' Ensure we have this minimum stack space available        

  ' Serial terminal
  ' Control characters
  LF    = 10  ''LF: Line Feed
  CR    = 13  ''CR: Carriage Return
  CAN   = 24  ''CAN: Cancel (Ctrl-X) 
  
  ' JTAGulator I/O pin definitions
  PROP_SDA      = 29
  PROP_SCL      = 28  
  LED_R         = 27   ' Bi-color Red/Green LED, common cathode
  LED_G         = 26
  DAC_OUT       = 25   ' PWM output for DAC
  TXS_OE        = 24   ' Output Enable for TXS0108E level translators

  ' JTAGulator general constants  
  MAX_CHAN      = 24   ' Maximum number of pins/channels the JTAGulator hardware provides (P23..P0)

  ' JTAG/IEEE 1149.1
  MAX_NUM_JTAG  = 32   ' Maximum number of devices allowed in a single JTAG chain

  ' UART
  MAX_LEN_UART  = 16   ' Maximum number of bytes to receive from target
   
  
VAR                   ' Globally accessible variables 
  long vTarget        ' Target system voltage (for example, 18 = 1.8V)
  
  long jTDI           ' JTAG pins (must stay in this order)
  long jTDO
  long jTCK
  long jTMS
  long jNUM           ' Number of devices in JTAG chain         
  
  long uTXD           ' UART pins (as seen from the target) (must stay in this order)
  long uRXD
  long uBAUD
  
  
OBJ
  ser           : "Parallax Serial Terminal"            ' Serial communication for user interface (included w/ Parallax Propeller Tool)
  rr            : "RealRandom"                          ' Random number generation (Chip Gracey, http://obex.parallax.com/object/498) 
  jtag          : "PropJTAG"                            ' JTAG/IEEE 1149.1 low-level functions
  uart          : "JDCogSerial"                         ' UART/Asynchronous Serial communication engine (Carl Jacobs, http://obex.parallax.com/object/298)
  
  
PUB main | cmd, bPattern, value 
  SystemInit
  ser.Str(@InitHeader)          ' Display header; uses string in DAT section.

  ' Start command receive/process cycle
  repeat
    TXSDisable                     ' Disable level shifter outputs (high-impedance)
    LEDGreen                       ' Set status indicator to show that we're ready
    ser.Str(String(CR, LF, ":"))   ' Display command prompt
    cmd := ser.CharIn              ' Wait here to receive a byte
    LEDRed                         ' Set status indicator to show that we're processing a command

    case cmd
      "U", "u":                 ' Identify UART pinout
        if (vTarget == -1)
          Display_Voltage_Error
        else
          UART_Scan

      "P", "p":                 ' UART pass through
        if (vTarget == -1)
          Display_Voltage_Error
        else
          UART_Passthrough
                    
      "I", "i":                 ' Identify JTAG pinout (IDCODE Scan)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          IDCODE_Scan

      "B", "b":                 ' Identify JTAG pinout (BYPASS Scan)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          BYPASS_Scan
          
      "D", "d":                 ' Get JTAG Device IDs (Pinout already known)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          IDCODE_Known

      "T", "t":                 ' Test BYPASS (TDI to TDO) (Pinout already known)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          BYPASS_Known
                        
      "V", "v":                 ' Set target system voltage
        Set_Target_Voltage
        
      "R", "r":                 ' Read all channels (input)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          Read_IO_Pins

      "W", "w":                 ' Write all channels (output)
        if (vTarget == -1)
          Display_Voltage_Error
        else
          Write_IO_Pins
      
      "H", "h":                 ' Display list of available commands
        ser.Str(@CommandList)      ' Uses string in DAT section.
                
      other:                    ' Unknown command    
        ser.Str(String(CR, LF, "?"))

        
CON {{ UART COMMANDS }}

PRI UART_Scan  | value, num_chan, baud_idx, i, userstr[(MAX_LEN_UART >> 2) + 3], data[MAX_LEN_UART >> 2]     ' Identify UART pinout
  ' Get user string to send during UART discovery
  ser.Str(String(CR, LF, "Enter text string to output [CR]: "))
  ser.StrInMax(@userstr,  MAX_LEN_UART)
  i := strsize(@userstr)
  byte[@userstr][i]     := CR   ' Append a CR and NULL to the end of the string
  byte[@userstr][i+1]   := 0    

  num_chan := Get_Channels(2)   ' Get the number of channels to use
  if (num_chan == -1)           ' If value is out of range, skip function
    return
   
  Display_Permutations(num_chan, 2) ' TXD, RXD 

  ser.Str(String(CR, LF, "Press spacebar to begin (any other key to abort)..."))
  if (ser.CharIn <> " ")
    ser.Str(String(CR, LF, "UART scan aborted!"))
    return

  ser.Str(String(CR, LF, "JTAGulating! Press any key to abort...", CR, LF))
  TXSEnable     ' Enable level shifter outputs
  
  repeat uTXD from 0 to (num_chan-1)   ' For every possible pin combination...
    repeat uRXD from 0 to (num_chan-1)
      if (uRXD == uTXD)
        next

      repeat baud_idx from 0 to (constant(BaudRateEnd - BaudRate) >> 2) - 1   ' For every possible baud rate in BaudRate table...
        if (ser.RxCount)                   ' Abort scan if any key is pressed
          ser.RxFlush
          ser.Str(String(CR, LF, "UART scan aborted!"))
          return
      
        uBAUD := BaudRate[baud_idx]        ' Store current baud rate into uBAUD variable
        UART.Start(|<uTXD, |<uRXD, uBAUD)  ' Configure UART
        UART.RxFlush                       ' Flush receive buffer
        UART.str(@userstr)                 ' Send string to target
        
        i := 0
        repeat while (i < MAX_LEN_UART)    ' Check for a response from the target and grab up to MAX_LEN_UART bytes
          value := UART.RxTime(20)           ' Wait up to 20ms to receive a byte from the target
          if (value < 0)                     ' If there's no data, exit the loop
            quit
          byte[@data][i++] := value          ' Store the byte in our array and try for more!

        repeat until (UART.RxTime(20) < 0)   ' Wait here until the target has stopped sending data
        
        if (i > 0)                           ' If we've received any data...
          Display_UART_Pins                    ' Display current UART pinout
          ser.Str(String("Data: "))            ' Display the data in ASCII
          repeat value from 0 to (i-1)                  
            if (byte[@data][value] < $20) or (byte[@data][value] > $7E) ' If the byte is an unprintable character 
              ser.Char(".")                                               ' Print a . instead
            else
              ser.Char(byte[@data][value])

          ser.Str(String(" [ "))
          repeat value from 0 to (i-1)        ' Display the data in hexadecimal
            ser.Hex(byte[@data][value], 2)
            ser.Char(" ")
          ser.Str(String("]", CR, LF))
          
  longfill(@uTXD, 0, 3) ' Clear UART pinout + settings
  UART.Stop
  ser.Str(String(CR, LF, "UART scan complete!"))


PRI UART_Passthrough | value    ' UART/terminal pass through
  if (Set_UART == -1)     ' Ask user for the known UART configuration
    return                ' Abort if error

  TXSEnable                          ' Enable level shifter outputs
  UART.Start(|<uTXD, |<uRXD, uBAUD)  ' Configure UART

  ser.Str(String(CR, LF, "Entering UART passthrough! Press Ctrl-X to abort...", CR, LF))

  repeat until (value == CAN)  ' stay in terminal pass-through until cancel value is received  
    repeat while ((value := UART.rxcheck) => 0) ' if the target buffer contains data...
      ser.Char(value)                             ' ...display it

    repeat while (ser.RxCount > 0)              ' if the JTAGulator buffer contains data...
      value := ser.CharIn                         ' ...get it
      if (value <> CAN)                             
        UART.tx(value)                              ' and send to the target (as long as it isn't the cancel value)

  ser.RxFlush
  UART.RxFlush
  UART.Stop
  ser.Str(String(CR, LF, "UART passthrough complete!"))
    

PRI Set_UART : err | xtxd, xrxd, xbaud            ' Set UART configuration to known values
  ser.Str(String(CR, LF, "Enter new TXD pin ["))
  ser.Dec(uTXD)               ' Display current value
  ser.Str(String("]: "))
  xtxd := Get_Decimal_Pin     ' Get new value from user
  if (xtxd == -1)             ' If carriage return was pressed...      
    xtxd := uTXD                ' Keep current setting
  if (xtxd < 0) or (xtxd > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new RXD pin ["))
  ser.Dec(uRXD)               ' Display current value
  ser.Str(String("]: "))
  xrxd := Get_Decimal_Pin     ' Get new value from user
  if (xrxd == -1)             ' If carriage return was pressed...      
    xrxd := uRXD                ' Keep current setting
  if (xrxd < 0) or (xrxd > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new baud rate ["))
  ser.Dec(uBAUD)              ' Display current value
  ser.Str(String("]: "))
  xbaud := Get_Decimal_Pin    ' Get new value from user
  if (xbaud == -1)            ' If carriage return was pressed...      
    xbaud := uBAUD              ' Keep current setting
  if (xbaud < 1) or (xbaud > BaudRate[(constant(BaudRateEnd - BaudRate) >> 2) - 1])  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ' Make sure that the pin numbers are unique
  if (xtxd == xrxd)  ' If we have a collision
    ser.Str(String(LF, "Pin numbers must be unique!"))
    return -1
  else                ' If there are no collisions, update the globals with the new values
    uTXD := xtxd      
    uRXD := xrxd
    uBAUD := xbaud


PRI Display_UART_Pins
  ser.Str(String(CR, LF, "TXD: "))
  ser.Dec(uTXD)
  ser.Str(String(CR, LF, "RXD: "))
  ser.Dec(uRXD)
  ser.Str(String(CR, LF, "Baud: "))
  ser.Dec(uBAUD)
  ser.Str(String(CR, LF))


{{ UNUSED CODE }}
{
PRI UART_Set_Parity(stringptr, parity) | x   ' Convert each byte in the string to 7 bits + parity
  repeat strsize(stringptr)            ' for each byte in the string
    x := byte[stringptr] & %01111111     ' clear MSB

    ' add parity bit in place of the MSB
    if (parity == 2)                            ' if even parity...
      x |= UART_Check_Parity(x) << 7
    elseif (parity == 1)                        ' if odd parity...
      x |= (UART_Check_Parity(x) ^ %1) << 7
         
    byte[stringptr] := x                 ' store byte
    stringptr++                          ' increment string pointer
    
      
PRI UART_Check_Parity(x)   ' Calculate the parity bit (http://en.wikipedia.org/wiki/Parity_bit) for the current byte. Code based on Hacker's Delight by Henry Warren.  
  x ^= x >> 4
  x ^= x >> 2
  x ^= x >> 1   
  result := x & 1    ' invert result for odd parity
}  


CON {{ JTAG COMMANDS }}
                   
PRI IDCODE_Scan | value, num_chan    ' Identify JTAG pinout (IDCODE Scan)
  num_chan := Get_Channels(3)   ' Get the number of channels to use
  if (num_chan == -1)           ' If value is out of range, skip function
    return

  Display_Permutations(num_chan, 3)  ' TDO, TCK, TMS

  ser.Str(String(CR, LF, "Press spacebar to begin (any other key to abort)..."))
  if (ser.CharIn <> " ")
    ser.Str(String(CR, LF, "IDCODE scan aborted!"))
    return

  ser.Str(String(CR, LF, "JTAGulating! Press any key to abort...", CR, LF))
  TXSEnable     ' Enable level shifter outputs

  ' We assume the IDCODE is the default DR after reset
  jTDI := PROP_SDA    ' TDI isn't used when we're just shifting data from the DR. Set TDI to a temporary pin so it doesn't interfere with enumeration.
  repeat jTDO from 0 to (num_chan-1)   ' For every possible pin combination (except TDI)...
    repeat jTCK from 0 to (num_chan-1)
      if (jTCK == jTDO)
        next
      repeat jTMS from 0 to (num_chan-1)
        if (jTMS == jTCK) or (jTMS == jTDO)
          next

        if (ser.RxCount)  ' Abort scan if any key is pressed
          ser.RxFlush
          ser.Str(String(CR, LF, "IDCODE scan aborted!"))
          return

        Set_Pins_High(num_chan)              ' Set currently selected channels to output HIGH (in case there is a signal that needs to be held HIGH, like /SRST or /TRST)
        jtag.Config(jTDI, jTDO, jTCK, jTMS)  ' Configure JTAG pins
        jtag.Get_Device_IDs(1, @value)       ' Try to get Device ID by reading the DR      
        if (value <> -1) and (value & 1)     ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
          Display_JTAG_Pins                    ' Display current JTAG pinout

  longfill(@jTDI, 0, 4) ' Clear JTAG pinout 
  ser.Str(String(CR, LF, "IDCODE scan complete!"))


PRI BYPASS_Scan | value, num_chan, bPattern      ' Identify JTAG pinout (BYPASS Scan)
  num_chan := Get_Channels(4)   ' Get the number of channels to use
  if (num_chan == -1)           ' If value is out of range, skip function
    return

  Display_Permutations(num_chan, 4)  ' TDI, TDO, TCK, TMS
    
  ser.Str(String(CR, LF, "Press spacebar to begin (any other key to abort)..."))
  if (ser.CharIn <> " ")
    ser.Str(String(CR, LF, "BYPASS scan aborted!"))
    return

  ser.Str(String(CR, LF, "JTAGulating! Press any key to abort...", CR, LF))
  TXSEnable     ' Enable level shifter outputs

  ' Pin enumeration logic based on JTAGenum (http://deadhacker.com/2010/02/03/jtag-enumeration/)
  repeat jTDI from 0 to (num_chan-1)        ' For every possible pin combination... 
    repeat jTDO from 0 to (num_chan-1)
      if (jTDO == jTDI)  ' Ensure each pin number is unique
        next
      repeat jTCK from 0 to (num_chan-1)
        if (jTCK == jTDO) or (jTCK == jTDI)
          next
        repeat jTMS from 0 to (num_chan-1)
          if (jTMS == jTCK) or (jTMS == jTDO) or (jTMS == jTDI)
            next
            
          if (ser.RxCount)  ' Abort scan if any key is pressed
            ser.RxFlush
            ser.Str(String(CR, LF, "BYPASS scan aborted!"))
            return

          Set_Pins_High(num_chan)                  ' Set currently selected channels to output HIGH (in case there is a signal that needs to be held HIGH, like /SRST or /TRST)
          jtag.Config(jTDI, jTDO, jTCK, jTMS)      ' Configure JTAG pins
          value := jtag.Detect_Devices
          if (value)
            ser.Str(String(CR, LF, "Number of devices detected: "))
            ser.Dec(value)
            Display_JTAG_Pins                      ' Display current JTAG pinout         

  longfill(@jTDI, 0, 4) ' Clear JTAG pinout        
  ser.Str(String(CR, LF, "BYPASS scan complete!"))

  
PRI IDCODE_Known | value, id[MAX_NUM_JTAG], i        ' Get JTAG Device IDs (Pinout already known)  
  if (Set_JTAG(0) == -1)  ' Ask user for the known JTAG pinout
    return                ' Abort if error
    
  if (Set_NUM == -1)      ' Ask user for the number of devices in JTAG chain
    return                ' Abort if error 

  TXSEnable                               ' Enable level shifter outputs
  Set_Pins_High(MAX_CHAN)                 ' Set all channels to output HIGH (in case there is a signal that needs to be held HIGH, like /SRST or /TRST)
  jtag.Config(jTDI, jTDO, jTCK, jTMS)     ' Configure JTAG pins 
  jtag.Get_Device_IDs(jNUM, @id)          ' We assume the IDCODE is the default DR after reset
  repeat i from 0 to (jNUM-1)             ' For each device in the chain...
    value := id[i]
    if (value <> -1) and (value & 1)        ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
      if (jNUM == 1)
        Display_Device_ID(value, 0)
      else
        Display_Device_ID(value, i + 1)       ' Display Device ID of current device    

  jTDI := 0               ' Reset TDI to an actual channel value (it was set to a temporary pin value to avoid contention)
  ser.Str(String(CR, LF, "IDCODE listing complete!"))


PRI BYPASS_Known | dataIn, dataOut   ' Test BYPASS (TDI to TDO) (Pinout already known)
  if (Set_JTAG(1) == -1)  ' Ask user for the known JTAG pinout
    return                ' Abort if error
    
  if (Set_NUM == -1)      ' Ask user for the number of devices in JTAG chain
    return                ' Abort if error
    
  TXSEnable                                   ' Enable level shifter outputs
  Set_Pins_High(MAX_CHAN)                     ' Set all channels to output HIGH (in case there is a signal that needs to be held HIGH, like /SRST or /TRST)
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  dataIn := rr.random                         ' Get 32-bit random number to use as the BYPASS pattern
  dataOut := jtag.Bypass_Test(jNUM, dataIn)   ' Run the BYPASS instruction 

  ' Display input/output data and check if they match
  ser.Str(String(CR, LF, "Pattern in to TDI:    "))
  ser.Bin(dataIn, 32)   ' Display value as binary characters (0/1)

  ser.Str(String(CR, LF, "Pattern out from TDO: "))
  ser.Bin(dataOut, 32)  ' Display value as binary characters (0/1)

  if (dataIn == dataOut)
    ser.Str(String(CR, LF, "Match!"))
  else
    ser.Str(String(CR, LF, "No Match!"))
    

PRI Set_NUM  : err | value          ' Set the number of devices in chain
  ser.Str(String(CR, LF, "Enter number of devices in JTAG chain ["))
  ser.Dec(jNUM)               ' Display current value
  ser.Str(String("]: "))
  value := Get_Decimal_Pin    ' Get new value from user
  if (value == -1)            ' If carriage return was pressed...      
    value := jNUM               ' Keep current setting
  if (value < 1) or (value > MAX_NUM_JTAG)   ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  jNUM := value


PRI Set_JTAG(useTDI) : err | xtdi, xtdo, xtck, xtms, buf, c     ' Set JTAG configuration to known values
  if (useTDI == 1)          
    ser.Str(String(CR, LF, "Enter new TDI pin ["))
    ser.Dec(jTDI)               ' Display current value
    ser.Str(String("]: "))
    xtdi := Get_Decimal_Pin     ' Get new value from user
    if (xtdi == -1)             ' If carriage return was pressed...      
      xtdi := jTDI                ' Keep current setting
    if (xtdi < 0) or (xtdi > MAX_CHAN-1)  ' If entered value is out of range, abort
      ser.Str(String(LF, "Out of range!"))
      return -1
  else
    xtdi := PROP_SDA            ' TDI isn't used when we're just shifting data from the DR. Set TDI to a temporary pin so it doesn't interfere with enumeration. 
    ser.Char(CR)

  ser.Str(String(LF, "Enter new TDO pin ["))
  ser.Dec(jTDO)               ' Display current value
  ser.Str(String("]: "))
  xtdo := Get_Decimal_Pin     ' Get new value from user
  if (xtdo == -1)             ' If carriage return was pressed...      
    xtdo := jTDO                ' Keep current setting
  if (xtdo < 0) or (xtdo > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new TCK pin ["))
  ser.Dec(jTCK)               ' Display current value
  ser.Str(String("]: "))
  xtck := Get_Decimal_Pin     ' Get new value from user
  if (xtck == -1)             ' If carriage return was pressed...      
    xtck := jTCK                ' Keep current setting
  if (xtck < 0) or (xtck > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1

  ser.Str(String(LF, "Enter new TMS pin ["))
  ser.Dec(jTMS)               ' Display current value
  ser.Str(String("]: "))
  xtms := Get_Decimal_Pin     ' Get new value from user
  if (xtms == -1)             ' If carriage return was pressed...      
    xtms := jTMS                ' Keep current setting
  if (xtms < 0) or (xtms > MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(String(LF, "Out of range!"))
    return -1       

  ' Make sure that the pin numbers are unique
  ' Set bit in a long corresponding to each pin number
  buf := 0
  buf |= (1 << xtdi)
  buf |= (1 << xtdo)
  buf |= (1 << xtck)
  buf |= (1 << xtms)
  
  ' Count the number of bits that are set in the long
  c := 0
  repeat 32
    c += (buf & 1)
    buf >>= 1

  if (c <> 4)         ' If there are not exactly 4 bits set, then we have a collision
    ser.Str(String(LF, "Pin numbers must be unique!"))
    return -1
  else                ' If there are no collisions, update the globals with the new values
    jTDI := xtdi      
    jTDO := xtdo
    jTCK := xtck
    jTMS := xtms
    

PRI Display_JTAG_Pins
  ser.Str(String(CR, LF, "TDI: "))
  if (jTDI => MAX_CHAN)     ' TDI isn't used during an IDCODE Scan (we're not shifting any data into the target), so it can't be determined
    ser.Str(String("N/A"))  
  else
    ser.Dec(jTDI)
  ser.Str(String(CR, LF, "TDO: "))
  ser.Dec(jTDO)
  ser.Str(String(CR, LF, "TCK: "))
  ser.Dec(jTCK)
  ser.Str(String(CR, LF, "TMS: "))
  ser.Dec(jTMS)
  ser.Str(String(CR, LF))


PRI Display_Device_ID(value, num)
  ser.Str(String(CR, LF, "Device ID"))
  if (num > 0)
    ser.Str(String(" #"))
    ser.Dec(num)
  ser.Str(String(": "))
  
  ' Display value as binary characters (0/1) based on IEEE Std. 1149.1 2001 Device Identification Register structure  
  ser.Bin(value >> 28, 4)       ' Version
  ser.Char(" ")
  ser.Bin(value >> 12, 16)      ' Part Number
  ser.Char(" ")  
  ser.Bin(value >> 1, 11)       ' Manufacturer Identity
  ser.Char(" ")
  ser.Bin(value, 1)             ' Fixed (should always be 1)

  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 8)
  ser.Str(String(")"))
      

CON {{ GENERAL COMMANDS }}
    
PRI Set_Target_Voltage | value
  ser.Str(String(CR, LF, "Current target voltage: "))
  Display_Target_Voltage

  ser.Str(String(CR, LF, "Enter new target voltage (1.2 - 3.3, 0 for off): "))
  value := Get_Decimal_Pin   ' Receive decimal value (including 0)
  if (value == 0)                              
    vTarget := -1
    DACOutput(0)               ' DAC output off 
    ser.Str(String(LF, "Target voltage off!"))
  elseif (value < 12) or (value > 33)
    ser.Str(String(LF, "Out of range!"))
  else
    vTarget := value
    DACOutput(VoltageTable[vTarget - 12])       ' Look up value that corresponds to the actual desired voltage and set DAC output
    ser.Str(String(LF, "New target voltage set!"))


PRI Display_Target_Voltage
  if (vTarget == -1)
    ser.Str(String("Undefined"))
  else
    ser.Dec(vTarget / 10)          ' Display vTarget as an x.y value
    ser.Char(".")
    ser.Dec(vTarget // 10)

    
PRI Read_IO_Pins | value, count              ' Read all channels (input)  
  ser.Char(CR)
  
  TXSEnable               ' Enable level shifter outputs
  dira[23..0]~            ' Set P23-P0 as inputs
  value := ina[23..0]     ' Read all channels

  ser.Str(String(CR, LF, "CH23..CH0: "))
  
  ' Display value as binary characters (0/1)
  repeat count from 16 to 0 step 8
    ser.Bin(value >> count, 8)
    ser.Char(" ")
 
  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 6)
  ser.Str(String(")"))    

  
PRI Write_IO_Pins : err | value, count       ' Write all channels (output)
  ser.Str(String(CR, LF, "Enter value to output (in hex): "))
  value := ser.HexIn      ' Receive carriage return terminated string of characters representing a hexadecimal value

  if (value & $ff000000)
    ser.Str(String(LF, "Out of range!"))
    return -1
      
  TXSEnable               ' Enable level shifter outputs
  dira[23..0]~~           ' Set P23-P0 as outputs
  outa[23..0] := value    ' Write value to output
  
  ser.Str(String(CR, LF, "CH23..CH0 set to: "))
  repeat count from 16 to 0 step 8
    ser.Bin(value >> count, 8)
    ser.Char(" ")
    
  ' Display value as hexadecimal
  ser.Str(String(" ("))
  ser.Hex(value, 6)
  ser.Str(String(")"))    

  ser.Str(String(CR, LF, "Press any key when done..."))
  ser.CharIn       ' Wait for any key to be pressed before finishing routine (and disabling level translators)


PRI Set_Pins_High(num) | i     ' Set currently selected channels to output HIGH during a scan
  repeat i from 0 to (num-1)   ' From CH0..CH(num-1)
    dira[i] := 1
    outa[i] := 1

       
PRI Get_Channels(min_chan) : value | buf
{
  Ask user for the number of JTAGulator channels actually hooked up
  
  Parameters: min_chan = Minimum number of pins/channels required (varies with on-chip debug interface)
}
  ser.Str(String(CR, LF, "Enter number of channels to use ("))
  ser.Dec(min_chan)       ' Display minimum channels
  ser.Str(String(" - "))
  ser.Dec(MAX_CHAN)       ' Display maximum channels
  ser.Str(String("): "))

  value := ser.DecIn                              ' Receive carriage return terminated string of characters representing a decimal value
  if (value < min_chan) or (value > MAX_CHAN)
    ser.Str(String(LF, "Out of range!"))
    value := -1
  else
    ser.Str(String(CR, LF, "Ensure connections are on CH"))
    ser.Dec(value-1)
    ser.Str(String("..CH0."))


PRI Get_Decimal_Pin : value | buf       ' Get a decimal number from the user (including number 0, which prevents us from using standard Parallax Serial Terminal routines)
  if ((buf := ser.CharIn) == CR)        ' If the first byte we receive is a carriage return...
    value := -1                               ' Then exit
  else                                  ' Otherwise, the first byte may be valid
    if (buf => "0") and (buf =< "9")      ' If the byte entered is an actual number
      value := (buf - "0")                      ' Convert it into a decimal value
      repeat while ((buf := ser.CharIn) <> CR)  ' Get subsequent bytes until a carriage return is received
        if (buf => "0") and (buf =< "9")          ' If the byte entered is an actual number
          value *= 10
          value += (buf - "0")                      ' Keep converting into a decimal value...


PRI Display_Permutations(n, r) | value, i
{{  http://www.mathsisfun.com/combinatorics/combinations-permutations-calculator.html

    Order important, no repetition
    Total pins (n)
    Number of pins needed (r)
    Number of permutations: n! / (n-r)!
}}

  ser.Str(String(CR, LF, "Possible permutations: "))

  ' Thanks to Rednaxela of #tymkrs for the optimized calculation
  value := 1
  repeat i from (n - r + 1) to n
    value *= i    

  ser.Dec(value)


PRI Display_Voltage_Error
  ser.Str(String(CR, LF, "Target voltage must be defined!"))

     
PRI SystemInit
  ' Set direction of I/O pins
  ' Output
  dira[TXS_OE] := 1
  dira[LED_R]  := 1        
  dira[LED_G]  := 1
   
  ' Set I/O pins to the proper initialization values
  TXSDisable      ' Disable level shifter outputs (high-impedance)
  LedYellow       ' Yellow = system initialization

  ' Set up PWM channel for DAC output
  ' Based on Andy Lindsay's PropBOE D/A Converter (http://learn.parallax.com/node/107)
  ctra[30..26]  := %00110       ' Set CTRMODE to PWM/duty cycle (single ended) mode
  ctra[5..0]    := DAC_OUT      ' Set APIN to desired pin
  dira[DAC_OUT] := 1            ' Set pin as output
  DACOutput(0)                  ' DAC output off 

  vTarget := -1                 ' Target voltage is undefined 
  rr.start                      ' Start RealRandom cog
  ser.Start(115_200)            ' Start serial communications


PRI DACOutput(dacval)
  spr[10] := dacval * 16_777_216    ' Set counter A frequency (scale = 2³²÷ 256)  

    
PRI TXSEnable
  dira[23..0]~                      ' Set P23-P0 as inputs to avoid contention when driver is enabled. Pin directions will be configured by other functions as needed.
  outa[TXS_OE] := 1
  waitcnt(clkfreq / 100_000 + cnt)  ' 10uS delay (must wait > 200nS for TXS0108E one-shot circuitry to become operational)


PRI TXSDisable
  outa[TXS_OE] := 0

    
PRI LedOff
  outa[LED_R] := 0 
  outa[LED_G] := 0

  
PRI LedGreen
  outa[LED_R] := 0 
  outa[LED_G] := 1

  
PRI LedRed
  outa[LED_R] := 1 
  outa[LED_G] := 0

  
PRI LedYellow
  outa[LED_R] := 1 
  outa[LED_G] := 1

               
DAT
InitHeader    byte CR, LF, "JTAGulator 1.1.1", CR, LF
              byte "Designed by Joe Grand [joe@grandideastudio.com]", CR, LF, 0

CommandList   byte CR, LF, "JTAG Commands:", CR, LF
              byte "I   Identify JTAG pinout (IDCODE Scan)", CR, LF
              byte "B   Identify JTAG pinout (BYPASS Scan)", CR, LF
              byte "D   Get Device ID(s)", CR, LF
              byte "T   Test BYPASS (TDI to TDO)", CR, LF
              byte CR, LF, "UART Commands:", CR, LF
              byte "U   Identify UART pinout", CR, LF
              byte "P   UART pass through", CR, LF              
              byte CR, LF, "General Commands:", CR, LF
              byte "V   Set target system voltage (1.2V to 3.3V)", CR, LF
              byte "R   Read all channels (input)", CR, LF  
              byte "W   Write all channels (output)", CR, LF
              byte "H   Print available commands", 0

' Look-up table to correlate actual voltage (1.2V to 3.3V) to DAC value
' Full DAC range is 0 to 3.3V @ 256 steps = 12.89mV/step
'                  1.2  1.3  1.4  1.5  1.6  1.7  1.8  1.9  2.0  2.1  2.2  2.3  2.4  2.5  2.6  2.7  2.8  2.9  3.0  3.1  3.2  3.3           
VoltageTable  byte  93, 101, 109, 116, 124, 132, 140, 147, 155, 163, 171, 179, 186, 194, 202, 210, 217, 225, 233, 241, 248, 255

' Look-up table of accepted values for use with UART identification
BaudRate      long  75, 110, 150, 300, 900, 1200, 1800, 2400, 3600, 4800, 7200, 9600, 14400, 19200, 28800, 31250 {MIDI}, 38400, 57600, 76800, 115200, 153600, 230400, 250000 {DMX}, 307200
BaudRateEnd

      