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


ctl-opt dftactgrp(*no) actgrp(*new);

////////////////////////
//     Prototypes     //
////////////////////////

dcl-pi SGMAIN;
  in_Pgm likeds(QualObj_t)  const;
  in_pcmlFilePath like(pcmlFilePath) const options(*nopass);
end-pi;

// parses pcml into a temp table
dcl-pr ParsePcml extpgm('SGPARSE');
  *n likeds(in_Pgm) const;
  *n like(in_pcmlFilePath) const;
  *n likeds(resolvedPgm);
  *n like(errMsg) options(*nopass);
end-pr;

// gui
dcl-pr ScreenDriver extpgm('SGSCREEN');
  *n like(ResolvedPgm) const;
end-pr;

////////////////////////
//     Variables      //
////////////////////////

dcl-ds QualObj_t qualified template;
  name char(10);
  lib  char(10);
end-ds;

dcl-ds ResolvedPgm likeds(QualObj_t);

dcl-s pcmlFilePath char(100);
dcl-s errMsg char(50);

////////////////////////
//       Main         //
////////////////////////

if %parms() >= %parmnum(in_pcmlFilePath);
  pcmlFilePath = in_pcmlFilePath;
else;
  pcmlFilePath = *blanks;
endif;

callp ParsePcml(in_Pgm:pcmlFilePath:ResolvedPgm:errMsg);
if errMsg <> *blanks;
  dsply %trim(errMsg);
  *inlr = *on;
  return;
endif;

callp ScreenDriver(ResolvedPgm);

*inlr = *on;
