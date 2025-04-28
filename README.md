# Simgen

Utility for IBM i (AS/400) that allows calling programs with a gui (DSPF).

## Features:
* view and modify program parameters and pass values via green screen
* view the state of passed parameters after the call to the desired program
* easy to use, only one line needs to be added to source code of called program

## How to use:
1) add control option to the called program ``` ctl-opt pgminfo(*pcml:*module) ```
2) compile the called program
3) add the utility library to the Library List
4) in command line, enter command SIMGEN and press prompt(F4)

## Installation:
* for easy installation, it's recommended to put all source files
  in a library called PSIMGEN and source file SIMGENSRC(rcdlen 112)
* add source files in src folder to PSIMGEN/SIMGENSRC
* compile CL member SGINTALL into lib PSIMGEN and run it
* to install manually, run commands in order:
  ```
  CRTPF   FILE(MYLIB/F_SIMGEN) SRCFILE(MYLIB/MYSRCPF) SRCMBR(F_SIMGEN)
  CRTDSPF FILE(MYLIB/D_SIMGEN) SRCFILE(MYLIB/MYSRCPF) SRCMBR(D_SIMGEN)
  CRTSQLRPGI OBJ(MYLIB/SGMAIN) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SGMAIN) OBJTYPE(*PGM)
  CRTSQLRPGI OBJ(MYLIB/SGPARSE) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SGPARSE) OBJTYPE(*PGM)
  CRTSQLRPGI OBJ(MYLIB/SGSCREEN) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SGSCREEN) OBJTYPE(*PGM)
  CRTSQLRPGI OBJ(MYLIB/SGUTILS) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SGUTILS) OBJTYPE(*MODULE)
  CRTSRVPGM SRVPGM(MYLIB/SGUTILS) EXPORT(*ALL)
  CRTSQLRPGI OBJ(MYLIB/SGINVOKE) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SGINVOKE) OBJTYPE(*MODULE)
  CRTPGM PGM(MYLIB/SGINVOKE) BNDSRVPGM((SGUTILS))
  CRTCMD CMD(PSIMGEN/SIMGEN) PGM(PSIMGEN/SGMAIN) SRCFILE(PSIMGEN/SIMGENSRC) SRCMBR(SIMGEN)
  ```
## How it works:
   the main program (SGMAIN) accepts two parameters, pgm_info (name + lib) and pcml_file_path.
   Atleast one of them has to be passed, but its optional to use both. 
   If pgm_info was passed, the called program will be based on this arg.
   If pcml_file_path was passed, the called program parameters will be based on this arg.

   If both are passed, the pgm_info arg overrides the pgm info that's in the pcml when determining what program to call.<br>
   The pcml_file_path arg takes precedence over the pcml that's embedded in the module of the passed pgm_info. In this case,
   it's not necessary to embed the pcml in the module.
  
   if pcml file path wasn't provided, the pcml info is extracted from the module
   of the pgm_info arg.<br> You can embed the pcml info in the module during compilation
   by using the above mentioned ctl-opt, or by compiling with the PGMINFO parameter in CRTBNDxxx/CRTxxxMOD cmd.

## WIP:
* add support for service programs (currently only programs are supported)
