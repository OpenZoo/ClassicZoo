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
		VideoSidebarX = 60;
		PORT_CGA_MODE = $03D8;
		PORT_CGA_PALETTE = $03D9;
		VIDEO_MODE_40X25 = 0;
		VIDEO_MODE_80X25 = 1;
		VIDEO_MODE_80X43 = 2;
		VIDEO_MODE_80X50 = 3;
		VIDEO_CHARSET_UNCHANGED = -1;
	var
		VideoWriteText: TVideoWriteTextProc;
		VideoForceSafe: boolean;
		VideoForceNoSnow: boolean;
		VideoCurrentMode: integer;
		VideoMonochrome: boolean;
		VideoBlink: boolean;
		VideoColumns: integer;
		VideoRows: integer;
		VideoCharsetHeight: integer;
		VideoTextSegment: word;
		VideoEGAInstalled: boolean;
		VideoVGAInstalled: boolean;
		VideoMDAInstalled: boolean;
		VideoLastMode: word;
	function VideoGetBlinkMode: TVideoBlinkMode;
	function VideoInstall(mode: integer; charsetData: PTCharsetData; charsetHeight: integer;
		borderColor: integer): boolean;
	procedure VideoUninstall;
	procedure VideoShowCursor;
	procedure VideoHideCursor;
	procedure VideoSetBorderColor(value: integer);
	procedure VideoSetBlink(value: boolean);
	function VideoSetCharset(data: PTCharsetData; height: integer): boolean;
	function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	procedure VideoClear(bgColor: integer);
	procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	procedure VideoInvert(x1, y1, x2, y2: integer);
	procedure VideoScroll(x, y, width, height, dx, dy: integer);

implementation
uses Crt, Dos, TimerSys;
var
	InitialTextAttr: byte;
const
	EGA_PALETTE_LUT: array[0 .. 15] of byte = (
		0, 1, 2, 3, 4, 5, 20, 7,
		56, 57, 58, 59, 60, 61, 62, 63
	);

{$IFDEF DSX86}
{$DEFINE VNOCGA}
{$DEFINE VNOSAFE}
{$ENDIF}
{$IFDEF ZETAEMU}
{$DEFINE VNOCGA}
{$ENDIF}

function VideoGetBlinkMode: TVideoBlinkMode;
	begin
		if VideoBlink then
			VideoGetBlinkMode := BlinkModeOn
		else
			VideoGetBlinkMode := BlinkModeHigh;
	end;

{$F+}

{$IFNDEF FPC}
{$IFNDEF VNOCGA}
procedure VideoWriteTextCGA(x, y, color: byte; text: TVideoLine);
	begin
		inline(
			$8B/$06/VideoTextSegment/{ MOV AX, VideoTextSegment }
			$8E/$C0/             { MOV ES, AX }
			$8A/$86/y/           { MOV AL, byte ptr [BP + y] }
			$F6/$26/VideoColumns/{ MUL VideoColumns }
			$31/$C9/             { XOR CX, CX }
			$89/$CE/             { MOV SI, CX }
			$8A/$8E/x/           { MOV CL, byte ptr [BP + x] }
			$01/$C8/             { ADD AX, CX }
			$D1/$E0/             { SHL AX, 1 }
			$8B/$F8/             { MOV DI, AX }
			$8A/$BE/color/       { MOV BH, byte ptr [BP + color] }
			$8A/$8E/text/        { MOV CL, byte ptr [BP + text] }
			$BA/$03DA/           { MOV DX, 0x03DA }
			$22/$C9/             { AND CL, CL }
			$74/$1A/             { JZ finish }
			$FA/                 { CLI }
		{ next_char: }
			$46/                 { INC SI }
			$8A/$9A/text/        { MOV BL, byte ptr [BP + SI + text] }
		{ cga_snow: }
			$EC/                 { IN AL, DX }
			$A8/$08/             { TEST AL, 8 }
			$75/$09/             { JNZ write_char }
			$D0/$E8/             { SHR AL, 1 }
			$72/$F7/             { JC cga_snow }
		{ cga_snow2: }
			$EC/                 { IN AL, DX }
			$D0/$E8/             { SHR AL, 1 }
			$73/$FB/             { JNC cga_snow2 }
		{ write_char: }
			$89/$D8/             { MOV AX, BX }
			$AB/                 { STOSW }
			$E2/$E8/             { LOOP next_char }
			$FB                  { STI }
		{ finish: }
		);
	end;
{$ENDIF}

procedure VideoWriteTextFast(x, y, color: byte; text: TVideoLine);
	begin
{$IFDEF DSX86}
		{ HACK: DSx86 does not properly emulate blinking attributes. }
		if VideoBlink then
			color := color and $7F;
{$ENDIF}
		inline(
			$8B/$06/VideoTextSegment/{ MOV AX, VideoTextSegment }
			$8E/$C0/             { MOV ES, AX }
			$8A/$86/y/           { MOV AL, byte ptr [BP + y] }
			$F6/$26/VideoColumns/{ MUL VideoColumns }
			$31/$C9/             { XOR CX, CX }
			$89/$CE/             { MOV SI, CX }
			$8A/$8E/x/           { MOV CL, byte ptr [BP + x] }
			$01/$C8/             { ADD AX, CX }
			$D1/$E0/             { SHL AX, 1 }
			$8B/$F8/             { MOV DI, AX }
			$8A/$A6/color/       { MOV AH, byte ptr [BP + color] }
			$8A/$8E/text/        { MOV CL, byte ptr [BP + text] }
			$22/$C9/             { AND CL, CL }
			$74/$0A/             { JZ finish }
			$FA/                 { CLI }
		{ next_char: }
			$46/                 { INC SI }
			$8A/$82/text/        { MOV AL, byte ptr [BP + SI + text] }
			$AB/                 { STOSW }
			$E2/$F8/             { LOOP next_char }
			$FB                  { STI }
		{ finish: }
		);
	end;
{$ELSE}
{$IFNDEF VNOCGA}
procedure VideoWriteTextCGA(x, y, color: byte; text: TVideoLine);
	assembler;
	label next_char;
	label cga_snow;
	label cga_snow2;
	label write_char;
	label finish;
	asm
		push es
		mov ax, VideoTextSegment
		mov es, ax
		mov al, y
		mul VideoColumns
		xor cx, cx
		mov cl, x
		add ax, cx
		shl ax, 1
		mov di, ax
		mov bh, color
		mov dx, 03DAh
		push ds
		lds si, [text]
		mov cl, [si]
		and cl, cl
		jz finish
		cli
	next_char:
		inc si
		mov bl, [si]
	cga_snow:
		in al, dx
		test al, 8
		jnz write_char
		shr al, 1
		jc cga_snow
	cga_snow2:
		in al, dx
		shr al, 1
		jnc cga_snow2
	write_char:
		mov ax, bx
		stosw
		loop next_char
		sti
	finish:
		pop ds
		pop es
	end ['ax', 'bx', 'cx', 'dx', 'si', 'di'];
{$ENDIF}

procedure VideoWriteTextFast(x, y, color: byte; text: TVideoLine);
	assembler;
	label next_char;
	label finish;
	asm
		push es
		mov ax, VideoTextSegment
		mov es, ax
		mov al, y
		mul VideoColumns
		xor cx, cx
		mov cl, x
		add ax, cx
		shl ax, 1
		mov di, ax
		mov ah, color
		mov dx, 03DAh
		push ds
		lds si, [text]
		mov cl, [si]
		and cl, cl
		jz finish
		cli
	next_char:
		inc si
		mov al, [si]
		stosw
		loop next_char
		sti
	finish:
		pop ds
		pop es
	end ['ax', 'cx', 'dx', 'si', 'di'];
{$ENDIF}

{$F-}

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

{$IFNDEF VNOCGA}
procedure VideoWriteTextCGABW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextCGA(x, y, ColorToBW(color), text);
	end;
{$ENDIF}

procedure VideoWriteTextFastBW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextFast(x, y, ColorToBW(color), text);
	end;

{$IFNDEF VNOSAFE}
procedure VideoWriteTextSafe(x, y, color: byte; text: TVideoLine);
	var
		i: byte;
		regs: Registers;
	begin
		for i := 1 to Length(text) do begin
			{ move cursor }
			regs.AH := $02;
			regs.BX := $0000;
			regs.DH := y;
			regs.DL := x;
			Intr($10, regs);

			{ write character }
			regs.AL := Ord(text[i]);
			regs.AH := $09;
			regs.BL := color;
			regs.CX := 1;
			Intr($10, regs);

			Inc(x);
			if x >= VideoColumns then begin
				x := 1;
				Inc(y);
			end;
		end;
	end;

procedure VideoWriteTextSafeBW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextSafe(x, y, ColorToBW(color), text);
	end;
{$ENDIF}

{$F-}

procedure VideoPreInstall;
	var
		regs: Registers;
	begin
		VideoMDAInstalled := LastMode = 7;
		VideoVGAInstalled := false;

		regs.AH := $12;
		regs.BX := $FF10;
		Intr($10, regs);
		VideoEGAInstalled := regs.BH <> $FF;

		if VideoEGAInstalled then begin
			regs.AX := $1A00;
			Intr($10, regs);
			VideoVGAInstalled := regs.AL = $1A;
		end;

		SetCBreak(false);
		InitialTextAttr := TextAttr;
	end;

function VideoInstall(mode: integer; charsetData: PTCharsetData; charsetHeight: integer;
	borderColor: integer): boolean;
	var
		regs: Registers;
	label FinishVideoInstall;
	begin
		VideoInstall := false;
		if (mode = VideoCurrentMode) and (charsetHeight = VIDEO_CHARSET_UNCHANGED) then
			goto FinishVideoInstall;
		if (mode >= VIDEO_MODE_80X43) and (not VideoEGAInstalled) then exit;
		if (mode >= VIDEO_MODE_80X50) and (not VideoVGAInstalled) then exit;

		VideoColumns := 80;
		VideoRows := 25;
		if mode = VIDEO_MODE_40X25 then
			VideoColumns := 40
		else if mode = VIDEO_MODE_80X43 then
			VideoRows := 43
		else if mode = VIDEO_MODE_80X50 then
			VideoRows := 50;

		VideoCurrentMode := -1;

		if charsetHeight > 0 then begin
			VideoCharsetHeight := charsetHeight;
			if (VideoCharsetHeight > 8) and (VideoRows <> 25) then exit;
		end else begin
			if VideoVGAInstalled then begin
				if VideoRows = 25 then
					VideoCharsetHeight := 14
				else
					VideoCharsetHeight := 8;
			end else if VideoEGAInstalled or VideoMDAInstalled then begin
				VideoCharsetHeight := 14;
			end else begin
				VideoCharsetHeight := 8;
			end;
		end;

		if VideoVGAInstalled then begin
			if (mode = VIDEO_MODE_80X50) or (VideoCharsetHeight = 16) then begin
				regs.AX := $1202;
			end else if (mode = VIDEO_MODE_80X43) or (VideoCharsetHeight = 14) then begin
				regs.AX := $1201;
			end else begin
				regs.AX := $1200;
			end;
			regs.BL := $30;
			Intr($10, regs);

			if (regs.AL <> $12) and (VideoRows <> 25) then exit;
		end;

		if VideoMonochrome then begin
			if (VideoLastMode and $FFFC) = 0 {>= 0, <= 3} then begin
				if VideoColumns = 80 then begin
					TextMode(BW80);
				end else begin
					TextMode(BW40);
				end;
			end else begin
				TextMode(7);
				VideoColumns := 80;
			end;
		end else begin
			if VideoColumns = 80 then begin
				TextMode(CO80);
			end else begin
				TextMode(CO40);
			end;

			TextBackground(borderColor);
		end;

		if VideoEGAInstalled then begin
{$IFNDEF DSX86}
			if charsetHeight <= 0 then begin
				{ set default charset }
				if VideoRows >= 43 then
					regs.AX := $1112
				else
					regs.AX := $1111;
				regs.BL := $00;
				Intr($10, regs);
			end;
{$ENDIF}

			{ set palette }
			{ regs.AX := $1002;
			regs.BX := $0000;
			regs.ES := Seg(VideoEGAPalette);
			regs.DX := Ofs(VideoEGAPalette);
			VideoEGAPalette[16] := VideoEGAPalette[borderColor];
			Intr($10, regs); }
		end;

FinishVideoInstall:
		if VideoMonochrome then begin
{$IFDEF VNOCGA}
			VideoWriteText := VideoWriteTextFastBW;
{$ELSE}
			if VideoEGAInstalled or VideoMDAInstalled or VideoForceNoSnow then
				VideoWriteText := VideoWriteTextFastBW
			else
				VideoWriteText := VideoWriteTextCGABW;
{$ENDIF}
{$IFNDEF VNOSAFE}
			if VideoForceSafe then
				VideoWriteText := VideoWriteTextSafeBW;
{$ENDIF}
		end else begin
{$IFDEF VNOCGA}
			VideoWriteText := VideoWriteTextFast;
{$ELSE}
			if VideoEGAInstalled or VideoForceNoSnow then
				VideoWriteText := VideoWriteTextFast
			else
				VideoWriteText := VideoWriteTextCGA;
{$ENDIF}
{$IFNDEF VNOSAFE}
			if VideoForceSafe then
				VideoWriteText := VideoWriteTextSafe;
{$ENDIF}
		end;

		VideoClear(borderColor);

		VideoHideCursor;
		VideoSetBorderColor(borderColor);

		if charsetHeight > 0 then begin
			if not VideoSetCharset(charsetData, charsetHeight) then exit;
		end;

{$IFNDEF DSX86}
		if VideoVGAInstalled then begin
			{ Set 8-dot-clock character mode.  }
			Port[$3C4] := $01;
			Port[$3C5] := (Port[$3C5]) or $01;
			Port[$3C4] := $01;

			if (VideoRows = 25) and (VideoCharsetHeight = 8) then begin
				Port[$3D4] := $09;
				Port[$3D5] := (Port[$3D5]) or $80;
				Port[$3D4] := $09;
			end;
		end;
{$ENDIF}

		VideoCurrentMode := mode;
		VideoInstall := true;
	end;

procedure VideoUninstall;
	var
		regs: Registers;
	begin
		if VideoEGAInstalled then begin
			regs.AX := $1201;
			regs.BL := $30;
			Intr($10, regs);
{$IFNDEF DSX86}
			regs.AX := $1111;
			regs.BL := $00;
			Intr($10, regs);
{$ENDIF}
		end;

		TextBackground(0);
		VideoColumns := 80;
		VideoRows := 25;
		VideoCurrentMode := -1;
		TextMode(VideoLastMode);
		VideoSetBorderColor(0);

		TextAttr := InitialTextAttr;
		ClrScr;
		VideoShowCursor;
	end;

procedure VideoSetCursorShape(value: integer);
	var
		regs: Registers;
	begin
		regs.AH := $01;
		regs.CX := value;
		Intr($10, regs);
	end;

procedure VideoShowCursor;
	begin
		VideoSetCursorShape($0607);
	end;

procedure VideoHideCursor;
	begin
		VideoSetCursorShape($2000);
	end;

procedure VideoSetBorderColor(value: integer);
	begin
{$IFNDEF DSX86}
		if not VideoForceSafe then begin
			Port[PORT_CGA_PALETTE] := value;
		end;
{$ENDIF}
	end;

procedure VideoSetBlink(value: boolean);
	var
		regs: Registers;
	begin
		VideoBlink := value;
{$IFNDEF DSX86}
		{ CGA route }
		if not VideoForceSafe then begin
			if value then
				Port[PORT_CGA_MODE] := Port[PORT_CGA_MODE] or $20
			else
				Port[PORT_CGA_MODE] := Port[PORT_CGA_MODE] and $DF;
		end;
		{ EGA/VGA route }
		regs.AX := $1003;
		regs.BH := 0;
		regs.BL := Byte(value);
		Intr($10, regs);
{$ENDIF}
	end;

function VideoSetCharset(data: PTCharsetData; height: integer): boolean;
	var
		regs: Registers;
	begin
{$IFDEF DSX86}
		{ DSx86 only has a default character set. }
		VideoSetCharset := (data = nil);
{$ELSE}
		VideoSetCharset := false;
		if not VideoEGAInstalled then exit;
		if (height <> 8) and (height <> 14) then exit;
		if not VideoVGAInstalled then begin
			if (height <> 8) and (VideoRows = 43) then exit;
			if (height <> 14) and (VideoRows = 25) then exit;
		end;

		regs.BX := (height shl 8);
		regs.CX := 256;
		regs.DX := 0;

		regs.AX := $1110;
		regs.ES := Seg(data^);
		regs.BP := Ofs(data^);

		Intr($10, regs);

		VideoHideCursor;
		VideoSetCharset := true;
{$ENDIF}
	end;

function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	var
		colorArray: array[0 .. 2] of byte;
		regs: Registers;
	begin
		VideoSetPaletteColor := false;
		if not VideoEGAInstalled then exit;

		colorArray[0] := r;
		colorArray[1] := g;
		colorArray[2] := b;

		regs.ax := $1012;
		regs.bx := EGA_PALETTE_LUT[idx];
		regs.cx := 1;
		regs.es := Seg(colorArray);
		regs.dx := Ofs(colorArray);
		Intr($10, regs);

		VideoSetPaletteColor := true;
	end;

procedure VideoClear(bgColor: integer);
	begin
		if VideoMonochrome then bgColor := 0;
		FillChar(Ptr(VideoTextSegment, $0000)^, VideoColumns * VideoRows * 2, bgColor * $11);
	end;

procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	var
		regs: Registers;
		i, offset: integer;
	begin
{$IFNDEF VNOSAFE}
		if VideoForceSafe then begin
			offset := 0;
			for i := 1 to chars do begin
				regs.AH := $02;
				regs.BX := $0000;
				regs.DH := y;
				regs.DL := x;
				Intr($10, regs);

				if toVideo then begin
					regs.AH := $09;
					regs.CX := 1;
					regs.AL := Ord(TVideoLine(data^)[offset]);
					Inc(offset);
					regs.BL := Ord(TVideoLine(data^)[offset]);
					Intr($10, regs);
				end else begin
					regs.AH := $08;
					Intr($10, regs);
					TScreenCopyLine16(data^)[offset] := regs.AX;
				end;

				Inc(offset);
				Inc(x);
				if x >= VideoColumns then begin
					x := 1;
					Inc(y);
				end;
			end;

			exit;
		end;
{$ENDIF}
		offset := (y * VideoColumns + x) * 2;
		if toVideo then
			Move(data^, Ptr(VideoTextSegment, offset)^, chars * 2)
		else
			Move(Ptr(VideoTextSegment, offset)^, data^, chars * 2);
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
			offset := (((iy * VideoColumns) + x1) shl 1) + 1;
			for ix := x1 to x2 do begin
				Mem[VideoTextSegment:offset] := Mem[VideoTextSegment:offset] xor $7F;
				Inc(offset, 2);
			end;
		end;
	end;

procedure VideoScroll(x, y, width, height, dx, dy: integer);
	var
		iy: integer;
		srcOfs, destOfs: integer;
	begin
		if dy = 0 then begin
			if dx >= 0 then begin
				{ move right }
				srcOfs := (y * VideoColumns + x) * 2;
				destOfs := srcOfs + (dx * 2);
				for iy := 1 to height do begin
 					{ if (iy mod 2) = 1 then
						VideoWriteTextCO80(0, 0, 0, ''); }
					Move(Ptr(VideoTextSegment, srcOfs)^, Ptr(VideoTextSegment, destOfs)^, (width - dx) * 2);
					srcOfs := srcOfs + (VideoColumns * 2);
					destOfs := destOfs + (VideoColumns * 2);
				end;
			end else begin
				{ move left }
				destOfs := (y * VideoColumns + x) * 2;
				srcOfs := destOfs - (dx * 2);
				for iy := 1 to height do begin
 					{ if (iy mod 2) = 1 then
						VideoWriteTextCO80(0, 0, 0, ''); }
					Move(Ptr(VideoTextSegment, srcOfs)^, Ptr(VideoTextSegment, destOfs)^, (width + dx) * 2);
					srcOfs := srcOfs + (VideoColumns * 2);
					destOfs := destOfs + (VideoColumns * 2);
				end;
			end;
		end else begin
			if dy > 0 then begin
				{ move down }
				srcOfs := ((y + height - 2) * VideoColumns + x) * 2;
				destOfs := VideoColumns * 2 + srcOfs;
				for iy := 1 to (height - 1) do begin
 					{ if (iy mod 2) = 1 then
						VideoWriteTextCO80(0, 0, 0, ''); }
					Move(Ptr(VideoTextSegment, srcOfs)^, Ptr(VideoTextSegment, destOfs)^, width * 2);
					srcOfs := srcOfs - (VideoColumns * 2);
					destOfs := destOfs - (VideoColumns * 2);
				end;
			end else begin
				{ move up }
				destOfs := (y * VideoColumns + x) * 2;
				srcOfs := VideoColumns * 2 + destOfs;
				for iy := 1 to (height - 1) do begin
 					{ if (iy mod 2) = 1 then
						VideoWriteTextCO80(0, 0, 0, ''); }
					Move(Ptr(VideoTextSegment, srcOfs)^, Ptr(VideoTextSegment, destOfs)^, width * 2);
					srcOfs := srcOfs + (VideoColumns * 2);
					destOfs := destOfs + (VideoColumns * 2);
				end;
			end;
		end;
	end;

begin
	VideoColumns := 80;
	VideoRows := 25;
{$IFDEF VNOCGA}
	VideoWriteText := VideoWriteTextFast;
{$ELSE}
	VideoWriteText := VideoWriteTextCGA;
{$ENDIF}
	VideoLastMode := LastMode;
	if VideoLastMode = 7 then begin
		VideoTextSegment := $B000;
		VideoMonochrome := true;
	end else begin
		VideoTextSegment := $B800;
		VideoMonochrome := false;
	end;
	VideoForceNoSnow := false;
	VideoForceSafe := false;
{$IFDEF DSX86}
	VideoBlink := false;
{$ELSE}
	VideoBlink := true;
{$ENDIF}
	VideoCurrentMode := -1;

	VideoPreInstall;
end.
