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

dcl-pi SGSCREEN;
  in_Pgm likeds(qualObj_t) const;
end-pi;

dcl-pr InvokePgm extpgm('SGINVOKE');
  *n like(in_Pgm) const;
  *n char(50); // err message
end-pr;

dcl-f D_SIMGEN workstn indds(Dspf) infds(infoDs)
                       sfile(MAINSFL:RRN)
                       sfile(ARRSFL:RRN_B);

dcl-ds Dspf qualified;
  // func keys
  exit ind pos(3);
  exec ind pos(6);
  cancel ind pos(12);
  // sfl & ctl
  dspSfl ind pos(31);
  dspCtl ind pos(32);
  moreSfl ind pos(33);
  dspArrSfl ind pos(36);
  dspArrCtl ind pos(37);
  moreArrSfl ind pos(38);
  // sfl "value" field size
  fieldSize char(10) pos(51);
  fieldSizeInds ind dim(10) overlay(fieldSize);
  // error inds
  showErr ind pos(70);
  selectionErr ind pos(71);
  inputErr ind pos(72);
  showArrWdwErr ind pos(73);
  errOverlay ind dim(10) samepos(showErr);
  // view mode
  nestedView ind pos(81);
  arrayView  ind pos(82);
  elemSlctView   ind pos(83);
  changedVarView ind pos(84);
  promptView ind pos(85);
end-ds;

dcl-ds qualObj_t qualified template;
  name char(10);
  lib  char(10);
end-ds;

dcl-ds infoDs;
  keyPressed char(1) pos(369);
end-ds;

// holds main sfl page context
dcl-ds Ctx qualified;
  pageIdx zoned(5) inz(1);
  parentId like(CurrPrm.PARENTID) inz(0);
  count zoned(3) inz(0);
  isFirstPage ind inz(True);
  isLastPage  ind inz(True);
end-ds;

// holds error context
dcl-ds ErrCtx qualified;
  rcdNum zoned(2);
  selectionErr ind;
  inputErr ind;
  msg char(30);
end-ds;

// holds current array sfl page context
dcl-ds ArrCtx qualified;
  pageIdx zoned(5) inz(1);
  arrId like(CurrPrm.ARRID) inz(0);
  count zoned(3) inz(0);
  isFirstPage ind inz(True);
  isLastPage  ind inz(True);
end-ds;

dcl-c SFL_PAGE const(15);
dcl-c SFL_PAGE_PLUS_ONE const(16);

dcl-c ARR_SFL_PAGE const(10);
dcl-c ARR_SFL_PAGE_PLUS_ONE const(11);

dcl-ds Data extname('F_SIMGEN') dim(SFL_PAGE_PLUS_ONE) qualified;
end-ds;

dcl-ds CurrPrm extname('F_SIMGEN') qualified;
end-ds;

dcl-ds g_Parents qualified;
  val char(15) dim(15);
  cnt zoned(2);
end-ds;

dcl-ds cacheResult_t qualified template;
  found ind;
  val like(CurrPrm.VALUE);
end-ds;

// variable types
dcl-c TYP_STRUCT const('STRUCT');
dcl-c TYP_CHAR const('CHAR');
dcl-c TYP_ZONED const('ZONED');
dcl-c TYP_PACKED const('PACKED');
dcl-c TYP_INT const('INT');

dcl-c True const('1');
dcl-c False const('0');
dcl-c DIGITS const('0123456789');
dcl-c MAX_DSP_LEN const(80);
dcl-c MAX_NESTED_DS const(15);

// key constants
dcl-c F2 const(x'32');
dcl-c F3 const(x'33');
dcl-c F6 const(x'36');
dcl-c F8 const(x'38');
dcl-c F12 const(x'3C');
dcl-c Enter const(x'F1');
dcl-c PageDown const(x'F5');
dcl-c PageUp const(x'F4');

dcl-s sizeToIndsMap char(6) dim(MAX_DSP_LEN) ctdata perrcd(10);
dcl-s RRN   zoned(3); // main sfl
dcl-s RRN_B zoned(3); // array sfl

dcl-s g_refreshMain ind;
dcl-s g_errDesc char(50);

// allows dynamic access to subfile fields
dcl-ds *n extname('D_SIMGEN':'MAINSFL');
  FldAOverlay char(3240) samepos(FLDA001);
end-ds;
dcl-ds *n extname('D_SIMGEN':'ARRSFL');
  FldBOverlay char(3240) samepos(FLDB001);
end-ds;

////////////////////////
//       Main         //
////////////////////////

exec sql set option commit = *none;

g_errDesc = TryInit();
if g_errDesc <> *blanks;
// TODO! - do something with errDesc
  *inlr = *on;
  return;
endif;

g_refreshMain = True;
dow not Dspf.exit;
  RefreshMainSfl();
  WriteScreen();

  exfmt MAINCTRL;
  ClearDspfErrors();

  // first we check for keys that don't
  // require reading user input(and validating it)
  select keyPressed;
    when-is F3;
      leave;
    when-is F8;
      Dspf.changedVarView = False;
      g_refreshMain = True;
      iter;
    when-is F12;
      if Dspf.nestedView;
        LoadParent();
        iter;
      endif;
  endsl;

  // save user input to cache
  CacheValues(FldAOverlay);

  // TODO - maybe add option to toggle validity check
  // ValidateMainInput();
  // if ErrCtx.rcdNum <> 0;
  //   g_refreshMain = True;
  //   iter; // user input err
  // endif;

  // keys that require reading/validating user input
  select keyPressed;
    when-is F2;
      SaveMainSfl();
    when-is F6;
      PerformCall();
    when-is PageDown;
      ChangePageByDelta(+1);
    when-is PageUp;
      ChangePageByDelta(-1);
    when-is Enter;
      HandleSelection();
      g_refreshMain = True;
  endsl;
enddo;

*inlr = *on;

////////////////////////
//   Sub-Procedures   //
////////////////////////

dcl-proc PerformCall;
  dcl-s err char(50);

  SaveMainSfl();
  callp InvokePgm(in_Pgm:err);

  if err <> *blanks;
  // TODO! - do something with err
    return;
  endif;

  // prompts user to select if they wish to view changed variables (post call)
  Dspf.changedVarView = PromptUpdatedVariables();
  // we should refresh the main sfl to load the update variables
  g_refreshMain = Dspf.changedVarView;
end-proc;

// return True if user wishes to view updated vars, else False
dcl-proc PromptUpdatedVariables;
  dcl-pi *n ind;
  end-pi;

  Dspf.promptView = True;

  dow not Dspf.cancel;
    exfmt CHGWDW;
    if keyPressed = Enter;
      return True;
    endif;
  enddo;

  return False;
  on-exit;
    Dspf.promptView = False;
end-proc;

dcl-proc ValidateMainInput;
  dcl-s errMsg char(30);
  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  for i = 1 to Ctx.count;
    chain i MAINSFL;

    if PRMDLEN <> 0;
      val = getSflValue(FldAOverlay:PRMDLEN);
      errMsg = ValidateInputVal(val:PRMOGTYP:PRMOGLEN:PRMOGPRC);
    endif;

    if errMsg <> *blanks;
      ErrCtx.rcdNum = i;
      ErrCtx.msg = errMsg;
      ErrCtx.inputErr = *on;
      return;
    endif;

  endfor;
end-proc;

dcl-proc LoadParent;
  dcl-s newParent like(Ctx.parentId);

  exec sql
    select PARENTID into :newParent
    from QTEMP/F_#SIMGEN
    where SMID = :Ctx.parentId;

  if sqlcode <> 0;
    // TODO - handle error, even though this shouldn't fail
  endif;

  g_Parents.val(g_Parents.cnt) = *blanks;
  g_Parents.cnt -= 1;

  // ClearCache('PARENTID':%char(Ctx.parentId));
  reset Ctx;
  Ctx.parentId = newParent;
  g_refreshMain = True;
end-proc;

dcl-proc ValidateInputVal;
  dcl-pi *n like(errMsg);
    val char(MAX_DSP_LEN) const;
    varType like(CurrPrm.TYPE) const;
    varLen like(CurrPrm.LENGTH) const;
    varPrecision like(CurrPrm.PRECISION) const;
  end-pi;

  dcl-s errMsg char(30);

  select varType;
    when-is TYP_CHAR; // a char is always valid
    when-is TYP_INT;
      errMsg = ValidateInt(val:varLen);
    when-is TYP_PACKED;
      errMsg = ValidateDec(val:varLen:varPrecision);
    when-is TYP_ZONED;
      errMsg = ValidateDec(val:varLen:varPrecision);
  endsl;

  return errMsg;
end-proc;

dcl-proc ValidateInt;
  dcl-pi *n like(errMsg);
    val char(MAX_DSP_LEN) const;
    varLen like(CurrPrm.LENGTH) const;
  end-pi;

  dcl-s errMsg char(30);

  dcl-s int3 int(3);
  dcl-s int5 int(5);
  dcl-s int10 int(10);
  dcl-s int20 int(20);

  monitor;
    select varLen;
      when-is 3;
        int3 = %int(val);
      when-is 5;
        int5 = %int(val);
      when-is 10;
        int10 = %int(val);
      when-is 20;
        int20 = %int(val);
      other;
        errMsg = 'Invalid int len:' + %char(varLen);
    endsl;
  on-error;
    errMsg = 'Invalid int value';
  endmon;

  return errMsg;
end-proc;

dcl-proc ValidateDec;
  dcl-pi *n like(errMsg);
    val char(MAX_DSP_LEN) const;
    varLen like(CurrPrm.LENGTH) const;
    varPrecision like(CurrPrm.PRECISION) const;
  end-pi;

  dcl-s wrk_val varchar(MAX_DSP_LEN);
  dcl-s errMsg char(30);

  dcl-s i int(3);
  dcl-s c char(1);
  dcl-s beforeDot ind;
  dcl-s intDigits int(3);
  dcl-s decDigits int(3);

  wrk_val = %trim(val);

  // check if blanks
  if wrk_val = *blanks;
    return 'Numeric value can''t be blanks';
  endif;

  c = %subst(wrk_val:1:1);
  if c = '-' or c = '+';
    if %len(wrk_val) = 1;
      return 'Numeric only contains sign';
    endif;
    wrk_val = %subst(wrk_val:2);
  endif;

  beforeDot = True;
  for i = 1 to %len(wrk_val);
    c = %subst(wrk_val:i:1);

    select;
      when %scan(c:DIGITS) > 0;
        if beforeDot;
          intDigits += 1;
        else;
          decDigits += 1;
        endif;
      when c = '.';
        if beforeDot;
          beforeDot = False;
        else;
          return 'Numeric contains two decimal points';
        endif;
      other;
        return 'Invalid Numeric Value';
    endsl;
  endfor;

  if intDigits > varLen;
    return 'Int part of Numeric is invalid';
  endif;

  if decDigits > varPrecision;
    return 'Dec part of Numeric is invalid';
  endif;

  return errMsg;
end-proc;

dcl-proc ClearDspfErrors;
  clear ErrCtx;

  clear Dspf.errOverlay;
  DSERRMSG = *blanks;
end-proc;

dcl-proc RefreshMainSfl;
  if g_refreshMain = False;
    return;
  endif;

  FillMainSfl(Ctx.parentId:Ctx.pageIdx);
  g_refreshMain = False;
end-proc;

dcl-proc CacheArrValues;
  dcl-pi *n;
    values like(FldBOverlay) const;
  end-pi;

  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  if Dspf.changedVarView;
    return;
  endif;

  for i = 1 to ArrCtx.count;
    chain i ARRSFL;
    val = getSflValue(values:DSPRMDLEN);
    exec sql
      merge into QTEMP/F_#TMPVAL as target
      using (values(:DSPRMID, :ArrCtx.arrId, :val)) as source (SMID, ARRID, VALUE)
      on target.SMID = source.SMID
      when matched then
        update set target.VALUE = source.VALUE
      when not matched then
        insert (SMID, ARRID, VALUE) values(source.SMID, source.ARRID, source.VALUE);
  endfor;
end-proc;

dcl-proc CacheValues;
  dcl-pi *n;
    values like(FldAOverlay) const;
  end-pi;

  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  if Dspf.changedVarView;
    return;
  endif;

  for i = 1 to Ctx.count;
    chain i MAINSFL;
    val = getSflValue(values:PRMDLEN);
    exec sql
      merge into QTEMP/F_#TMPVAL as target
      using (values(:PRMID, :val, :PRMARRID)) as source (SMID, VALUE, ARRID)
      on target.SMID = source.SMID
      when matched then
        update set target.VALUE = source.VALUE
      when not matched then
        insert (SMID, VALUE, ARRID) values(source.SMID, source.VALUE, source.ARRID);
  endfor;

end-proc;

dcl-proc ChangeArrPageByDelta;
  dcl-pi *n;
    i_Ctx likeds(ArrCtx) const;
    delta zoned(3) const;
  end-pi;

  if i_Ctx.isFirstPage and delta < 0;
    return;
  endif;

  if i_Ctx.isLastPage and delta > 0;
    return;
  endif;

  FillArrSfl(i_Ctx.arrId:(i_Ctx.pageIdx + delta));
end-proc;

dcl-proc ChangePageByDelta;
  dcl-pi *n;
    delta zoned(3) const;
  end-pi;

  if Ctx.isFirstPage and delta < 0;
    return;
  endif;

  if Ctx.isLastPage and delta > 0;
    return;
  endif;

  Ctx.pageIdx += delta;
  g_refreshMain = True;
end-proc;

dcl-proc HandleSelection;
  dcl-c WORK_WITH_DS const('1');
  dcl-c WORK_WITH_ARRAY const('2');
  dcl-c DISPLAY const('5');

  dcl-s errMsg char(30);
  dcl-s i int(3);

  for i = 1 to Ctx.count;
    chain i MAINSFL;

    select OP;
      when-is WORK_WITH_DS;
        errMsg = ShowSubFields(PRMID:PRMOGTYP);
      when-is WORK_WITH_ARRAY;
        errMsg = ShowArrayWindow(PRMID);
      when-is DISPLAY;
      // TODO - impl
    endsl;

    if errMsg <> *blanks;
      ErrCtx.rcdNum = i;
      ErrCtx.msg = errMsg;
      ErrCtx.selectionErr = *on;
      leave;
    endif;

  endfor;

  g_refreshMain = True;
end-proc;

dcl-proc ShowSubFields;
  dcl-pi *n like(errMsg);
    id   like(PRMID) const;
    type like(PRMOGTYP) const;
  end-pi;

  dcl-s newParentId like(CurrPrm.SMID);
  dcl-s elemIdx like(CurrPrm.ARRPOS) inz(1);
  dcl-s errMsg char(30);

  clear ErrCtx;

  if %upper(type) <> TYP_STRUCT;
    errMsg = ' Variable is not a DataStruct ';
    return errMsg;
  endif;

  if g_Parents.cnt = MAX_NESTED_DS;
    errMsg = 'Reached max num of nested DS';
    return errMsg;
  endif;

  if PRMARRDIM > 0;
    elemIdx = ShowElementSelectionWindow(PRMARRDIM);

    if Dspf.cancel;
      return *blanks;
    endif;

    // elem idx can't be less than 1
    if elemIdx < 1;
      return *blanks;
    endif;
  endif;

  // fetch new parent id
  if elemIdx <> 1;
    exec sql select SMID into :newParentId
      from QTEMP/F_#SIMGEN
      where ARRID = :PRMARRID and
        ARRPOS = :elemIdx;
    if sqlcode <> 0;
      // TODO - handle error, even though this shouldn't fail
    endif;
  else;
    newParentId = PRMID;
  endif;

  g_Parents.cnt += 1;
  g_Parents.val(g_Parents.cnt) = VARNAME;

  reset Ctx;
  Ctx.parentId = newParentId;
  g_refreshMain = True;

  return *blanks; // success
end-proc;

dcl-proc ShowElementSelectionWindow;
  dcl-pi *n like(elemIdx);
    maxElems like(PRMARRDIM) const;
  end-pi;

  dcl-s elemIdx like(CurrPrm.ARRPOS);

  clear ELEMWDW;
  Dspf.elemSlctView = True;

  SLCMAXELM = maxElems;
  dow not Dspf.cancel;
    exfmt ELEMWDW;
    if keyPressed = Enter;
      if SLCTELEM > maxElems;
        SLCTELEM = 0;
      else;
        leave;
      endif;
    endif;
  enddo;

  Dspf.elemSlctView = False;
  return SLCTELEM;
end-proc;

dcl-proc ShowArrayWindow;
  dcl-pi *n like(errMsg);
    id like(PRMID) const;
  end-pi;

  dcl-s refreshArr ind;
  dcl-s arrId like(CurrPrm.ARRID);
  dcl-s type  like(CurrPrm.TYPE);
  dcl-s errMsg char(30);

  Dspf.arrayView = *on;
  clear ErrCtx;

  exec sql
    select TYPE, ARRID into :type, :arrId
    from QTEMP/F_#SIMGEN
    where SMID = :id;

  if sqlcode <> 0;
    errMsg = '   Sql error, sqlcode:' + %char(sqlcode);
    return errMsg;
  endif;

  if arrId = 0;
    errMsg = '   Variable is not an Array   ';
    return errMsg;
  endif;

  if type = TYP_STRUCT;
    errMsg = '   Variable is DataStructure  ';
    return errMsg;
  endif;

  reset ArrCtx;
  ArrCtx.arrId = arrId;

  refreshArr = True;
  dow not Dspf.cancel;
    RefreshArrSfl(refreshArr);
    write ARRWDW;
    exfmt ARRCTRL;
    ClearDspfErrors();

    // doesn't require validation
    select keyPressed;
      when-is F12;
        leave;
    endsl;

    // TODO - maybe add option to toggle validity check
    // ValidateArrInput();
    if ErrCtx.rcdNum <> 0;
      refreshArr = True;
      iter; // user input err
    endif;
    CacheArrValues(FldBOverlay);
    // requires validation
    select keyPressed;
      when-is F2;
        SaveArrSfl();
      when-is PageDown;
        ChangeArrPageByDelta(ArrCtx:+1);
      when-is PageUp;
        ChangeArrPageByDelta(ArrCtx:-1);
    endsl;
  enddo;

  return *blanks;
  on-exit;
    // cleanup
    ClearDspfErrors();
    Dspf.arrayView = *off;
    if arrId <> 0;
      ClearCache('ARRID':%char(arrId));
    endif;
end-proc;

dcl-proc ValidateArrInput;
  dcl-s errMsg char(30);
  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  for i = 1 to ArrCtx.count;
    chain i ARRSFL;

    val = getSflValue(FldBOverlay:DSPRMDLEN);
    errMsg = ValidateInputVal(val:DSPRMOGTYP:DSPRMOGLEN:DSPRMOGPRC);

    if errMsg <> *blanks;
      ErrCtx.rcdNum = i;
      ErrCtx.msg = errMsg;
      ErrCtx.inputErr = *on;
      return;
    endif;
  endfor;

end-proc;

dcl-proc RefreshArrSfl;
  dcl-pi *n;
    shouldRefresh ind;
  end-pi;
  if not shouldRefresh;
    return;
  endif;

  FillArrSfl(ArrCtx.arrId:ArrCtx.pageIdx);
  shouldRefresh = False;
end-proc;

dcl-proc ClearCache;
  dcl-pi *n;
    colName  varchar(10) const;
    colValue varchar(10) const;
  end-pi;

  dcl-s sqlQuery varchar(250);

  sqlQuery  = 'delete from QTEMP/F_#TMPVAL where ';
  sqlQuery += colName + '=';
  sqlQuery += colValue;

  exec sql execute immediate :sqlQuery;
end-proc;

dcl-proc FillArrSfl;
  dcl-pi *n;
    arrId like(CurrPrm.ARRID) const;
    pageIdx like(Ctx.pageIdx) const;
  end-pi;

  dcl-ds CacheResult likeds(cacheResult_t);

  dcl-s fetched int(3);
  dcl-s offset zoned(5);

  dcl-s val like(CurrPrm.VALUE);
  dcl-s dspLen int(3);
  dcl-s i int(3);

  ClearArrSfl();

  ArrCtx.arrId = arrId;
  ArrCtx.pageIdx  = pageIdx;

  ArrCtx.isFirstPage = (pageIdx = 1);
  ArrCtx.isLastPage  = True;

  offset = (ARR_SFL_PAGE * (ArrCtx.pageIdx - 1));
  exec sql
    declare c2 cursor for
    select *
    from QTEMP/F_#SIMGEN
    where ARRID = :ArrCtx.arrId
    order by SMID
    offset :offset rows;

  exec sql close c2;
  exec sql open c2;

  exec sql fetch c2 for :ARR_SFL_PAGE_PLUS_ONE rows into :Data;
  exec sql get diagnostics :fetched = ROW_COUNT;

  if sqlcode <> 0;
    // TODO! - handle sql error
    return;
  endif;
  exec sql close c2;

  if fetched = ARR_SFL_PAGE_PLUS_ONE;
    Dspf.moreArrSfl = True;
    ArrCtx.isLastPage = False;
    fetched = ARR_SFL_PAGE;
  endif;

  if fetched = 0;
    return;
  endif;

  Dspf.fieldSize = *all'0';
  clear ARRSFL;

  // since elems of array have the same type, size etc.
  // we use the first elem to fill these fields only once
  dspLen = FillArrayCommonFields(Data(1));

  for i = 1 to fetched;
    clear CurrPrm;
    clear CacheResult;

    CurrPrm = Data(i);

    DSARRIDX = CurrPrm.ARRPOS;
    RRN_B += 1;
    DSPRMID  = CurrPrm.SMID; // hidden

    CacheResult = GetCachedValue(CurrPrm.SMID);
    if CacheResult.found;
      val = CacheResult.val;
    else;
      val = CurrPrm.VALUE;
    endif;

    FillValueField(val:dspLen:FldBOverlay);
    write ARRSFL;
  endfor;

  if RRN_B > 0;
    Dspf.dspArrSfl = *on;
  endif;
  ArrCtx.count = RRN_B;

  // a subfile record contains an error
  if ErrCtx.rcdNum <> 0;
    chain ErrCtx.rcdNum ARRSFL;

    select;
      when ErrCtx.selectionErr;
        Dspf.showArrWdwErr = *on;
        Dspf.selectionErr = *on;
        // DSERRMSG1 = ErrCtx.msg;
        update ARRSFL;
      when ErrCtx.inputErr;
        Dspf.showArrWdwErr = *on;
        Dspf.inputErr = *on;
        // DSERRMSG1 = ErrCtx.msg;
        update ARRSFL;
    endsl;
  endif;
end-proc;

dcl-proc FillArrayCommonFields;
  dcl-pi *n like(dspLen);
    ArrElem likeds(CurrPrm) const;
  end-pi;

  dcl-s dspLen int(3);
  dcl-s indsToTurnOn char(6);
  dcl-s ind1 int(3);
  dcl-s ind2 int(3);
  dcl-s ind3 int(3);

  DSARRNAM = ArrElem.SIMPNAME;
  DSARRTYP  = %upper(ArrElem.TYPE);
  DSARRLEN  = ArrElem.LENGTH;
  DSDECIMAL = ArrElem.PRECISION;
  dspLen = %min(ArrElem.length:MAX_DSP_LEN);

  DSPRMOGTYP = ArrElem.TYPE; // hidden
  DSPRMOGLEN = ArrElem.LENGTH; // hidden
  DSPRMOGPRC = ArrElem.PRECISION; // hidden

  if IsSignedNumeric(ArrElem.TYPE);
    dspLen += 1; // extra char for sign
  endif;
  if ArrElem.PRECISION > 0;
    dspLen += 1; // extra char for decimal point
  endif;
  DSPRMDLEN = dspLen; // hidden

  indsToTurnOn = sizeToIndsMap(dspLen);

  ind1 = %int(%subst(indsToTurnOn:1:2)) - 50;
  ind2 = %int(%subst(indsToTurnOn:3:2)) - 50;
  ind3 = %int(%subst(indsToTurnOn:5:2)) - 50;
  Dspf.fieldSizeInds(ind1) = *on;
  Dspf.fieldSizeInds(ind2) = *on;
  Dspf.fieldSizeInds(ind3) = *on;

  return dspLen;
end-proc;

dcl-proc ClearArrSfl;
  RRN_B = 0;
  clear ARRSFL;
  clear Data;

  Dspf.dspArrSfl  = *off;
  Dspf.dspArrCtl  = *off;
  Dspf.moreArrSfl = *off;

  write ARRCTRL;
  Dspf.dspArrCtl = *on;
end-proc;

dcl-proc SaveMainSfl;
  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  // exec sql
  //   merge into QTEMP/F_#SIMGEN as target
  //   using (select SMID, VALUE from QTEMP/F_#TMPVAL) as source
  //   on target.SMID = source.SMID
  //   when matched and target.PARENTID = :Ctx.parentId then
  //     update set target.VALUE = source.VALUE;

  exec sql
    merge into QTEMP/F_#SIMGEN as target
    using (select SMID, VALUE from QTEMP/F_#TMPVAL) as source
    on target.SMID = source.SMID
    when matched then
      update set target.VALUE = source.VALUE;

  if sqlcode <> 0 and sqlcode <> 100;
    // TODO - handle sql error
    return;
  endif;

  ClearCache('PARENTID':%char(Ctx.parentId));
end-proc;

dcl-proc SaveArrSfl;
  dcl-s val char(MAX_DSP_LEN);
  dcl-s i int(3);

  for i = 1 to ArrCtx.count;
    chain i ARRSFL;
    val = getSflValue(FldBOverlay:DSPRMDLEN);
    exec sql
    update QTEMP/F_#SIMGEN
    set VALUE = :val
    where SMID = :DSPRMID;
  endfor;
end-proc;

dcl-proc getSflValue;
  dcl-pi *n char(MAX_DSP_LEN);
    values like(FldAOverlay) const;
    dspLen zoned(3) const;
  end-pi;
  dcl-s startPos zoned(5);

  startPos = ((dspLen * (dspLen - 1)) / 2) + 1;
  return %subst(values:startPos:dspLen);
end-proc;

dcl-proc FillMainSfl;
  dcl-pi *n;
    parentId like(CurrPrm.PARENTID) const;
    pageIdx like(Ctx.pageIdx) const;
  end-pi;

  dcl-ds CacheResult likeds(cacheResult_t);

  dcl-s fetched int(3);
  dcl-s offset zoned(5);

  dcl-s val like(CurrPrm.VALUE);
  dcl-s dspLen int(3);
  dcl-s indsToTurnOn char(6);
  dcl-s i int(3);

  dcl-s ind1 int(3);
  dcl-s ind2 int(3);
  dcl-s ind3 int(3);

  ClearMainSfl();

  Ctx.parentId = parentId;
  Ctx.pageIdx  = pageIdx;

  Ctx.isFirstPage = (pageIdx = 1);
  Ctx.isLastPage  = True;

  offset = (SFL_PAGE * (Ctx.pageIdx - 1));
  exec sql
    declare c1 cursor for
    select *
    from QTEMP/F_#SIMGEN
    where PARENTID = :Ctx.parentId and ARRPOS = 1
    offset :offset rows;

  exec sql close c1;
  exec sql open c1;

  exec sql fetch c1 for :SFL_PAGE_PLUS_ONE rows into :Data;
  exec sql get diagnostics :fetched = ROW_COUNT;

  if sqlcode <> 0;
    // TODO! - handle sql error
    return;
  endif;
  exec sql close c1;

  // check if there are more recs
  if fetched = SFL_PAGE_PLUS_ONE;
    Dspf.moreSfl = True;
    Ctx.isLastPage = False;
    fetched = SFL_PAGE;
  endif;

  if parentId = 0;
    Dspf.nestedView = False;
    DSVIEWMD = 'Top Level Parameters';
  else;
    Dspf.nestedView = True;
    DSVIEWMD = 'Subfields of ' + %trim(FormatParentsName(g_Parents));
  endif;

  for i = 1 to fetched;
    Dspf.fieldSize = *all'0';
    clear MAINSFL;

    CurrPrm = Data(i);

    // calc dsp len and turn on indicators
    // for the relevant "VALUE" field
    if CurrPrm.Type = TYP_STRUCT or CurrPrm.ARRDIM <> 0;
      dspLen = 0;
    else;
      dspLen = %min(CurrPrm.length:MAX_DSP_LEN);

      if IsSignedNumeric(CurrPrm.TYPE);
        dspLen += 1; // extra char for sign
      endif;
      if CurrPrm.PRECISION > 0;
        dspLen += 1; // extra char for decimal point
      endif;

      indsToTurnOn = sizeToIndsMap(dspLen);

      ind1 = %int(%subst(indsToTurnOn:1:2)) - 50;
      ind2 = %int(%subst(indsToTurnOn:3:2)) - 50;
      ind3 = %int(%subst(indsToTurnOn:5:2)) - 50;
      Dspf.fieldSizeInds(ind1) = *on;
      Dspf.fieldSizeInds(ind2) = *on;
      Dspf.fieldSizeInds(ind3) = *on;
    endif;

    // Dspf sfl fields
    OP = *blank;
    VARNAME = CurrPrm.SIMPNAME;
    TLEN = FormatTypeLen(CurrPrm.TYPE:CurrPrm.LENGTH:CurrPrm.PRECISION);
    RRN += 1;
    PRMID  = CurrPrm.SMID; // hidden
    PRMARRID = CurrPrm.ARRID; // hidden
    PRMARRDIM = CurrPrm.ARRDIM; // hidden
    PRMOGTYP = CurrPrm.TYPE; // hidden
    PRMOGLEN = CurrPrm.LENGTH; // hidden
    PRMOGPRC = CurrPrm.PRECISION; // hidden
    PRMDLEN = dspLen; // hidden

    if CurrPrm.ARRDIM = 0;
      MAXDIM = '--';
    else;
      MAXDIM = %char(CurrPrm.ARRDIM);
    endif;

    if dspLen <> 0;
      CacheResult = GetCachedValue(CurrPrm.SMID);
      if CacheResult.found;
        val = CacheResult.val;
      else;
        val = CurrPrm.VALUE;
      endif;
      FillValueField(val:dspLen:FldAOverlay);
    endif;

    write MAINSFL;
  endfor;

  if RRN > 0;
    Dspf.dspSfl = *on;
  endif;
  Ctx.count = RRN;

  // check if a subfile record contains an error
  if ErrCtx.rcdNum <> 0;
    chain ErrCtx.rcdNum MAINSFL;

    select;
      when ErrCtx.selectionErr;
        Dspf.showErr = *on;
        Dspf.selectionErr = *on;
        DSERRMSG = ErrCtx.msg;
        update MAINSFL;
      when ErrCtx.inputErr;
        Dspf.showErr = *on;
        Dspf.inputErr = *on;
        DSERRMSG = ErrCtx.msg;
        update MAINSFL;
    endsl;
  endif;
end-proc;

// return err msg if init failed, else blanks
dcl-proc TryInit;
  dcl-pi *n like(g_errDesc);
  end-pi;

  dcl-s errMsg like(g_errDesc);

  exec sql
    create or replace table
    QTEMP/F_#TMPVAL as
    (
      select SMID, ARRID, VALUE from F_SIMGEN
    )
    with no data on replace delete rows;

  if sqlcode <> 0;
    return
      'unable to create QTEMP/F_#TMPVAL, sqlcde:' + %char(sqlcode);
  endif;

  reset Ctx;
  reset ArrCtx;

  clear ErrCtx;
  clear g_Parents;

  return *blanks;
end-proc;

dcl-proc FormatParentsName;
  dcl-pi *n char(50);
    Parents likeds(g_Parents) const;
  end-pi;

  if Parents.cnt = 0;
    return *blanks;
  endif;

  return
    %concatarr('.':%trimr(%subarr(Parents.val:1:Parents.cnt)));
end-proc;

dcl-proc GetCachedValue;
  dcl-pi *n likeds(cacheResult_t);
    id like(CurrPrm.SMID) const;
  end-pi;

  dcl-ds Result likeds(cacheResult_t);
  dcl-s data like(CurrPrm.VALUE);

  clear Result;

  // check  if we should get the values
  // stored in the changed values temp table
  if Dspf.changedVarView;
    exec sql
    select NEWVAL into :data
    from QTEMP/F_#CHGVAR
    where SMID = :id;

    if sqlcode = 0;
      Result.found = True;
      Result.val = data;
    endif;
  else; // we get the values from cache
    exec sql
    select VALUE into :data
    from QTEMP/F_#TMPVAL
    where SMID = :id;

    if sqlcode = 0;
      Result.found = True;
      Result.val = data;
    endif;
  endif;

  return Result;
end-proc;

dcl-proc FillValueField;
  dcl-pi *n;
    varValue char(MAX_DSP_LEN) const;
    dspLen int(3) const;
    receiver like(FldAOverlay);
  end-pi;

  dcl-s startPos zoned(5);

  startPos = ((dspLen * (dspLen - 1)) / 2) + 1;
  %subst(receiver:startPos:dspLen) = varValue;
end-proc;

dcl-proc FormatTypeLen;
  dcl-pi *n like(TLEN);
    varType like(CurrPrm.TYPE)  const;
    varLen like(CurrPrm.LENGTH) const;
    varPrecision like(CurrPrm.PRECISION) const;
  end-pi;

  dcl-ds Formatted len(8);
    shortTyp char(2)    pos(1);
    *n char(1) inz('(') pos(3);
    length char(5)      pos(4);
  end-ds;

  select varType;
    when-is TYP_STRUCT;
      shortTyp = 'DS';
      length = %char(varLen);
    when-is TYP_CHAR;
      shortTyp = 'A';
      length = %char(varLen);
    when-is TYP_ZONED;
      shortTyp = 'S';
      length = %char(varLen) + ',' + %char(varPrecision);
    when-is TYP_PACKED;
      shortTyp = 'P';
      length = %char(varLen) + ',' + %char(varPrecision);
    when-is TYP_INT;
      shortTyp = 'I';
      length = %char(varLen);
  endsl;

  return %trim(Formatted) + ')';
end-proc;

dcl-proc IsSignedNumeric;
  dcl-pi *n ind;
    varType like(CurrPrm.TYPE) const;
  end-pi;

  select varType;
    when-is TYP_ZONED;
      return True;
    when-is TYP_PACKED;
      return True;
    when-is TYP_INT;
      return True;
  endsl;

  return False;
end-proc;

dcl-proc WriteScreen;
  write TITLE;
  write MSGBOX;
  write FUNCK;
end-proc;

dcl-proc ClearMainSfl;
  RRN = 0;
  clear MAINSFL;
  clear Data;

  Dspf.dspSfl  = *off;
  Dspf.dspCtl  = *off;
  Dspf.moreSfl = *off;

  write MAINCTRL;
  Dspf.dspCtl = *on;
end-proc;

** sizeToIndsMap
515253515254515255515256515257515258515259515260515354515355
515356515357515358515359515360515455515456515457515458515459
515460515556515557515558515559515560515657515658515659515660
515758515759515760515859515860515960525354525355525356525357
525358525359525360525455525456525457525458525459525460525556
525557525558525559525560525657525658525659525660525758525759
525760525859525860525960535455535456535457535458535459535460
535556535557535558535559535560535657535658535659535660535758
