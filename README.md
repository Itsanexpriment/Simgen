# Simgen

Utility for IBM i (AS/400) that allows calling programs with a gui (DSPF).

## Features:
* View and modify program parameters and pass values via green screen
* View the state of passed parameters after the call to the desired program
* Easy to use, only one line needs to be added to source code of the called program

## How to use:
1) add control option to the called program ``` ctl-opt pgminfo(*pcml:*module) ```
2) compile the called program
3) add the utility library to the Library List
4) in command line, enter command SIMGEN and press F4 (prompt)

## Installation:
1) add source files in src folder to your preferred lib/srcfile (with the same member name)
2) compile CLLE member SGINTALL
3) SGINTALL accepts three (optional) params:<br>
  a) srclib  - lib of SIMGEN source file,  defaults to PSIMGEN<br>
  b) srcfile - srcfile of SIMGEN members, defaults to SIMGENSRC<br>
  c) dstlib  - destination of compiled objects, defaults to srclib<br>

for <b>quick installation</b>, create a lib called PSIMGEN and source file SIMGENSRC with rcdlen 112.<br>
place the source members in SIMGENSRC, compile and run SGINSTALL without any params (CALL PSIMGEN/SGINSTALL).

to install manually, run commands in order:
  <details>
    <summary> Click to expand </summary>
    
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
    CRTCMD CMD(MYLIB/SIMGEN) PGM(MYLIB/SGMAIN) SRCFILE(MYLIB/MYSRCPF) SRCMBR(SIMGEN)
    ```
  </details>
 
## How it works:
   The main program (SGMAIN) accepts two parameters, pgm_info(name + lib) and pcml_file_path.<br>
   pcml_file_path is optional.<br> 
   If only pgm_info was passed, both the program that will be called and its params definition will be based on this arg.<br>
   If pcml_file_path was passed, the program parameters definition will be based on this arg.<br>
  
   Passing both params allows flexibility when trying to call programs that don't have the pgminfo embedded in the module.<br>
   It also enables calling wrapper programs that don't have the definition of all the parameters<br> 
   (e.g. calling a wrapper CLLE program which accepts a char(1000) whose DS structure is defined in the inner RPGLE)

## WIP:
* add support for service programs (currently only programs are supported)
