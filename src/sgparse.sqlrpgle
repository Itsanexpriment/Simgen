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

ctl-opt dftactgrp(*no);

////////////////////////
//     Prototypes     //
////////////////////////

dcl-pi SGPARSE;
  in_Pgm likeds(qualObj_t) const;
  in_pcmlFilePath char(100) const;
  out_resolvedPgm likeds(qualObj_t);
  out_errMsg char(50) options(*nopass);
end-pi;

dcl-pr WriteVariable extproc(g_writerPtr);
  *n likeds(SimGenRec) const;
end-pr;

////////////////////////
//     Variables      //
////////////////////////

dcl-ds g_Pcml qualified;
  Program likeds(program_t);
  Struct likeds(struct_t) dim(MAX_STRUCTS); // structs definition
end-ds;

dcl-ds program_t qualified template;
  name char(10);
  lib char(10); // not part of the pcml, added manually
  path char(50);
  data likeds(data_t) dim(MAX_VARS);  // parameters
end-ds;

dcl-ds struct_t qualified template;
  name char(20);
  count zoned(5);
  data likeds(data_t) dim(MAX_VARS);  // subfields
end-ds;

dcl-ds data_t qualified template;
  name char(20);
  type char(10);
  length zoned(5);
  precision zoned(5);
  struct char(20);  // name of parent struct
  count zoned(5);   // dim of array
end-ds;

dcl-ds qualObj_t qualified template;
  name char(10);
  lib  char(10);
end-ds;

dcl-ds SimGenRec extname('F_SIMGEN') qualified template end-ds;

dcl-ds g_Pgm likeds(in_Pgm);

dcl-ds PgmDs psds;
  excpCode char(6) pos(40);
end-ds;

dcl-ds CalledPgm likeds(qualObj_t);

dcl-c MAX_STRUCTS const(99);
dcl-c MAX_VARS const(99);
dcl-c MAX_ARR_DIM const(9999);

// variable types
dcl-c TYP_STRUCT const('STRUCT');
dcl-c TYP_CHAR const('CHAR');
dcl-c TYP_ZONED const('ZONED');
dcl-c TYP_PACKED const('PACKED');
dcl-c TYP_INT const('INT');

// pointer to the current writer proc
dcl-s g_writerPtr pointer(*proc);

// each variable(inc. elems of array) has a unique id
dcl-s g_id zoned(5);
// each array has a unique id
dcl-s g_arrId zoned(5);

dcl-s g_errMsg char(50);

////////////////////////
//       Main         //
////////////////////////

exec sql set option commit = *none;

g_errMsg = Init();
if g_errMsg <> *blanks;
  ExitWithError(g_errMsg);
  return;
endif;

g_Pcml = ParsePcml(g_Pgm:in_pcmlFilePath:g_errMsg);
if g_errMsg <> *blanks;
  ExitWithError(g_errMsg);
  return;
endif;

// first we parse the data structures
g_writerPtr = %paddr(WriteDs);

g_errMsg = ParseDataStructures(g_Pcml.Struct);
if g_errMsg <> *blanks;
  ExitWithError(g_errMsg);
  return;
endif;

// then we parse the program parameters
ResetId();
ResetArrId();
g_writerPtr = %paddr(WriteParm);

g_errMsg = ParseParamterList(g_Pcml.Program.data);
if g_errMsg <> *blanks;
  ExitWithError(g_errMsg);
  return;
endif;

// if program name was passed as param,
// we override the pgm name that was in the pcml
if g_Pgm.name <> *blanks;
  g_Pcml.Program.name = g_Pgm.name;
endif;
// same with lib
if g_Pgm.lib <> *blanks;
  g_Pcml.Program.lib = g_Pgm.lib;
endif;

out_resolvedPgm.name = g_Pcml.Program.name;
out_resolvedPgm.lib = g_Pcml.Program.lib;

exec sql drop table QTEMP/F_#STRCT;
*inlr = *on;

////////////////////////
//   Sub-Procedures   //
////////////////////////

dcl-proc ParsePcml;
  dcl-pi *n like(g_Pcml);
    Pgm likeds(in_Pgm) const;
    pcmlPath like(in_pcmlFilePath) const;
    errMsg like(out_errMsg);
  end-pi;

  dcl-ds Pcml likeds(g_Pcml);
  dcl-s srcPcml char(65535);
  dcl-s xmlOptions char(250);

  clear Pcml;

  xmlOptions = 'case=any allowmissing=yes allowextra=yes ccsid=UCS2';
  if pcmlPath <> *blanks;
    srcPcml = pcmlPath;
    xmlOptions = %trim(xmlOptions) + ' doc=file';
  else;
    srcPcml = ExtractPcmlFromModule(Pgm:errMsg);
  endif;

  if errMsg <> *blanks;
    return *blanks;
  endif;

  monitor;
    xml-into Pcml %xml(%trim(srcPcml):%trim(xmlOptions));
  on-error;
    errMsg = 'Parsing error occurred';
    return *blanks;
  endmon;

  Pcml.Program.lib = extractLib(Pcml.Program.path);

  return Pcml;
end-proc;

dcl-proc ExtractPcmlFromModule;
  dcl-pi *n like(data);
    QualObj likeds(qualObj_t) const;
    errMsg like(out_errMsg);
  end-pi;

  dcl-pr QBNRPII extpgm('QBNRPII');
    *n likeds(PgmInterfaceInfoHeader_t); // receiver
    *n int(10) const; // receiver length
    *n like(formatName) const; // format name
    *n likeds(qualObj_t) const; // obj name
    *n like(objType) const;
    *n likeds(qualObj_t) const; // bound module name
    *n likeds(errCode);
  end-pr;

  // QBNRPII variables
  dcl-ds PgmInterfaceInfoHeader_t qualified;
    bytesReturned int(10);
    bytesAvailable int(10);
    objName char(10);
    objLibName char(10);
    objType char(10);
    *n char(2);
    offsetFirstEntry int(10);
    numberEntries int(10);
  end-ds;

  dcl-ds Entry qualified based(pEntry);
    offsetNextEntry int(10);
    moduleName char(10);
    moduleLibrary char(10);
    interfaceInfoCcsid int(10);
    interfaceInfoType int(10);
    offsetInterfaceInfo int(10);
    interfaceInfoLengthRet int(10);
    interfaceInfoLengthAvail int(10);
  end-ds;

  dcl-ds errCode qualified;
    bytesProv  int(10);
    bytesAvail int(10);
  end-ds;

  dcl-ds TempHeader likeds(PgmInterfaceInfoHeader_t);
  dcl-ds Header likeds(PgmInterfaceInfoHeader_t) based(pHeader);
  dcl-ds QualMod likeds(QualObj);
  dcl-s formatName char(8) inz('RPII0100');
  dcl-s objType char(10);
  // end of QBNRPII variables

  dcl-s data char(65535) based(pData);
  dcl-s freeOnExit ind;

  clear TempHeader;
  clear pHeader;
  clear pEntry;
  clear errMsg;

  QualMod.name = '*ALLBNDMOD';
  callp QBNRPII(TempHeader:%len(TempHeader):formatName:QualObj:'*PGM':QualMod:errCode);

  if TempHeader.bytesAvailable <= TempHeader.bytesReturned;
    pHeader = %addr(TempHeader);
  else;
    pHeader = %alloc(TempHeader.bytesAvailable);
    freeOnExit = *on;

    callp QBNRPII (Header:TempHeader.bytesAvailable:
                   formatName:QualObj:'*PGM':QualMod:errcode);
  endif;

  if Header.numberEntries = 0 or errCode.bytesAvail > 0;
    errMsg = 'Pcml info not found in module';
    return *blanks;
  endif;

  pEntry = pHeader + Header.offsetFirstEntry;
  pData = pHeader + Entry.offsetInterfaceInfo;

  if Entry.interfaceInfoLengthRet > %len(data);
    errMsg = 'Pcml info exceeds limit:' + %char(%len(data));
    return *blanks;
  endif;

  return %subst(data:1:Entry.interfaceInfoLengthRet);
  on-exit;
  // cleanup
    if freeOnExit;
      dealloc(n) pHeader;
    endif;
end-proc;

dcl-proc extractLib;
  dcl-pi *n like(program_t.lib);
    src like(program_t.path) value;
  end-pi;

  dcl-c LIB_SUFFIX const('.LIB');

  dcl-s lib like(program_t.lib);
  dcl-s word varchar(50);
  dcl-s sPos zoned(3);

  src = %upper(src);
  for-each word in %split(src :'/');
    word = %trim(word);
    if %len(word) > %len(lib) + %len(LIB_SUFFIX);
      iter;
    endif;

    sPos = %scan(LIB_SUFFIX:word);
    if sPos < 2 or
       sPos <> %len(word) - %len(LIB_SUFFIX) + 1;
      iter;
    endif;

    lib = %subst(word:1:sPos - 1);
  endfor;

  return lib;
end-proc;

dcl-proc ParseDataStructures;
  dcl-pi *n like(g_errMsg);
    Structs likeds(struct_t) dim(MAX_STRUCTS) const;
  end-pi;

  dcl-s errDesc like(g_errMsg);
  dcl-s i int(5);

  for i = 1 to %elem(Structs);
    if Structs(i).name = *blanks;
      return *blanks; // no more Structs to parse
    endif;

    errDesc = ParseDataStructure(Structs(i));
    if errDesc <> *blanks;
      return errDesc;
    endif;
  endfor;

  return *blanks;
end-proc;

dcl-proc ParseDataStructure;
  dcl-pi *n like(g_errMsg);
    Struct likeds(struct_t) const;
  end-pi;

  dcl-ds StructsRec extname('F_SIMGEN') qualified inz;
  end-ds;

  dcl-s structName like(struct_t.name);
  dcl-s id like(g_id);
  dcl-s errDesc like(g_errMsg);
  dcl-s nbytes zoned(5);
  dcl-s i int(5);

  structName = Struct.name;
  if not isNameUnique(structName);
    return 'DS name in not unique: ' + %trim(structName);
  endif;

  if Struct.count > MAX_ARR_DIM;
    return 'Invalid dim of array: ' + %trim(structName);
  endif;

  clear StructsRec;

  // gen array id
  if Struct.count > 0;
    StructsRec.ARRID = GenArrId();
  endif;

  // static fields
  StructsRec.SIMPNAME = structName;
  StructsRec.TYPE = TYP_STRUCT;
  StructsRec.ARRDIM = Struct.count;

  for i = 1 to %max(1:Struct.count);
    id = GenId();
    StructsRec.SMID = id;
    StructsRec.ARRPOS = i;

    nbytes = ParseSubFields(Struct.data:id);
    // TODO! - add check for valid nbytes value
    StructsRec.LENGTH = nbytes;
    WriteVariable(StructsRec);
  endfor;

  return *blanks;
end-proc;

dcl-proc ParseSubFields;
  dcl-pi *n like(nbytes);
    subFields likeds(data_t) dim(MAX_VARS) const;
    parentId int(5) const;
  end-pi;

  dcl-s nbytes zoned(5);
  dcl-s i int(5);

  for i = 1 to %elem(subFields);
    if subFields(i).name = *blanks;
      leave;
    endif;

    nbytes += ParseSubField(subFields(i):parentId);
  endfor;

  return nbytes;
end-proc;

dcl-proc ParseSubField;
  dcl-pi *n like(nbytes);
    subField likeds(data_t) const;
    parentId int(5) const;
  end-pi;

  dcl-ds SubFldRec extname('F_SIMGEN') qualified;
  end-ds;

  dcl-s id like(g_id);
  dcl-s templateId like(SubFldRec.SMID);
  dcl-s nbytes zoned(5);
  dcl-s i int(5);

  if subField.count > MAX_ARR_DIM;
    return -1;
  endif;

  clear SubFldRec;

  // gen array id
  if subField.count > 0;
    SubFldRec.ARRID = GenArrId();
  endif;

  // constant fields
  SubFldRec.SIMPNAME = subField.name;
  SubFldRec.ARRDIM   = subField.count;
  SubFldRec.PARENTID = parentId;
  SubFldRec.TYPE = %upper(subField.type);
  SubFldRec.PRECISION = subField.precision;

  for i = 1 to %max(1:subField.count);
    id = GenId();
    SubFldRec.SMID      = id;
    SubFldRec.ARRPOS    = i;

    if SubFldRec.TYPE = TYP_STRUCT;
      // fetch templateId only once
      if templateId = 0;
        templateId = FetchTemplateDsId(subField.struct);
        if templateId < 1;
          return -1;
        endif;
      endif;
      // TODO! - handle copy error (returns -1)
      SubFldRec.LENGTH = CopySubFields(templateId:id);
    else;
      SubFldRec.LENGTH = subField.length;
    endif;
    nbytes += CalcSizeInBytes(SubFldRec.TYPE:SubFldRec.LENGTH);

    WriteVariable(SubFldRec);
  endfor;

  return nbytes;
end-proc;

dcl-proc ParseParamterList;
  dcl-pi *n like(g_errMsg);
    Params likeds(data_t) dim(MAX_VARS) const;
  end-pi;

  dcl-s errDesc like(g_errMsg);
  dcl-s i int(5);

  for i = 1 to %elem(Params);
    if Params(i).name = *blanks;
      return *blanks; // no more Params to parse
    endif;
    errDesc = ParseParamter(Params(i));
    if errDesc <> *blanks;
      return errDesc;
    endif;
  endfor;

  return *blanks;
end-proc;

dcl-proc ParseParamter;
  dcl-pi *n like(g_errMsg);
    Param likeds(data_t) const;
  end-pi;

  dcl-ds ParamRec extname('F_SIMGEN') qualified;
  end-ds;

  dcl-s errDesc like(g_errMsg);
  dcl-s templateId like(ParamRec.SMID);
  dcl-s i int(5);

  if Param.count > MAX_ARR_DIM;
    return 'Invalid dim of array: ' + %trim(Param.name);
  endif;

  clear ParamRec;

  ParamRec.SIMPNAME = Param.name;
  ParamRec.TYPE = %upper(Param.type);
  ParamRec.ARRDIM = Param.count;
  ParamRec.PRECISION = Param.precision;

  // gen array id
  if Param.count > 0;
    ParamRec.ARRID = GenArrId();
  endif;

  for i = 1 to %max(1:Param.count);
    ParamRec.SMID = GenId();
    ParamRec.ARRPOS = i;

    if ParamRec.TYPE = TYP_STRUCT;
      // fetch templateId only once
      if templateId = 0;
        templateId = FetchTemplateDsId(Param.struct);
        if templateId < 1;
          return 'no Ds definiton for: ' + %trim(Param.struct);
        endif;
      endif;
      // TODO! - handle copy error (returns -1)
      ParamRec.LENGTH = CopySubFields(templateId:ParamRec.SMID);
    else;
      ParamRec.LENGTH = Param.length;
    endif;

    WriteVariable(ParamRec);
  endfor;

  return *blanks;
end-proc;

// c1 cursor
dcl-proc CopySubFields;
  dcl-pi *n like(SimGenRec.LENGTH);
    oldParentId like(SimGenRec.PARENTID) const;
    newParentId like(SimGenRec.PARENTID) const;
  end-pi;

  dcl-ds Data likeds(SubFld) dim(MAX_VARS);

  dcl-ds SubFld extname('F_SIMGEN') qualified;
  end-ds;

  dcl-s prevId like(SimGenRec.SMID);
  dcl-s nbytes like(SimGenRec.LENGTH);
  dcl-s i int(5);
  dcl-s fetched int(5);

  // TODO - maybe fetch just the columns we need,
  //        since we don't use "VALUE" col
  exec sql declare c1 cursor for
            select *
            from QTEMP/F_#STRCT
            where PARENTID = :oldParentId
              and ARRPOS = 1
            order by SMID;
  exec sql open c1;

  exec sql fetch c1 for :MAX_VARS ROWS into :Data;
  exec sql get diagnostics :fetched = ROW_COUNT;

  if sqlcode <> 0;
    // TODO! - better error handling
    snd-msg *ESCAPE ('sql error, code: ' + %char(sqlcode));
    return -1;
  endif;

  exec sql close c1;

  for i = 1 to fetched;
    SubFld = Data(i);
    nbytes += CopySubField(SubFld:oldParentId:newParentId);
  endfor;

  return nbytes;
end-proc;

dcl-proc CopySubField;
  dcl-pi *n like(SimGenRec.LENGTH);
    SrcSubFld likeds(NewSubFld) const;
    oldParentId like(SimGenRec.PARENTID) const;
    newParentId like(SimGenRec.PARENTID) const;
  end-pi;

  dcl-ds NewSubFld extname('F_SIMGEN') qualified;
  end-ds;

  dcl-s prevId like(SimGenRec.SMID);
  dcl-s nbytes like(SimGenRec.LENGTH);
  dcl-s i int(5);
  dcl-s fetched int(5);

  eval-corr NewSubFld = SrcSubFld;

  // gen array id
  if SrcSubFld.ARRDIM > 0;
    NewSubFld.ARRID = GenArrId();
  endif;

  NewSubFld.PARENTID = newParentId;
  for i = 1 to %max(1:SrcSubFld.ARRDIM);
    NewSubFld.SMID = GenId();
    NewSubFld.ARRPOS = i;
    WriteVariable(NewSubFld);

    if SrcSubFld.TYPE = TYP_STRUCT;
      // TODO! - handle copy error (returns -1)
      prevId = SrcSubFld.SMID;
      NewSubFld.LENGTH = CopySubFields(prevId:NewSubFld.SMID);
      nbytes += NewSubFld.LENGTH;
    else;
      nbytes += CalcSizeInBytes(NewSubFld.TYPE:NewSubFld.LENGTH);
    endif;
  endfor;

  return nbytes;
end-proc;

dcl-proc FetchTemplateDsId;
  dcl-pi *n like(SimGenRec.SMID);
    templateName like(SimGenRec.SIMPNAME) const;
  end-pi;

  dcl-s wrk_id like(SimGenRec.SMID);

  exec sql select SMID into :wrk_id
           from QTEMP/F_#STRCT
           where SIMPNAME = :templateName and parentId = 0
           order by SMID;

  if sqlcode <> 0;
    // TODO! - better error handling
    return -1;
  endif;
  return wrk_id;
end-proc;

dcl-proc CalcSizeInBytes;
  dcl-pi *n like(nbytes);
    wrk_varType like(SimGenRec.TYPE)   const;
    wrk_varLen  like(SimGenRec.LENGTH) const;
  end-pi;


  dcl-s nbytes zoned(5);
  dcl-s varLen zoned(5);

  monitor;
    varLen = %int(wrk_varLen);
  on-error;
    return -1;
  endmon;

  select wrk_varType;
    when-is TYP_STRUCT;
      nbytes = varLen;
    when-is TYP_CHAR;
      nbytes = varLen;
    when-is TYP_ZONED;
      nbytes = varLen;
    when-is TYP_PACKED;
      if (%rem(varLen:2) = 0); // is even
        nbytes = (varLen / 2) + 1;
      else;
        nbytes = (varLen + 1) / 2 ;
      endif;
    when-is TYP_INT;
      select varLen;
        when-is 3;
          nbytes = 1;
        when-is 5;
          nbytes = 2;
        when-is 10;
          nbytes = 4;
        when-is 20;
          nbytes = 8;
        other;
          nbytes = -1; // invalid int length
      endsl;
      nbytes = -1; // unsupported var type
  endsl;

  return nbytes;
end-proc;

dcl-proc isNameUnique;
  dcl-pi *n ind;
    dsName like(struct_t.name) const;
  end-pi;
  dcl-s tmp int(3);
  exec sql select (1) into :tmp from QTEMP/F_#STRCT
            where SIMPNAME = :dsName and PARENTID = 0
            fetch first row only;
  return sqlcode = 100; // if not found(=100), it's unique
end-proc;

dcl-proc GetParamtersCount;
  dcl-pi *n zoned(5);
    wrk_pgm likeds(program_t);
  end-pi;

  dcl-s count int(5);
  dcl-s i int(5);

  for i = 1 to %elem(wrk_pgm.data);
    if wrk_pgm.data(i).name = *blanks;
      leave;
    endif;

    count += %min(1:wrk_pgm.data(i).count);
  endfor;

  return count;
end-proc;

dcl-proc GenId;
  dcl-pi *n like(g_id);
  end-pi;
  g_id += 1;
  return g_id;
end-proc;

dcl-proc GenArrId;
  dcl-pi *n like(g_arrId);
  end-pi;
  g_arrId += 1;
  return g_arrId;
end-proc;

dcl-proc ResetId;
  g_id = 0;
end-proc;

dcl-proc ResetArrId;
  g_arrId = 0;
end-proc;

dcl-proc WriteDs;
  dcl-pi *n;
    Rec likeds(SimGenRec) const;
  end-pi;

  exec sql insert into QTEMP/F_#STRCT values :Rec;
end-proc;

dcl-proc WriteParm;
  dcl-pi *n;
    Rec likeds(SimGenRec) const;
  end-pi;

  exec sql insert into QTEMP/F_#SIMGEN values :Rec;
end-proc;

dcl-proc ExecCmd;
  dcl-pi *n;
    wrk_cmd varchar(500) const;
    rtn_excpCode like(excpCode) options(*nopass); // optional error info
  end-pi;

  dcl-pr QCMDEXC extpgm('QCMDEXC');
    *n like(cmd) options(*varsize) const;
    *n like(cmdLen) const;
  end-pr;

  dcl-s cmd char(500);
  dcl-s cmdLen packed(15:5);

  cmd = wrk_cmd;
  cmdLen = %len(wrk_cmd);
  monitor;
    callp QCMDEXC(cmd:cmdLen);
  on-error;
    if %parms() >= %parmnum(rtn_excpCode);
      rtn_excpCode = excpCode;
    endif;
  endmon;
end-proc;

dcl-proc ExitWithError;
  dcl-pi *n;
    errMsg like(out_errMsg) const;
  end-pi;

  exec sql drop table QTEMP/F_#STRCT;

  out_errMsg = %trim(errMsg);
  *inlr = *on;
end-proc;

dcl-proc Init;
  dcl-pi *n like(g_errMsg);
  end-pi;
  dcl-s cmdErr char(10);

  clear out_errMsg;
  clear g_Pcml;

  if in_Pgm.name = *blanks and in_pcmlFilePath = *blanks;
    return 'Must pass Pgm name and/or pcml path';
  endif;

  // delete temp files
  ExecCmd('DLTF FILE(QTEMP/F_#STRCT)');
  ExecCmd('DLTF FILE(QTEMP/F_#SIMGEN)');

  // create temp files
  ExecCmd('CRTDUPOBJ  OBJ(F_SIMGEN) FROMLIB(*LIBL) OBJTYPE(*FILE) +
           TOLIB(QTEMP) NEWOBJ(F_#STRCT)':cmdErr);
  if cmdErr <> *blanks;
    return 'Init error, msgid: ' + %trim(cmdErr);
  endif;

  ExecCmd('CRTDUPOBJ  OBJ(F_SIMGEN) FROMLIB(*LIBL) OBJTYPE(*FILE) +
           TOLIB(QTEMP) NEWOBJ(F_#SIMGEN)':cmdErr);
  if cmdErr <> *blanks;
    return 'Init error, msgid: ' + %trim(cmdErr);
  endif;

  g_Pgm = %upper(in_Pgm);

  return *blanks;
end-proc;
