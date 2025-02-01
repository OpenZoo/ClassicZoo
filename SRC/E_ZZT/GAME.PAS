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
unit Game;

interface
	uses GameVars, TxtWind;
	procedure BoardChange(boardId: integer);
	procedure BoardCreate;
	procedure WorldCreate;
	procedure TransitionDrawToFill(chr: char; color: integer);
	procedure BoardDrawTile(x, y: integer);
	procedure BoardDrawBorder;
	procedure TransitionDrawToBoard;
	procedure PauseOnError;
	procedure WorldUnload;
	function WorldLoad(filename, extension: TString50; titleOnly: boolean): boolean;
	procedure WorldSave(filename, extension: TString50);
	procedure GameWorldSave(prompt: TString50; var filename: TString50; extension: TString50);
	function GameWorldLoad(extension: TString50): boolean;
	procedure AddStat(tx, ty: integer; element: byte; color, tcycle: integer; template: TStat);
	procedure RemoveStat(statId: integer);
	function BoardPrepareTileForPlacement(x, y: integer): boolean;
	procedure MoveStat(statId: integer; newX, newY: integer);
	procedure DamageStat(attackerStatId: integer);
	procedure BoardDamageTile(x, y: integer);
	procedure BoardAttack(attackerStatId: integer; x, y: integer);
	function BoardShoot(element: byte; tx, ty, deltaX, deltaY: integer; source: integer): boolean;
	procedure TransitionDrawBoardChange;
	procedure GameUpdateSidebar;
	procedure GamePlayLoop(boardChanged: boolean);
	procedure DisplayMessage(ticks: integer; message: string);
	procedure BoardEnter;
	procedure BoardPassageTeleport(x, y: integer);
{$IFDEF ZDEMOVAL}
	procedure GameValidateRun;
{$ENDIF}
	procedure GameTitleLoop;
	procedure ResetCachedLinePos;
const
	LFSR11_START = 42;
	ColorNames: array[1 .. 7] of string[8] =
		('Blue', 'Green', 'Cyan', 'Red', 'Purple', 'Yellow', 'White');
	{}
	DiagonalDeltaX: array[0 .. 7] of integer = (-1, 0, 1, 1, 1, 0, -1, -1);
	DiagonalDeltaY: array[0 .. 7] of integer = (1, 1, 1, 0, -1, -1, -1, 0);
	NeighborDeltaX: array[0 .. 3] of integer = (0, 0, -1, 1);
	NeighborDeltaY: array[0 .. 3] of integer = (-1, 1, 0, 0);
	{}
	TileBorder: TTile = (Element: E_NORMAL; Color: $0E);
	TileBoardEdge: TTile = (Element: E_BOARD_EDGE; Color: $00);
	StatTemplateDefault: TStat = (
		X: 0; Y: 0; StepX: 0; StepY: 0;
		Cycle: 0; P1: 0; P2: 0; P3: 0;
		Follower: -1; Leader: -1;
                Under: (Element: E_EMPTY; Color: $00);
	{$IFDEF RAWMEM}
        {$IFDEF CPU64}
                UnusedData: 0; DataPos: 0; DataLen: 0; Unused1: 0; Unused2: 0; Data: nil
        {$ELSE}
                Data: nil; DataPos: 0; DataLen: 0
        {$ENDIF}
	{$ELSE}
                Data: nil; DataPos: 0; DataLen: 0
	{$ENDIF}
	);
	LineChars: string[16] = #249#208#210#186#181#188#187#185#198#200#201#204#205#202#203#206;

implementation
uses
{$IFDEF DEBUGWND} DebugWnd, {$ENDIF}
{$IFNDEF RAWMEM} GameVSer, {$ENDIF}
{$IFDEF WEBBROW} WebBrow, {$ENDIF}
{$IFDEF UISCBACK} UiScBack, {$ENDIF}
Dos, GameSh, Cheats, GameIo,
FileOps, FileSel, FileSys, GameConf, ExtMem, ZVideo, Sounds, ZDemo, TimerSys,
ZInput, Elements, Editor, Oop, Sidebar;

function LFSR11UpdateSeed(var seed: word; var tx, ty: byte): boolean;
	begin
		seed := (seed shr 1) xor ((-(seed and 1)) and $740);
		tx := (seed - 1) and $3F;
		ty := ((seed - 1) shr 6) and $3F;
		LFSR11UpdateSeed := seed = LFSR11_START;
	end;

procedure BoardChange(boardId: integer);
	begin
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;
		BoardClose;
		BoardOpen(boardId);
	end;

procedure BoardCreate;
	var
		ix, iy: integer;
	begin
		Board.Name := '';
		Board.Info.Message := '';
		Board.Info.MaxShots := 255;
		Board.Info.IsDark := false;
		Board.Info.ReenterWhenZapped := false;
		Board.Info.TimeLimitSec := 0;

		{ Unrolled - takes up a bit less code. }
		Board.Info.NeighborBoards[0] := 0;
		Board.Info.NeighborBoards[1] := 0;
		Board.Info.NeighborBoards[2] := 0;
		Board.Info.NeighborBoards[3] := 0;

		FillChar(Board.Tiles, SizeOf(Board.Tiles), 0);

		for ix := 0 to BOARD_WIDTH+1 do begin
			Board.Tiles[ix][0] := TileBoardEdge;
			Board.Tiles[ix][BOARD_HEIGHT+1] := TileBoardEdge;
		end;
		for iy := 0 to BOARD_HEIGHT+1 do begin
			Board.Tiles[0][iy] := TileBoardEdge;
			Board.Tiles[BOARD_WIDTH+1][iy] := TileBoardEdge;
		end;

		for ix := 1 to BOARD_WIDTH do begin
			Board.Tiles[ix][1] := TileBorder;
			Board.Tiles[ix][BOARD_HEIGHT] := TileBorder;
		end;
		for iy := 1 to BOARD_HEIGHT do begin
			Board.Tiles[1][iy] := TileBorder;
			Board.Tiles[BOARD_WIDTH][iy] := TileBorder;
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
	end;

procedure WorldCreate;
	var
		i: integer;
	begin
		InitElementsGame;
		World.BoardCount := 0;
		WorldExt.BoardLen[0] := 0;
		InitEditorStatSettings;
		ResetMessageNotShownFlags;
		BoardCreate;
		World.Info.IsSave := false;
		World.Info.CurrentBoard := 0;
		World.Info.Ammo := 0;
		World.Info.Gems := 0;
		World.Info.Health := 100;
		World.Info.EnergizerTicks := 0;
		World.Info.Torches := 0;
		World.Info.TorchTicks := 0;
		World.Info.Score := 0;
		World.Info.BoardTimeSec := 0;
		World.Info.BoardTimeHsec := 0;
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
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
		seed := LFSR11_START;
		i := 0;
		repeat
			if (tx < 60) and (ty < 25) then begin
				VideoWriteText(tx, ty, color, chr);
{$IFDEF FASTVID}
				Inc(i);
				if i >= TransitionBlocksPerFrame then begin
					SoundIdle(IMUntilFrame);
					i := 0;
				end;
{$ENDIF}
			end;
		until LFSR11UpdateSeed(seed, tx, ty);

		if (tx < 60) and (ty < 25) then
			VideoWriteText(tx, ty, color, chr);
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(0, 0, 59, 24); {$ENDIF}
	end;

procedure BoardDrawTile(x, y: integer);
	var
		ch: byte;
	begin
		with Board.Tiles[x][y] do begin
			if not Board.Info.IsDark
				or (ElementDefs[Element].VisibleInDark)
				or (
					(World.Info.TorchTicks > 0)
					and ((Sqr(Board.Stats[0].X - x) + Sqr(Board.Stats[0].Y - y) * 2) < TORCH_DIST_SQR)
				) or ForceDarknessOff then
			begin
				if Element = E_EMPTY then
					VideoWriteText(x - 1, y - 1, $0F, ' ')
				else if (Element <= MAX_ELEMENT) and ElementDefs[Element].HasDrawProc then begin
					ElementDefs[Element].DrawProc(x, y, ch);
{$IFDEF EXTCHEAT}
					VideoWriteText(x - 1, y - 1, Color xor CheatColorModifiers[Element], Chr(ch));
{$ELSE}
					VideoWriteText(x - 1, y - 1, Color, Chr(ch));
{$ENDIF}
				end else if Element < E_TEXT_MIN then
{$IFDEF EXTCHEAT}
					VideoWriteText(x - 1, y - 1, Color xor CheatColorModifiers[Element],
						ElementDefs[Element].Character)
{$ELSE}
					VideoWriteText(x - 1, y - 1, Color, ElementDefs[Element].Character)
{$ENDIF}
				else begin
					{ Text drawing }
					if Element = E_TEXT_WHITE then
						VideoWriteText(x - 1, y - 1, $0F, Chr(Color))
{$IFDEF NEC98}
					else if (VideoPc98DrawingMode < 2) or VideoMonochrome then
{$ELSE}
					else if VideoMonochrome then
{$ENDIF}
						VideoWriteText(x - 1, y - 1, ((Element - E_TEXT_MIN) + 1) shl 4, Chr(Color))
					else
						VideoWriteText(x - 1, y - 1, (((Element - E_TEXT_MIN) + 1) shl 4) + $F, Chr(Color));
				end
			end else begin
				{ Darkness }
				VideoWriteText(x - 1, y - 1, $07, #176);
			end;
		end;
	end;

procedure BoardDrawBorder;
	var
		ix, iy: integer;
	begin
		for ix := 1 to BOARD_WIDTH do begin
			BoardDrawTile(ix, 1);
			BoardDrawTile(ix, BOARD_HEIGHT);
		end;

		for iy := 1 to BOARD_HEIGHT do begin
			BoardDrawTile(1, iy);
			BoardDrawTile(BOARD_WIDTH, iy);
		end;
	end;

procedure TransitionDrawToBoard;
	var
		i, seed: word;
		tx, ty: byte;
	begin
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
		BoardDrawBorder;

		i := 0;
		seed := LFSR11_START;
		repeat
			if (tx < 60) and (ty < 25) then begin
				BoardDrawTile(tx+1, ty+1);
{$IFDEF FASTVID}
				Inc(i);
				if i >= TransitionBlocksPerFrame then begin
					SoundIdle(IMUntilFrame);
					i := 0;
				end;
{$ENDIF}
			end;
		until LFSR11UpdateSeed(seed, tx, ty);

		if (tx < 60) and (ty < 25) then
			BoardDrawTile(tx+1, ty+1);
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(0, 0, 59, 24); {$ENDIF}
	end;

procedure PauseOnError;
	begin
		SoundQueue(1, SoundParse('s004x114x9'));
		AccurateDelay(2000);
	end;


procedure GameDemoShowError;
	var
		numStr: TString50;
		textWindow: TTextWindowState;
{$IFDEF ZDEMOVAL}
		demoValFile: text;
{$ENDIF}
	begin
		Str(DemoErrorCode, textWindow.Title);
		textWindow.Title := 'Demo Error #' + textWindow.Title;
		TextWindowInitState(textWindow);
		if DemoIsPlaying then
			TextWindowAppend(textWindow, 'Playback has been stopped!')
		else
			TextWindowAppend(textWindow, 'Recording has been stopped!');
		TextWindowAppend(textWindow, '');
		TextWindowAppend(textWindow, '$Debug information:');
		TextWindowAppend(textWindow, '');
		Str(DemoCommandsFetched, numStr);
		TextWindowAppend(textWindow, 'Position: ' + numStr);

{$IFDEF ZDEMOVAL}
		Assign(demoValFile, 'RESULT.ZZV');
		Rewrite(demoValFile);
		WriteLn(demoValFile, 'Error');
		if TextWindowWrite(textWindow, demoValFile) then begin end;
		DemoFlushFile(demoValFile);
		Close(demoValFile);
{$ELSE}
		TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, 0);
		TextWindowDrawClose(textWindow);
{$ENDIF}
		TextWindowFree(textWindow);

		DemoErrorCode := 0;
	end;

procedure TimeToString(timeHs: longint; var fullStr: TString50);
	var
		i: integer;
		numStr: TString50;
	begin
		if timeHs < 0 then begin
			Str(i, fullStr);
			fullStr := fullStr + ' ???';
			exit;
		end;

		i := timeHs mod 100;
		Str(i:2, numStr);
		if numStr[1] = ' ' then numStr[1] := '0';
		fullStr := '.' + numStr;
		i := (timeHs div 100) mod 60;
		Str(i:2, numStr);
		if numStr[1] = ' ' then numStr[1] := '0';
		fullStr := ':' + numStr + fullStr;
		i := (timeHs div 6000) mod 60;
		Str(i:2, numStr);
		if timeHs >= 360000 then begin
			if numStr[1] = ' ' then numStr[1] := '0';
		end;
		fullStr := numStr + fullStr;
		if timeHs >= 360000 then begin
			i := (timeHs div 360000);
			Str(i, numStr);
			fullStr := numStr + ':' + fullStr;
		end;
	end;

procedure GameDemoShowSuccess;
	var
		timeHs: longint;
		i: integer;
		numStr: TString50;
		fullStr: TString50;
		textWindow: TTextWindowState;
{$IFDEF ZDEMOVAL}
		demoValFile: text;
{$ENDIF}
	begin
		textWindow.Title := 'Demo Playback Complete';
		TextWindowInitState(textWindow);

		{ Calculate run time. }
		{ 1 PIT tick = 55ms }
		timeHs := ((DemoPitTicksLast - DemoPitTicksFirst) * 11) div 2;
		TimeToString(timeHs, numStr);
		Str(DemoPitTicksLast - DemoPitTicksFirst, fullStr);
		TextWindowAppend(textWindow, 'Run time: ' + numStr + ' (' + fullStr + ' ticks)');
		{ Calculate recording time. }
		timeHs := (DemoPitTicks * 11) div 2;
		TimeToString(timeHs, numStr);
		Str(DemoPitTicks, fullStr);
		TextWindowAppend(textWindow, 'Recording time: ' + numStr + ' (' + fullStr + ' ticks)');
		{ Seed, etc. }
		Str(World.Info.Score, numStr);
		TextWindowAppend(textWindow, 'Score: ' + numStr);
		Str(DemoStartSeed, numStr);
		TextWindowAppend(textWindow, 'Seed: ' + numStr);
		Str(TickSpeed, numStr);
		TextWindowAppend(textWindow, 'Tick speed: ' + numStr);

{$IFDEF ZDEMOVAL}
		Assign(demoValFile, 'RESULT.ZZV');
		Rewrite(demoValFile);
		WriteLn(demoValFile, 'Success');
		if TextWindowWrite(textWindow, demoValFile) then begin end;
		DemoFlushFile(demoValFile);
		Close(demoValFile);
{$ELSE}
		TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, 0);
		TextWindowDrawClose(textWindow);
{$ENDIF}
		TextWindowFree(textWindow);

		DemoErrorCode := 0;
	end;

procedure WorldUnload;
	var
		i: integer;
	begin
		BoardClose;
		for i := 0 to World.BoardCount do
			ExtMemFree(WorldExt.BoardData[i], WorldExt.BoardLen[i]);
	end;

function WorldLoad(filename, extension: TString50; titleOnly: boolean): boolean;
	var
		f: file;
		ptr: pointer;
		boardId: integer;
		loadProgress: integer;
		newLength: longint;
	label OnError;
	begin
		WorldLoad := false;
		loadProgress := 0;

		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(62, 5, $1F, 'Loading.....');

		AssignFSys(f, filename + extension);
		Reset(f, 1);

		if not DisplayIOError then begin
			WorldUnload;
			BlockRead(f, IoTmpBuf^, WORLD_FILE_HEADER_SIZE);

			if not DisplayIOError then begin
				ptr := IoTmpBuf;
				Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
				AdvancePointer(ptr, SizeOf(World.BoardCount));
{$IFDEF ENDIAN_BIG}
				World.BoardCount := LEtoN(World.BoardCount);
{$ENDIF}

				if World.BoardCount < 0 then begin
					if World.BoardCount <> -1 then begin
						VideoWriteText(62, 5, $1E, 'You need a newer');
						VideoWriteText(63, 6, $1E, 'version of ZZT!');
						goto OnError;
					end else begin
						Move(ptr^, World.BoardCount, SizeOf(World.BoardCount));
						AdvancePointer(ptr, SizeOf(World.BoardCount));
{$IFDEF ENDIAN_BIG}
						World.BoardCount := LEtoN(World.BoardCount);
{$ENDIF}
					end;
				end;

				if (World.BoardCount > MAX_BOARD) or (World.BoardCount < 0) then begin
					VideoWriteText(62, 5, $1E, 'Too many boards!');
					World.BoardCount := 0;
					exit;
				end;

{$IFDEF RAWMEM}
				Move(ptr^, World.Info, SizeOf(World.Info));
				AdvancePointer(ptr, SizeOf(World.Info));
{$ELSE}
				CopyWorldInfoToLocal(ptr);
{$ENDIF}

				if titleOnly then begin
					World.BoardCount := 0;
					World.Info.CurrentBoard := 0;
					World.Info.IsSave := true;
				end;

				for boardId := 0 to World.BoardCount do begin
					SidebarAnimateLoading(loadProgress);
					BlockRead(f, WorldExt.BoardLen[boardId], 2);
{$IFDEF ENDIAN_BIG}
					WorldExt.BoardLen[boardId] := LEtoN(WorldExt.BoardLen[boardId]);
{$ENDIF}

					{ Try to un-corrupt Super Locked worlds. }
					if (boardId = World.BoardCount) and (WorldExt.BoardLen[boardId] <= 51) then begin
						newLength := FileSize(f) - FilePos(f);
						if (newLength > 51) and (newLength <= 32767) then
							WorldExt.BoardLen[boardId] := newLength;
					end;

					if ExtMemGet(WorldExt.BoardData[boardId], WorldExt.BoardLen[boardId]) then begin
						case EnsureIoTmpBufSize(WorldExt.BoardLen[boardId]) of
							0, 1: begin end;
							2: RunError(203);
						end;

						BlockRead(f, IoTmpBuf^, WorldExt.BoardLen[boardId]);
						ExtMemWrite(WorldExt.BoardData[boardId], IoTmpBuf^, WorldExt.BoardLen[boardId]);
					end else RunError(203);
				end;

				BoardOpen(World.Info.CurrentBoard);
				LoadedGameFileName := filename;
				WorldLoad := true;

				HighScoresLoad;

				if HighCompatAuto then
					HighCompat := (World.Info.Name = 'PHOEBUS');
				if CleenModeAuto then
					CleenMode := (World.Info.Name = 'obelisk')
						or (World.Info.Name = 'CYBERPRG');
{$IFDEF DEBUGWND}
				{ BoardEnter is only called for play-boards, not title-boards. }
				if titleOnly and DebugCompatEnabled then
					DebugBoardIllegalElements;
{$ENDIF}
				SidebarClearLine(5);
			end;
		end;

	OnError:
		Close(f);
	end;

procedure WorldSave(filename, extension: TString50);
	var
		f: file;
		i: integer;
		unk1: integer;
		ptr: pointer;
		version: integer;
	label OnError;
	begin

		{ If a demo is being recorded, save the demo too. }
		if DemoIsRecording then begin
			SaveCopyDemoFiles(filename);
		end;

		{ If a demo is being played, don't save the game again,
		  as usually you don't want it to be doing file ops when
		  replaying a demo.
		  If we're replaying a demo, this might also be the end of
		  one segment, meaning the rest of the gameplay starts with
		  a restore. Call DemoRestartHere to check if that's the
		  case and to set GameRestartNeeded if so.}
		if DemoIsPlaying then begin
			{BoardClose;
			BoardOpen(World.Info.CurrentBoard);}
			DemoRestartHere;
			Exit;
		end;

		BoardClose;
		VideoWriteText(63, 5, $1F, 'Saving...');

		AssignFSys(f, filename + extension);
		Rewrite(f, 1);

		if not DisplayIOError then begin
			ptr := IoTmpBuf;
			FillChar(IoTmpBuf^, WORLD_FILE_HEADER_SIZE, 0);
			version := -1;
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
				BlockWrite(f, SwapEndian(WorldExt.BoardLen[i]), 2);
{$ELSE}
				BlockWrite(f, WorldExt.BoardLen[i], 2);
{$ENDIF}
				if DisplayIOError then goto OnError;

				ExtMemRead(WorldExt.BoardData[i], IoTmpBuf^, WorldExt.BoardLen[i]);
				BlockWrite(f, IoTmpBuf^, WorldExt.BoardLen[i]);
				if DisplayIOError then goto OnError;
			end;
		end;

		BoardOpen(World.Info.CurrentBoard);
		SidebarClearLine(5);
		Close(f);
		exit;

	OnError:
		Close(f);
		Erase(f);
		BoardOpen(World.Info.CurrentBoard);
		SidebarClearLine(5);
	end;

procedure GameWorldSave(prompt: TString50; var filename: TString50; extension: TString50);
	var
		newFilename: TString50;
	begin
		newFilename := filename;
		SidebarPromptFilename(prompt, extension, newFilename, PROMPT_ALPHANUM);
		if (InputKeyPressed <> KEY_ESCAPE) and (Length(newFilename) <> 0)
		and ((filename = newFilename) or (extension <> '.ZZT') or OverwriteCheck(newFilename + extension)) then begin
			filename := newFilename;
			if extension = '.ZZT' then
				World.Info.Name := filename;
			WorldSave(filename, extension);
		end;
	end;

function GameWorldLoad(extension: TString50): boolean;
	var
		entryName: string;
		demoOK: boolean;
	begin
		{ As directory listings can take up a lot of memory, }
		{ free IoTmpBuf for the duration - the data will be }
		{ unloaded later anyway. - asie }
		FreeMem(IoTmpBuf, IoTmpBufSize);

		GameWorldLoad := false;
		if extension = '.ZZT' then
			entryName := FileSelect('ZZT Worlds', extension, FileWorldCachedLinePos)
		else
			entryName := FileSelect('Saved Games', extension, FileSaveCachedLinePos);

		GetMem(IoTmpBuf, IoTmpBufSize);

		if Length(entryName) > 0 then begin
			if WorldLoad(entryName, extension, false) then begin
				GameWorldLoad := true;
				{ Try to resume recording a demo if the save game comes with one. 
				  TODO: Only if a savegame. }
				demoOK := DemoRestoreRecord(entryName);
			end else begin
				WorldCreate;
				PauseOnError;
				TransitionDrawToFill(#219, $44);
			end;
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
				with Board.Stats[Board.StatCount] do begin
					GetMem(Data, template.DataLen);
					Move(template.Data^, Data^, template.DataLen);
				end;
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
				with Board.Stats[i] do begin
					if Follower >= statId then begin
						if Follower = statId then
							Follower := -1
						else
							Dec(Follower);
					end;

					if Leader >= statId then begin
						if Leader = statId then
							Leader := -1
						else
							Dec(Leader);
					end;
				end;
			end;

			for i := (statId + 1) to Board.StatCount do
				Board.Stats[i - 1] := Board.Stats[i];
			Dec(Board.StatCount);
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
				Board.Tiles[x][y].Element := E_EMPTY;
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
		ix, iy: integer;
		oldX, oldY: integer;
	begin
		with Board.Stats[statId] do begin
			oldX := X;
			oldY := Y;

			iUnder := Under;
{$IFDEF MEMBOUND}
			if TileOutOfBounds(newX, newY) then begin
				Board.Tiles[oldX][oldY] := iUnder;
				X := newX;
				Y := newY;
				BoardDrawTile(oldX, oldY);
			end else begin
{$ENDIF}
			Under := Board.Tiles[newX][newY];

			with Board.Tiles[oldX][oldY] do begin
				if Element = E_PLAYER then
					Board.Tiles[newX][newY].Color := Color
				else if Board.Tiles[newX][newY].Element = E_EMPTY then
					Board.Tiles[newX][newY].Color := Color and $0F
				else
					Board.Tiles[newX][newY].Color := (Color and $0F)
						or (Board.Tiles[newX][newY].Color and $70);

				Board.Tiles[newX][newY].Element := Element;
				Board.Tiles[oldX][oldY] := iUnder;
			end;

			X := newX;
			Y := newY;

			BoardDrawTile(X, Y);
			BoardDrawTile(oldX, oldY);
{$IFDEF MEMBOUND}
			end;
{$ENDIF}

{$IFDEF DEBUGWND}
			if DebugUndefEnabled and ((X > (BOARD_WIDTH+1)) or (Y > (BOARD_HEIGHT+1))) then begin
				DebugShowElementMessage('Move out of bounds!', X, Y);
			end;
{$ENDIF}

			if (statId = 0) and Board.Info.IsDark and (World.Info.TorchTicks > 0) then begin
				if (Sqr(oldX-X) + Sqr(oldY-Y)) = 1 then begin
					for ix := (X - TORCH_DX - 3) to (X + TORCH_DX + 3) do
						if (ix >= 1) and (ix <= BOARD_WIDTH) then
							for iy := (Y - TORCH_DY - 3) to (Y + TORCH_DY + 3) do
								if (iy >= 1) and (iy <= BOARD_HEIGHT) then
									if (((Sqr(ix-oldX))+(Sqr(iy-oldY)*2)) < TORCH_DIST_SQR) xor
										(((Sqr(ix-X))+(Sqr(iy-Y)*2)) < TORCH_DIST_SQR) then
										BoardDrawTile(ix, iy);
				end else begin
					DrawPlayerSurroundings(oldX, oldY, 0);
					DrawPlayerSurroundings(X, Y, 0);
				end;
			end;

		end;
	end;

procedure GameDemoUpdateSidebar;
	var
		numStr: string[8];
	procedure DrawHighlight(x, y, color: integer; sv: string; cond: boolean);
		begin
			if cond then color := color or $0F;
			VideoWriteText(x, y, color, sv);
		end;
	procedure DrawArrowHighlight(x, y: integer; sv: string; cond: boolean);
		begin
			DrawHighlight(x, y, $30, sv, cond and (not InputShiftPressed));
			DrawHighlight(x, y + 1, $70, sv, cond and InputShiftPressed);
		end;
	begin
		{TODO? Instead of file position, use relative time?}
		Str(((DemoFilePos * 100) div DemoFileSize), numStr);
		VideoWriteText(72, 16, $1E, numStr + '% ');

		DrawHighlight(63, 14, $70, 'T', InputKeyPressed = 'T');
		DrawHighlight(63, 22, $30, 'P', InputKeyPressed = 'P');

		DrawHighlight(62, 19, $70, 'Shift', InputShiftPressed);

		DrawArrowHighlight(68, 18, #24, (InputDeltaX = 0) and (InputDeltaY < 0));
		DrawArrowHighlight(69, 18, #25, (InputDeltaX = 0) and (InputDeltaY > 0));
		DrawArrowHighlight(70, 18, #26, (InputDeltaX > 0) and (InputDeltaY = 0));
		DrawArrowHighlight(71, 18, #27, (InputDeltaX < 0) and (InputDeltaY = 0));
	end;

procedure GameUpdateSidebar;
	var
		numStr: string[8];
		i: integer;
	begin
		if GameStateElement = E_PLAYER then begin
			if Board.Info.TimeLimitSec > 0 then begin
				VideoWriteText(64, 6, $1E, '   Time:');
				Str(Board.Info.TimeLimitSec - World.Info.BoardTimeSec, numStr);
				VideoWriteText(72, 6, $1E, numStr + ' ');
			end else begin
				SidebarClearLine(6);
			end;

			if World.Info.Health < 0 then
				World.Info.Health := 0;

			i := $77;
			if DemoIsPlaying then i := $FA
			else if DemoIsRecording then i := $74;
			VideoWriteText(73, 1, i, #7);

			Str(World.Info.Health, numStr);
			VideoWriteText(72, 7, $1E, numStr + ' ');
			Str(World.Info.Ammo, numStr);
			VideoWriteText(72, 8, $1E, numStr + '  ');
			Str(World.Info.Torches, numStr);
			VideoWriteText(72, 9, $1E, numStr + ' ');
			Str(World.Info.Gems, numStr);
			VideoWriteText(72, 10, $1E, numStr + ' ');
			Str(World.Info.Score, numStr);
			VideoWriteText(72, 11, $1E, numStr + ' ');

			if World.Info.TorchTicks = 0 then
				VideoWriteText(75, 9, $16, '    ')
			else begin
				for i := 2 to 5 do begin
					if i <= ((World.Info.TorchTicks * 5) div TORCH_DURATION) then
						VideoWriteText(73 + i, 9, $16, #177)
					else
						VideoWriteText(73 + i, 9, $16, #176);
				end;
			end;

			for i := 1 to 7 do begin
				if World.Info.Keys[i] then
					VideoWriteText(71 + i, 12, $18 + i, ElementDefs[E_KEY].Character)
				else
					VideoWriteText(71 + i, 12, $1F, ' ');
			end;

			if not DemoIsPlaying then begin
			if SoundEnabled then
				VideoWriteText(65, 15, $1F, ' Be quiet')
			else
				VideoWriteText(65, 15, $1F, ' Be noisy');
			end;

{$IFDEF MSDOS}
			if DebugEnabled then begin
				Str(MemAvail, numStr);
				VideoWriteText(62, 3, $1E, 'm' + numStr + ' ');
{$IFNDEF NOEXTMEM}
				if ExtMemEmsActive then begin
					Str(ExtMemEmsAvailPages, numstr);
					VideoWriteText(70, 3, $1E, 'e' + numStr + 'p ');
				end;
				if ExtMemXmsActive then begin
					Str(ExtMemXmsAvail, numStr);
					VideoWriteText(62, 4, $1E, 'x' + numStr + ' ');
				end;
{$ENDIF}
			end;
{$ENDIF}
		end;
	end;

procedure DisplayMessage(ticks: integer; message: string);
	begin
		if GetStatIdAt(0, 0) <> -1 then begin
			RemoveStat(GetStatIdAt(0, 0));
			BoardDrawBorder;
		end;

		if Length(message) <> 0 then begin
			AddStat(0, 0, E_MESSAGE_TIMER, 0, 1, StatTemplateDefault);
			Board.Stats[Board.StatCount].P2 := ticks div (TickTimeDuration + 1);
			Board.Info.Message := message;
{$IFDEF UISCBACK}
			ScrollbackAppend(message);
{$ENDIF}
		end;
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
					DisplayMessage(100, 'Ouch!');

					Board.Tiles[X][Y].Color := $70 + (ElementDefs[E_PLAYER].Color and $0F);

					if World.Info.Health > 0 then begin
						World.Info.BoardTimeSec := 0;
						if Board.Info.ReenterWhenZapped then begin
							SoundQueue(4, #32#1#35#1#39#1#48#1#16#1);

							{ Move player to start }
							Board.Tiles[X][Y].Element := E_EMPTY;
							BoardDrawTile(X, Y);
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
			Board.Tiles[x][y].Element := E_EMPTY;
			BoardDrawTile(x, y);
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
			Inc(World.Info.Score, ElementDefs[Board.Tiles[Board.Stats[attackerStatId].X][Board.Stats[attackerStatId].Y].Element]
				.ScoreValue);
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
			or (Board.Tiles[tx + deltaX][ty + deltaY].Element = E_WATER) then
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

		if Board.Info.IsDark and MessageHintTorchNotShown then begin
			DisplayMessage(200, 'Room is dark - you need to light a torch!');
			MessageHintTorchNotShown := false;
		end;

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
				if (Board.Tiles[ix][iy].Element = E_PASSAGE) and (Board.Tiles[ix][iy].Color = col) then begin
					newX := ix;
					newY := iy;
				end;

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_EMPTY;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := 0;
		if newX <> 0 then begin
			Board.Stats[0].X := newX;
			Board.Stats[0].Y := newY;
		end;

		GamePaused := true;
		SoundQueue(4, #48#1#52#1#55#1#49#1#53#1#56#1#50#1#54#1#57#1#51#1#55#1#58#1#52#1#56#1#64#1);
		TransitionDrawBoardChange;
		BoardEnter;
	end;

procedure GameOnStart;
	var
		f: file;
	begin
		if Length(StartupWorldFileName) <> 0 then begin
			if FileExists(StartupWorldFileName + '.ZZT') then begin
				if WorldLoad(StartupWorldFileName, '.ZZT', true) then begin
					SidebarClearLine(8);
					VideoWriteText(69, 8, $1F, StartupWorldFileName);
				end else begin
					WorldCreate;
				end;

				ReturnBoardId := World.Info.CurrentBoard;
				{ BoardChange(0); - called after GameOnStart }
			end;
		end;
	end;

procedure GamePlayLoop(boardChanged: boolean);
	var
		pauseBlink: boolean;
		pausedElement: byte;
	procedure GameDrawSidebar;
		var
			colorMask: byte;
		begin
			colorMask := 0;
			SidebarClear;
			SidebarClearLine(0);
			SidebarClearLine(1);
			SidebarClearLine(2);
			VideoWriteText(61, 0, $1F, '    - - - - -      ');
			VideoWriteText(62, 1, $70, '      ZZT*     ');
			VideoWriteText(61, 2, $1F, '    - - - - -      ');
			if GameStateElement = E_PLAYER then begin
				VideoWriteText(64, 7, $1E, ' Health:');
				VideoWriteText(64, 8, $1E, '   Ammo:');
				VideoWriteText(64, 9, $1E, 'Torches:');
				VideoWriteText(64, 10, $1E, '   Gems:');
				VideoWriteText(64, 11, $1E, '  Score:');
				VideoWriteText(64, 12, $1E, '   Keys:');
				VideoWriteText(62, 7, $1F, ElementDefs[E_PLAYER].Character);
				VideoWriteText(62, 8, $1B, ElementDefs[E_AMMO].Character);
				VideoWriteText(62, 9, $16, ElementDefs[E_TORCH].Character);
				VideoWriteText(62, 10, $1B, ElementDefs[E_GEM].Character);
				VideoWriteText(62, 12, $1F, ElementDefs[E_KEY].Character);
				VideoWriteText(62, 14, $70, ' T ');
				VideoWriteText(65, 14, $1F, ' Torch');
				if not DemoIsPlaying then begin
				VideoWriteText(62, 15, $30, ' B ');
				VideoWriteText(62, 16, $70, ' H ');
				VideoWriteText(65, 16, $1F, ' Help');
				end else begin
				VideoWriteText(64, 16, $1E, ' Played:');
				end;
				VideoWriteText(67, 18, $30, ' '#24#25#26#27' ');
				VideoWriteText(72, 18, $1F, ' Move');
				VideoWriteText(61, 19, $70, ' Shift '#24#25#26#27' ');
				VideoWriteText(72, 19, $1F, ' Shoot');
				if not DemoIsPlaying then begin
				VideoWriteText(62, 21, $70, ' S ');
				VideoWriteText(65, 21, $1F, ' Save game');
				end;
				VideoWriteText(62, 22, $30, ' P ');
				if NeuromotorAssist then
					VideoWriteText(65, 22, $1F, ' Proceed')
				else
					VideoWriteText(65, 22, $1F, ' Pause');
				VideoWriteText(62, 23, $70, ' Q ');
				VideoWriteText(65, 23, $1F, ' Quit');
			end else if GameStateElement = E_MONITOR then begin
				SidebarPromptSlider(false, 66, 21, 'Game speed:;FS', TickSpeed);
				VideoWriteText(62, 21, $70, ' S ');
				VideoWriteText(62, 7, $30, ' W ');
				VideoWriteText(65, 7, $1E, ' World:');

				if Length(World.Info.Name) <> 0 then
					VideoWriteText(69, 8, $1F, World.Info.Name)
				else
					VideoWriteText(69, 8, $1F, 'Untitled');

				VideoWriteText(62, 11, $70, ' P ');
				VideoWriteText(65, 11, $1F, ' Play');
				VideoWriteText(62, 12, $30, ' R ');
				VideoWriteText(65, 12, $1E, ' Restore game');
				VideoWriteText(62, 13, $70, ' Q ');
				VideoWriteText(65, 13, $1E, ' Quit');
{$IFDEF WEBBROW}
				VideoWriteText(62, 14, $30, ' B ');
				VideoWriteText(65, 14, $1E, ' Browse/Web');
				colorMask := $40;
{$ENDIF}
				VideoWriteText(62, 16, $30 xor colorMask, ' A ');
				VideoWriteText(65, 16, $1F, ' Options/About');
				VideoWriteText(62, 17, $70 xor colorMask, ' H ');
				VideoWriteText(65, 17, $1E, ' High Scores');
{$IFDEF EDITOR}
				if EditorEnabled then begin
					VideoWriteText(62, 18, $30 xor colorMask, ' E ');
					VideoWriteText(65, 18, $1E, ' Board Editor');
				end;
{$ENDIF}
			end;
		end;
	begin
		{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}

		{ We've started playing; disable GameRestartNeeded so that when we quit,
		  the title screen handler won't immediately restart the game.
		  If we're running a demo and that demo includes a restore from
		  a saved game, it will set GameRestartNeeded when that event occurs.
		}
		GameRestartNeeded := false;

		GameDrawSidebar;
		GameUpdateSidebar;
		{$IFDEF BASICSYS} VideoUnlockScreenUpdate(60, 0, 79, 24); {$ENDIF}

{$IFNDEF ZDEMOVAL}
		if JustStarted then begin
			GameAboutScreen;
			JustStarted := false;
		end;
{$ENDIF}

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := GameStateElement;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[GameStateElement].Color;

		if GameStateElement = E_MONITOR then begin
			DisplayMessage(0, '');
			VideoWriteText(62, 5, $1B, 'Pick a command:');
		end;

		if boardChanged then
			TransitionDrawBoardChange
		else
			BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);

		TickTimeDuration := TickSpeed * 2;
		GamePlayExitRequested := false;
		GameControllerHasTicked := true;

		DemoReseedCurrentTick;
		CurrentStatTicked := Board.StatCount + 1;

		repeat
			if GamePaused then begin
				if SoundHasTimeElapsed(TickTimeCounter, 25) then
					pauseBlink := not pauseBlink;

				if pauseBlink then begin
					VideoWriteText(Board.Stats[0].X - 1, Board.Stats[0].Y - 1,
						ElementDefs[E_PLAYER].Color, ElementDefs[E_PLAYER].Character);
				end else begin
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then
						VideoWriteText(Board.Stats[0].X - 1, Board.Stats[0].Y - 1, $0F, ' ')
					else
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
				end;

				VideoWriteText(64, 5, $1F, 'Pausing...');
{$IFDEF SDL2}
				SoundIdle(IMUntilFrame);
{$ENDIF}
				DemoInputUpdate(0, false);
				if DemoIsPlaying then GameDemoUpdateSidebar;

				case UpCase(InputKeyPressed) of KEY_ESCAPE, 'Q': begin
					GamePromptEndPlay;
				end; end;

				if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
					ElementDefs[Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element].TouchProc(
						Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY, 0, InputDeltaX, InputDeltaY);
				end;

				pausedElement := Board.Tiles[Board.Stats[0].X + InputDeltaX][Board.Stats[0].Y + InputDeltaY].Element;
				if ((InputDeltaX <> 0) or (InputDeltaY <> 0))
					and (
						(ElementDefs[pausedElement].Walkable)
{$IFDEF EXTCHEAT}
						or (CheatNoClip and (pausedElement <> E_BOARD_EDGE))
{$ENDIF}
					)
				then begin
					{ Move player }
					if Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element = E_PLAYER then
						MoveStat(0, Board.Stats[0].X + InputDeltaX, Board.Stats[0].Y + InputDeltaY)
					else begin
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						Inc(Board.Stats[0].X, InputDeltaX);
						Inc(Board.Stats[0].Y, InputDeltaY);
						with Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y] do begin
							Element := E_PLAYER;
							Color := ElementDefs[E_PLAYER].Color;
						end;
						BoardDrawTile(Board.Stats[0].X, Board.Stats[0].Y);
						DrawPlayerSurroundings(Board.Stats[0].X, Board.Stats[0].Y, 0);
						DrawPlayerSurroundings(Board.Stats[0].X - InputDeltaX, Board.Stats[0].Y - InputDeltaY, 0);
					end;

					{ Fix bug where the unpause movement is not taken into account for SPACE. }
					if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
						PlayerDirX := InputDeltaX;
						PlayerDirY := InputDeltaY;
					end;

					{ Unpause }
					GamePaused := false;
					GameControllerHasTicked := true;
					SidebarClearLine(5);
					DemoReseedCurrentTick;
					CurrentStatTicked := Board.StatCount + 1;
					World.Info.IsSave := true;
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

			if ((CurrentStatTicked > Board.StatCount)) and not GamePlayExitRequested then begin
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

				{ TODO: Having DemoFastForward here is a bit of a hack. }
				if DemoFastForward or DemoSoundHasTimeElapsed(TickTimeCounter, TickTimeDuration) then begin
					DemoInputUpdate(((TickTimeDuration shl 1) + 10) div 11, true);
					if DemoIsPlaying then GameDemoUpdateSidebar;
					GameControllerHasTicked := false;

					{ This is here, as to not break ElementMonitorTick. }
					if GameStateElement = E_MONITOR then begin
						if UpCase(InputKeyPressed) in ['B', 'D', 'L'] then
							GamePlayExitRequested := true;
					end;

					if (GameStateElement = E_PLAYER) and NeuromotorAssist and (InputKeyPressed = #0) then begin
						SoundIdle(IMUntilFrame);
					end else if DemoErrorCode <> 0 then begin
						DemoStop(true);
						GameDemoShowError;
						GamePlayExitRequested := true;
					end else if DemoIsComplete then begin
						DemoStop(false);
						GameDemoShowSuccess;
						World.Info.Score := 0; { prevent setting high score from demo }
						GamePlayExitRequested := true;
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

			{ If the player finished a save game operation and we're playing
			  back a demo, it's possible that GameRestartNeeded was set. If
			  so, exit so we can start this procedure from the top. (Is this
			  better than a goto?) }

			if GameRestartNeeded then Exit;
		until GamePlayExitRequested;

		SoundClearQueue;

		if GameStateElement = E_PLAYER then begin
			if World.Info.Health <= 0 then begin
				HighScoresAdd(World.Info.Score);
			end;
		end else if GameStateElement = E_MONITOR then begin
			SidebarClearLine(5);
		end;

		DemoStop(false);

		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Element := E_PLAYER;
		Board.Tiles[Board.Stats[0].X][Board.Stats[0].Y].Color := ElementDefs[E_PLAYER].Color;

		SoundBlockQueueing := false;
	end;

function GameDemoStartRecord: boolean;
	var
		filename: TString50;
	begin
		GameDemoStartRecord := false;
		filename := World.Info.Name;
		SidebarPromptFilename('Demo name?', '.ZZD', filename, PROMPT_ALPHANUM);
		if (InputKeyPressed <> KEY_ESCAPE) and (Length(filename) <> 0) then begin
			if DemoStartRecord(filename, '.ZZD') then begin
				if DemoStartLogging(filename, '.ZZL') then begin
					GameDemoStartRecord := true;
				end else begin
					DemoStop(true);
					GameDemoStartRecord := false;
				end;
			end;
		end;
	end;

function GameDemoStartPlay: boolean;
	var
		filename: TString50;
	begin
		GameDemoStartPlay := false;
		filename := World.Info.Name;
		SidebarPromptFilename('Demo name?', '.ZZD', filename, PROMPT_ALPHANUM);
		if (InputKeyPressed <> KEY_ESCAPE) and (Length(filename) <> 0) then begin
			if DemoStartPlay(filename, '.ZZD') then begin
				if DemoStartLogging(filename, '.ZZL') then begin
					GameDemoStartPlay := true;
					if DemoFastForward then begin
						SoundEnabled := false;
					end;
				end else begin
					DemoStop(true);
					GameDemoStartPlay := false;
				end;
			end;
		end;
	end;

{$IFDEF ZDEMOVAL}
{TODO: Make this a function that returns score. Take a parameter
 indicating whether we want to save the end state to a SAV file.}
procedure GameValidateRun;
	begin
		GameTitleExitRequested := false;
		JustStarted := true;
		ReturnBoardId := 0;
		BoardChange(0);
		DemoFastForward := true;
		DemoStopOnEndgame := false;
		SoundEnabled := false;

		{ We'll return the player's score as the exit code (error level).
		  If the demo can't be played, that's zero points. }

		ExitCode := 0;

		if DemoStartPlay(StartupWorldFileName, '.ZZD') then begin
			if DemoStartLogging(StartupWorldFileName, '.ZZL') then begin
				{ TODO: If the world doesn't exist, then exit straight away,
			 	  don't play back a demo on the IO error screen.}
				if WorldLoad(DemoGetWorldName, '.ZZT', false) then begin
					ReturnBoardId := World.Info.CurrentBoard;

					GameStateElement := E_PLAYER;
					GamePaused := true;

					GamePlayLoop(true);
					WorldSave('RESULT', '.SAV');
				end;
			end;
		end;
	end;
{$ENDIF}

procedure GameTitleLoop;
	var
		boardChanged: boolean;
		startPlay: boolean;
	label PlayStart;
	begin
		GameTitleExitRequested := false;
		ReturnBoardId := 0;
		boardChanged := true;

		GameOnStart;

		repeat
{$IFDEF UISCBACK}
			ScrollbackClear(-1);
{$ENDIF}
			BoardChange(0);
			repeat
				GameStateElement := E_MONITOR;
				startPlay := false;
				DemoFastForward := false;
				DemoStopOnEndgame := false;
				GamePaused := false;
				GamePlayLoop(boardChanged);
				boardChanged := false;

				case UpCase(InputKeyPressed) of
					'W': begin
						if GameWorldLoad('.ZZT') then begin
							ReturnBoardId := World.Info.CurrentBoard;
							boardChanged := true;
						end;
					end;
					'P': begin
	PlayStart:
						if World.Info.IsSave and not DebugEnabled then begin
							startPlay := WorldLoad(World.Info.Name, '.ZZT', false);
							ReturnBoardId := World.Info.CurrentBoard;
						end else begin
							startPlay := true;
						end;
						if startPlay then begin
							BoardChange(ReturnBoardId);
							BoardEnter;
						end;
					end;
{$IFDEF WEBBROW}
					'B': begin
						WebBrowserLoop;
						TransitionDrawToBoard;
					end;
{$ENDIF}
					'A': begin
						GameOptionsScreen(false);
						TransitionDrawToBoard;
					end;
{$IFDEF EDITOR}
					'E': if EditorEnabled then begin
						EditorLoop;
						ReturnBoardId := World.Info.CurrentBoard;
						boardChanged := true;
					end;
{$ENDIF}
					'D': begin
						if GameDemoStartRecord then begin
							{ Force file reload. }
							World.Info.IsSave := true;
							goto PlayStart;
						end;
					end;
					'L': begin
						DemoFastForward := (InputKeyPressed = 'L');
						if GameDemoStartPlay then begin
							{ Force file reload. }
							World.Info.IsSave := true;
							goto PlayStart;
						end;
					end;
					'S': begin
						SidebarPromptSlider(true, 66, 21, 'Game speed:;FS', TickSpeed);
						InputKeyPressed := #0;
					end;
					'R': begin
						if GameWorldLoad('.SAV') then begin
							ReturnBoardId := World.Info.CurrentBoard;
							BoardChange(ReturnBoardId);
							startPlay := true;
						end;
					end;
					'H': begin
						HighScoresLoad;
						HighScoresDisplay(1);
					end;
					'|': begin
						GameDebugPrompt;
					end;
					KEY_ESCAPE, 'Q': begin
						GameTitleExitRequested := SidebarPromptYesNo('Quit ZZT? ', true);
					end;
				end;

				if startPlay then begin
					GameRestartNeeded := true;
					{ Needed to make the transition only play once
					  when playing back a demo. }
					boardChanged := true;
					while GameRestartNeeded do begin
						GameStateElement := E_PLAYER;
						GamePaused := true;
						GamePlayLoop(boardChanged);
						boardChanged := false;
					end;
					boardChanged := true;
				end;
			until boardChanged or GameTitleExitRequested;
		until GameTitleExitRequested;
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
