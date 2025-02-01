{
	Copyright (c) 2020 Adrian Siekierka

	Based on a reconstruction of code from ZZT,
	Copyright 1991 Epic MegaGames, used with permission.

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
}

{$I-}
{$V-}

{$IFDEF FPC}
{$IFDEF RAWMEM}
{$PACKRECORDS 1}
{$ENDIF}
{$ENDIF}

unit TxtWind;

interface
	uses GameVars, ZVideo;
	const
{$IFDEF SDL2}
		MAX_TEXT_WINDOW_LINES = 6144;
{$ELSE}
		MAX_TEXT_WINDOW_LINES = 1024;
{$ENDIF}
		MAX_RESOURCE_DATA_FILES = 24;
		RESOURCE_DATA_VERSION = -3;
		MAX_LINE_LENGTH_EDIT = 58;
		MAX_LINE_LENGTH = 50;
		{ TextWindowSelect flags }
		TWS_HYPERLINK_AS_SELECT = $01;
		TWS_VIEWING_FILE = $02;
		TWS_IGNORE_HYPERLINKS = $04;
{$IFDEF EDITOR}
		TWS_EXIT_MINUS_PLUS_DEL = $08;
{$ENDIF}
		TWS_CONSTANT_TITLE = $10;
		TWS_LONG_HYPERLINKS = $20;
		MAX_TEXT_WINDOW_WIDTH = 50;
{$IFDEF E_SUPERZ}
	{$IFDEF NEC98}
		MAX_TEXT_WINDOW_HEIGHT = 22;
	{$ELSE}
		{$IFDEF HASAMIGA}
		MAX_TEXT_WINDOW_HEIGHT = 22;
		{$ELSE}
		MAX_TEXT_WINDOW_HEIGHT = 43;
		{$ENDIF}
	{$ENDIF}
{$ELSE}
		MAX_TEXT_WINDOW_HEIGHT = 18;
{$ENDIF}
	type
{$IFDEF SDL2}
		TExtensionString = string[12];
{$ELSE}
		TExtensionString = string[4];
{$ENDIF}
		TTextWindowLine = string[MAX_LINE_LENGTH_EDIT];
		PTTextWindowLine = ^TTextWindowLine;
		TTextWindowState = record
			Selectable: boolean;
			LineCount: integer;
			LinePos: integer;
			Lines: array[1 .. MAX_TEXT_WINDOW_LINES] of PTTextWindowLine;
			Hyperlink: string[50];
			Title: TTextWindowLine;
			ScreenCopy: array[1 .. (MAX_TEXT_WINDOW_HEIGHT + 1)] of TScreenCopyLine;
		end;
		TResourceDataHeader = record
			Version: integer;
			EntryCount: integer;
			Name: array[1 .. MAX_RESOURCE_DATA_FILES] of string[12];
			FileOffset: array[1 .. MAX_RESOURCE_DATA_FILES] of longint;
			FileSize: array[1 .. MAX_RESOURCE_DATA_FILES] of word;
		end;
	var
		TextWindowX: integer;
		TextWindowY: integer;
		TextWindowWidth: integer;
		TextWindowHeight: integer;
		TextWindowStrInnerEmpty: TVideoLine;
		TextWindowStrText: TVideoLine;
		TextWindowStrInnerLine: TVideoLine;
		TextWindowStrTop: TVideoLine;
		TextWindowStrBottom: TVideoLine;
		TextWindowStrSep: TVideoLine;
		TextWindowStrInnerSep: TVideoLine;
		TextWindowStrInnerArrows: TVideoLine;
		TextWindowRejected: boolean;
		ResourceDataFileName: TFilenameString;
		ResourceDataHeader: TResourceDataHeader;
		{ OrderPrintId: ^string; }
	function UpCaseString(input: string): string;
	procedure TextWindowPromptFilename(title: TString50; var filename: TFilenameString);
	procedure TextWindowInitState(var state: TTextWindowState);
	procedure TextWindowDrawOpen(var state: TTextWindowState);
	procedure TextWindowDrawClose(var state: TTextWindowState);
	procedure TextWindowDraw(var state: TTextWindowState; withoutFormatting, viewingFile: boolean);
	procedure TextWindowAppend(var state: TTextWindowState; line: TTextWindowLine);
	procedure TextWindowAppendEdit(var state: TTextWindowState; line: TTextWindowLine);
	procedure TextWindowFree(var state: TTextWindowState);
	procedure TextWindowFreeEdit(var state: TTextWindowState);
	procedure TextWindowSelect(var state: TTextWindowState; flags: byte);
	procedure TextWindowSort(var state: TTextWindowState; fromIdx, toIdx: integer);
{$IFDEF EDITOR}
	procedure TextWindowEdit(var state: TTextWindowState; extension: TExtensionString;
		syntaxHighlighting, multiExtension: boolean);
{$ENDIF}
	function ResourceDataCheckPresent: boolean;
	function ResourceDataReadBinaryFile(name: TFilenameString; var fdata: pointer; foffset, fmaxsize: word): word;
	procedure TextWindowOpenFile(filename: TFilenameString; var state: TTextWindowState; editing, showError: boolean);
	procedure TextWindowSaveFile(filename: TFilenameString; var state: TTextWindowState);
	procedure TextWindowDisplayFile(filename: TFilenameString; title: TTextWindowLine);
	function TextWindowWrite(var state: TTextWindowState; var f: text): boolean;
	procedure TextWindowInit(x, y, width, height: integer);
	procedure TextWindowInitXY(x, y: integer);

implementation
uses
{$IFDEF PRINTTXT} Printer, {$ENDIF}
{$IFDEF WIDECHAR} ZWideChr, {$ENDIF}
Sounds, TimerSys, ZDemo, FileSys, ZInput, Keys, FileOps, FileSel, Game, Sidebar;

type
	TTextWindowLineBuffer = array[1 .. MAX_TEXT_WINDOW_LINES] of PTTextWindowLine;
{$IFNDEF FASTVID}
const
	TransitionTextWindowDelay = 25;
{$ENDIF}

function UpCaseString(input: string): string;
	var
		i: integer;
	begin
		for i := 1 to Length(input) do
			input[i] := UpCase(input[i]);
		UpCaseString := input;
	end;

procedure TextWindowPromptFilename(title: TString50; var filename: TFilenameString);
	begin
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);

		VideoWriteText(VideoSidebarX + 3, 3, $1F, title);
		VideoWriteText(VideoSidebarX + 3, 5, $0F, '            ');

		filename := '';
		PromptString(VideoSidebarX + 3, 5, $1E, $0F, 12, 128, PROMPT_ANY, filename);

		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
	end;

procedure TextWindowInitState(var state: TTextWindowState);
	begin
		with state do begin
			LineCount := 0;
			LinePos := 1;
		end;
	end;

procedure TextWindowDrawTitle(color: integer; title: TTextWindowLine);
	begin
		VideoWriteText(TextWindowX + 2, TextWindowY + 1, color, TextWindowStrInnerEmpty);
{$IFDEF WIDECHAR}
		VideoWriteTextWide(TextWindowX + ((TextWindowWidth - Length(title)) div 2), TextWindowY + 1, color, title);
{$ELSE}
		VideoWriteText(TextWindowX + ((TextWindowWidth - Length(title)) div 2), TextWindowY + 1, color, title);
{$ENDIF}
	end;

procedure TextWindowDrawOpen(var state: TTextWindowState);
	var
		ix, iy: integer;
	begin
		with state do begin
			for iy := 1 to (TextWindowHeight + 1) do
				VideoMove(TextWindowX, iy + TextWindowY - 1, TextWindowWidth, @ScreenCopy[iy], false);

{$IFDEF FASTVID}
			if TransitionTextWindowDelay <= 0 then begin
				{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
				VideoWriteText(TextWindowX, TextWindowY, $0F, TextWindowStrTop);
				for iy := 1 to (TextWindowHeight - 1) do begin
					VideoWriteText(TextWindowX, TextWindowY + iy, $0F, TextWindowStrText);
				end;
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight, $0F, TextWindowStrBottom);
				{$IFDEF BASICSYS} VideoUnlockScreenUpdate(
					TextWindowX, TextWindowY,
					TextWindowX + TextWindowWidth - 1, TextWindowY + TextWindowHeight); {$ENDIF}
			end else
{$ENDIF}
			for iy := (TextWindowHeight shr 1) downto 0 do begin
				{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
				VideoWriteText(TextWindowX, TextWindowY + iy + 1, $0F, TextWindowStrText);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy - 1, $0F, TextWindowStrText);
				VideoWriteText(TextWindowX, TextWindowY + iy, $0F, TextWindowStrTop);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy, $0F, TextWindowStrBottom);
				{$IFDEF BASICSYS} VideoUnlockScreenUpdate(
					TextWindowX, TextWindowY,
					TextWindowX + TextWindowWidth - 1, TextWindowY + TextWindowHeight); {$ENDIF}
				AccurateDelay(TransitionTextWindowDelay);
			end;

			VideoWriteText(TextWindowX, TextWindowY + 2, $0F, TextWindowStrSep);
			TextWindowDrawTitle($1E, Title);
		end;
	end;

procedure TextWindowDrawClose(var state: TTextWindowState);
	var
		ix, iy: integer;
		unk1, unk2: integer;
	begin
		with state do begin
			{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
{$IFDEF FASTVID}
			if TransitionTextWindowDelay <= 0 then begin
				for iy := 0 to TextWindowHeight do begin
					VideoMove(TextWindowX, TextWindowY + iy, TextWindowWidth,
						@ScreenCopy[iy + 1], true);
				end;
			end else
{$ENDIF}
			for iy := 0 to (TextWindowHeight shr 1) do begin
				VideoWriteText(TextWindowX, TextWindowY + iy, $0F, TextWindowStrTop);
				VideoWriteText(TextWindowX, TextWindowY + TextWindowHeight - iy, $0F, TextWindowStrBottom);
				{$IFDEF BASICSYS} VideoUnlockScreenUpdate(
					TextWindowX, TextWindowY,
					TextWindowX + TextWindowWidth - 1, TextWindowY + TextWindowHeight - 1); {$ENDIF}
				AccurateDelay(TransitionTextWindowDelay * 3 div 4);
				{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
				VideoMove(TextWindowX, TextWindowY + iy, TextWindowWidth,
					@ScreenCopy[iy + 1], true);
				VideoMove(TextWindowX, TextWindowY + TextWindowHeight - iy, TextWindowWidth,
					@ScreenCopy[(TextWindowHeight - iy) + 1], true);
			end;
			{$IFDEF BASICSYS} VideoUnlockScreenUpdate(
					TextWindowX, TextWindowY,
					TextWindowX + TextWindowWidth - 1, TextWindowY + TextWindowHeight); {$ENDIF}
		end;
	end;

procedure TextWindowDrawLine(var state: TTextWindowState; lpos: integer; withoutFormatting, viewingFile: boolean);
	var
		lineY: integer;
		textOffset, textColor, textX: integer;
	begin
		with state do begin
			lineY := ((TextWindowY + lpos) - LinePos) + (TextWindowHeight shr 1) + 1;
			if lpos = LinePos then
				VideoWriteText(TextWindowX + 2, lineY, $1C, TextWindowStrInnerArrows)
			else
				VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerEmpty);
			if (lpos > 0) and (lpos <= LineCount) then begin
				if withoutFormatting then begin
{$IFDEF WIDECHAR}
					VideoWriteTextWide(TextWindowX + 4, lineY, $1E, Lines[lpos]^);
{$ELSE}
					VideoWriteText(TextWindowX + 4, lineY, $1E, Lines[lpos]^);
{$ENDIF}
				end else begin
					textOffset := 1;
					textColor := $1E;
					textX := TextWindowX + 4;
					if Length(state.Lines[lpos]^) > 0 then begin
						case state.Lines[lpos]^[1] of
							'!': begin
								textOffset := Pos(';', Lines[lpos]^) + 1;
								VideoWriteText(textX + 2, lineY, $1D, #16);
								Inc(textX, 5);
								textColor := $1F;
							end;
							':': begin
								textOffset := Pos(';', Lines[lpos]^) + 1;
								textColor := $1F;
							end;
							'$': begin
								textOffset := 2;
								textColor := $1F;
								textX := (textX - 4) + ((TextWindowWidth - Length(Lines[lpos]^)) div 2);
							end;
						end;
					end;
					if textOffset > 0 then begin
{$IFDEF WIDECHAR}
						VideoWriteTextWide(textX, lineY, textColor,
							Copy(Lines[lpos]^, textOffset,Length(Lines[lpos]^) - textOffset + 1));
{$ELSE}
						VideoWriteText(textX, lineY, textColor,
							Copy(Lines[lpos]^, textOffset,Length(Lines[lpos]^) - textOffset + 1));
{$ENDIF}
					end;
				end;
			end else if (lpos = 0) or (lpos = (state.LineCount + 1)) then begin
				VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerSep);
{$IFDEF PRINTTXT}
			end else if (lpos = -4) and viewingFile then begin
				VideoWriteText(TextWindowX + 2, lineY, $1A, '   Use            to view text,');
				VideoWriteText(TextWindowX + 2 + 7, lineY, $1F, #24' '#25', Enter');
			end else if (lpos = -3) and viewingFile then begin
				VideoWriteText(TextWindowX + 2 + 1, lineY, $1A, '                 to print.');
				VideoWriteText(TextWindowX + 2 + 12, lineY, $1F, 'Alt-P');
{$ELSE}
			end else if (lpos = -3) and viewingFile then begin
				VideoWriteText(TextWindowX + 2, lineY, $1A, '   Use            to view text.');
				VideoWriteText(TextWindowX + 2 + 7, lineY, $1F, #24' '#25', Enter');
{$ENDIF}
			end;
		end;
	end;

procedure TextWindowDraw(var state: TTextWindowState; withoutFormatting, viewingFile: boolean);
	var
		i: integer;
		unk1: integer;
	begin
		for i := 0 to (TextWindowHeight - 4) do
			TextWindowDrawLine(state, state.LinePos - (TextWindowHeight shr 1) + i + 2,
				withoutFormatting, viewingFile);
		TextWindowDrawTitle($1E, state.Title);
	end;

procedure TextWindowAppend(var state: TTextWindowState; line: TTextWindowLine);
	var
		len: integer;
	begin
		with state do begin
			if LineCount >= MAX_TEXT_WINDOW_LINES then exit;

			len := Length(line);

			Inc(LineCount);
			GetMem(Lines[LineCount], len + 1);
			Lines[LineCount]^ := Copy(line, 1, len);
		end;
	end;

procedure TextWindowAppendEdit(var state: TTextWindowState; line: TTextWindowLine);
	begin
		with state do begin
			if LineCount >= MAX_TEXT_WINDOW_LINES then exit;
			Inc(LineCount);
			New(Lines[LineCount]);
			Lines[LineCount]^ := Copy(line, 1, MAX_LINE_LENGTH_EDIT);
		end;
	end;

procedure TextWindowFree(var state: TTextWindowState);
	begin
		with state do begin
			while LineCount > 0 do begin
				FreeMem(Lines[LineCount], Ord(Lines[LineCount]^[0]) + 1);
				Dec(LineCount);
			end;
		end;
	end;

procedure TextWindowFreeEdit(var state: TTextWindowState);
	begin
		with state do begin
			while LineCount > 0 do begin
				Dispose(Lines[LineCount]);
				Dec(LineCount);
			end;
		end;
	end;

function TextWindowWrite(var state: TTextWindowState; var f: text): boolean;
	var
		iLine, iChar: integer;
		line: string;
	begin
		TextWindowWrite := false;
		with state do begin
			for iLine := 1 to LineCount do begin
				line := Lines[iLine]^;
				if Length(line) > 0 then begin
					case line[1] of
						'$': begin
							Delete(line, 1, 1);
							for iChar := ((80 - Length(line)) div 2) downto 1 do
								line := ' ' + line;
						end;
						'!', ':': begin
							iChar := Pos(';', line);
							if iChar > 0 then
								Delete(line, 1, iChar)
							else
								line := '';
						end;
					else
						line := '          ' + line
					end;
				end;
				WriteLn(f, line);
				if IOResult <> 0 then begin
					exit;
				end;
			end;
		end;
		TextWindowWrite := true;
	end;

{$IFDEF PRINTTXT}
procedure TextWindowPrint(var state: TTextWindowState);
	begin
		Rewrite(Lst);
		if TextWindowWrite(state, Lst) then
			Write(Lst, Chr(12) { form feed });
		Close(Lst);
	end;
{$ENDIF}

procedure TextWindowSelect(var state: TTextWindowState; flags: byte);
	var
		newLinePos: integer;
		viewingFile: boolean;
		exitWindow: boolean;
		iLine, iChar: integer;
		pointerStr: TString50;
	label LabelMatched;
	label LabelNotMatched;
	begin
		viewingFile := (flags and TWS_VIEWING_FILE) <> 0;
		exitWindow := false;

		with state do begin
			TextWindowRejected := false;
			Hyperlink := '';
			TextWindowDraw(state, false, viewingFile);
			repeat
{$IFDEF SDL2}
				SoundIdle(IMUntilFrame);
{$ENDIF}
				DemoInputUpdate(0, false);
				newLinePos := LinePos;
				if InputDeltaY <> 0 then begin
					Inc(newLinePos, InputDeltaY);
				end else if InputShiftPressed or (InputKeyPressed = KEY_ENTER) then begin
					InputShiftAccepted := true;
					if ((flags and TWS_IGNORE_HYPERLINKS) = 0) and ((Lines[LinePos]^[1]) = '!') then begin
						pointerStr := Copy(Lines[LinePos]^, 2, Length(Lines[LinePos]^) - 1);

						if Pos(';', pointerStr) > 0 then begin
							pointerStr := Copy(pointerStr, 1, Pos(';', pointerStr) - 1);
						end;

						if ((flags and TWS_LONG_HYPERLINKS) = 0) and (Length(pointerStr) > 20) then
							pointerStr[0] := Chr(20);

						if pointerStr[1] = '-' then begin
							Delete(pointerStr, 1, 1);
							TextWindowFree(state);
							TextWindowOpenFile(pointerStr, state, false, false);
							if state.LineCount = 0 then
								exit
							else begin
								viewingFile := true;
								newLinePos := LinePos;
								TextWindowDraw(state, false, viewingFile);
								InputKeyPressed := #0;
								InputShiftPressed := false;
							end;
						end else begin
							if (flags and TWS_HYPERLINK_AS_SELECT) <> 0 then begin
								Hyperlink := pointerStr;
							end else begin
								pointerStr := ':' + pointerStr;
								for iLine := 1 to LineCount do begin
									if Length(pointerStr) > Length(Lines[iLine]^) then begin
									end else begin
										for iChar := 1 to Length(pointerStr) do begin
											if UpCase(pointerStr[iChar]) <> UpCase(Lines[iLine]^[iChar]) then
												goto LabelNotMatched;
										end;
										newLinePos := iLine;
										InputKeyPressed := #0;
										InputShiftPressed := false;
										goto LabelMatched;
									LabelNotMatched:
									end;
								end;
							end;
						end;
					end;
				end else begin
					if InputKeyPressed = KEY_PAGE_UP then begin
						newLinePos := LinePos - TextWindowHeight + 4;
					end else if InputKeyPressed = KEY_PAGE_DOWN then begin
						newLinePos := LinePos + TextWindowHeight - 4;
{$IFDEF EDITOR}
					end else if ((InputKeyPressed = '-') or (InputKeyPressed = '+')
					or (InputKeyPressed = KEY_DELETE))
					and ((flags and TWS_EXIT_MINUS_PLUS_DEL) <> 0) then begin
						exitWindow := true;	
{$ENDIF}
{$IFDEF PRINTTXT}
					end else if InputKeyPressed = KEY_ALT_P then begin
						TextWindowPrint(state);
{$ENDIF}
					end;
				end;

			LabelMatched:
				if newLinePos < 1 then
					newLinePos := 1
				else if newLinePos > state.LineCount then
					newLinePos := LineCount;

				if newLinePos <> LinePos then begin
					LinePos := newLinePos;
					TextWindowDraw(state, false, viewingFile);
					if ((Lines[LinePos]^[1]) = '!') and ((flags and TWS_CONSTANT_TITLE) = 0) then
						if (flags and TWS_HYPERLINK_AS_SELECT) <> 0 then
							TextWindowDrawTitle($1E, #174'Press ENTER to select this'#175)
						else
							TextWindowDrawTitle($1E, #174'Press ENTER for more info'#175);
				end;
				if InputJoystickMoved then begin
					AccurateDelay(35);
				end;
			until (InputKeyPressed = KEY_ESCAPE) or (InputKeyPressed = KEY_ENTER)
			or exitWindow or InputShiftPressed;
			if InputKeyPressed = KEY_ESCAPE then begin
				InputKeyPressed := #0;
				TextWindowRejected := true;
			end;
		end;
	end;

procedure TextWindowSort(var state: TTextWindowState; fromIdx, toIdx: integer);
	var
		i, j: integer;
		smallestIdx: integer;

	procedure Swap(var a, b: PTTextWindowLine);
		var
			c: PTTextWindowLine;
		begin
			c := a;
			a := b;
			b := c;
		end;

	{ Returns the location of the pivot after separating. }
	function Partition(var state: TTextWindowState; low: integer;
		high: integer): integer;
	var
		pivot: PTTextWindowLine;
		i, j: integer;
	begin
		{ Choose a random pivot. A cannae be bothered to do anything
		  faster/more sophisticated. }
		pivot := state.Lines[Random(high-low) + low];
		i := low;
		j := high;

	    repeat
			while state.Lines[i]^ < pivot^ do Inc(i);
			while state.Lines[j]^ > pivot^ do Dec(j);

			if i <= j then begin
				Swap(state.Lines[i], state.Lines[j]);

				Inc(i);
				Dec(j);
	    	end;
		until i > j;

		Partition := i;
	end;

	procedure Quicksort(var state: TTextWindowState; low: integer;
		high: integer);
	var
		pivotPt: integer;
	begin
		if low < high then begin
			pivotPt := partition(state, low, high);
			Quicksort(state, low, pivotPt-1);
			Quicksort(state, pivotPt, high);
		end;
	end;

	begin
		if fromIdx < 1 then fromIdx := 1;
		if toIdx > state.LineCount then toIdx := state.LineCount;
		Quicksort(state, fromIdx, toIdx);
	end;

{$IFDEF EDITOR}
procedure TextWindowEdit(var state: TTextWindowState; extension: TExtensionString;
	syntaxHighlighting, multiExtension: boolean);
	var
		newLinePos: integer;
		insertMode: boolean;
		xOffset: integer;
		charPos: integer;
		i: integer;
		inputByte: byte;
		highlightLineStart, highlightLineEnd: integer;
		copyBuffer: ^TTextWindowLineBuffer;
		copyBufferLines: integer;
		forceFullRedraw: boolean;
		shiftHeld: boolean;
		textFilename: TFilenameString;
	procedure DrawLineEdit(lpos: integer);
		var
			i, lineX, lineY: integer;
{$IFDEF WIDECHAR}
			localXOffset, lineXLen: integer;
{$ENDIF}
			textColor: byte;
		begin
			with state do begin
				lineY := ((TextWindowY + lpos) - LinePos) + (TextWindowHeight div 2) + 1;
				if lpos = LinePos then begin
					VideoWriteText(TextWindowX + 2, lineY, $1C, #175);
					VideoWriteText(TextWindowX + (TextWindowWidth - 4), lineY, $1C, #174);
				end else begin
					VideoWriteText(TextWindowX + 2, lineY, $1C, ' ');
					VideoWriteText(TextWindowX + (TextWindowWidth - 4), lineY, $1C, ' ');
				end;
				VideoWriteText(TextWindowX + 3, lineY, $1E, ' ');
				if (lpos > 0) and (lpos <= LineCount) then begin
					textColor := $1E;
					if (lpos >= highlightLineStart) and (lpos <= highlightLineEnd) then begin
						textColor := $70;
					end else if syntaxHighlighting and (not VideoMonochrome) then begin
						case Lines[lpos]^[1] of
							#39: textColor := $1B; { comments }
							':': textColor := $1C; { labels }
							'$', '!': textColor := $1F; { centered text, selection }
							'@': textColor := $1D; { program name }
							'/', '?', '#': textColor := $1A; { direction/command }
						end;
					end;
					lineX := xOffset + 1;
{$IFDEF WIDECHAR}
					WideAdjustCursor(Lines[lpos]^, lineX, 1);
					localXOffset := (lineX - 1) - xOffset;
					lineXLen := WideGetStringLength(Lines[lpos]^, lineX, TextWindowWidth - 8 - localXOffset);
					for i := 1 to localXOffset do
						VideoWriteText(TextWindowX + 3 + i, lineY, $1E, ' ');
					VideoWriteTextWide(TextWindowX + 4 + localXOffset, lineY, textColor,
						Copy(Lines[lpos]^, lineX, lineXLen));
					for i := (lineXLen + 1) to (TextWindowWidth - 8 - localXOffset) do
						VideoWriteText(TextWindowX + 3 + localXOffset + i, lineY, $1E, ' ');
{$ELSE}
					for i := 1 to (TextWindowWidth - 8) do begin
						if lineX > Length(Lines[lpos]^) then
							VideoWriteText(TextWindowX + 3 + i, lineY, $1E, ' ')
						else
							VideoWriteText(TextWindowX + 3 + i, lineY, textColor, Lines[lpos]^[lineX]);
						Inc(lineX);
					end;
{$ENDIF}
				end else if (lpos = 0) or (lpos = (state.LineCount + 1)) then begin
					VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerSep);
				end else begin
					VideoWriteText(TextWindowX + 2, lineY, $1E, TextWindowStrInnerEmpty);
				end;
			end;
		end;
	procedure ClampCharPos;
		var
			i: integer;
		begin
			with state do begin
				i := Length(Lines[LinePos]^) + 1;
				if charPos > i then charPos := i;
{$IFDEF WIDECHAR}
				WideAdjustCursor(Lines[LinePos]^, charPos, -1);
{$ENDIF}
			end;
		end;
	procedure Redraw(line: integer);
		var
			i: integer;
{$IFDEF WIDECHAR}
			promptChar: string[WIDE_CHAR_MAX_LENGTH];
{$ELSE}
			promptChar: char;
{$ENDIF}
			newXOffset: integer;
			fullRedraw: boolean;
		begin
			fullRedraw := (line < 0);
			newXOffset := charPos - (TextWindowWidth - 8);
			if newXOffset < 0 then newXOffset := 0;
			if newXOffset <> xOffset then begin
				xOffset := newXOffset;
				fullRedraw := true;
			end;
			if fullRedraw then begin
				for i := 0 to (TextWindowHeight - 4) do
					DrawLineEdit(state.LinePos - (TextWindowHeight div 2) + i + 2);
			end else begin
				DrawLineEdit(line);
			end;
			{ draw prompt }
			with state do begin
{$IFDEF WIDECHAR}
				if charPos > Length(Lines[LinePos]^) then
					promptChar := ' '
				else begin
					promptChar[0] := Chr(WideGetCharLength(Lines[LinePos]^, charPos));
					for i := 1 to Ord(promptChar[0]) do
						promptChar[i] := Lines[LinePos]^[charPos + i - 1];
				end;
				VideoWriteTextWide(charPos - xOffset + TextWindowX + 3,
					TextWindowY + (TextWindowHeight div 2) + 1,
					$70, promptChar);
{$ELSE}
				if charPos > Length(Lines[LinePos]^) then
					promptChar := ' '
				else
					promptChar := state.Lines[state.LinePos]^[charPos];
				VideoWriteText(charPos - xOffset + TextWindowX + 3,
					TextWindowY + (TextWindowHeight div 2) + 1,
					$70, promptChar);
{$ENDIF}
			end;
		end;
	procedure DeleteLine(lpos: integer);
		var
			i: integer;
		begin
			with state do begin
				if (lpos < 1) or (lPos > LineCount) then exit;
				if LineCount > 1 then begin
					Dispose(Lines[lpos]);
					for i := (lpos + 1) to LineCount do
						Lines[i - 1] := Lines[i];

					Dec(LineCount);
					if newLinePos > lpos then Dec(newLinePos);
				end else begin
					Lines[1]^ := '';
				end;
			end;
		end;
	procedure InsertCharacter(ch: char);
		begin
			with state do begin
				if not insertMode then begin
					Lines[LinePos]^ := Copy(Lines[LinePos]^, 1, charPos - 1)
						+ ch
						+ Copy(Lines[LinePos]^, charPos + 1, Length(Lines[LinePos]^) - charPos);
					Inc(charPos);
				end else begin
					if Length(Lines[LinePos]^) < MAX_LINE_LENGTH_EDIT then begin
						Lines[LinePos]^ := Copy(Lines[LinePos]^, 1, charPos - 1)
							+ ch
							+ Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
						Inc(charPos);
					end;
				end;
			end;
		end;
	procedure InsertString(var s: string);
		var
			i: integer;
		begin
			with state do begin
				if ((not insertMode) and ((charPos + Length(s)) <= MAX_LINE_LENGTH_EDIT))
					or (insertMode and ((Length(Lines[LinePos]^) + Length(s)) <= MAX_LINE_LENGTH_EDIT))
				then begin
					for i := 1 to Length(s) do
						InsertCharacter(s[i]);
				end;
			end;
		end;
	procedure ClearHighlight;
		begin
			highlightLineStart := -1;
			highlightLineEnd := -1;
		end;
	procedure AddLinePosToHighlight(lpos: integer);
		begin
			if lPos = (highlightLineStart - 1) then  begin
				highlightLineStart := lpos;
				Redraw(lpos);
			end else if lPos = (highlightLineEnd + 1) then begin
				highlightLineEnd := lpos;
				Redraw(lpos);
			end else if (lPos < highlightLineStart) or (lPos > highlightLineEnd) then begin
				if highlightLineStart = -1 then begin
					highlightLineStart := lpos;
					highlightLineEnd := lpos;
				end else begin
					ClearHighlight;
				end;
				Redraw(-1);
			end;
		end;
	procedure FreeCopyBuffer;
		begin
			if copyBufferLines > 0 then begin
				FreeMem(copyBuffer, copyBufferLines * SizeOf(pointer));
				copyBufferLines := 0;
			end;
		end;
	procedure CopyHighlightToBuffer;
		var
			i: integer;
		begin
			FreeCopyBuffer;
			if (highlightLineEnd >= highlightLineStart) and (highlightLineStart > 0) then begin
				copyBufferLines := highlightLineEnd - highlightLineStart + 1;
				GetMem(copyBuffer, copyBufferLines * SizeOf(pointer));
				for i := 1 to copyBufferLines do begin
					New(copyBuffer^[i]);
					copyBuffer^[i]^ := state.Lines[i + highlightLineStart - 1]^;
				end;
			end;
		end;
	procedure InsertLine(lpos: integer; contents: TTextWindowLine);
		var
			i: integer;
		begin
			with state do if (lpos >= 1) and (lpos <= LineCount) and (LineCount < (MAX_TEXT_WINDOW_LINES - 1)) then begin
				for i := LineCount downto lpos do
					Lines[i + 1] := Lines[i];
				New(Lines[lpos]);
				Lines[lpos]^ := contents;
				Inc(LineCount);
				if newLinePos >= lpos then Inc(newLinePos);
			end;
		end;
	begin
		InputKeyBuffering := true;
{$IFDEF SDL2}
		VideoSetTextInputArea(TextWindowX + 4, TextWindowY + (TextWindowHeight div 2) + 1, TextWindowWidth - 8, 1);
{$ENDIF}

		with state do begin
			if LineCount = 0 then
				TextWindowAppendEdit(state, '');
			insertMode := true;
			ClearHighlight;
			copyBufferLines := 0;
			LinePos := 1;
			charPos := 1;
			Redraw(-1);
			forceFullRedraw := false;
			TextWindowDrawTitle($1E, state.Title);
			repeat
				if insertMode then
					VideoWriteText(VideoSidebarX + 15, 12, $1E, 'on ')
				else
					VideoWriteText(VideoSidebarX + 15, 12, $1E, 'off');

				ClampCharPos;
				shiftHeld := false;
				repeat
{$IFDEF SDL2}
					SoundIdle(IMUntilFrame);
{$ENDIF}
					DemoInputUpdate(0, false);
					shiftHeld := shiftHeld or KeysShiftHeld;
				until InputKeyPressed <> #0;
				newLinePos := LinePos;

				case InputKeyPressed of
					KEY_ESCAPE: begin
						if highlightLineStart <> -1 then begin
							ClearHighlight;
							InputKeyPressed := #0;
							forceFullRedraw := true;
						end;
					end;
{$IFNDEF WIDECHAR}
					KEY_F10: begin
						SidebarPromptCharacter(true, VideoSidebarX + 3, 3, 'Character?', inputByte);
						InsertCharacter(Chr(inputByte));
						SidebarClearLine(3);
						SidebarClearLine(4);
						SidebarClearLine(5);
					end;
{$ENDIF}
					KEY_UP: begin
						newLinePos := LinePos - 1;
						if shiftHeld and (newLinePos >= 1) then AddLinePosToHighlight(newLinePos);
					end;
					KEY_DOWN: begin
						newLinePos := LinePos + 1;
						if shiftHeld then AddLinePosToHighlight(LinePos);
					end;
					KEY_PAGE_UP: newLinePos := LinePos - TextWindowHeight + 4;
					KEY_PAGE_DOWN: newLinePos := LinePos + TextWindowHeight - 4;
					KEY_RIGHT: begin
{$IFDEF WIDECHAR}
						Inc(charPos, WideGetCharLength(Lines[LinePos]^, charPos));
{$ELSE}
						Inc(charPos);
{$ENDIF}
						if charPos > (Length(Lines[LinePos]^) + 1) then begin
							charPos := 1;
							newLinePos := LinePos + 1;
						end;

					end;
					KEY_LEFT: begin
						Dec(charPos);
{$IFDEF WIDECHAR}
						WideAdjustCursor(Lines[LinePos]^, charPos, -1);
{$ENDIF}
						if charPos < 1 then begin
							charPos := 255;
							newLinePos := LinePos - 1;
						end;
					end;
					KEY_ENTER: begin
						if LineCount < (MAX_TEXT_WINDOW_LINES - 1) then begin
							for i := LineCount downto (LinePos + 1) do
								Lines[i + 1] := Lines[i];

							New(Lines[LinePos + 1]);
							Lines[LinePos + 1]^
								:= Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
							Lines[LinePos]^
								:= Copy(Lines[LinePos]^, 1, charPos - 1);

							newLinePos := LinePos + 1;
							charPos := 1;
							Inc(LineCount);
						end;
					end;
					KEY_BACKSPACE: begin
						if charPos > 1 then begin
{$IFDEF WIDECHAR}
							Dec(charPos);
							WideAdjustCursor(Lines[LinePos]^, charPos, -1);
							Lines[LinePos]^ :=
								Copy(Lines[LinePos]^, 1, charPos - 1)
								+ Copy(Lines[LinePos]^,
									charPos + WideGetCharLength(Lines[LinePos]^, charPos),
									Length(Lines[LinePos]^) - charPos);
{$ELSE}
							Lines[LinePos]^ :=
								Copy(Lines[LinePos]^, 1, charPos - 2)
								+ Copy(Lines[LinePos]^, charPos, Length(Lines[LinePos]^) - charPos + 1);
							Dec(charPos);
{$ENDIF}
						end else if Length(Lines[LinePos]^) = 0 then begin
							DeleteLine(LinePos);
							newLinePos := LinePos - 1;
							charPos := 255;
							forceFullRedraw := true;
						end;
					end;
					KEY_INSERT: begin
						insertMode := not insertMode;
					end;
					KEY_DELETE: begin
						Lines[LinePos]^ :=
							Copy(Lines[LinePos]^, 1, charPos - 1)
{$IFDEF WIDECHAR}
							+ Copy(Lines[LinePos]^,
								charPos + WideGetCharLength(Lines[LinePos]^, charPos),
								Length(Lines[LinePos]^) - charPos);
{$ELSE}
							+ Copy(Lines[LinePos]^,
								charPos + 1,
								Length(Lines[LinePos]^) - charPos);
{$ENDIF}
					end;
					KEY_CTRL_X: if highlightLineStart > 0 then begin
						CopyHighlightToBuffer;
						for i := highlightLineStart to highlightLineEnd do
							DeleteLine(highlightLineStart);
						ClearHighlight;
						forceFullRedraw := true;
					end;
					KEY_CTRL_C: if highlightLineStart > 0 then begin
						CopyHighlightToBuffer;
						ClearHighlight;
						forceFullRedraw := true;
					end;
					KEY_CTRL_V: if copyBufferLines > 0 then begin
						for i := copyBufferLines downto 1 do
							InsertLine(LinePos, copyBuffer^[i]^);
					end;
					KEY_CTRL_Y: begin
						if highlightLineStart > 0 then begin
							for i := highlightLineStart to highlightLineEnd do
								DeleteLine(highlightLineStart);
							ClearHighlight;
						end else begin
							DeleteLine(LinePos);
						end;
						forceFullRedraw := true;
					end;
					KEY_CTRL_O: begin
						textFilename := FileSelect('Text Files', extension, FileTextCachedLinePos);
						if (InputKeyPressed <> KEY_ESCAPE) and (Length(textFilename) <> 0) then begin
							if not multiExtension then
								textFilename := textFilename + extension;
							if FileExists(textFilename) then begin
								TextWindowFreeEdit(state);
								TextWindowOpenFile('*' + textFilename, state, true, true);
							end else begin
								VideoWriteText(VideoSidebarX + 3, 4, $1E, 'File not found!');
								PauseOnError;
								SidebarClearLine(4);
							end;
							forceFullRedraw := true;
						end;
						InputKeyPressed := #0;
					end;
					KEY_CTRL_S: begin
						textFilename := '';
						if multiExtension then begin
							SidebarPromptFilename('Filename', '', textFilename, PROMPT_ANY);
						end else begin
							SidebarPromptFilename('Filename', extension, textFilename, PROMPT_ALPHANUM);
							if Length(textFilename) > 0 then
								textFilename := textFilename + extension;
						end;
						if (Length(textFilename) > 0) and (OverwriteCheck(textFilename)) then begin
							TextWindowSaveFile(textFilename, state);
						end;
						InputKeyPressed := #0;
					end;
{$IFDEF WIDECHAR}
					KEY_WIDESTRING: begin
						InsertString(InputKeyPressedWide);
					end;
{$ENDIF}
				else
					if ((InputKeyPressed >= #32) and (InputKeyPressed < #127))
{$IFDEF SHIFTJIS}
						or ((InputKeyPressed >= #$A1) and (InputKeyPressed <= #$DF))
{$ENDIF}
					then
						InsertCharacter(InputKeyPressed);
				end;

				if newLinePos < 1 then begin
					newLinePos := 1;
					charPos := 1;
				end else if newLinePos > LineCount then begin
					newLinePos := LineCount;
					charPos := 255;
				end;

				if (newLinePos <> LinePos) or forceFullRedraw then begin
					LinePos := newLinePos;
					ClampCharPos;
					Redraw(-1);
					forceFullRedraw := false;
				end else begin
					ClampCharPos;
					Redraw(LinePos);
				end;

			until InputKeyPressed = KEY_ESCAPE;

			if Length(Lines[LineCount]^) = 0 then begin
				Dispose(Lines[LineCount]);
				Dec(LineCount);
			end;
		end;
		FreeCopyBuffer;

		InputKeyBuffering := false;
	end;
{$ENDIF}

function ResourceDataCheckPresent: boolean;
	var
		f: file;
		i: integer;
	begin
		if ResourceDataHeader.EntryCount = 0 then begin
			AssignFSys(f, ResourceDataFileName);
			Reset(f, 1);
			if IOResult = 0 then begin
{$IFDEF RAWMEM}
				BlockRead(f, ResourceDataHeader, SizeOf(ResourceDataHeader));
{$ELSE}
				BlockRead(f, ResourceDataHeader.Version, SizeOf(ResourceDataHeader.Version));
				BlockRead(f, ResourceDataHeader.EntryCount, SizeOf(ResourceDataHeader.EntryCount));
				for i := 1 to MAX_RESOURCE_DATA_FILES do
					BlockRead(f, ResourceDataHeader.Name[i], SizeOf(ResourceDataHeader.Name[i]));
				for i := 1 to MAX_RESOURCE_DATA_FILES do
					BlockRead(f, ResourceDataHeader.FileOffset[i], SizeOf(ResourceDataHeader.FileOffset[i]));
				for i := 1 to MAX_RESOURCE_DATA_FILES do
					BlockRead(f, ResourceDataHeader.FileSize[i], SizeOf(ResourceDataHeader.FileSize[i]));
{$ENDIF}
{$IFDEF ENDIAN_BIG}
				ResourceDataHeader.Version := LEtoN(ResourceDataHeader.Version);
				ResourceDataHeader.EntryCount := LEtoN(ResourceDataHeader.EntryCount);
				for i := 1 to MAX_RESOURCE_DATA_FILES do
					ResourceDataHeader.FileOffset[i] := LEtoN(ResourceDataHeader.FileOffset[i]);
				for i := 1 to MAX_RESOURCE_DATA_FILES do
					ResourceDataHeader.FileSize[i] := LEtoN(ResourceDataHeader.FileSize[i]);
{$ENDIF}
			end;
			if (IOResult <> 0) or (ResourceDataHeader.Version <> RESOURCE_DATA_VERSION) then
				ResourceDataHeader.EntryCount := -1;
			Close(f);
			if IOResult <> 0 then begin end;
		end;

		ResourceDataCheckPresent := (ResourceDataHeader.EntryCount > 0);
	end;

function ResourceDataReadBinaryFile(name: TFilenameString; var fdata: pointer; foffset: word; fmaxsize: word): word;
	var
		f: file;
		i: integer;
		entryPos: integer;
		fsize: longint;
		bsize: word;
	begin
		bsize := 0;
		entryPos := -1;

		if ResourceDataCheckPresent then begin
			for i := 1 to ResourceDataHeader.EntryCount do begin
				if (entryPos < 0) and (ResourceDataHeader.Name[i] = name) then begin
					entryPos := i;
				end;
			end;

			if entryPos >= 1 then begin
				AssignFSys(f, ResourceDataFilename);
				Reset(f, 1);
				Seek(f, ResourceDataHeader.FileOffset[entryPos] + foffset);
				if IOResult = 0 then begin
					fsize := ResourceDataHeader.FileSize[entryPos] - foffset;
					bsize := fmaxsize;
					if (fsize < bsize) then bsize := fsize;
					if bsize > 0 then begin
						GetMem(fdata, bsize);
						BlockRead(f, fdata^, bsize);
					end;
					Close(f);
				end;
			end;
		end;

		ResourceDataReadBinaryFile := bsize;
	end;

procedure TextWindowOpenFile(filename: TFilenameString; var state: TTextWindowState; editing, showError: boolean);
	var
		f: file;
		tf: text;
		i: integer;
		entryPos: integer;
		retVal: boolean;
		line: ^string;
		lineLen: byte;
	label EntryPosFoundResData;
	begin
		with state do begin
			retVal := true;
			for i := 1 to Length(filename) do
				retVal := retVal and (filename[i] <> '.');
			if retVal then
				filename := filename + '.HLP';

			if filename[1] = '*' then begin
				filename := Copy(filename, 2, Length(filename) - 1);
				entryPos := -1;
			end else begin
				entryPos := 0;
			end;

			TextWindowInitState(state);

			if ResourceDataCheckPresent and (entryPos = 0) then begin
				for i := 1 to ResourceDataHeader.EntryCount do begin
					if ResourceDataHeader.Name[i] = UpCaseString(filename) then begin
						entryPos := i;
						goto EntryPosFoundResData;
					end;
				end;
			end;
			EntryPosFoundResData:

			if entryPos <= 0 then begin
			{$IFDEF EDITOR}
				if showError and (not FileExists(filename)) then begin
					VideoWriteText(VideoSidebarX + 3, 4, $1E, 'File not found!');
					PauseOnError;
					exit;
				end;
			{$ENDIF}
				AssignFSysText(tf, filename);
				Reset(tf);
				while (IOResult = 0) and (not Eof(tf)) do begin
					Inc(LineCount);
					New(Lines[LineCount]);
					ReadLn(tf, Lines[LineCount]^);
				end;
				Close(tf);
			end else begin
				AssignFSys(f, ResourceDataFilename);
				Reset(f, 1);
				Seek(f, ResourceDataHeader.FileOffset[entryPos]);
				if IOResult = 0 then begin
					retVal := true;
					while (IOResult = 0) and retVal do begin
						Inc(LineCount);

						BlockRead(f, lineLen, 1);
						if editing then
							New(Lines[LineCount])
						else
							GetMem(Lines[LineCount], lineLen + 1);
						Lines[LineCount]^[0] := Chr(lineLen);
						{$IFNDEF FPC}
						line := Ptr(Seg(Lines[LineCount]^), Ofs(Lines[LineCount]^) + 1);
						{$ELSE}
						line := Pointer(Lines[LineCount]) + 1;
						{$ENDIF}

						if lineLen = 0 then begin
							Lines[LineCount]^ := '';
						end else begin
							BlockRead(f, line^, lineLen);
							if Lines[LineCount]^ = '@' then begin
								retVal := false;
								Lines[LineCount]^ := '';
							end;
						end;
					end;
				end;
				Close(f);
			end;
		end;
	end;

procedure TextWindowSaveFile(filename: TFilenameString; var state: TTextWindowState);
	var
		f: text;
		i: integer;
	label OnError;
	begin
		AssignFSysText(f, filename);
		Rewrite(f);
		if DisplayIOError then goto OnError;

		with state do begin
			for i := 1 to LineCount do begin
{$IFDEF FPC}
				Write(f, Lines[i]^);
				Write(f, #13#10); { always write DOS endings }
{$ELSE}
				WriteLn(f, Lines[i]^);
{$ENDIF}
				if DisplayIOError then goto OnError;
			end;
		end;

	OnError:
		Close(f);
	end;

procedure TextWindowDisplayFile(filename: TFilenameString; title: TTextWindowLine);
	var
		state: TTextWindowState;
	begin
		state.Title := title;
		TextWindowOpenFile(filename, state, false, false);
		state.Selectable := false;
		if state.LineCount > 0 then begin
			TextWindowDrawOpen(state);
			TextWindowSelect(state, TWS_VIEWING_FILE);
			TextWindowDrawClose(state);
		end;
		TextWindowFree(state);
	end;

procedure TextWindowInit(x, y, width, height: integer);
	var
		i: integer;
	begin
		TextWindowX := x;
		TextWindowY := y;
		if width > MAX_TEXT_WINDOW_WIDTH then
			TextWindowWidth := MAX_TEXT_WINDOW_WIDTH
		else
			TextWindowWidth := width;
		if height > MAX_TEXT_WINDOW_HEIGHT then
			TextWindowHeight := MAX_TEXT_WINDOW_HEIGHT
		else
			TextWindowHeight := height;

		TextWindowStrInnerEmpty[0] := Chr(TextWindowWidth - 5);
		TextWindowStrInnerLine[0] := Chr(TextWindowWidth - 5);
		for i := 1 to (TextWindowWidth - 5) do begin
			TextWindowStrInnerEmpty[i] := ' ';
			TextWindowStrInnerLine[i] := #205;
		end;
		TextWindowStrTop    := #198#209 + TextWindowStrInnerLine  + #209#181;
		TextWindowStrBottom := #198#207 + TextWindowStrInnerLine  + #207#181;
		TextWindowStrSep    :=  ' '#198 + TextWindowStrInnerLine  + #181' ';
		TextWindowStrText   :=  ' '#179 + TextWindowStrInnerEmpty + #179' ';
		TextWindowStrInnerArrows := TextWindowStrInnerEmpty;
		TextWindowStrInnerArrows[1] := #175;
		TextWindowStrInnerArrows[Length(TextWindowStrInnerArrows)] := #174;
		TextWindowStrInnerSep := TextWindowStrInnerEmpty;
		for i := 1 to (TextWindowWidth div 5) do
			TextWindowStrInnerSep[i * 5 + ((TextWindowWidth mod 5) shr 1)] := #7;
	end;

procedure TextWindowInitXY(x, y: integer);
	begin
		TextWindowX := x;
		TextWindowY := y;
	end;

begin
	ResourceDataFileName := '';
	ResourceDataHeader.EntryCount := 0;
end.
