**free

// Copyright (c) 2025 Paul Gougassian

// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

ctl-opt main(Main);

////////////////////////
//     Prototypes     //
////////////////////////

dcl-pr Main extpgm('SGINVOKE');
  *n likeds(QualObj_t) const; // in_Pgm
  *n like(errMsg_t);
end-pr;

// start: SGUTILS
dcl-pr utl_Serialize likeds(FlatParm_t);
  *n like(errMsg_t);
end-pr;

dcl-pr utl_SizeInBytes like(nBytes_t);
  *n like(VarRec_t.TYPE)  const;
  *n like(VarRec_t.LENGTH) const;
end-pr;

dcl-pr utl_Deserialize like(errMsg_t);
  *n likeds(FlatParm_t) const;
end-pr;
// end: SGUTILS

dcl-ds VarRec_t extname('F_SIMGEN') qualified template;
end-ds;

dcl-c MAX_TOP_LVL_PRMS const(999);
dcl-ds ParmsList_t qualified; // dim(MAX_TOP_LVL_PRMS)
  type char(10);
  byteSize zoned(5);
end-ds;

dcl-ds FlatParm_t qualified template;
  val char(65535);
  size zoned(5);
end-ds;

dcl-ds QualObj_t qualified template;
  name char(10);
  lib  char(10);
end-ds;

dcl-s errMsg_t char(50);
dcl-s nBytes_t zoned(5);

////////////////////////
//       Main         //
////////////////////////

dcl-proc Main;
  dcl-pi *n;
    in_Pgm likeds(QualObj_t) const;
    out_errMsg like(errMsg_t);
  end-pi;

  dcl-ds FlatParm likeds(FlatParm_t);
  dcl-ds ParmsList likeds(ParmsList_t) dim(MAX_TOP_LVL_PRMS);

  clear out_errMsg;

  FlatParm = utl_Serialize(out_errMsg);
  if out_errMsg <> *blanks;
    return;
  endif;

  ParmsList = FillTopLevelParms();

  out_errMsg = InvokePgm(in_Pgm:ParmsList:FlatParm);
  if out_errMsg <> *blanks;
    return;
  endif;

  out_errMsg = utl_Deserialize(FlatParm);
  if out_errMsg <> *blanks;
    return;
  endif;

  return; // success
end-proc;

////////////////////////
//   Sub-Procedures   //
////////////////////////

dcl-proc FillTopLevelParms;
  dcl-pi *n likeds(ParmsList_t) dim(MAX_TOP_LVL_PRMS);
  end-pi;

  dcl-ds RecDs likeds(VarRec_t);
  dcl-ds ParmsList likeds(ParmsList_t) dim(MAX_TOP_LVL_PRMS);
  dcl-s i zoned(5);

  clear ParmsList;

  exec sql declare c1 cursor for
    select * from QTEMP/F_#SIMGEN
    where PARENTID = 0 and ARRPOS = 1
    order by SMID;

  exec sql open c1;
  dow 1 = 1;
    clear RecDs;
    exec sql fetch next from c1 into :RecDs;

    if sqlcode = 100;
      leave;
    endif;

    if sqlcode <> 0;
     // TODO! - handle sql error
      leave;
    endif;

    i += 1;
    ParmsList(i).type = RecDs.TYPE;
    ParmsList(i).byteSize = utl_SizeInBytes(RecDs.TYPE:RecDs.LENGTH) *
                              %max(1:RecDs.ARRDIM);
  enddo;

  exec sql close c1;
  return ParmsList;
end-proc;

dcl-proc InvokePgm;
  dcl-pi *n like(errMsg_t);
    Pgm likeds(QualObj_t) const;
    ParmsList likeds(ParmsList_t) dim(MAX_TOP_LVL_PRMS) const;
    FlatParm likeds(FlatParm_t);
  end-pi;

  dcl-pr CALLPGMV extproc('_CALLPGMV');
    *n like(pgmPtr);
    *n like(argv) dim(MAX_TOP_LVL_PRMS);
    *n like(argc) value;
  end-pr;

  dcl-s pgmPtr pointer;
  dcl-s argc uns(10) inz(0);
  dcl-s argv pointer dim(MAX_TOP_LVL_PRMS);
  dcl-s errMsg like(errMsg_t);

  dcl-s pFlatParm pointer;
  dcl-s i int(5);
  dcl-s byteCount zoned(7);

  errMsg = GetProgramSysPointer(Pgm:pgmPtr);
  if errMsg <> *blanks;
    return errMsg;
  endif;

  pFlatParm = %addr(FlatParm.val);
  for i = 1 to %elem(ParmsList);
    if ParmsList(i).type = *blanks;
      leave;
    endif;
    argv(i) = pFlatParm + byteCount;
    byteCount += ParmsList(i).byteSize;
    argc += 1;
  endfor;

  CALLPGMV(pgmPtr:argv:argc);
  return *blanks;
end-proc;

dcl-proc GetProgramSysPointer;
  dcl-pi *n like(errMsg_t);
    Pgm likeds(QualObj_t) const;
    pgmPtr pointer;
  end-pi;

  dcl-pr RSLVSP2 extproc('_RSLVSP2');
    *n like(libPtr);
    *n likeDs(resolveOpt);
  end-pr;

  dcl-pr RSLVSP4 extproc('_RSLVSP4');
    *n like(pgmPtr);
    *n likeDs(resolveOpt);
    *n like(libPtr);
  end-pr;

  dcl-ds resolveOpt qualified;
    objType char(2);
    objName char(30);
    auth char(2);
  end-ds;

  dcl-c OBJ_PGM const(x'0201');
  dcl-c OBJ_LIB const(x'0401');

  dcl-s libPtr pointer;
  dcl-s withLib ind;

  clear resolveOpt;

  // resolve lib pointer
  if Pgm.lib <> *blanks and %upper(Pgm.lib) <> '*LIBL';
    withLib = *on;
    resolveOpt.objType = OBJ_LIB;
    resolveOpt.objName = Pgm.lib;
    resolveOpt.auth = x'0000';
    monitor;
      RSLVSP2(libPtr:resolveOpt);
    on-error;
      return 'Error resolving library:' + %trim(Pgm.lib);
    endmon;
  endif;

  resolveOpt.objType = OBJ_PGM;
  resolveOpt.objName = %upper(Pgm.name);
  resolveOpt.auth = x'0000';

  monitor;
    if withLib;
      RSLVSP4(pgmPtr:resolveOpt:libPtr);
    else;
      RSLVSP2(pgmPtr:resolveOpt);
    endif;
  on-error;
    return 'Error resolving program:' + Pgm.name;
  endmon;

  return *blanks; // success
end-proc;
