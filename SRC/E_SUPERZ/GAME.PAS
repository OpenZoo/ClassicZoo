{
	Copyright (c) 2020 Adrian Siekierka

	Based on a reconstruction of code from Super ZZT,
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
unit Game;

interface
	uses GameVars, TxtWind;
	const
		VIEW_TITLE = 0;
		VIEW_PLAY = 1;
		VIEW_PLAY_LARGE = 2;
		VIEW_EDITOR = 3;
		VIEW_EDITOR_LARGE = 4;
	function GameVideoInstall(videoMode, mode: integer): boolean;
	procedure BoardChange(boardId: integer);
	procedure BoardCreate;
	procedure WorldCreate;
	procedure TransitionDrawToFill(chr: char; color: integer);
	procedure BoardDrawTile(x, y: integer);
	procedure TransitionDrawToBoard;
	procedure ClearDisplayMessage;
	procedure DrawStatusMessage(msg: string);
	function PromptYesNo(message: string; defaultReturn: boolean; color: integer): boolean;
	procedure PauseOnError;
	procedure WorldUnload;
	function WorldLoad(filename, extension: TSmallString; titleOnly: boolean): boolean;
	procedure WorldSave(filename, extension: TSmallString; saveZxts: boolean);
	procedure GameWorldSave(prompt: TSmallString; var filename: TSmallString; extension: TSmallString);
	function GameWorldLoad(extension: TSmallString): boolean;
	procedure AddStat(tx, ty: integer; element: byte; color, tcycle: integer; template: TStat);
	procedure RemoveStat(statId: integer);
	procedure BoardRemoveTile(x, y: integer);
	function BoardPrepareTileForPlacement(x, y: integer): boolean;
	procedure MoveStat(statId: integer; newX, newY: integer);
	procedure GameUpdateSidebar;
	procedure DisplayMessage(time: integer; line1, line2: TSmallString);
	procedure DamageStat(attackerStatId: integer);
	procedure BoardDamageTile(x, y: integer);
	procedure BoardAttack(attackerStatId: integer; x, y: integer);
	function BoardShoot(element: byte; tx, ty, deltaX, deltaY: integer; source: integer): boolean;
	procedure TransitionDrawBoardChange;
	procedure BoardEnter;
	procedure BoardPassageTeleport(x, y: integer);
	procedure DrawPlayfieldBorder(inner: boolean);
	procedure BoardUpdateDrawOffset;
	procedure GamePlayLoop(isTitle: boolean);
	procedure GameTitleLoop;
	procedure ResetCachedLinePos;

const
	LFSR_START = 42;
	LFSR10_TAP_CONST = $321;
	LFSR11_TAP_CONST = $740;
	LFSR12_TAP_CONST = $F71;
	LFSR14_TAP_CONST = $3740;
	ProgressAnimColors: array[0 .. 7] of byte = ($18, $1C, $19, $1D, $1A, $1E, $1B, $1F);
	ProgressAnimStrings: array[0 .. 7] of string[5] =
		('....|', '...*/', '..*.-', '.*..\', '*...|', '..../', '....-', '....\');
	ColorNames: array[1 .. 7] of string[8] =
		('Blue', 'Green', 'Cyan', 'Red', 'Purple', 'Yellow', 'White');
	{}
	DiagonalDeltaX: array[0 .. 7] of integer = (-1, 0, 1, 1, 1, 0, -1, -1);
	DiagonalDeltaY: array[0 .. 7] of integer = (1, 1, 1, 0, -1, -1, -1, 0);
	NeighborDeltaX: array[0 .. 3] of integer = (0, 0, -1, 1);
	NeighborDeltaY: array[0 .. 3] of integer = (-1, 1, 0, 0);
	{}
	TileBoardEdge: TTile = (Element: E_BOARD_EDGE; Color: $00);
	{}
	StatTemplateDefault: TStat = (
		X: 0; Y: 0; StepX: 0; StepY: 0;
		Cycle: 0; P1: 0; P2: 0; P3: 0;
		Follower: -1; Leader: -1;
                Under: (Element: E_EMPTY; Color: $00);
	{$IFDEF RAWMEM}
        {$IFDEF CPU64}
                UnusedData: 0; DataPos: 0; DataLen: 0; Data: nil
        {$ELSE}
                Data: nil; DataPos: 0; DataLen: 0
        {$ENDIF}
	{$ELSE}
                Data: nil; DataPos: 0; DataLen: 0
	{$ENDIF}
	);
	WebChars: TSmallString = #250#179#179#179#196#217#191#180#196#192#218#195#196#193#194#197;
	LineChars: TSmallString = #249#208#210#186#181#188#187#185#198#200#201#204#205#202#203#206;

implementation
uses
{$IFDEF DEBUGWND} DebugWnd, {$ENDIF}
{$IFNDEF RAWMEM} GameVSer, {$ENDIF}
{$IFDEF WEBBROW} WebBrow, {$ENDIF}
{$IFDEF UISCBACK} UiScBack, {$ENDIF}
Dos, GameSh, Cheats, GameIo, ZxtMgr,
GameConf, FileSys, ExtMem, FileSel, ZVideo, Sounds, TimerSys, ZInput, Elements, Editor, Oop, Sidebar;

function GameVideoInstall(videoMode, mode: integer): boolean;
	var
		borderColor: integer;
		fileData: pointer;
		fileDataLen: word;
		viResult: boolean;
	label GameVideoInstalled;
	begin
		GameVideoInstall := false;

		borderColor := 1;
		if mode = VIEW_TITLE then
			borderColor := 0;
{$IFDEF SDL2}
		if (mode = VIEW_TITLE) and (videoMode = VIDEO_MODE_80X25) then
			videoMode := VIDEO_MODE_80X25_STRETCH;
{$ENDIF}

{$IFNDEF NEC98}
{$IFNDEF BASICSYS}
{$IFNDEF DSX86}
		if UseCustomFont then
			fileDataLen := ResourceDataReadBinaryFile('8X8.CHR', fileData, 0, 2048)
		else
			fileDataLen := 0;

		if fileDataLen > 0 then begin
			viResult := VideoInstall(videoMode, fileData, 8, borderColor);
			FreeMem(fileData, fileDataLen); 
			if viResult then goto GameVideoInstalled;
		end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

		if not VideoInstall(videoMode, nil, -1, borderColor) then exit;

GameVideoInstalled:
		if mode = VIEW_TITLE then
			TextWindowInit((VideoColumns - 50) shr 1, (VideoRows - 18) shr 1, 50, 18)
{$IFDEF EDITOR}
		else if mode >= VIEW_EDITOR then
			TextWindowInit(5, 3, 50, VideoRows - 7)
{$ENDIF}
		else if mode = VIEW_PLAY then
			TextWindowInit((VideoColumns - 38) shr 1, (VideoRows - 21) shr 1, 38, 22);
{$IFDEF EDITOR}
		if (mode = VIEW_EDITOR_LARGE) then begin
			BOARD_DRAW_X := 2;
			BOARD_DRAW_Y := 2;
			BOARD_DRAW_WIDTH := VideoColumns - 24;
			BOARD_DRAW_HEIGHT := VideoRows - 5;
		end else if (mode = VIEW_PLAY_LARGE) then begin
			BOARD_DRAW_WIDTH := VideoColumns - 16;
			if BOARD_DRAW_WIDTH > BOARD_WIDTH then
				BOARD_DRAW_WIDTH := BOARD_WIDTH;
			BOARD_DRAW_HEIGHT := VideoRows - 5;
			if BOARD_DRAW_HEIGHT > BOARD_HEIGHT then
				BOARD_DRAW_HEIGHT := BOARD_HEIGHT;
			BOARD_DRAW_X := 12 + ((VideoColumns - 12 - BOARD_DRAW_WIDTH) div 2);
			BOARD_DRAW_Y := 2;
		end else begin
{$ENDIF}
			BOARD_DRAW_WIDTH := 24;
			BOARD_DRAW_HEIGHT := 20;

			BOARD_DRAW_Y := (VideoRows - BOARD_DRAW_HEIGHT) div 2;
{$IFDEF EDITOR}
			if mode = VIEW_EDITOR then begin
				BOARD_DRAW_X := ((VideoColumns - 20 - BOARD_DRAW_WIDTH) div 2);
			end else begin
{$ENDIF}
				BOARD_DRAW_X := 12 + ((VideoColumns - 12 - BOARD_DRAW_WIDTH) div 2);
{$IFDEF EDITOR}
			end;
		end;
{$ENDIF}
		BOARD_DRAW_OX_MAX := BOARD_WIDTH - BOARD_DRAW_WIDTH + 1;
		BOARD_DRAW_OY_MAX := BOARD_HEIGHT - BOARD_DRAW_HEIGHT + 1;

		if (BOARD_DRAW_WIDTH > 64) or (BOARD_DRAW_HEIGHT > 64) then begin
			LfsrTapConst := LFSR14_TAP_CONST;
			LfsrAndConst := $7F;
			LfsrShrConst := 7;
		end else if (BOARD_DRAW_WIDTH > 32) or (BOARD_DRAW_HEIGHT > 32) then begin
			LfsrTapConst := LFSR12_TAP_CONST;
			LfsrAndConst := $3F;
			LfsrShrConst := 6;
		end else begin
			LfsrTapConst := LFSR10_TAP_CONST;
			LfsrAndConst := $1F;
			LfsrShrConst := 5;
		end;

		GameVideoInstall := true;
	end;

function LFSRUpdateSeed(var seed: word; var tx, ty: byte): boolean;
	begin
		seed := (seed shr 1) xor ((-(seed and 1)) and LfsrTapConst);
		tx := (seed - 1) and LfsrAndConst;
		ty := ((seed - 1) shr LfsrShrConst) and LfsrAndConst;
		LFSRUpdateSeed := seed = LFSR_START;
	end;

procedure BoardChange(boardId: integer);
	begin
		with Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y] do begin
			if ExtensionEnabled[ExtFixPassageDestroy] then begin
				if Element = E_PLAYER then
					Color := ElementDefs[E_PLAYER].Color;
			end else begin
				Element := E_PLAYER;
				Color := ElementDefs[E_PLAYER].Color;
			end;
		end;

		BoardClose;
		BoardOpen(boardId);
	end;

procedure BoardCreate;
	var
		ix, iy, i: integer;
	begin
		Board.Name := '';
		MessageLine1 := '';
		Board.Info.MaxShots := 255;
		Board.Info.ReenterWhenZapped := false;
		Board.Info.TimeLimitSec := 0;
		for i := 0 to 3 do
			Board.Info.NeighborBoards[i] := 0;

		for ix := 0 to BOARD_WIDTH+1 do begin
			Board.Tiles[ix][0] := TileBoardEdge;
			Board.Tiles[ix][BOARD_HEIGHT+1] := TileBoardEdge;
		end;
		for iy := 0 to BOARD_HEIGHT+1 do begin
			Board.Tiles[0][iy] := TileBoardEdge;
			Board.Tiles[BOARD_WIDTH+1][iy] := TileBoardEdge;
		end;

		for ix := 1 to BOARD_WIDTH do
			for iy := 1 to BOARD_HEIGHT do begin
				Board.Tiles[ix][iy].Element := E_EMPTY;
				Board.Tiles[ix][iy].Color := 0;
			end;

		Board.Tiles[BOARD_WIDTH div 2][BOARD_HEIGHT div 2].Element := E_PLAYER;
		Board.Tiles[BOARD_WIDTH div 2][BOARD_HEIGHT div 2].Color := ElementDefs[E_PLAYER].Color;
		Board.StatCount := 0;
		Board.Stats[0].X := BOARD_WIDTH div 2;
		Board.Stats[0].Y := BOARD_HEIGHT div 2;
		Board.Stats[0].Cycle := 1;
		Board.Stats[0].Under.Element := E_EMPTY;
		Board.Stats[0].Under.Color := 0;
		Board.Stats[0].Data := nil;
		Board.Stats[0].DataLen := 0;
		Board.Info.DrawXOffset := Board.Stats[0].X - (BOARD_DRAW_WIDTH shr 1);
		if Board.Info.DrawXOffset < 1 then
			Board.Info.DrawXOffset := 1;
		Board.Info.DrawYOffset := Board.Stats[0].Y - (BOARD_DRAW_HEIGHT shr 1);
		if Board.Info.DrawYOffset < 1 then
			Board.Info.DrawYOffset := 1;
	end;

procedure WorldCreate;
	var
		i: integer;
	begin
		InitElementsGame;
		World.BoardCount := 0;
		World.BoardLen[0] := 0;
		InitEditorStatSettings;
		ResetMessageNotShownFlags;
		BoardCreate;
		World.Info.IsSave := false;
		World.Info.CurrentBoard := 0;
		World.Info.Ammo := 0;
		World.Info.Gems := 0;
		World.Info.Health := 100;
		World.Info.EnergizerTicks := 0;
		World.Info.Score := 0;
		World.Info.BoardTimeSec := 0;
		World.Info.BoardTimeHsec := 0;
		World.Info.StonesOfPower := -1;
		for i := 1 to 7 do
			World.Info.Keys[i] := false;
		for i := 1 to MAX_FLAG do
			World.Info.Flags[i] := '';
		BoardChange(0);
		Board.Name := 'Title screen';
		LoadedGameFileName := '';
		World.Info.Name := '';
	end;

procedure TransitionDrawToFill(chr: char; color: integer);
	var
		i, seed: word;
		tx, ty: byte;
	begin
		seed := LFSR_START;
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
		repeat
			if (tx < BOARD_DRAW_WIDTH) and (ty < BOARD_DRAW_HEIGHT) then begin
				VideoWriteText(tx + BOARD_DRAW_X, ty + BOARD_DRAW_Y, color, chr);
{$IFDEF FASTVID}
				Inc(i);
				if i >= TransitionBlocksPerFrame then begin
					SoundIdle(IMUntilFrame);
					i := 0;
				end;
{$ENDIF}
			end;
		until LFSRUpdateSeed(seed, tx, ty);

		if (tx < BOARD_DRAW_WIDTH) and (ty < BOARD_DRAW_HEIGHT) then
			VideoWriteText(tx + BOARD_DRAW_X, ty + BOARD_DRAW_Y, color, chr);
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(BOARD_DRAW_X, BOARD_DRAW_Y,
		BOARD_DRAW_X-1+BOARD_DRAW_WIDTH, BOARD_DRAW_Y-1+BOARD_DRAW_HEIGHT); {$ENDIF}
	end;

procedure BoardDrawTile(x, y: integer);
	var
		drawnChar: byte;
		drawnColor: integer;
	begin
		if (
			(x >= Board.Info.DrawXOffset)
			and (y >= Board.Info.DrawYOffset)
			and (x < (Board.Info.DrawXOffset + BOARD_DRAW_WIDTH))
			and (y < (Board.Info.DrawYOffset + BOARD_DRAW_HEIGHT))
		) then with Board.Tiles[x][y] do begin
			if Element = E_EMPTY then begin
				drawnChar := $20;
				drawnColor := $0F;
			end else if ElementDefs[Element].HasDrawProc then begin
				ElementDefs[Element].DrawProc(x, y, drawnChar);
				drawnColor := Color;
			end else if Element < E_TEXT_MIN then begin
				drawnChar := Ord(ElementDefs[Element].Character);
				drawnColor := Color;
			end else begin
				{ Text drawing }
				drawnChar := Color;
				if Element = E_TEXT_WHITE then
					drawnColor := $0F
{$IFDEF NEC98}
				else if (VideoPc98DrawingMode < 2) then
					drawnColor := (((Element - E_TEXT_MIN) + 1) shl 4)
{$ELSE}
				else if VideoMonochrome then
					drawnColor := $F0
{$ENDIF}
				else
					drawnColor := (((Element - E_TEXT_MIN) + 1) shl 4) + $F;
			end;
{$IFDEF EXTCHEAT}
			drawnColor := drawnColor xor CheatColorModifiers[Element];
{$ENDIF}
			VideoWriteText(
				x + BOARD_DRAW_X - Board.Info.DrawXOffset,
				y + BOARD_DRAW_Y - Board.Info.DrawYOffset,
				drawnColor, Chr(drawnChar)
			);
		end;
	end;

procedure TransitionDrawToBoard;
	var
		i, seed: word;
		tx, ty: byte;
	begin
		seed := LFSR_START;
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
		repeat
			if (tx < BOARD_DRAW_WIDTH) and (ty < BOARD_DRAW_HEIGHT) then begin
				BoardDrawTile(
					tx + Board.Info.DrawXOffset,
					ty + Board.Info.DrawYOffset
				);
{$IFDEF FASTVID}
				Inc(i);
				if i >= TransitionBlocksPerFrame then begin
					SoundIdle(IMUntilFrame);
					i := 0;
				end;
{$ENDIF}
			end;
		until LFSRUpdateSeed(seed, tx, ty);

		if (tx < BOARD_DRAW_WIDTH) and (ty < BOARD_DRAW_HEIGHT) then
			BoardDrawTile(
				tx + Board.Info.DrawXOffset,
				ty + Board.Info.DrawYOffset
			);
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(BOARD_DRAW_X, BOARD_DRAW_Y,
		BOARD_DRAW_X-1+BOARD_DRAW_WIDTH, BOARD_DRAW_Y-1+BOARD_DRAW_HEIGHT); {$ENDIF}
	end;

procedure ClearDisplayMessage;
	var
		i: integer;
	begin
		for i := 12 to VideoColumns - 1 do begin
			VideoWriteText(i, VideoRows - 2, $1F, ' ');
			VideoWriteText(i, VideoRows - 1, $1F, ' ');
		end;
	end;

procedure DrawStatusMessage(msg: string);
	begin
		ClearDisplayMessage;
		VideoWriteText(12 + (((VideoColumns - 12) - Length(msg)) shr 1), VideoRows - 1, $1E, msg);
	end;

function PromptYesNo(message: string; defaultReturn: boolean; color: integer): boolean;
	begin
		VideoWriteText(15, VideoRows - 1, color, message);
		VideoWriteText(15 + Length(message), VideoRows - 1, (color and $70) + $8E, '_');

		repeat
			InputReadWaitKey;
		until UpCase(InputKeyPressed) in [KEY_ESCAPE, 'N', 'Y'];
		if UpCase(InputKeyPressed) = 'Y' then
			defaultReturn := true
		else
			defaultReturn := false;

		ClearDisplayMessage;
		PromptYesNo := defaultReturn;
	end;

procedure PauseOnError;
	begin
		SoundQueue(1, SoundParse('s004x114x9'));
		AccurateDelay(2000);
	end;

procedure WorldUnload;
	var
		i: integer;
	begin
		BoardClose;
		if ZxtUnloadExtensions then begin end;
		for i := 0 to World.BoardCount do
			ExtMemFree(World.BoardData[i], World.BoardLen[i]);
	end;

function WorldLoad(filename, extension: TSmallString; titleOnly: boolean): boolean;
	var
		f: file;
		ptr: pointer;
		i: integer;
		loadProgress: integer;
	label OnError;
	begin
		WorldLoad := false;
		loadProgress := 0;

		VideoWriteText(15, VideoRows - 1, $1F, 'Loading.....');

		{ .ZXT files - hack }
		if (extension = '.SZT') and FileExists(filename + '.ZXT') then
			extension := '.ZXT';

		AssignFSys(f, filename + extension);
		Reset(f, 1);

		if not DisplayIOError then begin
			WorldUnload;
			BlockRead(f, World.BoardCount, 2);

			if not DisplayIOError then begin
				if not ZxtLoadExtensions(f, filename) then begin
					VideoWriteText(63, 5, $1E, ' .ZXT extension');
					VideoWriteText(63, 6, $1E, ' loading error!');
					exit;
				end;

				BlockRead(f, IoTmpBuf^, WORLD_FILE_HEADER_SIZE - 2);
				ptr := IoTmpBuf;
				Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
				AdvancePointer(ptr, SizeOf(World.BoardCount));
{$IFDEF ENDIAN_BIG}
				World.BoardCount := LEtoN(World.BoardCount);
{$ENDIF}

				if World.BoardCount < 0 then begin
					if World.BoardCount <> -2 then begin
						DrawStatusMessage('Wrong ZZT version!');
						PauseOnError;
						ClearDisplayMessage;
						goto OnError;
					end else begin
						Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
						AdvancePointer(ptr, SizeOf(World.BoardCount));
{$IFDEF ENDIAN_BIG}
						World.BoardCount := LEtoN(World.BoardCount);
{$ENDIF}
					end;
				end;

{$IFDEF RAWMEM}
				Move(ptr^, World.Info, SizeOf(World.Info));
				AdvancePointer(ptr, SizeOf(World.Info));
{$ELSE}
				CopyWorldInfoToLocal(ptr);
{$ENDIF}

				for i := 0 to World.BoardCount do begin
					BottomAnimateLoading(loadProgress);
					BlockRead(f, World.BoardLen[i], 2);
{$IFDEF ENDIAN_BIG}
					World.BoardLen[i] := LEtoN(World.BoardLen[i]);
{$ENDIF}

					if ExtMemGet(World.BoardData[i], World.BoardLen[i]) then begin
						case EnsureIoTmpBufSize(World.BoardLen[i]) of
							0, 1: begin end;
							2: RunError(203);
						end;

						BlockRead(f, IoTmpBuf^, World.BoardLen[i]);
						ExtMemWrite(World.BoardData[i], IoTmpBuf^, World.BoardLen[i]);
					end else RunError(203);
				end;

				BoardOpen(World.Info.CurrentBoard);
				LoadedGameFileName := filename;
				WorldLoad := true;

				HighScoresLoad;
				ClearDisplayMessage;

				if HighCompatAuto then
					HighCompat := false;
				if CleenModeAuto then
					CleenMode := false;
{$IFDEF DEBUGWND}
				{ BoardEnter is only called for play-boards, not title-boards. }
				if titleOnly and DebugCompatEnabled then
					DebugBoardIllegalElements;
{$ENDIF}
			end;
		end;

	OnError:
		Close(f);
	end;

procedure BottomPromptString(prompt: string; extension: TSmallString; var filename: string; promptMode: byte);
	begin
		ClearDisplayMessage;

		VideoWriteText(13, VideoRows - 1, $1F, prompt);
		VideoWriteText(Length(prompt) + 13 + 2, VideoRows - 1, $0F, '        ' + extension);

		PromptString(Length(prompt) + 13 + 2, VideoRows - 1, $1E, $0F, 8, 8, promptMode, filename);

		ClearDisplayMessage;
	end;

procedure WorldSave(filename, extension: TSmallString; saveZxts: boolean);
	var
		f: file;
		i: integer;
		unk1: integer;
		ptr: pointer;
		version: integer;
	label OnError;
	begin
		BoardClose;
		DrawStatusMessage('Saving...');

		AssignFSys(f, filename + extension);
		Rewrite(f, 1);

		if not DisplayIOError then begin
			if saveZxts and (ZxtBlockGetCount > 0) then begin
				if not ZxtWriteExtensions(f) then goto OnError;
			end;

			ptr := IoTmpBuf;
			FillChar(IoTmpBuf^, WORLD_FILE_HEADER_SIZE, 0);
			version := -2;
{$IFDEF ENDIAN_BIG}
			version := NtoLE(version);
{$ENDIF}
			Move(version, ptr^, SizeOf(version));
			AdvancePointer(ptr, SizeOf(version));

{$IFDEF ENDIAN_BIG}
			World.BoardCount := NtoLE(World.BoardCount);
{$ENDIF}
			Move(World.BoardCount, ptr^, SizeOf(World.BoardCount));
			AdvancePointer(ptr, SizeOf(World.BoardCount));
{$IFDEF ENDIAN_BIG}
			World.BoardCount := LEtoN(World.BoardCount);
{$ENDIF}

{$IFDEF RAWMEM}
			Move(World.Info, ptr^, SizeOf(World.Info));
			AdvancePointer(ptr, SizeOf(World.Info));
{$ELSE}
			CopyWorldInfoFromLocal(ptr);
{$ENDIF}

			BlockWrite(f, IoTmpBuf^, WORLD_FILE_HEADER_SIZE);
			if DisplayIOError then goto OnError;

			for i := 0 to World.BoardCount do begin
{$IFDEF ENDIAN_BIG}
				BlockWrite(f, SwapEndian(World.BoardLen[i]), 2);
{$ELSE}
				BlockWrite(f, World.BoardLen[i], 2);
{$ENDIF}
				if DisplayIOError then goto OnError;

				ExtMemRead(World.BoardData[i], IoTmpBuf^, World.BoardLen[i]);
				BlockWrite(f, IoTmpBuf^, World.BoardLen[i]);
				if DisplayIOError then goto OnError;
			end;

			Close(f);
		end;

		BoardOpen(World.Info.CurrentBoard);
		ClearDisplayMessage;
		exit;

	OnError:
		Close(f);
		Erase(f);
		BoardOpen(World.Info.CurrentBoard);
		ClearDisplayMessage;
	end;

procedure GameWorldSave(prompt: TSmallString; var filename: TSmallString; extension: TSmallString);
	var
		newFilename: TSmallString;
		zxtChoice: byte;
	begin
		newFilename := filename;
		if (extension = '.SZT') and (ZxtBlockGetCount > 0) then begin
			zxtChoice := 1;
			SidebarPromptChoice(true, 3, 'Save as:', '.SZT .ZXT', zxtChoice);
			if zxtChoice > 0 then extension := '.ZXT';
		end;
		BottomPromptString(prompt, extension, newFilename, PROMPT_ALPHANUM);
		if (InputKeyPressed <> KEY_ESCAPE) and (Length(newFilename) <> 0)
		and ((filename = newFilename) or (extension <> '.SZT') or OverwriteCheck(newFilename + extension)) then begin
			filename := newFilename;
			if extension <> '.SAV' then
				World.Info.Name := filename;

			if extension = '.SZT' then begin
				WorldSave(filename, extension, false);
				if ZxtBlockGetCount > 0 then
					WorldSaveZax(filename);
			end else begin
				WorldSave(filename, extension, true);
			end;
		end;
	end;

function GameWorldLoad(extension: TSmallString): boolean;
	var
		entryName: string;
		i: integer;
	begin
		GameWorldLoad := false;
		if extension = '.SZT' then
			entryName := FileSelect('ZZT Worlds', extension, FileWorldCachedLinePos)
		else
			entryName := FileSelect('Saved Games', extension, FileSaveCachedLinePos);

		if Length(entryName) > 0 then begin
			GameWorldLoad := WorldLoad(entryName, extension, false);
			if extension <> '.SAV' then
				SavedGameFileName := entryName;
		end;
	end;

procedure AddStat(tx, ty: integer; element: byte; color, tcycle: integer; template: TStat);
	begin
		if Board.StatCount < MAX_STAT then begin
			Inc(Board.StatCount);
			Board.Stats[Board.StatCount] := template;
			with Board.Stats[Board.StatCount] do begin
				X := tx;
				Y := ty;
				Cycle := tcycle;
				Under := Board.Tiles[tx][ty];
				Data := nil;
				DataPos := 0;
			end;

			if (template.Data <> nil) and (template.DataLen > 0) then begin
				GetMem(Board.Stats[Board.StatCount].Data, template.DataLen);
				Move(template.Data^, Board.Stats[Board.StatCount].Data^, template.DataLen);
			end;

			if ElementDefs[Board.Tiles[tx][ty].Element].PlaceableOnTop then
				Board.Tiles[tx][ty].Color := (color and $0F) + (Board.Tiles[tx][ty].Color and $70)
			else
				Board.Tiles[tx][ty].Color := color;
			Board.Tiles[tx][ty].Element := element;

			if ty > 0 then
				BoardDrawTile(tx, ty);
		end;
	end;

procedure RemoveStat(statId: integer);
	var
		i: integer;
	begin
		FreeStatDataMem(statId, false);

		with Board.Stats[statId] do begin
			if statId < CurrentStatTicked then
				Dec(CurrentStatTicked);

			Board.Tiles[X][Y] := Under;
			if Y > 0 then
				BoardDrawTile(X, Y);

			for i := 1 to Board.StatCount do begin
				if Board.Stats[i].Follower >= statId then begin
					if Board.Stats[i].Follower = statId then
						Board.Stats[i].Follower := -1
					else
						Dec(Board.Stats[i].Follower);
				end;

				if Board.Stats[i].Leader >= statId then begin
					if Board.Stats[i].Leader = statId then
						Board.Stats[i].Leader := -1
					else
						Dec(Board.Stats[i].Leader);
				end;
			end;

			for i := (statId + 1) to Board.StatCount do
				Board.Stats[i - 1] := Board.Stats[i];
			Dec(Board.StatCount);
		end;
	end;

procedure BoardRemoveTile(x, y: integer);
	var
		i, ix, iy: integer;
		iElem, iColor: byte;
		floorColor: integer;
	label SearchComplete;
	begin
		floorColor := 0;
		for i := 0 to 3 do begin
			ix := x + NeighborDeltaX[i];
			iy := y + NeighborDeltaY[i];
			iElem := Board.Tiles[ix][iy].Element;
			iColor := Board.Tiles[ix][iy].Color;

			if ElementDefs[iElem].Cycle <> -1 then begin
				iElem := Board.Stats[GetStatIdAt(ix, iy)].Under.Element;
				iColor := Board.Stats[GetStatIdAt(ix, iy)].Under.Color;	
			end;

			if (iElem = E_EMPTY)
				or (iElem = E_SLIDER_NS)
				or (iElem = E_SLIDER_EW)
				or (iElem = E_BOULDER)
			then begin
				floorColor := 0;
				goto SearchComplete;
			end else if (iElem = E_FLOOR) then begin
				floorColor := iColor;
			end;
		end;

	SearchComplete:
		if floorColor = 0 then begin
			Board.Tiles[x][y].Element := E_EMPTY;
		end else begin
			Board.Tiles[x][y].Element := E_FLOOR;
			Board.Tiles[x][y].Color := floorColor;
		end;
	end;

function BoardPrepareTileForPlacement(x, y: integer): boolean;
	var
		statId: integer;
		result: boolean;
	begin
		statId := GetStatIdAt(x, y);
		if statId > 0 then begin
			RemoveStat(statId);
			result := true;
		end else if statId < 0 then begin
			if not ElementDefs[Board.Tiles[x][y].Element].PlaceableOnTop then
				BoardRemoveTile(x, y);
			result := true;
		end else begin { statId = 0 (player) cannot be modified }
			result := false;
		end;
		BoardDrawTile(x, y);
		BoardPrepareTileForPlacement := result;
	end;

procedure MoveStat(statId: integer; newX, newY: integer);
	var
		iUnder: TTile;
		oldX, oldY: integer;
		i: integer;
		scrollOffset: boolean;
		recalcRequired: boolean;
		deltaX, deltaY, oldOX, oldOY: integer;
	begin
		with Board.Stats[statId] do begin
			scrollOffset := true;
			if newX < 0 then begin
				newX := -newX;
				scrollOffset := false;
			end;

			iUnder := Under;
{$IFDEF MEMBOUND}
			if TileOutOfBounds(newX, newY) then begin
				if not TileOutOfBounds(X, Y) then
					Board.Tiles[X][Y] := iUnder;
			end else begin
{$ENDIF}
			Board.Stats[statId].Under := Board.Tiles[newX][newY];

			if Board.Tiles[newX][newY].Element = E_EMPTY then
				Board.Tiles[newX][newY].Color := Board.Tiles[X][Y].Color and $0F
			else
				Board.Tiles[newX][newY].Color := (Board.Tiles[X][Y].Color and $0F) + (Board.Tiles[newX][newY].Color and $70);

			Board.Tiles[newX][newY].Element := Board.Tiles[X][Y].Element;
			Board.Tiles[X][Y] := iUnder;
			BoardDrawTile(X, Y);
{$IFDEF MEMBOUND}
			end;
{$ENDIF}
{$IFDEF DEBUGWND}
			if DebugUndefEnabled and ((X > (BOARD_WIDTH+1)) or (Y > (BOARD_HEIGHT+1))) then begin
				DebugShowElementMessage('Move out of bounds!', X, Y);
			end;
{$ENDIF}
			if (statId = 0) and scrollOffset then begin
				recalcRequired := false;
				oldOX := Board.Info.DrawXOffset;
				oldOY := Board.Info.DrawYOffset;

				if ((newX - Board.Info.DrawXOffset) < ((BOARD_DRAW_WIDTH shr 1) - 3))
				and (Board.Info.DrawXOffset > BOARD_DRAW_OX_MIN) then begin
					if (X - 1) = newX then begin
						Dec(Board.Info.DrawXOffset);
					end else begin
						recalcRequired := true;
					end;
				end;


				if ((newX - Board.Info.DrawXOffset) >= ((BOARD_DRAW_WIDTH shr 1) + 2))
				and (Board.Info.DrawXOffset < BOARD_DRAW_OX_MAX) then begin
					if (X + 1) = newX then begin
						Inc(Board.Info.DrawXOffset);
					end else begin
						recalcRequired := true;
					end;
				end;

				if ((newY - Board.Info.DrawYOffset) < ((BOARD_DRAW_HEIGHT shr 1) - 2))
				and (Board.Info.DrawYOffset > BOARD_DRAW_OY_MIN) then begin
					if (Y - 1) = newY then begin
						Dec(Board.Info.DrawYOffset);
					end else begin
						recalcRequired := true;
					end;
				end;

				if ((newY - Board.Info.DrawYOffset) >= ((BOARD_DRAW_HEIGHT shr 1) + 4))
				and (Board.Info.DrawYOffset < BOARD_DRAW_OY_MAX) then begin
					if (Y + 1) = newY then begin
						Inc(Board.Info.DrawYOffset);
					end else begin
						recalcRequired := true;
					end;
				end;

				if recalcRequired then begin
					Board.Info.DrawXOffset := newX - (BOARD_DRAW_WIDTH div 2);
					Board.Info.DrawYOffset := newY - (BOARD_DRAW_HEIGHT div 2);
				end;

				if Board.Info.DrawXOffset < BOARD_DRAW_OX_MIN then
					Board.Info.DrawXOffset := BOARD_DRAW_OX_MIN
				else if Board.Info.DrawXOffset > BOARD_DRAW_OX_MAX then
					Board.Info.DrawXOffset := BOARD_DRAW_OX_MAX;
				if Board.Info.DrawYOffset < BOARD_DRAW_OY_MIN then
					Board.Info.DrawYOffset := BOARD_DRAW_OY_MIN
				else if Board.Info.DrawYOffset > BOARD_DRAW_OY_MAX then
					Board.Info.DrawYOffset := BOARD_DRAW_OY_MAX;

				if (oldOX <> Board.Info.DrawXOffset) or (oldOY <> Board.Info.DrawYOffset) then begin
					deltaX := oldOX - Board.Info.DrawXOffset;
					deltaY := oldOY - Board.Info.DrawYOffset;
					if ((Abs(deltaX) = 1) and (deltaY = 0)) or ((Abs(deltaY) = 1) and (deltaX = 0)) then begin
						VideoScroll(
							BOARD_DRAW_X, BOARD_DRAW_Y,
							BOARD_DRAW_WIDTH, BOARD_DRAW_HEIGHT,
							deltaX, deltaY
						);
						if deltaX = 1 then begin
							for i := Board.Info.DrawYOffset to (Board.Info.DrawYOffset + BOARD_DRAW_HEIGHT) do
								BoardDrawTile(Board.Info.DrawXOffset, i);
						end else if deltaX = -1 then begin
							for i := Board.Info.DrawYOffset to (Board.Info.DrawYOffset + BOARD_DRAW_HEIGHT) do
								BoardDrawTile(Board.Info.DrawXOffset + (BOARD_DRAW_WIDTH - 1), i);
						end else if deltaY = 1 then begin
							for i := Board.Info.DrawXOffset to (Board.Info.DrawXOffset + BOARD_DRAW_WIDTH) do
								BoardDrawTile(i, Board.Info.DrawYOffset);
						end else if deltaY = -1 then begin
							for i := Board.Info.DrawXOffset to (Board.Info.DrawXOffset + BOARD_DRAW_WIDTH) do
								BoardDrawTile(i, Board.Info.DrawYOffset + (BOARD_DRAW_HEIGHT - 1));
						end;
					end else begin
						TransitionDrawToBoard;
					end;
				end;
			end;
{$IFDEF MEMBOUND}
			if TileOutOfBounds(newX, newY) then exit;
{$ENDIF}
			X := newX;
			Y := newY;
			BoardDrawTile(X, Y);
		end;
	end;

procedure GameUpdateSidebar;
	var
		numStr: string[8];
		drawnChar: char;
		i: integer;
	begin
		if GameStateElement = E_PLAYER then begin
			if World.Info.Health < 0 then
				World.Info.Health := 0;
			for i := 1 to 5 do begin
				if (i * 20) <= World.Info.Health then
					VideoWriteText(i + 6, 15, $6E, #219)
				else if ((i * 20) - 10) > World.Info.Health then
					VideoWriteText(i + 6, 15, $6E, ' ')
				else
					VideoWriteText(i + 6, 15, $6E, #221)
			end;

			Str(World.Info.Gems, numStr);
			VideoWriteText(7, 17, $6E, '   ');
			VideoWriteText(11 - Length(numStr), 17, $6E, numStr);

			Str(World.Info.Ammo, numStr);
			VideoWriteText(7, 18, $6E, '   ');
			VideoWriteText(11 - Length(numStr), 18, $6E, numStr);

			Str(World.Info.Score, numStr);
			VideoWriteText(7, 21, $6E, '   ');
			VideoWriteText(11 - Length(numStr), 21, $6E, numStr);

			VideoWriteText(0, 22, $6F, '            ');
			for i := 1 to MAX_FLAG do begin
				if (Length(World.Info.Flags[i]) <> 0)
					and (World.Info.Flags[i][1] = 'Z')
				then begin
					VideoWriteText(1, 22, $6F, Copy(World.Info.Flags[i], 2, Length(World.Info.Flags[i]) - 1));
				end;
			end;
			if World.Info.StonesOfPower >= 0 then begin
				Str(World.Info.StonesOfPower, numStr);
				VideoWriteText(11 - Length(numStr), 22, $6E, numStr);
			end;

			if (not HighCompat) and (Board.Info.TimeLimitSec > 0) then begin
				VideoWriteText(2, 23, $6F, 'Time ');
				Str(Board.Info.TimeLimitSec - World.Info.BoardTimeSec, numStr);
				VideoWriteText(7, 23, $6E, '   ');
				VideoWriteText(11 - Length(numStr), 23, $6E, numStr);
			end else begin
				VideoWriteText(2, 23, $6E, '        ');
			end;

			for i := 1 to 7 do begin
				if World.Info.Keys[i] then
					drawnChar := ElementDefs[E_KEY].Character
				else
					drawnChar := ' ';
				VideoWriteText(((i - 1) and 3) + 7, ((i - 1) shr 2) + 19, $68 + i, drawnChar);
			end;

			if SoundEnabled then
				VideoWriteText(3, 10, $6E, 'Be Quiet ')
			else
				VideoWriteText(3, 10, $6E, 'Be Noisy ');

{$IFDEF MSDOS}
			if DebugEnabled then begin
				Str(MemAvail, numStr);
				VideoWriteText(0, 0, $1E, 'm' + numStr + ' ');
				if ExtMemEmsActive then begin
					Str(ExtMemEmsAvailPages, numstr);
					VideoWriteText(0, 1, $1E, 'e' + numStr + 'p ');
				end;
				if ExtMemXmsActive then begin
					Str(ExtMemXmsAvail, numStr);
					VideoWriteText(0, 2, $1E, 'x' + numStr + ' ');
				end;
			end;
{$ENDIF}
		end;
	end;

procedure DisplayMessage(time: integer; line1, line2: TSmallString);
	begin
		if GetStatIdAt(0, 0) <> -1 then begin
			RemoveStat(GetStatIdAt(0, 0));
		end;

		if (Length(line1) <> 0) or (Length(line2) <> 0) then begin
			AddStat(0, 0, E_MESSAGE_TIMER, 0, 1, StatTemplateDefault);
			Board.Stats[Board.StatCount].P2 := Time div (TickTimeDuration + 1);
			MessageLine1 := line1;
			MessageLine2 := line2;
{$IFDEF UISCBACK}
			ScrollbackAppend(line1 + ' ' + line2);
{$ENDIF}
		end;
		ClearDisplayMessage;
	end;

procedure DamageStat(attackerStatId: integer);
	var
		oldX, oldY: integer;
	begin
		with Board.Stats[attackerStatId] do begin
			if attackerStatId = 0 then begin
				if World.Info.Health > 0 then begin
					Dec(World.Info.Health, 10);

					GameUpdateSidebar;
					DisplayMessage(100, '', 'Ouch!');

					if (not ExtensionEnabled[ExtFixPassageColorDamage])
					or (Board.Tiles[X][Y].Element = E_PLAYER) then
						Board.Tiles[X][Y].Color := $70 + (ElementDefs[E_PLAYER].Color and $0F);

					if World.Info.Health > 0 then begin
						World.Info.BoardTimeSec := 0;
						if Board.Info.ReenterWhenZapped then begin
							SoundQueue(4, #32#1#35#1#39#1#48#1#16#1);

							{ Move player to start }
							BoardRemoveTile(X, Y);
							oldX := X;
							oldY := Y;
							X := Board.Info.StartPlayerX;
							Y := Board.Info.StartPlayerY;
							DrawPlayerSurroundings(oldX, oldY, 0);
							DrawPlayerSurroundings(X, Y, 0);

							GamePaused := true;
						end;
						SoundQueue(4, #16#1#32#1#19#1#35#1);
					end else begin
						SoundQueue(5, #32#3#35#3#39#3#48#3#39#3#42#3#50#3#55#3#53#3#56#3#64#3#69#3#16#10);
					end;
				end;
			end else begin
				case Board.Tiles[X][Y].Element of
					E_BULLET: SoundQueue(3, #32#1);
					E_OBJECT: begin end;
				else
					SoundQueue(3, #64#1#16#1#80#1#48#1)
				end;
				RemoveStat(attackerStatId);
			end;
		end;
	end;

procedure BoardDamageTile(x, y: integer);
	var
		statId: integer;
	begin
		statId := GetStatIdAt(x, y);
		if statId <> -1 then begin
			DamageStat(statId);
		end else begin
			BoardRemoveTile(x, y);
		end;
	end;

procedure BoardAttack(attackerStatId: integer; x, y: integer);
	begin
		if (attackerStatId = 0) and (World.Info.EnergizerTicks > 0) then begin
			Inc(World.Info.Score, ElementDefs[Board.Tiles[x][y].Element].ScoreValue);
			GameUpdateSidebar;
		end else begin
			DamageStat(attackerStatId);
		end;

		if (attackerStatId > 0) and (attackerStatId <= CurrentStatTicked) then
			Dec(CurrentStatTicked);

		if (Board.Tiles[x][y].Element = E_PLAYER) and (World.Info.EnergizerTicks > 0) then begin
			World.Info.Score := ElementDefs[Board.Tiles[Board.Stats[attackerStatId].X][Board.Stats[attackerStatId].Y].Element]
				.ScoreValue + World.Info.Score;
			GameUpdateSidebar;
		end else begin
			BoardDamageTile(x, y);
			SoundQueue(2, #16#1);
		end;
	end;

function BoardShoot(element: byte; tx, ty, deltaX, deltaY: integer; source: integer): boolean;
	begin
{$IFDEF EXTCHEAT}
		if CheatNoShoot or (CheatNoStar and (element = E_STAR)) then begin
			if source <> SHOT_SOURCE_PLAYER then begin
				BoardShoot := false;
				exit;
			end;
		end;
{$ENDIF}
		if ElementDefs[Board.Tiles[tx + deltaX][ty + deltaY].Element].Walkable
			or (Board.Tiles[tx + deltaX][ty + deltaY].Element = E_LAVA) then
		begin
			AddStat(tx + deltaX, ty + deltaY, element, ElementDefs[element].Color, 1, StatTemplateDefault);
			with Board.Stats[Board.StatCount] do begin
				P1 := source;
				StepX := deltaX;
				StepY := deltaY;
				P2 := 100;
			end;
			BoardShoot := true;
		end else if (Board.Tiles[tx + deltaX][ty + deltaY].Element = E_BREAKABLE)
			or (
				ElementDefs[Board.Tiles[tx + deltaX][ty + deltaY].Element].Destructible
				and ((Board.Tiles[tx + deltaX][ty + deltaY].Element = E_PLAYER) = Boolean(source))
				and (World.Info.EnergizerTicks <= 0)
			) then
		begin
			BoardDamageTile(tx + deltaX, ty + deltaY);
			SoundQueue(2, #16#1);
			BoardShoot := true;
		end else begin
			BoardShoot := false;
		end;
	end;

procedure TransitionDrawBoardChange;
	begin
{$IFDEF FASTVID}
		if TransitionBlocksPerFrame = 32767 then begin
			TransitionDrawToBoard;
			exit;
		end;
{$ENDIF}
		TransitionDrawToFill(#219, $05);
		TransitionDrawToBoard;
	end;

procedure BoardEnter;
	begin
		Board.Info.StartPlayerX := Board.Stats[0].X;
		Board.Info.StartPlayerY := Board.Stats[0].Y;

		World.Info.BoardTimeSec := 0;
		GameUpdateSidebar;

{$IFDEF DEBUGWND}
		if DebugCompatEnabled then
			DebugBoardIllegalElements;
{$ENDIF}
	end;

procedure BoardPassageTeleport(x, y: integer);
	var
		oldBoard: integer;
		col: byte;
		ix, iy: integer;
		newX, newY: integer;
	begin
		col := Board.Tiles[x][y].Color;

		oldBoard := World.Info.CurrentBoard;
		BoardChange(Board.Stats[GetStatIdAt(x, y)].P3);

		newX := 0;
		for ix := 1 to BOARD_WIDTH do
			for iy := 1 to BOARD_HEIGHT do
				if (Board.Tiles[ix][iy].Element = E_PASSAGE) and (Board.Tiles[ix][iy].Color = col)
					and ((newX = 0) or (ix <> x) or (iy <> y))
				then begin
					newX := ix;
					newY := iy;
				end;

		with Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y] do begin
			if (not ExtensionEnabled[ExtFixPassageDestroy])
			or (Element = E_PLAYER) then begin
				if ExtensionEnabled[ExtFixPlayerUnpauseDamage] then begin
					Element := Board.Stats[0].Under.Element;
					Color := Board.Stats[0].Under.Color;
				end else begin
					Element := E_EMPTY;
					Color := 0;
				end;
			end;
		end;
		if newX <> 0 then begin
			Board.Stats[0].X := newX;
			Board.Stats[0].Y := newY;
		end;

		GamePaused := true;
		SoundQueue(4, #48#1#52#1#55#1#49#1#53#1#56#1#50#1#54#1#57#1#51#1#55#1#58#1#52#1#56#1#64#1);
		BoardUpdateDrawOffset;
		TransitionDrawBoardChange;
		BoardEnter;
	end;

procedure DrawPlayfieldBorder(inner: boolean);
	var
		i, j: integer;
	begin
		for i := (BOARD_DRAW_X - 1) to (BOARD_DRAW_X + BOARD_DRAW_WIDTH) do begin
			VideoWriteText(i, BOARD_DRAW_Y - 1, $1F, #220);
			VideoWriteText(i, BOARD_DRAW_Y + BOARD_DRAW_HEIGHT, $7F, #223);
		end;
		VideoWriteText(BOARD_DRAW_X - 1, BOARD_DRAW_Y + BOARD_DRAW_HEIGHT, $1F,
			#223);
		for i := BOARD_DRAW_Y to (BOARD_DRAW_Y + BOARD_DRAW_HEIGHT - 1) do begin
			VideoWriteText(BOARD_DRAW_X - 1, i, $0F, #219);
			VideoWriteText(BOARD_DRAW_X + BOARD_DRAW_WIDTH, i, $0F, #219);
			if inner then
				for j := BOARD_DRAW_X to (BOARD_DRAW_X + BOARD_DRAW_WIDTH - 1) do
					VideoWriteText(j, i, $0F,' ');
{$IFDEF NEC98}
			if VideoPc98DrawingMode > 0 then
{$ENDIF}
			VideoWriteText(BOARD_DRAW_X + BOARD_DRAW_WIDTH + 1, i + 1, $17, #221);
		end;
	end;

procedure BoardUpdateDrawOffset;
	begin
		Board.Info.DrawXOffset := Board.Stats[0].X - (BOARD_DRAW_WIDTH shr 1);
		if Board.Info.DrawXOffset < BOARD_DRAW_OX_MIN then
			Board.Info.DrawXOffset := BOARD_DRAW_OX_MIN;
		if Board.Info.DrawXOffset > BOARD_DRAW_OX_MAX then
			Board.Info.DrawXOffset := BOARD_DRAW_OX_MAX;

		Board.Info.DrawYOffset := Board.Stats[0].Y - (BOARD_DRAW_HEIGHT shr 1);
		if Board.Info.DrawYOffset < BOARD_DRAW_OY_MIN then
			Board.Info.DrawYOffset := BOARD_DRAW_OY_MIN;
		if Board.Info.DrawYOffset > BOARD_DRAW_OY_MAX then
			Board.Info.DrawYOffset := BOARD_DRAW_OY_MAX;
	end;

procedure GamePlayLoop(isTitle: boolean);
	var
		exitLoop: boolean;
		pauseBlink: boolean;
		pausePlayerStr: TSmallString;
		pausePlayerColor: integer;
	procedure GameDrawSidebar;
		var
			i: integer;
		begin
			VideoClear(1);

			if GameStateElement = E_PLAYER then begin
				VideoWriteText(0, 0, $1D, #220#220#220#220#220#220#220#220#220#220#220#220);
				VideoWriteText(0, 1, $6F, '  Commands  ');
				VideoWriteText(0, 2, $6D, #223#223#223#223#223#223#223#223#223#223#223#223);

				VideoWriteText(0, 3, $6F, ' '#24#25#26#27'       ');
				VideoWriteText(0, 4, $6E, '   Move     ');
				VideoWriteText(0, 5, $6F, ' Shift+'#24#25#26#27+' ');
				VideoWriteText(0, 6, $6B, '   Shoot    ');
				VideoWriteText(0, 7, $6E, '   Hint     ');
				VideoWriteText(1, 7, $6F,  'H');
				VideoWriteText(0, 8, $6B, '   Save Game');
				VideoWriteText(1, 8, $6F,  'S');
				VideoWriteText(0, 9, $6E, '   Restore  ');
				VideoWriteText(1, 9, $6F,  'R');
				VideoWriteText(0, 10, $6B, '   Be Quiet ');
				VideoWriteText(1, 10, $6F,  'B');
				VideoWriteText(0, 11, $6E, '   Quit     ');
				VideoWriteText(1, 11, $6F,  'Q');

				VideoWriteText(0, 12, $1D, #220#220#220#220#220#220#220#220#220#220#220#220);
				VideoWriteText(0, 13, $6F, '   Status   ');
				VideoWriteText(0, 14, $6D, #223#223#223#223#223#223#223#223#223#223#223#223);

				VideoWriteText(0, 15, $6F, 'Health      ');
				VideoWriteText(0, 16, $6F, '            ');
				VideoWriteText(0, 17, $6F, ' Gems       ');
				VideoWriteText(6, 17, $62, #4);
				VideoWriteText(0, 18, $6F, ' Ammo       ');
				VideoWriteText(6, 18, $6B, #132);
				VideoWriteText(0, 19, $6F, ' Keys       ');
				VideoWriteText(0, 20, $6F, '            ');
				VideoWriteText(0, 21, $6F, ' Score      ');
				VideoWriteText(0, 22, $6F, '            ');
				VideoWriteText(0, 23, $6F, '            ');
			end else if GameStateElement = E_MONITOR then begin
				VideoWriteText(4, 10, $1E, 'Press');
				VideoWriteText(4, 12, $1F, 'ENTER');
				VideoWriteText(1, 14, $1E, 'to continue');
			end;

			DrawPlayfieldBorder(true);
		end;
	begin
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
		GameDrawSidebar;
		GameUpdateSidebar;
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(0, 0, VideoColumns-1, VideoRows-1); {$ENDIF}

		if isTitle then
			BoardChange(0)
		else
			BoardChange(ReturnBoardId);

		BoardEnter;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := GameStateElement;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[GameStateElement].Color;

		if GameStateElement = E_MONITOR then begin
			DisplayMessage(0, '', '');
		end;

		BoardUpdateDrawOffset;
		TransitionDrawBoardChange;		

		TickTimeDuration := TickSpeed * 2;
		GamePlayExitRequested := false;
		GameControllerHasTicked := true;
		exitLoop := false;

		CurrentTick := ZRandom(100);
		CurrentStatTicked := Board.StatCount + 1;

		repeat
			if GamePaused then begin
				if SoundHasTimeElapsed(TickTimeCounter, 25) then
					pauseBlink := not pauseBlink;

				if pauseBlink then begin
					pausePlayerColor := ElementDefs[E_PLAYER].Color;
					pausePlayerStr := ElementDefs[E_PLAYER].Character;
				end else begin
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then begin
						pausePlayerColor := $0F;
						pausePlayerStr := ' ';
					end else begin
						pausePlayerStr := '';
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
					end;
				end;

				VideoWriteText(
					Board.Stats[0].X + BOARD_DRAW_X - Board.Info.DrawXOffset,
					Board.Stats[0].Y + BOARD_DRAW_Y - Board.Info.DrawYOffset,
					pausePlayerColor,
					pausePlayerStr
				);
				VideoWriteText(21, VideoRows - 1, $1E, 'Pausing...');
{$IFDEF SDL2}
				SoundIdle(IMUntilFrame);
{$ENDIF}
				InputUpdate;

				case UpCase(InputKeyPressed) of KEY_ESCAPE, 'Q': begin
					GamePromptEndPlay;
				end; end;

				if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
					ElementDefs[Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element].TouchProc(
						Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY, 0, InputDeltaX, InputDeltaY);
				end;

				if ((InputDeltaX <> 0) or (InputDeltaY <> 0))
					and ElementDefs[Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element].Walkable
				then begin
					{ Move player }
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then
						MoveStat(0, Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY)
					else begin
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						Inc(Board.Stats[0].X, InputDeltaX);
						Inc(Board.Stats[0].Y, InputDeltaY);
						Board.Stats[0].Under.Element :=  Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element;
						Board.Stats[0].Under.Color :=  Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color;
						Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
						Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						DrawPlayerSurroundings(Board.Stats[0].X, Board.Stats[0].Y, 0);
						DrawPlayerSurroundings(Board.Stats[0].X - InputDeltaX, Board.Stats[0].Y - InputDeltaY, 0);
					end;

					{ Unpause }
					GamePaused := false;
					GameControllerHasTicked := true;
					CurrentTick := ZRandom(100);
					CurrentStatTicked := Board.StatCount + 1;
					World.Info.IsSave := true;
					ClearDisplayMessage;
				end;
			end else begin { not GamePaused }
				if CurrentStatTicked <= Board.StatCount then begin
					with Board.Stats[CurrentStatTicked] do begin
						if (Cycle <> 0) and ((CurrentTick mod Cycle) = (CurrentStatTicked mod Cycle)) then
							ElementDefs[Board.Tiles[X][Y].Element].TickProc(CurrentStatTicked);

						Inc(CurrentStatTicked);

{$IFDEF EXTCHEAT}
						if CheatFreeze then
							CurrentStatTicked := Board.StatCount + 1;
{$ENDIF}
					end;
				end;
			end;

			if (CurrentStatTicked > Board.StatCount) and not GamePlayExitRequested then begin
				{ all stats ticked }
				if not GameControllerHasTicked then begin
					if GameStateElement = E_MONITOR then begin
						ElementMonitorTick(-1);
					end else begin
						case UpCase(InputKeyPressed) of KEY_ESCAPE, 'Q': begin
							GamePromptEndPlay;
						end; end;
					end;
				end;
				GameControllerHasTicked := true;

				if SoundHasTimeElapsed(TickTimeCounter, TickTimeDuration) then begin
					InputUpdate;
					if (GameStateELement = E_PLAYER) and NeuromotorAssist and (InputKeyPressed = #0) then begin
						SoundIdle(IMUntilFrame);
					end else begin
						{ next cycle }
						Inc(CurrentTick);
						if CurrentTick > 420 then
							CurrentTick := 1;
						CurrentStatTicked := 0;
					end;

					{ In ZZT 3.2, InputUpdate; is here. }
				end else begin
					SoundIdle(IMUntilPit);
				end;
			end;
		until (exitLoop or GamePlayExitRequested) and GamePlayExitRequested;

		SoundClearQueue;

		if GameStateElement = E_PLAYER then begin
			if World.Info.Health <= 0 then begin
				HighScoresAdd(World.Info.Score);
			end;
		end else if GameStateElement = E_MONITOR then begin
		end;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;

		SoundBlockQueueing := false;
	end;

function GameIsWorldLoaded: boolean;
	begin
		if Length(World.Info.Name) = 0 then begin
			if FileExists(StartupWorldFileName + '.SZT') then begin
				GameIsWorldLoaded := true;

				if not WorldLoad(StartupWorldFileName, '.SZT', true) then begin
					WorldCreate;
					GameIsWorldLoaded := false;
				end;

				ReturnBoardId := World.Info.CurrentBoard;
				JustStarted := false;
			end else begin
				GameIsWorldLoaded := false;
			end;
		end else begin
			GameIsWorldLoaded := true;
		end;
	end;

procedure GamePlayVideoInstall;
	begin
{$IFDEF SDL2}
{		if not GameVideoInstall(VIDEO_MODE_RESIZABLE, VIEW_PLAY_LARGE) then }
{$ENDIF}
{		if not GameVideoInstall(VIDEO_MODE_80X50, VIEW_PLAY_LARGE) then }
{		if not GameVideoInstall(VIDEO_MODE_80X43, VIEW_PLAY_LARGE) then }
		if not GameVideoInstall(VIDEO_MODE_40X25, VIEW_PLAY) then
		if not GameVideoInstall(VIDEO_MODE_80X25, VIEW_PLAY) then begin end;
	end;

procedure GameTitleLoop;
	var
		runPlay: boolean;
		runTitle: boolean;
		returningFromGame: boolean;	
		needsTitleRefresh: boolean;
	label LoadWorldSelect;
	begin
		GameTitleExitRequested := false;
		GamePlayStartRequested := false;
		returningFromGame := false;
		needsTitleRefresh := true;
		repeat
			runTitle := false;
			if not GamePlayStartRequested then begin
				if returningFromGame then begin
					if GameVideoInstall(VIDEO_MODE_80X25, VIEW_TITLE) then begin end;
					returningFromGame := false;
				end;
				runPlay := false;
				if needsTitleRefresh then begin
					VideoClear(0);
					GameDisplayResourceImage('MAINMENU', 0, 0, 80, 25);
{$IFNDEF EDITOR}
					VideoWriteText(1, 18, $0A, #196#196#196#196#196#196#196#196#196#196#196#196
						+ #196#196#196#196#196#196#196#196#196);
{$ENDIF}
{$IFNDEF WEBBROW}
					VideoWriteText(1, 12, $0A, #196#196#196#196#196#196#196#196#196#196#196#196
						+ #196#196#196#196#196#196#196#196#196);
{$ENDIF}
				end;
				needsTitleRefresh := true;
				InputReadWaitKey;
				case UpCase(InputKeyPressed) of
					'W': begin
LoadWorldSelect:
						if GameWorldLoad('.SZT') then begin
							if ZxtShowFlagError(false) then begin end;
							ReturnBoardId := World.Info.CurrentBoard;
							returningFromGame := true;
							runTitle := true;
						end else begin
							needsTitleRefresh := false;
						end;
					end;
					'P': begin
						if GameIsWorldLoaded then begin
							if World.Info.IsSave and not DebugEnabled then begin
								runPlay := WorldLoad(World.Info.Name, '.SZT', false);
								ReturnBoardId := World.Info.CurrentBoard;
							end else begin
								runPlay := true;
							end;
						end else begin
							if GameWorldLoad('.SZT') then begin
								ReturnBoardId := World.Info.CurrentBoard;
								returningFromGame := true;
								runPlay := true;
							end else begin
								needsTitleRefresh := false;
							end;
						end;
						runTitle := runPlay;
					end;
					'R': begin
						if GameWorldLoad('.SAV') then begin
							if ZxtShowFlagError(false) then begin end;
							GamePlayVideoInstall;
							ReturnBoardId := World.Info.CurrentBoard;
							BoardChange(ReturnBoardId);
							runPlay := true;
							GamePlayStartRequested := true;
						end;
					end;
					'I': begin
						if GameIsWorldLoaded then begin
							runTitle := true;
						end else begin
							goto LoadWorldSelect;
						end;
					end;
					'Q', KEY_ESCAPE: begin
						GameTitleExitRequested := PromptYesNo('Quit ZZT?  ', true, $4F);
					end;
					'H': begin
						needsTitleRefresh := false;
						if GameIsWorldLoaded then begin
							HighScoresLoad;
							HighScoresDisplay(1);
						end;
					end;
{$IFDEF WEBBROW}
					'B': begin
						WebBrowserLoop;
					end;
{$ENDIF}
					'O': begin
						needsTitleRefresh := false;
						GameOptionsScreen(false);
					end;
					'|': begin
						GameDebugPrompt;
					end;
{$IFDEF EDITOR}
					'E': begin
						EditorLoop;
						ReturnBoardId := World.Info.CurrentBoard;
						returningFromGame := true;
					end;
{$ENDIF}
				end;
			end;
{$IFDEF UISCBACK}
			ScrollbackClear(-1);
{$ENDIF}
			if runTitle then begin
				GamePlayVideoInstall;
				GameStateElement := E_MONITOR;
				GamePaused := false;
				GamePlayLoop(true);
				returningFromGame := true;
			end;
			if runPlay or GamePlayStartRequested then begin
				GameStateElement := E_PLAYER;
				GamePaused := true;
				if (not runTitle) and (not GamePlayStartRequested) then begin
					GamePlayVideoInstall;
				end;
				GamePlayStartRequested := false;
				GamePlayLoop(false);
				returningFromGame := true;
			end;
		until GameTitleExitRequested <> false;
	end;

procedure ResetCachedLinePos;
	begin
{$IFDEF EDITOR}
		FileBoardCachedLinePos := 1;
		FileTextCachedLinePos := 1;
{$ENDIF}
		FileWorldCachedLinePos := 1;
		FileSaveCachedLinePos := 1;
	end;

end.
