             CMD        PROMPT('SIMGEN UTILITY')
             PARM       KWD(PGM) TYPE(Q1) PROMPT('Program')
 Q1:         QUAL       TYPE(*NAME) LEN(10)
             QUAL       TYPE(*NAME) LEN(10) DFT(*LIBL) SPCVAL((*LIBL)) +
                        PROMPT('Library')
             PARM       KWD(PCMLPTH) TYPE(*CHAR) LEN(100) +
                        PROMPT('Pcml file path')
