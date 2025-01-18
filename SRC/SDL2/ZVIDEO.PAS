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
		TSDLScalingMode = (SMNone, SM2x, SM3x, SMInteger, SMOrigAspect, SM43Aspect, SMIgnoreAspect);
		TVideoLine = string[160];
		TScreenCopyLine = string[255];
		TCharsetData = array[0 .. 31999] of byte;
		PTCharsetData = ^TCharsetData;
	const
		VIDEO_MODE_40X25 = 0;
		VIDEO_MODE_80X25 = 1;
		VIDEO_MODE_80X43 = 2;
		VIDEO_MODE_80X50 = 3;
		VIDEO_MODE_RESIZABLE = 256;
		VIDEO_MODE_80X25_STRETCH = 257;
		VIDEO_CHARSET_UNCHANGED = -1;
	var
		VideoMonochrome: boolean;
		VideoColumns: integer;
		VideoRows: integer;
		VideoSidebarX: integer;
		VideoBorderColor: integer;
		VideoTextSegment: word;
		VideoTextPointer: pointer;
		VideoCursorVisible: boolean;
		VideoEGAInstalled: boolean;
		VideoMDAInstalled: boolean;
		VideoForceSoftware: boolean;
		VideoCurrentMode: integer;
		VideoScaleChanged: boolean;
	procedure VideoForcePlayfieldRedraw;
	procedure VideoOnSizeChanged;
	function VideoGetBlinkMode: TVideoBlinkMode;
	procedure VideoSetSDLBlinkMode(value: TVideoBlinkMode);
	function VideoGetSDLScalingMode: TSDLScalingMode;
	procedure VideoSetSDLScalingMode(value: TSDLScalingMode);
	function VideoGetSDLWindowed: boolean;
	procedure VideoSetSDLWindowed(value: boolean);
	{ }
	procedure VideoWriteText(x, y, color: byte; text: TVideoLine);
{$IFDEF WIDECHAR}
	procedure VideoWriteTextWide(x, y, color: byte; text: TVideoLine);
{$ENDIF}
	function VideoIsCharsetCustom: boolean;
	function VideoIsPaletteCustom: boolean;
	function VideoSetCharset(data: pointer; height: integer): boolean;
	function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	procedure VideoLoadCharsetDialog;
	procedure VideoLoadCharsetFromFile(filename: string);
	procedure VideoLoadPaletteDialog;
	procedure VideoLoadPaletteFromFile(filename: string);
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
	procedure VideoSetTextInputArea(x, y, width, height: integer);

implementation
uses
{$IFDEF WIDECHAR}ZWideChr,{$ENDIF}
F_ASCII, FileSel, FileSys, SysUtils, Sounds, TimerSys, ZInput, SDL2;
type
	TByteArray = array[0 .. 65535] of byte;
	PByteArray = ^TByteArray;
	TCharsetTexture = record
		valid: boolean;
		charCount: Uint32;
		charWidth: Uint32;
		charHeight: Uint32;
		charsetPitch: Uint32;
		surface: PSDL_Surface;
		texture: PSDL_Texture;
	end;
const
	EGA_PALETTE: array[0 .. 15] of Uint32 = (
		$000000,
		$0000AA,
		$00AA00,
		$00AAAA,
		$AA0000,
		$AA00AA,
		$AA5500,
		$AAAAAA,
		$555555,
		$5555FF,
		$55FF55,
		$55FFFF,
		$FF5555,
		$FF55FF,
		$FFFF55,
		$FFFFFF
	);
	TEXT_BLINK_RATE = 534;
	MAX_VIDEO_WIDTH = 96 + 24;
	MAX_VIDEO_HEIGHT = 80 + 5;
	MAX_VIDEO_BUFFER_SIZE_CHARS = (MAX_VIDEO_WIDTH * MAX_VIDEO_HEIGHT);
{$IFDEF SHIFTJIS}
{$I NEC98/VIDCONST.INC}
{$ENDIF}
var
	window: PSDL_Window;
	renderer: PSDL_Renderer;
	palette: array[0 .. 15] of Uint32;
	mainThreadSdlChangesMutex: PSDL_Mutex;
	playfieldMutex: PSDL_Mutex;
	playfieldTexture: PSDL_Texture;
	charsetTexture: TCharsetTexture;
	renderThread: PSDL_Thread;
	renderThreadRunning: boolean;
	screenChars: array[0 .. (MAX_VIDEO_BUFFER_SIZE_CHARS - 1)] of Uint32;
	screenColors: array[0 .. (MAX_VIDEO_BUFFER_SIZE_CHARS - 1)] of byte;
	screenChanged: array[0 .. (MAX_VIDEO_BUFFER_SIZE_CHARS - 1)] of boolean;
	blinkMode: TVideoBlinkMode;
	scalingMode: TSDLScalingMode;
	windowed: boolean;
	installed: boolean;
	usingCustomCharset: boolean;
	usingCustomPalette: boolean;
	windowedLastWidth, windowedLastHeight: Int32;

{ macOS expects the SDL2 framework symbols. }
{$IFDEF darwin}
{$LINKFRAMEWORK SDL2}
{$ENDIF}

function VideoGetActiveScalingMode: TSDLScalingMode;
	begin
		if VideoCurrentMode = VIDEO_MODE_RESIZABLE then
			VideoGetActiveScalingMode := SMNone
		else
			VideoGetActiveScalingMode := scalingMode;
	end;

procedure VideoForcePlayfieldRedraw;
	begin
		SDL_LockMutex(playfieldMutex);
		FillChar(screenChanged, MAX_VIDEO_BUFFER_SIZE_CHARS, true);
		SDL_UnlockMutex(playfieldMutex);
	end;

procedure AfterSetWindowSize;
	begin
		InputUpdate;
		if charsetTexture.valid then begin
			if charsetTexture.texture <> nil then begin
				SDL_DestroyTexture(charsetTexture.texture);
				charsetTexture.texture := nil;
			end;
		end;
	end;		

{ Window handling }

procedure CalcRenderArea(rect: PSDL_Rect; w, h: Int32);
	var
		origw, origh, iw, ih, scale: Int32;
	begin
		iw := VideoColumns * charsetTexture.charWidth;
		ih := VideoRows * charsetTexture.charHeight;
		if (VideoCurrentMode = VIDEO_MODE_80X25_STRETCH) and (charsetTexture.charHeight <= 8) then
			ih := ih * 2;
		origw := w;
		origh := h;

		scale := 1;
		while (((scale+1)*iw <= w) and ((scale+1)*ih <= h)) do Inc(scale);

		if rect <> Nil then begin
			case VideoGetActiveScalingMode of
				SMNone: begin
					w := iw;
					h := ih;
				end;
				SM2x: begin
					w := iw * 2;
					h := ih * 2;
				end;
				SM3x: begin
					w := iw * 3;
					h := ih * 3;
				end;
				SMInteger: begin
					w := iw * scale;
					h := ih * scale;
				end;
				SMOrigAspect: begin
					if (w < iw) then w := iw;
					if (h < ih) then h := ih;

					if ((w * ih div iw) > h) then
						w := h * iw div ih
					else
						h := w * ih div iw;
				end;
				SM43Aspect: begin
					if (w < iw) then w := iw;
					if (h < (iw * 3 div 4)) then h := (iw * 3 div 4);

					if (w > 640) and ((w * 3 div 4) > h) then
						w := h * 4 div 3
					else
						h := w * 3 div 4;
				end;
				SMIgnoreAspect: begin
					{ Leave w/h as-is. }
				end;
			end;

			rect^.w := w;
			rect^.h := h;
			rect^.x := (origw - w) div 2;
			rect^.y := (origh - h) div 2;
		end;
	end;

{ TODO: Re-implement delta? }
procedure SDLResizeWindow(delta: Int32; onlyIfTooSmall: boolean; forceMinimumSize: boolean);
	var
		iw, ih, ww, wh, w, h, scale: Int32;
		destRect: TSDL_Rect;
	begin
		if window = Nil then exit;

		iw := VideoColumns * charsetTexture.charWidth;
		ih := VideoRows * charsetTexture.charHeight;
		if (VideoCurrentMode = VIDEO_MODE_80X25_STRETCH) and (charsetTexture.charHeight <= 8) then
			ih := ih * 2;
		case VideoGetActiveScalingMode of
			SMNone, SM2x, SM3x: begin
				onlyIfTooSmall := false;
			end;
		end;
		case VideoGetActiveScalingMode of
			SM43Aspect: ih := iw * 3 div 4;
			SM2x: begin
				iw := iw * 2;
				ih := ih * 2;
			end;
			SM3x: begin
				iw := iw * 3;
				ih := ih * 3;
			end;
		end;

		SDL_LockMutex(eventMutex);

		if VideoCurrentMode = VIDEO_MODE_RESIZABLE then
			SDL_SetWindowMinimumSize(window, 80 * charsetTexture.charWidth, 50 * charsetTexture.charHeight)
		else
			SDL_SetWindowMinimumSize(window, iw, ih);
		SDL_GetWindowSize(window, @ww, @wh);

		if forceMinimumSize then begin
			w := iw;
			h := ih;
		end else begin
			w := ww;
			h := wh;
		end;

		CalcRenderArea(@destRect, w, h);

		iw := destRect.w;
		ih := destRect.h;

		if windowed then begin
			if (not onlyIfTooSmall) or ((iw > w) or (ih > h)) then begin
				if (iw <> ww) or (ih <> wh) then begin
					SDL_SetWindowSize(window, iw, ih);
				end;
			end;
		end;

		SDL_UnlockMutex(eventMutex);

		AfterSetWindowSize;
		VideoForcePlayfieldRedraw;
	end;

procedure VideoOnSizeChanged;
	var
		iw, ih, nw, nh: integer;
	begin
		if VideoCurrentMode = VIDEO_MODE_RESIZABLE then begin
			SDL_GetWindowSize(window, @iw, @ih);
			nw := iw div charsetTexture.charWidth;
			if nw > MAX_VIDEO_WIDTH then nw := MAX_VIDEO_WIDTH;
			nh := ih div charsetTexture.charHeight;
			if nh > MAX_VIDEO_HEIGHT then nh := MAX_VIDEO_HEIGHT;
			if (nw <> VideoColumns) or (nh <> VideoRows) then begin
				VideoColumns := nw;
				VideoRows := nh;
				VideoSidebarX := VideoColumns - 20;
				VideoScaleChanged := true;
			end;
		end;
		VideoForcePlayfieldRedraw;
	end;

function VideoGetBlinkMode: TVideoBlinkMode;
	begin
		VideoGetBlinkMode := blinkMode;
	end;

procedure VideoSetSDLBlinkMode(value: TVideoBlinkMode);
	begin
		SDL_LockMutex(mainThreadSdlChangesMutex);
		blinkMode := value;
		VideoForcePlayfieldRedraw;
		SDL_UnlockMutex(mainThreadSdlChangesMutex);
	end;

function VideoGetSDLScalingMode: TSDLScalingMode;
	begin
		VideoGetSDLScalingMode := scalingMode;
	end;

procedure VideoSetSDLScalingMode(value: TSDLScalingMode);
	begin
		SDL_LockMutex(mainThreadSdlChangesMutex);
		scalingMode := value;
		SDLResizeWindow(-10000, false, true);
		SDLResizeWindow(0, true, false);
		SDL_UnlockMutex(mainThreadSdlChangesMutex);
	end;

function VideoGetSDLWindowed: boolean;
	begin
		VideoGetSDLWindowed := windowed;
	end;

procedure VideoSetSDLWindowed(value: boolean);
	var
		mode: TSDL_DisplayMode;
	begin
		SDL_LockMutex(mainThreadSdlChangesMutex);
		if windowed <> value then begin
			if windowed then begin
				SDL_GetWindowSize(window, @windowedLastWidth, @windowedLastHeight);
				SDL_GetDesktopDisplayMode(SDL_GetWindowDisplayIndex(window), @mode);
				SDL_SetWindowSize(window, mode.w, mode.h);
				AfterSetWindowSize;
				SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN);
				AfterSetWindowSize;
				windowed := false;
			end else begin
				SDL_SetWindowFullscreen(window, 0);
				AfterSetWindowSize;
				SDL_SetWindowSize(window, windowedLastWidth, windowedLastHeight);
				AfterSetWindowSize;
				SDLResizeWindow(0, true, false);
				AfterSetWindowSize;
				windowed := true;
			end;
		end;
		SDL_UnlockMutex(mainThreadSdlChangesMutex);
	end;

{ Charset management }

procedure FreeCharsetTexture(var tex: TCharsetTexture);
	begin
		if tex.valid then begin
			if tex.texture <> nil then begin
				SDL_DestroyTexture(tex.texture);
				tex.texture := nil;
			end;
			SDL_FreeSurface(tex.surface);
			tex.valid := false;
		end;
	end;

procedure LoadCharsetFromBMP(var tex: TCharsetTexture; path: string; totalTiles: Uint32);
	var
		surfaceOld, surface: PSDL_Surface;
		texWidth, texHeight: Int32;
		ix, iy, ip: Uint32;
		aspectRatio: Single;
	begin
		tex.valid := false;

		path := ExpandFileName(path);
		surface := SDL_LoadBMP(@path[1]);
		if surface = nil then exit;

		{ Ensure 32-bit color format for color key }
		if surface^.format^.format <> SDL_PIXELFORMAT_ARGB8888 then begin
			surfaceOld := surface;
			surface := SDL_ConvertSurfaceFormat(surfaceOld, SDL_PIXELFORMAT_ARGB8888, 0);
			SDL_FreeSurface(surfaceOld);
			if surface = nil then exit;
		end;

		if (PUint32(surface^.pixels)^ and $00FFFFFF) = $FFFFFF then begin
			{ black on white, invert }
			for iy := 0 to (surface^.h-1) do begin
				ip := iy * surface^.pitch div 4;
				for ix := 0 to (surface^.w-1) do begin
					(PUint32(surface^.pixels) + ip)^ := (PUint32(surface^.pixels) + ip)^ xor $FFFFFF;
					Inc(ip);
				end;
			end;
		end;

		SDL_SetColorKey(surface, 1, PUint32(surface^.pixels)^ and $00FFFFFF);
		texWidth := surface^.w;
		texHeight := surface^.h;

		tex.surface := surface;
		tex.texture := nil;

		if (texWidth * texHeight) < totalTiles then begin
			FreeCharsetTexture(tex);
			exit;
		end;

		tex.charCount := totalTiles;
		tex.valid := true;

		{ Try to figure out character width and height }
		tex.charsetPitch := 1;
		while tex.charsetPitch <= totalTiles do begin
			if ((texWidth mod tex.charsetPitch) = 0) and ((texHeight mod (totalTiles div tex.charsetPitch)) = 0) then begin
				{ Proper divisors, matching tiles }
				{ say, 8x16 will lead to 16x8 in the next iteration }
				{ so, clamping between 1:1 and 1:2 aspect ratios should work }
				tex.charWidth := (texWidth div tex.charsetPitch);
				tex.charHeight := (texHeight div (totalTiles div tex.charsetPitch));

				{ We go from highest to lowest aspect ratio, so just pick the first one which works. }
				{ aspectRatio := Single(LongInt(tex.charWidth)) / Single(LongInt(tex.charHeight)); }
				if tex.charWidth <= tex.charHeight then begin
					exit;
				end;
			end;
			tex.charsetPitch := tex.charsetPitch shl 1;
		end;

		FreeCharsetTexture(tex);
	end;

procedure LoadCharsetFromByteArray(var tex: TCharsetTexture; chByteArray: array of byte; chSizeBytes: longint);
	var
		surfaceOld, surface: PSDL_Surface;
		palette: array[0 .. 1] of TSDL_Color;
		colors: array[0 .. 256*128-1] of byte;
		i, ix, iy: Int32;
		iyo: Uint32;
		ib: byte;
	begin
		tex.charWidth := 8;
		tex.charHeight := chSizeBytes shr 8;
		tex.charsetPitch := 32;
		tex.valid := false;
		if (tex.charHeight < 8) or (tex.charHeight > 16) then exit;

		for i := 0 to 255 do
			for iy := 0 to (tex.charHeight - 1) do begin
				ib := chByteArray[i * tex.charHeight + iy];
				iyo := (((i shr 5) * tex.charHeight + iy) shl 8) + ((i and 31) shl 3);
				for ix := 0 to 7 do begin
					colors[iyo + ix] := (ib shr (7 - ix)) and 1;
				end;
			end;

		surface := SDL_CreateRGBSurfaceFrom(
			@colors, 256, tex.charHeight * 8, 8, 256,
			0, 0, 0, 0
		);

		if surface = nil then exit;

		palette[0].r := 0;
		palette[0].g := 0;
		palette[0].b := 0;
		palette[0].a := 0;
		palette[1].r := 255;
		palette[1].g := 255;
		palette[1].b := 255;
		palette[1].a := 255;
		SDL_SetPaletteColors(surface^.format^.palette, @palette, 0, 2);
		SDL_SetColorKey(surface, 1, 0);

		{ Make copy because colors is stack-allocated }
		surfaceOld := surface;
		surface := SDL_ConvertSurfaceFormat(surfaceOld, SDL_PIXELFORMAT_ARGB8888, 0);
		SDL_FreeSurface(surfaceOld);
		if surface = nil then exit;

		tex.surface := surface;
		tex.texture := nil;
		tex.charCount := 256;
		tex.valid := true;
	end;

const
	FONT_MANIA_ID_STRING = 'FONT MANIA';

procedure VideoLoadCharsetDialog;
	var
		i: integer;
		filename: string;
	begin
		i := 0;
		filename := FileSelect('Character Sets', '.CHR;.COM', i);
		VideoLoadCharsetFromFile(filename);
	end;

procedure VideoLoadCharsetFromFile(filename: string);
	var
		charsetData: pointer;
		charsetLen: word;
	label FinishLoadCharset;
	begin
		if filename = '' then begin
			VideoSetCharset(nil, 14);
			exit;
		end;

		charsetLen := FileReadAll(filename, charsetData, 8192);
		if charsetLen >= 5027 then begin
			if CompareMem(charsetData + 8, @FONT_MANIA_ID_STRING[1], Length(FONT_MANIA_ID_STRING)) then begin
				VideoSetCharset(charsetData + 1442, 14);
				goto FinishLoadCharset;
			end;
		end else if ((charsetLen and $FF) = 0) and (charsetLen > 0) then begin
			VideoSetCharset(charsetData, charsetLen shr 8);
			goto FinishLoadCharset;
		end;

		{ Fallback }
		VideoSetCharset(nil, 14);
FinishLoadCharset:
		if charsetLen > 0 then
			FreeMem(charsetData, charsetLen);
	end;

const
	EGA_PALETTE_LUT: array[0 .. 15] of byte = (
		0, 1, 2, 3, 4, 5, 20, 7,
		56, 57, 58, 59, 60, 61, 62, 63
	);

procedure VideoSetPalette(data: array of Uint32; custom: boolean);
	var
		i: integer;
	begin
		SDL_LockMutex(eventMutex);

		for i := 0 to 15 do
			palette[i] := data[i];
		usingCustomPalette := custom;

		SDL_UnlockMutex(eventMutex);
		VideoForcePlayfieldRedraw;
	end;

procedure VideoLoadPaletteDialog;
	var
		i: integer;
		filename: string;
	begin
		i := 0;
		filename := FileSelect('Palettes', '.PAL;.PLD', i);
		VideoLoadPaletteFromFile(filename);
	end;

procedure VideoLoadPaletteFromFile(filename: string);
	var
		i: integer;
		palette: array[0 .. 15] of Uint32;
		paletteData: pointer;
		paletteDataArr: PByteArray;
		paletteLen: word;
	begin
		if filename = '' then begin
			VideoSetPalette(EGA_PALETTE, false);
			exit;
		end;

		paletteLen := FileReadAll(filename, paletteData, 8192);
		paletteDataArr := PByteArray(paletteData);
		if paletteLen = 192 then begin
			{ .PLD file }
			for i := 0 to 15 do
				palette[i] :=
					(((paletteDataArr^[(EGA_PALETTE_LUT[i] * 3)] and $3F) * 255 div 63) shl 16)
					or (((paletteDataArr^[(EGA_PALETTE_LUT[i] * 3) + 1] and $3F) * 255 div 63) shl 8)
					or (((paletteDataArr^[(EGA_PALETTE_LUT[i] * 3) + 2] and $3F) * 255 div 63));
			VideoSetPalette(palette, true);
		end else if paletteLen = 48 then begin
			{ .PAL file }
			for i := 0 to 15 do
				palette[i] :=
					(((paletteDataArr^[(i * 3)] and $3F) * 255 div 63) shl 16)
					or (((paletteDataArr^[(i * 3) + 1] and $3F) * 255 div 63) shl 8)
					or (((paletteDataArr^[(i * 3) + 2] and $3F) * 255 div 63));
			VideoSetPalette(palette, true);
		end else begin
			{ Fallback }
			VideoSetPalette(EGA_PALETTE, false);
		end;

		if paletteLen > 0 then
			FreeMem(paletteData, paletteLen);
	end;

procedure VideoSetTextInputArea(x, y, width, height: integer);
	var
		inRect: TSDL_Rect;
	begin
		inRect.x := x * charsetTexture.charWidth;
		inRect.y := y * charsetTexture.charHeight;
		inRect.w := width * charsetTexture.charWidth;
		inRect.h := height * charsetTexture.charHeight;

		SDL_SetTextInputRect(@inRect);
	end;

{ Video drawing }

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

procedure VideoDrawCharBg(x, y: integer);
	var
		offset: integer;
		col: byte;
		bgCol: Uint32;
		outRect: TSDL_Rect;
	begin
		offset := y * MAX_VIDEO_WIDTH + x;
		col := screenColors[offset];

		if ((col < $80) or (blinkMode <> BlinkModeOn)) and (not screenChanged[offset]) then exit;

		if blinkMode <> BlinkModeHigh then col := col and $7F;
		if VideoMonochrome then
			col := ColorToBW(col);

		bgCol := palette[col shr 4];

		outRect.x := x * charsetTexture.charWidth;
		outRect.y := y * charsetTexture.charHeight;
		outRect.w := charsetTexture.charWidth;
		outRect.h := charsetTexture.charHeight;

		SDL_SetRenderDrawColor(renderer, (bgCol shr 16), (bgCol shr 8), (bgCol shr 0), SDL_ALPHA_OPAQUE);
		SDL_RenderFillRect(renderer, @outRect);
	end;

function VideoDrawCharFg(x, y: integer; blink: boolean): integer;
	var
		offset: integer;
		chr: Uint32;
		col: byte;
		fgCol: Uint32;
		inRect, outRect: TSDL_Rect;
		doubleWide: boolean;
	begin
		VideoDrawCharFg := 0;
		doubleWide := false;

		offset := y * MAX_VIDEO_WIDTH + x;
		chr := screenChars[offset];
		col := screenColors[offset];

{$IFDEF SHIFTJIS}
		if (chr >= $100) and ((chr and $FE) <> $56) then begin
			doubleWide := not ((chr and $FF) in [9, 10, 11]);
		end;
{$ENDIF}

		if doubleWide then VideoDrawCharFg := 1;
		if (chr = 0) or (chr = 32) then exit;
		if ((col < $80) or (blinkMode <> BlinkModeOn)) and (not screenChanged[offset]) then exit;

		if (blinkMode = BlinkModeOn) then begin
			blink := blink and (col >= $80);
			col := col and $7F;
			if blink or ((col shr 4) = (col and $0F)) then exit;
		end;

		if VideoMonochrome then
			col := ColorToBW(col);

		fgCol := palette[col and 15];

{$IFDEF SHIFTJIS}
		if chr < $100 then begin
			inRect.x := chr * charsetTexture.charWidth;
			inRect.y := 0;
		end else begin
			inRect.x := (chr and $FF) * charsetTexture.charWidth * 2;
			inRect.y := ((chr shr 8) and $FF) * charsetTexture.charHeight;
		end;
{$ELSE}
		inRect.x := (chr mod charsetTexture.charsetPitch) * charsetTexture.charWidth;
		inRect.y := (chr div charsetTexture.charsetPitch) * charsetTexture.charHeight;
{$ENDIF}
		inRect.w := charsetTexture.charWidth;
		inRect.h := charsetTexture.charHeight;

		outRect.x := x * charsetTexture.charWidth;
		outRect.y := y * charsetTexture.charHeight;
		outRect.w := charsetTexture.charWidth;
		outRect.h := charsetTexture.charHeight;

		if doubleWide then begin
			inRect.w := inRect.w * 2;
			outRect.w := outRect.w * 2;
		end;

		SDL_SetTextureColorMod(charsetTexture.texture, (fgCol shr 16), (fgCol shr 8), (fgCol shr 0));
		SDL_RenderCopy(renderer, charsetTexture.texture, @inRect, @outRect);
	end;

function VideoRenderThread(data: pointer): LongInt; cdecl;
	var
		ix, iy: integer;
		w, h: Int32;
		blink: boolean;
		srcRect: TSDL_Rect;
		destRect: TSDL_Rect;
	begin
		SDL_LockMutex(mainThreadSdlChangesMutex);
		SDL_LockMutex(eventMutex);

		renderer := nil;
		if not VideoForceSoftware then
			renderer := SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
		if renderer = nil then
			renderer := SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC);

		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, '0');

		playfieldTexture := SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET,
			MAX_VIDEO_WIDTH * 8, MAX_VIDEO_HEIGHT * 16); { TODO: Allocates 640x400 texture to allow up to 8x16 fonts. }

		SDL_RenderClear(renderer);
		SDL_RenderPresent(renderer);

		SDL_UnlockMutex(eventMutex);
		SDL_UnlockMutex(mainThreadSdlChangesMutex);

		while renderThreadRunning do begin
			SDL_LockMutex(mainThreadSdlChangesMutex);
			SDL_LockMutex(eventMutex);

			SDL_GetRendererOutputSize(renderer, @w, @h);
			CalcRenderArea(@destRect, w, h);

			srcRect.x := 0;
			srcRect.y := 0;
			srcRect.w := VideoColumns * charsetTexture.charWidth;
			srcRect.h := VideoRows * charsetTexture.charHeight;

			SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
			SDL_RenderClear(renderer);

			SDL_SetRenderTarget(renderer, playfieldTexture);

			SDL_LockMutex(playfieldMutex);

			if charsetTexture.valid then begin
				if charsetTexture.texture = nil then begin
					charsetTexture.texture := SDL_CreateTextureFromSurface(renderer, charsetTexture.surface);
				end;
			end;

			blink := (SDL_GetTicks mod TEXT_BLINK_RATE) >= (TEXT_BLINK_RATE div 2);

			for iy := 0 to (VideoRows - 1) do
				for ix := 0 to (VideoColumns - 1) do
					VideoDrawCharBg(ix, iy);

			for iy := 0 to (VideoRows - 1) do
				for ix := 0 to (VideoColumns - 1) do
					ix := ix + VideoDrawCharFg(ix, iy, blink);

			FillChar(screenChanged, MAX_VIDEO_BUFFER_SIZE_CHARS, false);
			SDL_UnlockMutex(playfieldMutex);

			SDL_SetRenderTarget(renderer, nil);
			SDL_RenderCopy(renderer, playfieldTexture, @srcRect, @destRect);

			SDL_UnlockMutex(eventMutex);

			SDL_RenderPresent(renderer);

			SDL_UnlockMutex(mainThreadSdlChangesMutex);

			TimerSysWake(IMUntilFrame);
			SDL_Delay(1);
		end;
		VideoRenderThread := 0;
	end;

procedure VideoWriteText(x, y, color: byte; text: TVideoLine);
	var
		i, offset: integer;
		oldChar: Uint32;
		oldColor: byte;
	begin
		offset := y * MAX_VIDEO_WIDTH + x;
		SDL_LockMutex(playfieldMutex);
		for i := 1 to Length(text) do begin
			oldChar := screenChars[offset];
			oldColor := screenColors[offset];
{$IFDEF SHIFTJIS}
			screenChars[offset] := CP437_NEC98_MAP[Byte(text[i])];
{$ELSE}
			screenChars[offset] := Byte(text[i]);
{$ENDIF}
			screenColors[offset] := color;
			if (oldChar <> screenChars[offset]) or (oldColor <> color) then
				screenChanged[offset] := true;
			Inc(offset);
		end;
		SDL_UnlockMutex(playfieldMutex);
	end;

{$IFDEF SHIFTJIS}
procedure VideoWriteTextWide(x, y, color: byte; text: TVideoLine);
	var
		i, j, offset: integer;
		doubleByte: boolean;
		s1, s2: byte; { FetchPC98Word }
	function FetchPC98Word: word;
		label DepackS2;
		begin
			if doubleByte then begin
				FetchPC98Word := (s2 shl 8) or s1;
				doubleByte := false;
				exit;
			end;

			s1 := Byte(text[i]);
			Inc(i);
			if (s1 >= $81) and (s1 <= $9F) then begin
				{ s1 := ((s1 - $70) shl 1); }
				s1 := ((s1 - $80) shl 1);
				s2 := Byte(text[i]);
				Inc(i);
				goto DepackS2;
			end else if ((s1 and $F0) = $E0) then begin
				{ s1 := ((s1 - $B0) shl 1); }
				s1 := ((s1 - $C0) shl 1);
				s2 := Byte(text[i]);
				Inc(i);
	DepackS2:
				if s2 >= 159 then begin
					s2 := s2 - 126;
				end else begin
					Dec(s1);
					if s2 >= 128 then
						s2 := s2 - 32
					else
						s2 := s2 - 31;
				end;
				doubleByte := true;
				FetchPC98Word := (s2 shl 8) or s1;
			end else FetchPC98Word := s1;
		end;
	begin
		i := 1;
		doubleByte := false;
		offset := y * MAX_VIDEO_WIDTH + x;
		SDL_LockMutex(playfieldMutex);
		for j := 1 to Length(text) do begin
			screenChars[offset] := FetchPC98Word;
			screenColors[offset] := color;
			screenChanged[offset] := true;
			Inc(offset);
		end;
		SDL_UnlockMutex(playfieldMutex);
	end;
{$ENDIF}

function VideoIsCharsetCustom: boolean;
	begin
		VideoIsCharsetCustom := usingCustomCharset;
	end;

function VideoIsPaletteCustom: boolean;
	begin
		VideoIsPaletteCustom := usingCustomPalette;
	end;

function VideoSetPaletteColor(idx, r, g, b: byte): boolean;
	begin
		SDL_LockMutex(eventMutex);
		palette[idx] :=
			((Uint32(r) * 255 div 63) shl 16)
			or ((Uint32(g) * 255 div 63) shl 8)
			or (Uint32(b) * 255 div 63);
		usingCustomPalette := true;
		SDL_UnlockMutex(eventMutex);
		VideoForcePlayfieldRedraw;
		VideoSetPaletteColor := true;
	end;

function VideoSetCharset(data: pointer; height: integer): boolean;
	label FinishSetCharset;
	begin
		VideoSetCharset := false;

		SDL_LockMutex(eventMutex);

		FreeCharsetTexture(charsetTexture);

		if data <> nil then begin
			LoadCharsetFromByteArray(charsetTexture, PByteArray(data)^, height shl 8);
			if charsetTexture.valid then begin
				VideoSetCharset := true;
				usingCustomCharset := true;
				goto FinishSetCharset;
			end;
		end;

		LoadCharsetFromByteArray(charsetTexture, F_ASCIIData, F_ASCIISize);
		usingCustomCharset := false;
		if not charsetTexture.valid then
			RunError(217);

FinishSetCharset:
		SDL_UnlockMutex(eventMutex);

		SDLResizeWindow(0, true, false);
	end;

function VideoInstall(mode: integer; charsetData: PTCharsetData; charsetHeight: integer;
	borderColor: integer): boolean;
	var
		charsetSurface: PSDL_Surface;
		asciiBmpPath: string;
		f: file;
		i: integer;
	begin
		VideoInstall := false;

		if installed then begin
			SDL_LockMutex(eventMutex);
		end;

		if mode <> VIDEO_MODE_RESIZABLE then begin
			VideoSidebarX := 60;
			VideoColumns := 80;
			VideoRows := 25;
			if mode = VIDEO_MODE_40X25 then
				VideoColumns := 40
			else if mode = VIDEO_MODE_80X43 then
				VideoRows := 43
			else if mode = VIDEO_MODE_80X50 then
				VideoRows := 50;
		end;
		VideoCurrentMode := mode;

		if not installed then begin
			windowed := true;

			window := SDL_CreateWindow('%NAME% %VERSION%',
				SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
				640, {$IFDEF E_SUPERZ}400{$ELSE}{$IFDEF SHIFTJIS}400{$ELSE}350{$ENDIF}{$ENDIF},
				SDL_WINDOW_RESIZABLE or SDL_WINDOW_ALLOW_HIGHDPI);
		end;

{$IFDEF SHIFTJIS}
		if (not charsetTexture.valid) or (not installed) then begin
			LoadCharsetFromBMP(charsetTexture, 'SJISFONT.BMP', 16384);
			charsetTexture.charWidth := charsetTexture.charWidth div 2;
		end;
{$ELSE}
		if installed then begin
			FreeCharsetTexture(charsetTexture);
		end;
		if charsetHeight > 0 then begin
			LoadCharsetFromByteArray(charsetTexture, PByteArray(charsetData)^, charsetHeight * 256);
			usingCustomCharset := false;
		end;
		if not charsetTexture.valid then begin
			LoadCharsetFromByteArray(charsetTexture, F_ASCIIData, F_ASCIISize);
			usingCustomCharset := false;
		end;
{$ENDIF}
		if not charsetTexture.valid then
			RunError(217);
	
		for i := 0 to 15 do
			palette[i] := EGA_PALETTE[i];
		usingCustomPalette := false;

		if not installed then begin
			mainThreadSdlChangesMutex := SDL_CreateMutex;
			playfieldMutex := SDL_CreateMutex;

			TimerSysAudioOpen;

			renderThreadRunning := true;
			renderThread := SDL_CreateThread(VideoRenderThread, 'Render thread', nil);

			SDL_Delay(50); { TODO: Really ugly hack! }
			SDLResizeWindow(0, false, false);
		end else begin
			SDL_UnlockMutex(eventMutex);

			if mode <> VIDEO_MODE_RESIZABLE then
				SDLResizeWindow(0, true, false);
		end;

		VideoScaleChanged := false;
		if installed then VideoOnSizeChanged;
		VideoClear(borderColor);

		installed := true;
		VideoInstall := true;
	end;

procedure VideoUninstall;
	begin
		renderThreadRunning := false;
		SDL_WaitThread(renderThread, nil);

		TimerSysAudioClose;

		SDL_DestroyMutex(playfieldMutex);
		SDL_DestroyMutex(mainThreadSdlChangesMutex);
		SDL_DestroyTexture(playfieldTexture);
		FreeCharsetTexture(charsetTexture);
		SDL_DestroyRenderer(renderer);
		SDL_DestroyWindow(window);

		installed := false;
	end;

procedure VideoSetCursorShape(value: integer);
	begin
		{ stub }
	end;

procedure VideoShowCursor;
	begin
		{ stub }
		VideoCursorVisible := true;
	end;

procedure VideoHideCursor;
	begin
		{ stub }
		VideoCursorVisible := false;
	end;

procedure VideoSetBorderColor(value: integer);
	begin
		{ stub }
	end;

procedure VideoSetBlink(value: boolean);
	begin
		if value then begin
			if blinkMode <> BlinkModeOff then begin
				VideoSetSDLBlinkMode(BlinkModeOn);
			end;
		end else begin
			VideoSetSDLBlinkMode(BlinkModeHigh);
		end;
	end;

procedure VideoClear(bgColor: integer);
	begin
		if installed then SDL_LockMutex(playfieldMutex);
		FillDWord(screenChars, MAX_VIDEO_BUFFER_SIZE_CHARS, 0);
		FillChar(screenColors, MAX_VIDEO_BUFFER_SIZE_CHARS, bgColor * $11);
		FillChar(screenChanged, MAX_VIDEO_BUFFER_SIZE_CHARS, true);
		if installed then SDL_UnlockMutex(playfieldMutex);
	end;

procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	var
		i, offset: integer;
	begin
		offset := y * MAX_VIDEO_WIDTH + x;
		if toVideo then begin
			SDL_LockMutex(playfieldMutex);
			Move(data^, screenChars[offset], chars * 4);
			Move((data + (chars * 4))^, screenColors[offset], chars);
			for i := 0 to chars - 1 do
				screenChanged[offset + i] := true;
			SDL_UnlockMutex(playfieldMutex);
		end else begin
			Move(screenChars[offset], data^, chars * 4);
			Move(screenColors[offset], (data + (chars * 4))^, chars);
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
		SDL_LockMutex(playfieldMutex);
		for iy := y1 to y2 do begin
			offset := (iy * MAX_VIDEO_WIDTH) + x1;
			for ix := x1 to x2 do begin
				screenColors[offset] := screenColors[offset] xor $7F;
				screenChanged[offset] := true;
				Inc(offset);
			end;
		end;
		SDL_UnlockMutex(playfieldMutex);
	end;

procedure VideoScroll(x, y, width, height, dx, dy: integer);
	var
		ix, iy: integer;
		srcOfs, destOfs, xOfs: integer;
	begin
		SDL_LockMutex(playfieldMutex);
		if dy = 0 then begin
			if dx >= 0 then begin
				{ move right }
				srcOfs := (y * MAX_VIDEO_WIDTH + x);
				destOfs := srcOfs + (dx);
				for iy := 1 to height do begin
					xOfs := ((width - dx) - 1);
					for ix := 1 to (width - dx) do begin
						screenChars[destOfs + xOfs] := screenChars[srcOfs + xOfs];
						screenColors[destOfs + xOfs] := screenColors[srcOfs + xOfs];
						screenChanged[destOfs + xOfs] := true;
						Dec(xOfs);
					end;
					srcOfs := srcOfs + (MAX_VIDEO_WIDTH);
					destOfs := destOfs + (MAX_VIDEO_WIDTH);
				end;
			end else begin
				{ move left }
				destOfs := (y * MAX_VIDEO_WIDTH + x);
				srcOfs := destOfs - (dx);
				for iy := 1 to height do begin					
					xOfs := 0;
					for ix := 1 to (width + dx) do begin
						screenChars[destOfs + xOfs] := screenChars[srcOfs + xOfs];
						screenColors[destOfs + xOfs] := screenColors[srcOfs + xOfs];
						screenChanged[destOfs + xOfs] := true;
						Inc(xOfs);
					end;
					srcOfs := srcOfs + (MAX_VIDEO_WIDTH);
					destOfs := destOfs + (MAX_VIDEO_WIDTH);
				end;
			end;
		end else begin
			if dy > 0 then begin
				{ move down }
				srcOfs := ((y + height - 2) * MAX_VIDEO_WIDTH + x);
				destOfs := MAX_VIDEO_WIDTH + srcOfs;
				for iy := 1 to (height - 1) do begin
					xOfs := 0;
					for ix := 1 to width do begin
						screenChars[destOfs + xOfs] := screenChars[srcOfs + xOfs];
						screenColors[destOfs + xOfs] := screenColors[srcOfs + xOfs];
						screenChanged[destOfs + xOfs] := true;
						Inc(xOfs);
					end;
					srcOfs := srcOfs - (MAX_VIDEO_WIDTH);
					destOfs := destOfs - (MAX_VIDEO_WIDTH);
				end;
			end else begin
				{ move up }
				destOfs := (y * MAX_VIDEO_WIDTH + x);
				srcOfs := MAX_VIDEO_WIDTH + destOfs;
				for iy := 1 to (height - 1) do begin
					xOfs := 0;
					for ix := 1 to width do begin
						screenChars[destOfs + xOfs] := screenChars[srcOfs + xOfs];
						screenColors[destOfs + xOfs] := screenColors[srcOfs + xOfs];
						screenChanged[destOfs + xOfs] := true;
						Inc(xOfs);
					end;
					srcOfs := srcOfs + (MAX_VIDEO_WIDTH);
					destOfs := destOfs + (MAX_VIDEO_WIDTH);
				end;
			end;
		end;
		SDL_UnlockMutex(playfieldMutex);
	end;

begin
	installed := false;
	VideoClear(0);
	VideoBorderColor := 0;
	VideoSidebarX := 60;
	VideoColumns := 80;
	VideoRows := 25;
	VideoForceSoftware := false;
	VideoCursorVisible := true;
	blinkMode := BlinkModeOn;
	scalingMode := SMInteger;
end.
