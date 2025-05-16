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

ctl-opt nomain;

dcl-ds FlatParm_t qualified template;
  val char(65535);
  size zoned(5);
end-ds;

dcl-ds SimGenRec extname('F_SIMGEN') qualified template;
end-ds;

dcl-ds Bytes_t qualified template;
  val char(100);
  size zoned(5);
end-ds;

dcl-ds ParseResult_t qualified template;
  val like(SimGenRec.VALUE);
  size like(SimGenRec.LENGTH);
  errMsg char(50);
end-ds;

// variable types
dcl-c TYP_STRUCT const('STRUCT');
dcl-c TYP_CHAR const('CHAR');
dcl-c TYP_ZONED const('ZONED');
dcl-c TYP_PACKED const('PACKED');
dcl-c TYP_INT const('INT');

dcl-c True const('1');
dcl-c False const('0');

dcl-c MIN_VAR_LEN const(1);
dcl-c MAX_VAR_LEN const(65535);

dcl-s errMsg_t char(50);
dcl-s nBytes_t zoned(5);
dcl-s pos_t    zoned(5);

dcl-proc utl_Serialize export;
  dcl-pi *n likeds(FlatParm_t);
    out_errMsg like(errMsg) options(*nopass);
  end-pi;

  dcl-ds FlatParm likeds(FlatParm_t);
  dcl-ds VarRec likeds(SimGenRec);
  dcl-s pos like(pos_t);
  dcl-s errMsg like(errMsg_t);

  exec sql set option commit = *none;
  clear FlatParm;

  pos = 1;

  exec sql declare c1 cursor for
  select * from QTEMP/F_#SIMGEN
  order by SMID;

  exec sql open c1;
  dow 1 = 1;
    clear VarRec;
    exec sql fetch next from c1 into :VarRec;

    if sqlcode = 100;
      leave;
    endif;

    if sqlcode <> 0;
      errMsg = 'sql error, code:' + %char(sqlcode);
      leave;
    endif;

    errMsg = WriteVariable(VarRec:FlatParm:pos);
    if errMsg <> *blanks;
      leave;
    endif;

  enddo;
  exec sql close c1;

  if errMsg <> *blanks;
    if %parms() >= %parmnum(out_errMsg);
      out_errMsg = errMsg;
    endif;
    clear FlatParm;
    return FlatParm;
  endif;

  FlatParm.size = pos - 1;
  return FlatParm;
end-proc;

dcl-proc utl_Deserialize export;
  dcl-pi *n like(errMsg);
    FlatParm likeds(FlatParm_t) const;
  end-pi;

  dcl-ds VarRec likeds(SimGenRec);
  dcl-ds ParseResult likeds(ParseResult_t);
  dcl-s pos like(pos_t);
  dcl-s errMsg like(errMsg_t);

  exec sql
  create or replace table QTEMP/F_#CHGVAR as
    (
      select SMID, PARENTID, VALUE as NEWVAL, VALUE as OLDVAL
      from F_SIMGEN
    )
  with no data on replace delete rows;

  if sqlcode <> 0;
    errMsg = 'Sql error, code:' + %char(sqlcode);
    return errMsg;
  endif;

  if FlatParm.size < MIN_VAR_LEN or MAX_VAR_LEN < FlatParm.size;
    errMsg = 'Total params len invalid: ' + %char(FlatParm.size);
    return errMsg;
  endif;

  exec sql declare c2 cursor for
    select * from QTEMP/F_#SIMGEN
    order by SMID;

  exec sql open c2;

  dow pos < FlatParm.size;
    clear VarRec;
    exec sql fetch next from c2 into :VarRec;

    if sqlcode = 100;
      leave;
    endif;

    if sqlcode <> 0;
      errMsg = 'Sql error occurred, sqlcode: ' + %char(sqlcode);
      leave;
    endif;

    ParseResult = DeserializeVar(VarRec:FlatParm:pos);
    if ParseResult.errMsg <> *blanks;
      errMsg = ParseResult.errMsg;
      leave;
    endif;

    // new val isn't equal to old value
    if ParseResult.val <> VarRec.VALUE;
      // TODO - maybe we should always write value
      InsertIntoChangedTable(VarRec:ParseResult.val);
    endif;

    pos += ParseResult.size;
  enddo;
  exec sql close c2;

  if errMsg <> *blanks;
    return errMsg;
  endif;

  // the parameters' total size should be
  // equal to their definition in F_#SIMGEN
  // if its not, it means that an error has occurred
  if pos <> FlatParm.size;
    errMsg = 'Parameters total size isnt equal to original size';
    return errMsg;
  endif;

  return *blanks; // success
end-proc;

dcl-proc utl_SizeInBytes export;
  dcl-pi *n like(nBytes);
    type like(SimGenRec.TYPE)   const;
    len  like(SimGenRec.LENGTH) const;
  end-pi;

  dcl-s nBytes like(nBytes_t);

  select type;
    when-is TYP_STRUCT;
      nBytes = len;
    when-is TYP_CHAR;
      nBytes = len;
    when-is TYP_ZONED;
      nBytes = len;
    when-is TYP_PACKED;
      nBytes = SizeOfPacked(len);
    when-is TYP_INT;
      nBytes = SizeOfInt(len);
    other;
      nBytes = 0;
  endsl;

  return nBytes;
end-proc;

dcl-proc DeserializeVar;
  dcl-pi *n likeds(ParseResult_t);
    Rec likeds(SimGenRec) const;
    Src likeds(FlatParm_t) const;
    startPos zoned(5) const;
  end-pi;

  dcl-ds Result likeds(ParseResult_t);
  dcl-s varType like(Rec.TYPE);

  clear Result;

  varType = %upper(Rec.TYPE);
  select varType;
    when-is TYP_STRUCT;
      // ignore
    when-is TYP_CHAR;
      Result = CharToChar(Rec:Src:startPos);
    when-is TYP_ZONED;
      Result = ZonedToChar(Rec:Src:startPos);
    when-is TYP_PACKED;
      Result = PackedToChar(Rec:Src:startPos);
    when-is TYP_INT;
      Result = IntToChar(Rec:Src:startPos);
    other;
      Result.errMsg = 'unsupported var type: ' + varType;
  endsl;

  return Result;
end-proc;

dcl-proc CharToChar;
  dcl-pi *n likeds(ParseResult_t);
    Rec likeds(SimGenRec) const;
    Src likeds(FlatParm_t) const;
    startPos zoned(5) const;
  end-pi;

  dcl-ds Result likeds(ParseResult_t);

  clear Result;
  Result.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);

  if (startPos + Result.size) > Src.size;
    Result.errMsg = 'variable out of bounds, var id: ' + %char(Rec.SMID);
    return Result;
  endif;

  Result.val = %subst(Src:startPos + 1:Result.size);
  return Result;
end-proc;

dcl-proc ZonedToChar;
  dcl-pi *n likeds(ParseResult_t);
    Rec likeds(SimGenRec) const;
    FlatParm likeds(FlatParm_t) const;
    startPos zoned(5) const;
  end-pi;

  dcl-ds Result likeds(ParseResult_t);
  dcl-ds wrapper;
    inner zoned(63);
  end-ds;

  dcl-s dummy like(inner);
  dcl-s rawVal char(63);
  dcl-s validZoned ind;

  clear Result;

  Result.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);
  if (startPos + Result.size) > FlatParm.size;
    Result.errMsg = 'variable out of bounds, var id: ' + %char(Rec.SMID);
    return Result;
  endif;

  clear inner;

  rawVal = %subst(FlatParm: startPos + 1: Result.size);
  %subst(wrapper:%len(wrapper) - Result.size + 1:Result.size) =
    %subst(FlatParm: startPos + 1: Result.size);

  validZoned = True;
  monitor;
    dummy = inner;
  on-error;
    validZoned = False;
  endmon;

  select validZoned;
    when-is True;
      if (inner = 0 or Rec.PRECISION = 0); // no need for decimal point
        Result.val = %char(inner);
      else;
        Result.val = ToCharWithDecPoint(rawVal: (inner < 0) :Rec.PRECISION);
      endif;
    when-is False;
      Result.val = %subst(FlatParm: startPos + 1 :Result.size); // return value as-is
  endsl;

  return Result;
end-proc;

dcl-proc PackedToChar;
  dcl-pi *n likeds(ParseResult_t);
    Rec likeds(SimGenRec) const;
    Src likeds(FlatParm_t) const;
    startPos zoned(5) const;
  end-pi;

  dcl-ds Result likeds(ParseResult_t);
  dcl-ds wrapper;
    inner packed(63);
  end-ds;

  dcl-s dummy like(inner);
  dcl-s val like(ParseResult_t.val);
  dcl-s rawVal char(63);
  dcl-s validPacked ind;

  clear Result;

  Result.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);

  if (startPos + Result.size) > Src.size;
    Result.errMsg = 'variable out of bounds, var id: ' + %char(Rec.SMID);
    return Result;
  endif;

  clear inner;

  rawVal = %subst(Src: startPos + 1: Result.size);
  %subst(wrapper:%len(wrapper) - Result.size + 1:Result.size) =
    %subst(Src: startPos + 1: Result.size);

  validPacked = True;
  monitor;
    dummy = inner;
  on-error;
    validPacked = False;
  endmon;

  if validPacked;
    if (Rec.PRECISION = 0 or inner = 0);
      val = %char(inner);
    else;
      val = ToCharWithDecPoint(rawVal:(inner < 0):Rec.PRECISION);
    endif;
    Result.val = val;
  else;
    Result.val = %subst(src: startPos + 1: Result.size);
  endif;

  return Result;
end-proc;

dcl-proc IntToChar;
  dcl-pi *n likeds(ParseResult_t);
    Rec likeds(SimGenRec) const;
    Src likeds(FlatParm_t) const;
    startPos zoned(5) const;
  end-pi;

  dcl-ds Result likeds(ParseResult_t);
  dcl-ds wrapper;
    inner int(20);
  end-ds;

  dcl-s dummy int(20);
  dcl-s validNumeric ind;

  clear Result;
  Result.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);
  if Result.size = 0;
    Result.errMsg = 'invalid int len for var id: ' + %char(Rec.SMID);
    return Result;
  endif;

  if (startPos + Result.size) > Src.size;
    Result.errMsg = 'variable out of bounds, var id: ' + %char(Rec.SMID);
    return Result;
  endif;

  validNumeric = True;
  wrapper = %subst(Src:startPos + 1:Result.size);
  monitor;
    dummy = inner;
  on-error;
    validNumeric = False;
  endmon;

  if validNumeric;
    Result.val = %char(inner);
  else;
    Result.val = %subst(Src:startPos + 1:Result.size);
  endif;

  return Result;
end-proc;

dcl-proc ToCharWithDecPoint;
  dcl-pi *n like(ParseResult_t.val);
    decWrapper char(63) value;
    isNegative ind const;
    precision zoned(2) const;
  end-pi;

  dcl-pr CharToHex extproc('cvthc');
    *n like(asHex);   // hex out
    *n like(decWrapper); // char in
    *n like(hexLen) value;
  end-pr ;
  dcl-s val varchar(65);

  dcl-s asHex char(126);
  dcl-s hexLen int(10);

  dcl-s len zoned(5);
  dcl-s trailing zoned(3);

  CharToHex(asHex:decWrapper:%len(asHex));
  asHex = %scanrpl('40':'':asHex); // remove blanks
  asHex = %scanrpl('F':'':asHex);  // remove plus  sign half-byte
  asHex = %scanrpl('D':'':asHex);  // remove minus sign half-byte

  if precision = %len(decWrapper);
    val = '.' + val;
  else;
    val = %trim(asHex);
    val = %subst(val:1:(%len(val) - precision)) +
              '.' +
              %subst(val:(%len(val) - precision) + 1:precision);
  endif;

  // trim leading zeroes (before decPoint) and trailing zeroes (after decPoint)
  val = %trim(val:'0');
  if val = *blanks or val = '.';
    val = '0';
  endif;

  // if last char is decPoint (no decimal digits), remove it
  if %subst(val:%len(val):1) = '.';
    val = %subst(val:1:%len(val) - 1);
  endif;

  // add negative sign
  if isNegative;
    val = '-' + val;
  endif;

  return %trim(val);
end-proc;

dcl-proc InsertIntoChangedTable;
  dcl-pi *n;
    Rec likeds(SimGenRec) const;
    newVal like(ParseResult_t.val) const;
  end-pi;

  exec sql
    insert into QTEMP/F_#CHGVAR
    values(:Rec.SMID, :Rec.PARENTID, :newVal, :Rec.VALUE);
end-proc;

dcl-proc WriteVariable;
  dcl-pi *n like(errMsg_t);
    Rec likeds(SimGenRec) const;
    FlatParm likeds(FlatParm_t);
    pos like(pos_t);
  end-pi;

  dcl-ds Bytes likeds(Bytes_t) inz;

  dcl-s varType like(Rec.TYPE);
  dcl-s varLen zoned(5);
  dcl-s errMsg like(errMsg_t);

  varLen = %min(Rec.LENGTH:MAX_VAR_LEN);
  if   varLen < MIN_VAR_LEN or MAX_VAR_LEN < varLen;
    return ('invalid varLen for var id: ' + %char(Rec.SMID));
  endif;

  varType = %upper(Rec.TYPE);
  select varType;
    when-is TYP_STRUCT;
      return *blanks; // skip
    when-is TYP_CHAR;
      Bytes = CharToBytes(Rec:errMsg);
    when-is TYP_ZONED;
      Bytes = ZonedToBytes(Rec:errMsg);
    when-is TYP_PACKED;
      Bytes = PackedToBytes(Rec:errMsg);
    when-is TYP_INT;
      Bytes = IntToBytes(Rec:errMsg);
    other;
      errMsg = 'Unsupported var type, id:' + %char(Rec.SMID);
  endsl;

  if errMsg <> *blanks;
    return errMsg;
  endif;

  if Bytes.size < 1;
    return ('invalid size for var id: ' + %char(Rec.SMID));
  endif;

  if (FlatParm.size + Bytes.size) > MAX_VAR_LEN;
    return ('Total params len invalid, last var id: ' + %char(Rec.SMID)) ;
  endif;
  %subst(FlatParm.val:pos:Bytes.size) = Bytes.val;
  pos += Bytes.size;

  return *blanks; // success
end-proc;

dcl-proc ZonedToBytes;
  dcl-pi *n likeds(Bytes_t);
    Rec likeds(SimGenRec) const;
    err like(errMsg_t);
  end-pi;

  dcl-ds Bytes likeds(Bytes_t) inz;
  dcl-ds wrapper;
    inner zoned(63);
  end-ds;

  dcl-s val like(SimGenRec.VALUE);

  clear Bytes;

  Bytes.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);

  if not IsValidNumeric(Rec.VALUE);
    Bytes.val = Rec.VALUE;
    return Bytes;
  endif;

  val = PadTrailingZeroes(Rec.VALUE:Rec.PRECISION);

  inner = %dec(%scanrpl('.':'':val):63:0);
  Bytes.val = %subst(wrapper:(%len(wrapper) - Rec.LENGTH) + 1:Rec.LENGTH);

  return Bytes;
end-proc;

dcl-proc PackedToBytes;
  dcl-pi *n likeds(Bytes_t);
    Rec likeds(SimGenRec) const;
    errMsg like(errMsg_t);
  end-pi;
  dcl-ds wrapper;
    inner packed(63);
  end-ds;

  dcl-ds Bytes likeds(Bytes_t) inz;

  dcl-s val like(SimGenRec.VALUE);
  dcl-s validNumeric ind;
  dcl-s dots zoned(5);

  clear Bytes;

  Bytes.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);

  if not IsValidNumeric(Rec.VALUE);
    Bytes.val = Rec.VALUE;
    return Bytes;
  endif;

  val = PadTrailingZeroes(Rec.VALUE:Rec.PRECISION);

  inner = %dec(%scanrpl('.':'':val):63:0);
  Bytes.val = %subst(wrapper:(%len(wrapper) - Bytes.size) + 1:Bytes.size);

  return Bytes;
end-proc;

dcl-proc IntToBytes;
  dcl-pi *n likeds(Bytes_t);
    Rec likeds(SimGenRec) const;
    errMsg like(errMsg_t);
  end-pi;

  dcl-ds wrapper;
    inner int(20);
  end-ds;

  dcl-ds Bytes likeds(Bytes_t) inz;
  dcl-s validNumeric ind;

  validNumeric = True;
  monitor;
    inner = %int(Rec.VALUE);
  on-error;
    validNumeric = False;
  endmon;

  select Rec.LENGTH;
    when-is 3;
      Bytes.size = 1;
    when-is 5;
      Bytes.size = 2;
    when-is 10;
      Bytes.size = 4;
    when-is 20;
      Bytes.size = 8;
    other;
      errMsg = 'invalid int len for var id: ' + %char(Rec.SMID);
      return Bytes;
  endsl;

  if validNumeric;
    Bytes.val = %subst(wrapper:(%len(wrapper) - Bytes.size) + 1:Bytes.size);
  else;
    Bytes.val = Rec.VALUE;
  endif;

  return Bytes;
end-proc;

dcl-proc CharToBytes;
  dcl-pi *n likeds(Bytes_t);
    Rec likeds(SimGenRec) const;
    err like(errMsg_t);
  end-pi;

  dcl-ds Bytes likeds(Bytes_t) inz;

  Bytes.val = Rec.VALUE;
  Bytes.size = utl_SizeInBytes(Rec.TYPE:Rec.LENGTH);

  return Bytes;
end-proc;

dcl-proc IsValidNumeric;
  dcl-pi *n ind;
    maybeNum like(SimGenRec.VALUE) const;
  end-pi;

  dcl-s dummy zoned(63);
  dcl-s dots zoned(5);

  dots = countDots(maybeNum);
  if dots > 1; // invalid numeric
    return False;
  endif;

  // byte representation of integer values and decimal values
  // are the same (e.g. 25 = 2.5), so we disregard the dot
  // for numeric validation
  monitor;
    dummy = %dec(%scanrpl('.':'':maybeNum):63:0);
  on-error; // invalid numeric
    return False;
  endmon;

  return True;
end-proc;

dcl-proc countDots;
  dcl-pi *n like(count);
    val like(SimGenRec.VALUE) const;
  end-pi;

  dcl-s i zoned(3);
  dcl-s count zoned(3);

  for i = 1 to %len(val);
    if %subst(val:i:1) = '.';
      count += 1;
    endif;
  endfor;

  return count;
end-proc;

dcl-proc PadTrailingZeroes;
  dcl-pi *n like(SimGenRec.VALUE);
    val like(SimGenRec.VALUE) const; // must be valid numeric
    precision like(SimGenRec.PRECISION) const;
  end-pi;

  dcl-s wrk_val varchar(100);
  dcl-s allZeros char(100) inz(*all'0');
  dcl-s dotPos zoned(3);
  dcl-s afterDot zoned(3);
  dcl-s dummy zoned(63);

  monitor;
    dummy = %dec(%scanrpl('.':'':val):63:0);
  on-error;
    return val; // invalid numeric
  endmon;

  if precision = 0;
    return val;
  endif;

  wrk_val = %trim(val);
  dotPos = %scan('.' :wrk_val);

  if dotPos = 0;
    wrk_val += '.' + %subst(allZeros:1:precision);
    return wrk_val;
  endif;

  afterDot = %len(wrk_val) - dotPos;

  if afterDot >= precision;
    return val; // no need to pad
  endif;

  wrk_val += %subst(allZeros:1:precision - afterDot);
  return wrk_val;
end-proc;

dcl-proc SizeOfPacked;
  dcl-pi *n like(nBytes);
    len like(SimGenRec.LENGTH) const;
  end-pi;

  dcl-s nBytes like(nBytes_t);
  dcl-s isEven ind;

  isEven = ( %rem(len:2) = 0 );
  if isEven;
    nBytes = (len / 2) + 1;
  else;
    nBytes = (len + 1) / 2 ;
  endif;

  return nBytes;
end-proc;

dcl-proc SizeOfInt;
  dcl-pi *n like(nBytes);
    len like(SimGenRec.LENGTH) const;
  end-pi;

  dcl-s nBytes like(nBytes_t);

  select len;
    when-is 3;
      nBytes = 1;
    when-is 5;
      nBytes = 2;
    when-is 10;
      nBytes = 4;
    when-is 20;
      nBytes = 8;
    other;
      nBytes = 0;
  endsl;

  return nBytes;
end-proc;
