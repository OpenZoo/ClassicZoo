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
{$MODE OBJFPC}
unit ZVideo;

interface
	type
		TVideoBlinkMode = (BlinkModeHigh, BlinkModeOn, BlinkModeOff);
		TVideoLine = string[80];
		{ Was 160 in ZZT 3.2. }
		TScreenCopyLine = string[100];
		TScreenCopyLine16 = array[0 .. 49] of word;
		TVideoWriteTextProc = procedure(x, y, color: byte; text: TVideoLine);
		TCharsetData = array[0 .. 31999] of byte;
		PTCharsetData = ^TCharsetData;
	const
		VIDEO_MODE_40X25 = 0;
		VIDEO_MODE_80X25 = 1;
		VIDEO_MODE_80X43 = 2;
		VIDEO_MODE_80X50 = 3;
		VIDEO_CHARSET_UNCHANGED = -1;
	var
		VideoWriteText: TVideoWriteTextProc;
		VideoSafetyLevel: byte;
		VideoMonochrome: boolean;
		VideoTextSegment: word;
		VideoEGAInstalled: boolean;
		VideoVGAInstalled: boolean;
		VideoMDAInstalled: boolean;
		VideoLastMode: word;
		VideoSidebarX: integer;
		VideoColumns: integer;
		VideoRows: integer;
		VideoCurrentMode: integer;
	function VideoGetBlinkMode: TVideoBlinkMode;
	procedure VideoLockScreenUpdate;
	procedure VideoUnlockScreenUpdate(x1, y1, x2, y2: integer);
	function VideoSetCharset(data: PTCharsetData; height: integer): boolean;
	function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	function VideoInstall(mode: integer; charsetData: PTCharsetData; charsetHeight: integer;
		borderColor: integer): boolean;
	procedure VideoUninstall;
	procedure VideoShowCursor;
	procedure VideoHideCursor;
	procedure VideoSetBorderColor(value: integer);
	procedure VideoSetBlink(value: boolean);
	procedure VideoClear(bgColor: integer);
	procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	procedure VideoInvert(x1, y1, x2, y2: integer);
	procedure VideoScroll(x, y, width, height, dx, dy: integer);

implementation
uses Dos, Video, Keyboard, Mouse, SysUtils, TimerSys;

var
	VSULocked: boolean;

function VideoGetBlinkMode: TVideoBlinkMode;
	begin
		VideoGetBlinkMode := BlinkModeOff; { TODO }
	end;

procedure VideoLockScreenUpdate;
	begin
		if not VSULocked then begin
			VSULocked := true;
			LockScreenUpdate;
		end;
	end;

procedure VideoUnlockScreenUpdate(x1, y1, x2, y2: integer);
	begin
		if VSULocked then begin
			UnlockScreenUpdate;
			UpdateScreenArea(x1, y1, x2, y2, false);
			VSULocked := false;
		end;
	end;

function ColorToBW(color: byte): byte;
	begin
		{ FIX: Special handling of blinking solids }
		if (color and $80) = $80 then
			if ((color shr 4) and $07) = (color and $0F) then
				color := (color and $7F);

		if (color and $09) = $09 then
			color := (color and $F0) or $0F
		else if (color and $07) <> 0 then
			color := (color and $F0) or $07;

		if (color and $0F) = $00 then begin
			if (color and $70) = $00 then
				color := (color and $8F)
			else
				color := (color and $8F) or $70;
		end else if (color and $70) <> $70 then
			color := color and $8F;

		ColorToBW := color;
	end;

{$F+}

procedure VideoWriteTextBuf(x, y, color: byte; text: TVideoLine);
	var
		i: integer;
		attr, offset: word;
	begin
		attr := color shl 8;
		offset := (y * ScreenWidth + x);
		for i := 1 to Length(text) do begin
			VideoBuf^[offset] := attr or Ord(text[i]);
			Inc(offset);
		end;
		UpdateScreenArea(x, y, x + Length(text) - 1, y, false);
	end;

procedure VideoWriteTextBufBW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextBuf(x, y, ColorToBW(color), text);
	end;

{$F-}

function VideoSetCharset(data: PTCharsetData; height: integer): boolean;
	begin
		VideoSetCharset := false;
	end;

function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	begin
		VIdeoSetPaletteColor := false;
	end;

procedure VideoPreInstall;
	begin
	end;

function VideoInstall(mode: integer; charsetData: PTCharsetData; charsetHeight: integer;
	borderColor: integer): boolean;
	begin
		VideoInstall := false;

		VideoSidebarX := 60;
		VideoColumns := 80;
		VideoRows := 25;
		if mode = VIDEO_MODE_40X25 then
			VideoColumns := 40
		else if mode = VIDEO_MODE_80X43 then
			VideoRows := 43
		else if mode = VIDEO_MODE_80X50 then
			VideoRows := 50;

		if (VideoColumns <> ScreenWidth) or (VideoRows <> ScreenHeight) then
			exit;

		VideoClear(borderColor);
		VideoCurrentMode := mode;

		VideoHideCursor;
		VideoInstall := true;
	end;

procedure VideoUninstall;
	begin
		VideoClear(0);
		VideoShowCursor;
	end;

procedure VideoShowCursor;
	begin
		SetCursorType(crUnderLine);
	end;

procedure VideoHideCursor;
	begin
		SetCursorType(crHidden);
	end;

procedure VideoSetBorderColor(value: integer);
	begin
	end;

procedure VideoSetBlink(value: boolean);
	begin
		{ TODO }
	end;

procedure VideoClear(bgColor: integer);
	begin
		FillWord(VideoBuf^, ScreenWidth * ScreenHeight, Word((bgColor * $11) shl 8));
		UpdateScreen(false);
	end;

procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	var
		offset: integer;
	begin
		offset := (y * ScreenWidth + x);
		if toVideo then begin
			Move(data^, VideoBuf^[offset], chars * 2);
			UpdateScreenArea(x, y, x + chars - 1, y, false);
		end else begin
			Move(VideoBuf^[offset], data^, chars * 2);
		end;
	end;

procedure VideoInvert(x1, y1, x2, y2: integer);
	var
		ix, iy, offset: integer;
	begin
		if x2 < x1 then begin
			ix := x1;
			x1 := x2;
			x2 := ix;
		end;
		if y2 < y1 then begin
			ix := y1;
			y1 := y2;
			y2 := ix;
		end;
		for iy := y1 to y2 do begin
			offset := ((iy * ScreenWidth) + x1);
			for ix := x1 to x2 do begin
				VideoBuf^[offset] := VideoBuf^[offset] xor $7F00;
				Inc(offset, 1);
			end;
		end;
		UpdateScreenArea(x1, y1, x2, y2, false);
	end;

procedure VideoScroll(x, y, width, height, dx, dy: integer);
	var
		iy: integer;
		srcOfs, destOfs: integer;
	begin
		if dy = 0 then begin
			if dx >= 0 then begin
				{ move right }
				srcOfs := (y * ScreenWidth + x);
				destOfs := srcOfs + (dx);
				for iy := 1 to height do begin
					Move(VideoBuf^[srcOfs], VideoBuf^[destOfs], (width - dx) * 2);
					srcOfs := srcOfs + (ScreenWidth);
					destOfs := destOfs + (ScreenWidth);
				end;
			end else begin
				{ move left }
				destOfs := (y * ScreenWidth + x);
				srcOfs := destOfs - (dx);
				for iy := 1 to height do begin
					Move(VideoBuf^[srcOfs], VideoBuf^[destOfs], (width + dx) * 2);
					srcOfs := srcOfs + (ScreenWidth);
					destOfs := destOfs + (ScreenWidth);
				end;
			end;
		end else begin
			if dy > 0 then begin
				{ move down }
				srcOfs := ((y + height - 2) * ScreenWidth + x);
				destOfs := ScreenWidth + srcOfs;
				for iy := 1 to (height - 1) do begin
					Move(VideoBuf^[srcOfs], VideoBuf^[destOfs], width * 2);
					srcOfs := srcOfs - (ScreenWidth);
					destOfs := destOfs - (ScreenWidth);
				end;
			end else begin
				{ move up }
				destOfs := (y * ScreenWidth + x);
				srcOfs := ScreenWidth + destOfs;
				for iy := 1 to (height - 1) do begin
					Move(VideoBuf^[srcOfs], VideoBuf^[destOfs], width * 2);
					srcOfs := srcOfs + (ScreenWidth);
					destOfs := destOfs + (ScreenWidth);
				end;
			end;
		end;
		{ TODO: Use UpdateScreenArea }
		UpdateScreen(false);
	end;

initialization
	InitVideo;
{$IFDEF HASAMIGA}
	SetWindowTitle(ExtractFileName(ParamStr(0)), '%NAME% %VERSION%');
{$ENDIF}
	InitMouse;
	InitKeyboard;
	VideoColumns := ScreenWidth;
	VideoRows := ScreenHeight;
	VideoWriteText := @VideoWriteTextBuf;
	VideoMDAInstalled := false;
	VideoVGAInstalled := false;
	VSULocked := false;
finalization
	DoneKeyboard;
	DoneMouse;
	DoneVideo;
end.
