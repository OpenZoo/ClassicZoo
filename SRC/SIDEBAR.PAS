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
unit Sidebar;

interface
	uses GameVars;
	const
		PROMPT_NUMERIC = 0;
		PROMPT_ALPHANUM = 1;
		PROMPT_ANY = 2;
	procedure SidebarClearLine(y: integer);
	procedure SidebarClear;
	procedure SidebarPromptCharacter(editable: boolean; x, y: integer; prompt: TSmallString; var value: byte);
	procedure SidebarPromptNumeric(editable: boolean; x, y: integer; prompt: string; minV, maxV: integer; var value: integer);
	procedure SidebarPromptSlider(editable: boolean; x, y: integer; prompt: string; var value: byte);
	{ choiceStr: "A B C", spaces are significant }
	procedure SidebarPromptChoice(editable: boolean; y: integer; prompt, choiceStr: string; var result: byte);
	procedure SidebarPromptDirection(editable: boolean; y: integer; prompt: string; var deltaX, deltaY: integer);
	procedure PromptString(x, y, arrowColor, color, width, stringLength: integer; mode: byte; var buffer: TSmallString);
	function SidebarPromptYesNo(message: string; defaultReturn: boolean): boolean;
	procedure SidebarPromptNumericAsString(prompt: string; extension: TSmallString; minV, maxV: integer; var value: integer);
	procedure SidebarPromptFilename(prompt: string; extension: TSmallString; var filename: string; promptMode: byte);
	procedure PopupPromptString(question: string; var buffer: TSmallString; maxLen: integer);
	procedure SidebarAnimateLoading(var loadProgress: integer);
	procedure BottomAnimateLoading(var loadProgress: integer);
	function DisplayIOError: boolean;
	procedure GameDisplayResourceImage(name: TString50; x, y, width, height: integer);
	function OverwriteCheck(filename: string): boolean;

implementation
uses
{$IFDEF WIDECHAR} ZWideChr, {$ENDIF}
FileOps, ZInput, TimerSys, Sounds, ZVideo, TxtWind, Game;

{$IFNDEF MSDOS}
{$DEFINE SAFEVID}
{$ELSE}
{$IFDEF NEC98}
{$DEFINE SAFEVID}
{$ENDIF}
{$ENDIF}

type
	TScreenBinArray = array[0 .. ((160*25)-1)] of byte;
const
{$IFDEF E_SUPERZ}
	ProgressAnimColors: array[0 .. 7] of byte = ($18, $1C, $19, $1D, $1A, $1E, $1B, $1F);
{$ELSE}
	ProgressAnimColors: array[0 .. 7] of byte = ($14, $1C, $15, $1D, $16, $1E, $17, $1F);
{$ENDIF}
	ProgressAnimStrings: array[0 .. 7] of string[5] =
		('....|', '...*/', '..*.-', '.*..\', '*...|', '..../', '....-', '....\');

procedure SidebarClearLine(y: integer);
	begin
{$IFDEF NEC98}
		if VideoPc98DrawingMode = 0 then
			VideoWriteText(VideoSidebarX + 0, y, $01,
				{$IFDEF E_SUPERZ}'                   '
				{$ELSE}#179'                   '{$ENDIF})
		else
{$ENDIF}
		VideoWriteText(VideoSidebarX + 0, y, $11,
			{$IFDEF E_SUPERZ}'                   '
			{$ELSE}#179'                   '{$ENDIF});
	end;

procedure SidebarClear;
	var
		i: integer;

	begin
		for i := 3 to VideoRows - 1 do
			SidebarClearLine(i);
	end;

procedure SidebarPromptCharacter(editable: boolean; x, y: integer; prompt: TSmallString; var value: byte);
	var
		i, newValue: integer;
	begin
		SidebarClearLine(y);
		VideoWriteText(x, y, Integer(editable) + $1E, prompt);
		SidebarClearLine(y + 1);
		VideoWriteText(x + 5, y + 1, $9F, #31);
		SidebarClearLine(y + 2);

		repeat
			for i := (value - 4) to (value + 4) do
				VideoWriteText(((x + i) - value) + 5, y + 2, $1E, Chr(i and $FF));

			if editable then begin
				AccurateDelay(25);
				InputUpdate;
				if (InputKeyPressed = KEY_TAB) or (InputKeyPressed = KEY_PAGE_DOWN) then
					InputDeltaX := 9
				else if (InputKeyPressed = KEY_PAGE_UP) then
					InputDeltaX := -9;

				newValue := value + InputDeltaX;
				if value <> newValue then begin
					value := newValue and $FF;
					SidebarClearLine(y + 2);
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(x + 5, y + 1, $1F, #31);
	end;

procedure SidebarPromptNumeric(editable: boolean; x, y: integer; prompt: string; minV, maxV: integer; var value: integer);
	var
		valueOffset: integer;
		newValue: longint;
		numStr: string[6];
	begin
		SidebarClearLine(y);
		VideoWriteText(x, y, Integer(editable) + $1E, prompt);
		SidebarClearLine(y + 1);
		SidebarClearLine(y + 2);
		VideoWriteText(x + 1, y + 2, $1E, #30#31);

		repeat
			if editable then begin
				if InputJoystickMoved then
					AccurateDelay(45);

				Str(value, numStr);
				VideoWriteText(x + 4, y + 2, $1F, numStr);

{$IFDEF SDL2}
				SoundIdle(IMUntilFrame);
{$ENDIF}
				InputUpdate;
				valueOffset := 0;
				case InputKeyPressed of
					KEY_UP: valueOffset := 1;
					KEY_DOWN: valueOffset := -1;
					KEY_PAGE_UP: valueOffset := 5;
					KEY_PAGE_DOWN: valueOffset := -5;
				end;
				
				if valueOffset <> 0 then begin
					newValue := LongInt(value) + valueOffset;
					if (newValue > maxV) then newValue := maxV
					else if (newValue < minV) then newValue := minV;

					if (value <> newValue) then begin
						value := Integer(newValue);
						VideoWriteText(x + 4, y + 2, $1E, '      ');
					end;
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		Str(value, numStr);
		VideoWriteText(x + 4, y + 2, $1E, numStr);
	end;

procedure SidebarPromptSlider(editable: boolean; x, y: integer; prompt: string; var value: byte);
	var
		newValue: integer;
		startChar, endChar: char;
	begin
		if prompt[Length(prompt) - 2] = ';' then begin
			startChar := prompt[Length(prompt) - 1];
			endChar := prompt[Length(prompt)];
			prompt := Copy(prompt, 1, Length(prompt) - 3);
		end else begin
			startChar := '1';
			endChar := '9';
		end;

		SidebarClearLine(y);
		VideoWriteText(x, y, Integer(editable) + $1E, prompt);
		SidebarClearLine(y + 1);
		SidebarClearLine(y + 2);
		VideoWriteText(x, y + 2, $1e, startChar + '....:....' + endChar);

		repeat
			if editable then begin
				if InputJoystickMoved then
					AccurateDelay(45);
				VideoWriteText(x + value + 1, y + 1, $9F, #31);

{$IFDEF SDL2}
				SoundIdle(IMUntilFrame);
{$ENDIF}
				InputUpdate;
				if (InputKeyPressed >= '1') and (InputKeyPressed <= '9') then begin
					value := Ord(InputKeyPressed) - 49;
					SidebarClearLine(y + 1);
				end else begin
					if (InputKeyPressed = KEY_PAGE_DOWN) then
						newValue := 8
					else if (InputKeyPressed = KEY_PAGE_UP) then
						newValue := 0
					else
						newValue := value + InputDeltaX;
					if (value <> newValue) and (newValue >= 0) and (newValue <= 8) then begin
						value := newValue;
						SidebarClearLine(y + 1);
					end;
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(x + value + 1, y + 1, $1F, #31);
	end;

procedure SidebarPromptChoice(editable: boolean; y: integer; prompt, choiceStr: string; var result: byte);
	var
		i, j, choiceCount: integer;
		newResult: integer;
	begin
		SidebarClearLine(y);
		SidebarClearLine(y + 1);
		SidebarClearLine(y + 2);
		VideoWriteText(VideoSidebarX + 3, y, Integer(editable) + $1E, prompt);
		VideoWriteText(VideoSidebarX + 3, y + 2, $1E, choiceStr);

		choiceCount := 1;
		for i := 1 to Length(choiceStr) do
			if choiceStr[i] = ' ' then
				Inc(choiceCount);

		repeat
			j := 0;
			i := 1;
			while (j < result) and (i < Length(choiceStr)) do begin
				if choiceStr[i] = ' ' then
					Inc(j);	
				Inc(i);
			end;

			if editable then begin
				VideoWriteText(VideoSidebarX + 2 + i, y + 1, $9F, #31);
				AccurateDelay(35);
				InputUpdate;

				if (InputKeyPressed = KEY_PAGE_DOWN) then
					newResult := choiceCount - 1
				else if (InputKeyPressed = KEY_PAGE_UP) then
					newResult := 0
				else
					newResult := result + InputDeltaX;
				if (result <> newResult) and (newResult >= 0) and (newResult <= (choiceCount - 1)) then begin
					result := newResult;
					SidebarClearLine(y + 1);
				end;
			end;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) or not editable or InputShiftPressed;

		VideoWriteText(VideoSidebarX + 2 + i, y + 1, $1F, #31);
	end;

procedure SidebarPromptDirection(editable: boolean; y: integer; prompt: string; var deltaX, deltaY: integer);
	var
		choice: byte;
	begin
		if deltaY = -1 then
			choice := 0
		else if deltaY = 1 then
			choice := 1
		else if deltaX = -1 then
			choice := 2
		else
			choice := 3;
		SidebarPromptChoice(editable, y, prompt, #24' '#25' '#27' '#26, choice);
		deltaX := NeighborDeltaX[choice];
		deltaY := NeighborDeltaY[choice];
	end;

procedure PromptString(x, y, arrowColor, color, width, stringLength: integer; mode: byte; var buffer: TSmallString);
	var
		i, iOffs: integer;
		oldBuffer: TSmallString;
		firstKeyPress: boolean;
	begin
		InputKeyBuffering := true;
{$IFDEF SDL2}
		VideoSetTextInputArea(x, y, width, 1);
{$ENDIF}

		oldBuffer := buffer;
		firstKeyPress := true;

		repeat
			iOffs := Length(buffer) - width + 1;
			if iOffs < 1 then iOffs := 1;
{$IFDEF WIDECHAR}
			WideAdjustCursor(buffer, iOffs, 1);
{$ENDIF}
			for i := 0 to (width - 1) do begin
				VideoWriteText(x + i, y, color, ' ');
				VideoWriteText(x + i, y - 1, arrowColor, ' ');
			end;
			VideoWriteText(x + width, y - 1, arrowColor, ' ');
			VideoWriteText(x + Length(buffer) - iOffs + 1, y - 1, (arrowColor and $F0) + $0F, #31);
{$IFDEF WIDECHAR}
			VideoWriteTextWide(x, y, color, Copy(buffer, iOffs, WideGetStringLength(buffer, iOffs, width)));
{$ELSE}
			VideoWriteText(x, y, color, Copy(buffer, iOffs, width));
{$ENDIF}

			InputReadWaitKey;

			if (InputKeyPressed = KEY_LEFT) or (InputKeyPressed = KEY_BACKSPACE) then begin
				if (Length(buffer) > 0) then begin
{$IFDEF WIDECHAR}
					i := Length(buffer);
					WideAdjustCursor(buffer, i, -1);
					buffer := Copy(buffer, 1, i - 1);
{$ELSE}
					buffer := Copy(buffer, 1, Length(buffer) - 1);
{$ENDIF}
				end;
			end else if (Length(buffer) < stringLength) then begin
				case mode of
					PROMPT_NUMERIC: begin
						if (InputKeyPressed in ['0' .. '9']) then begin
							if firstKeyPress then
								buffer := '';
							buffer := buffer + InputKeyPressed;
						end;
					end;
					PROMPT_ANY: begin
{$IFDEF WIDECHAR}
						if InputKeyPressed = KEY_WIDESTRING then begin
							if firstKeyPress then
								buffer := '';
							if (Length(buffer) + Length(InputKeyPressedWide)) <= stringLength then
								buffer := buffer + InputKeyPressedWide;
						end else
{$ENDIF}
						if (InputKeyPressed >= #32) and (InputKeyPressed < #128) then begin
							if firstKeyPress then
								buffer := '';
							buffer := buffer + InputKeyPressed;
						end;
					end;
					PROMPT_ALPHANUM: begin
						if (UpCase(InputKeyPressed) in ['A' .. 'Z'])
							or (InputKeyPressed in ['0' .. '9'])
							or (InputKeyPressed = '-') then
						begin
							if firstKeyPress then
								buffer := '';
							buffer := buffer + UpCase(InputKeyPressed);
						end;
					end;
				end;
			end;

			firstKeyPress := false;
		until (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE);

		if InputKeyPressed = KEY_ESCAPE then begin
			buffer := oldBuffer;
		end;

		InputKeyBuffering := false;
	end;

function SidebarPromptYesNo(message: string; defaultReturn: boolean): boolean;
	begin
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(VideoSidebarX + 3, 5, $1F, message);
		VideoWriteText(VideoSidebarX + 3 + Length(message), 5, $9E, '_');

		repeat
			InputReadWaitKey;
		until UpCase(InputKeyPressed) in [KEY_ESCAPE, 'N', 'Y'];
		if UpCase(InputKeyPressed) = 'Y' then
			defaultReturn := true
		else
			defaultReturn := false;

		SidebarClearLine(5);
		SidebarPromptYesNo := defaultReturn;
	end;

procedure SidebarPromptFilename(prompt: string; extension: TSmallString; var filename: string; promptMode: byte);
	begin
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);

		VideoWriteText(VideoSidebarX + 15 - Length(prompt), 3, $1F, prompt);

		if Length(extension) <= 0 then begin
			VideoWriteText(VideoSidebarX + 3, 5, $0F, '            ');
{$IFDEF SDL2}
			PromptString(63, 5, $1E, $0F, 12, 20, promptMode, filename);
{$ELSE}
			PromptString(63, 5, $1E, $0F, 12, 12, promptMode, filename);
{$ENDIF}
		end else begin
			VideoWriteText(VideoSidebarX + 3, 5, $0F, '        ' + extension);
{$IFDEF SDL2}
			PromptString(63, 5, $1E, $0F, 8, 16, promptMode, filename);
{$ELSE}
			PromptString(63, 5, $1E, $0F, 8, 8, promptMode, filename);
{$ENDIF}
		end;

		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
	end;

procedure SidebarPromptNumericAsString(prompt: string; extension: TSmallString; minV, maxV: integer; var value: integer);
	var
		running: boolean;
		valStr: string[20];
		i: integer;
	function ClampVal: boolean;
		begin
			ClampVal := true;
			if value < minV then
				value := minV
			else if value > maxV then
				value := maxV
			else
				ClampVal := false;
		end;
	begin
		running := true;
		while running do begin
			if ClampVal then begin end;
			Str(value, valStr);
			SidebarPromptFilename(prompt, extension, valStr, PROMPT_NUMERIC);
			Val(valStr, value, i);
			if not ClampVal then running := false;
		end;
	end;

function DisplayIOError: boolean;
	var
		ioResValue: word;
		errorNumStr: TSmallString;
		statusMsg: TSmallString;
		textWindow: TTextWindowState;
	begin
		ioResValue := IOResult;
		if ioResValue = 0 then begin
			DisplayIOError := false;
			exit;
		end;

		case ioResValue of
			2: statusMsg := 'File not found!';
			3: statusMsg := 'Path not found!';
			101: statusMsg := 'Disk full!';
		else
			statusMsg := 'DOS Error!';
		end;

{$IFDEF E_SUPERZ}
		DrawStatusMessage(statusMsg);
		PauseOnError;
		ClearDisplayMessage;
{$ENDIF}
		DisplayIOError := true;
		Str(ioResValue, textWindow.Title);
		textWindow.Title := 'Error # ' + textWindow.Title;
		TextWindowInitState(textWindow);
		TextWindowAppend(textWindow, '$' + statusMsg);
		TextWindowAppend(textWindow, '');
		TextWindowAppend(textWindow, 'This may be caused by missing');
		TextWindowAppend(textWindow, 'ZZT files or a bad disk.  If');
		TextWindowAppend(textWindow, 'you are trying to save a game,');
		TextWindowAppend(textWindow, 'your disk may be full -- try');
		TextWindowAppend(textWindow, 'using a blank, formatted disk');
		TextWindowAppend(textWindow, 'for saving the game!');

		TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, 0);
		TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);
	end;

procedure SidebarAnimateLoading(var loadProgress: integer);
	begin
		VideoWriteText(
			VideoSidebarX + 9, 5,
			ProgressAnimColors[loadProgress], ProgressAnimStrings[loadProgress]);
		loadProgress := (loadProgress + 1) and 7;
	end;

procedure BottomAnimateLoading(var loadProgress: integer);
	begin
		VideoWriteText(
			22, VideoRows - 1,
			ProgressAnimColors[loadProgress], ProgressAnimStrings[loadProgress]);
		loadProgress := (loadProgress + 1) and 7;
	end;

procedure PopupPromptString(question: string; var buffer: TSmallString; maxLen: integer);
	var
		x, y, yMin: integer;
		screenCopy: array[0 .. 5] of TScreenCopyLine;
	begin
		yMin := VideoRows - 7;
		for y := 0 to 5 do
			VideoMove(3, y + yMin, TextWindowWidth, @screenCopy[y], false);
		VideoWriteText(3, yMin, $4F, TextWindowStrTop);
		VideoWriteText(3, yMin + 1, $4F, TextWindowStrText);
		VideoWriteText(3, yMin + 2, $4F, TextWindowStrSep);
		VideoWriteText(3, yMin + 3, $4F, TextWindowStrText);
		VideoWriteText(3, yMin + 4, $4F, TextWindowStrText);
		VideoWriteText(3, yMin + 5, $4F, TextWindowStrBottom);
		VideoWriteText(4 + (TextWindowWidth - Length(question)) div 2, yMin + 1, $4F, question);
		buffer := '';
		{ x = x, y = width }
		if maxLen > (TextWindowWidth - 8) then y := (TextWindowWidth - 8) else y := maxLen;
		x := 6 + (((TextWindowWidth - 8) - y) shr 1);
		PromptString(x, yMin + 4, $4F, $4E, y, maxLen, PROMPT_ANY, buffer);
		for y := 0 to 5 do
			VideoMove(3, y + yMin, TextWindowWidth, @screenCopy[y], true);
	end;

procedure GameDisplayResourceImage(name: TString50; x, y, width, height: integer);
	var
		fileData: pointer;
		fileDataLen: word;
		i, j, k: integer;
	begin
		fileDataLen := ResourceDataReadBinaryFile(name + '.BIN', fileData, 0, width * height * 2);
		if fileDataLen > 0 then begin
			{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
{$IFDEF SAFEVID}
			k := 0;
			for i := 1 to height do
				for j := 1 to width do begin
					VideoWriteText(x + j - 1, y + i - 1, TScreenBinArray(fileData^)[k + 1],
						Chr(TScreenBinArray(fileData^)[k]));
					Inc(k, 2);
				end;
{$ELSE}
			for i := 1 to height do
{$IFDEF FPC}
				VideoMove(x, y + i - 1, width, fileData + ((i - 1) * width * 2), true);
{$ELSE}
				VideoMove(x, y + i - 1, width, Ptr(Seg(fileData^), Ofs(fileData^) + ((i - 1) * width * 2)), true);
{$ENDIF}
{$ENDIF}
			{$IFDEF BASICSYS} VideoUnlockScreenUpdate(x, y, x + width - 1, y + height - 1); {$ENDIF}
			FreeMem(fileData, fileDataLen);
		end;
	end;

function OverwriteCheck(filename: string): boolean;
	begin
		OverwriteCheck := true;
		if FileExists(filename) then begin
			OverwriteCheck := SidebarPromptYesNo('Overwrite? ', false);
		end;
	end;

end.
