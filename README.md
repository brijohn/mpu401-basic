# MPU401 Basic Extensions

This is a program for the C64 that will extend basic to support controlling a mpu401 unit via a MIF-C64 cartridge adapter.

### Build
``make`` will build mpu401.prg and mpu401.d64 in the build directory.

### Extended Basic Commands
* ``mpu <command>`` <br>
  Send a command to the MPU unit. <br>
  example: ``mpu 63: REM put the mpu into UART mode``
* ``mpu in <numeric variable>`` <br>
  Read incoming midi byte into a variable. A value of 244 means no data in queue. <br>
  example: ``mpu in MV: REM Read next midi in value into variable MV``
* ``midi voice on <note>,<channel>,<velocity>`` <br>
  Send midi noteon command <br>
  example: ``midi voice on 60,2,70: REM Turn on middle C on channel 2 with velocity of 70``
* ``midi voice off <note>,<channel>,<velocity>`` <br>
  Send midi noteoff command <br>
  example: ``midi voice off 60,2,70: REM Turn off middle C on channel 2 with velocity of 70``
* ``midi program <program>,<channel>`` <br>
  Send midi program change command <br>
  example: ``midi program 43,2: REM Change program on channel 2 to patch number 43``
* ``midi ctrl <control>,<channel>,<value>`` <br>
  Send midi control change command <br>
  example: ``midi ctrl 34,2,87: REM Change value of control 34 on channel 2 to 87`` <br>
* ``midi pitch <pitch>,<channel>`` <br>
  Send midi pitch bend change command <br>
  example: ``midi pitch 8448,2: REM Change pitch bend for channel 2 to 8448``
