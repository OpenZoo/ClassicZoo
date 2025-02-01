{	Copyright (c) 2020 Adrian Siekierka

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

unit Editor;

interface
	uses GameVars, TxtWind;
	var
		EditorAutoAppendPats: boolean;
		EditorSeparateStartingBoard: boolean;
		EditorLowLevelEnable: boolean;
		EditorSyntaxHighlightEnable: boolean;
		EditorShowDataSizes: boolean;
	procedure HighScoresLoad;
	procedure HighScoresSave;
	procedure HighScoresAdd(score: integer);
	procedure HighScoresDisplay(linePos: integer);
{$IFDEF EDITOR}
	procedure EditorLoop;
	procedure EditorOpenEditTextWindow(var state: TTextWindowState; extension: TExtensionString;
		syntaxHighlighting, multiExtension: boolean);
	procedure EditorEditTextFile;
{$ENDIF}
	function EditorGetBoardName(boardId: integer; titleScreenIsNone: boolean): TSmallString;
	function EditorSelectBoard(title: string; currentBoard: integer; titleScreenIsNone: boolean;
		windowAlreadyOpen: boolean; showAddNewBoard: boolean; editable: boolean): integer;
{$IFDEF EDITOR}
	function EditorGetElementName(elemId: integer): TString50;
	function EditorGetColorName(color: byte): TString50;
	procedure EditorSelectElement(title: string; var element: byte; windowAlreadyOpen: boolean);
	function EditorSelectStat(title: string; currentStat: integer; showNone: boolean;
		windowAlreadyOpen: boolean; showAddNewStat: boolean; editable: boolean): integer;
{$ENDIF}

implementation
uses Dos, GameIo, Cheats, GameSh, FileSel, FileSys, ExtMem,
GameConf, ZVideo, Sounds, TimerSys, Keys, ZInput, Elements, Oop, Game, Sidebar,
ZDemo;

type
	TLLEditAction = (
		LLEditNone,
		LLEditElement,
		LLEditColor,
		LLEditX,
		LLEditY,
		LLEditStepX,
		LLEditStepY,
		LLEditCycle,
		LLEditP1,
		LLEditP2,	
		LLEditP3,
		LLEditFollower,
		LLEditLeader,
		LLEditUnderElement,
		LLEditUnderColor,
		LLEditData,
		LLEditDataBound,
		LLEditDataPos,
		LLEditDeleteStat
	);

	TIdShiftMode = (
		IdShiftDelete,
		IdShiftAdd,
		{
			4 -> 1
			0 1 2 3 4 5 
			0 4 1 2 3 5

			1 -> 4
			0 1 2 3 4 5
			0 2 3 4 1 5
		}
		IdShiftMove
	);
	TDrawMode = (DrawingOff, DrawingOn, TextEntry);
	TEditorCopiedTile = record
		stat: TStat;
		isMainPlayer: boolean;
		hasStat: boolean;
		tile: TTile;
		previewChar: byte;
		previewColor: byte;
	end;
	TEditorCopyTileBuffer = array[0 .. 32000] of TTile;
	TEditorCopyStatBuffer = array[1 .. MAX_STAT + 2] of TStat;
	TEditorCopyBuffer = record
		tiles: ^TEditorCopyTileBuffer;
		stats: ^TEditorCopyStatBuffer;
		statCount: integer;
		width: byte;
		height: byte;
	end;

const
	COPIED_TILES_COUNT = 10;
	NeighborBoardStrs: array[0 .. 3] of string[20] =
		('       Board '#24, '       Board '#25, '       Board '#27, '       Board '#26);
	LongColorNames: array[0 .. 15] of string[7] =
		('Black', 'D.Blue', 'D.Green', 'D.Cyan', 'D.Red', 'DPurple', 'Brown', 'L.Gray',
		'D.Gray', 'Blue', 'Green', 'Cyan', 'Red', 'Purple', 'Yellow', 'White');
	ColorNames: array[0 .. 15] of string[3] =
		('Blk', 'DBl', 'DGn', 'DCy', 'DRe', 'DMa', 'Bro', 'LGr', 'DGr', 'LBl', 'LGn', 'LCy', 'LRe', 'LMa', 'Yel', 'Wht');

procedure EditorPadSpaces(var s: string; sLen: integer);
	begin
		while Length(s) < sLen do
			s := ' ' + s;
	end;

function IdShiftApply(mode: TIdShiftMode; bidFrom, bidTo, boardId: integer): integer;
	begin
		IdShiftApply := boardId;
		case mode of
		IdShiftDelete: begin
			if boardId > bidFrom then
				IdShiftApply := boardId - 1
			else if boardId = bidFrom then
				IdShiftApply := -1;
		end;
		IdShiftAdd: begin
			if boardId >= bidTo then
				IdShiftApply := boardId + 1;
		end;
		IdShiftMove: begin
			if boardId = bidFrom then
				IdShiftApply := bidTo
			else if bidFrom > bidTo then begin
				if (boardId < bidFrom) and (boardId >= bidTo) then
					IdShiftApply := boardId + 1;
			end else if bidFrom < bidTo then begin
				if (boardId <= bidTo) and (boardId > bidFrom) then
					IdShiftApply := boardId - 1;
			end;
		end;
		end;
	end;

function EditorShiftBoard(bidFrom, bidTo: integer; mode: TIdShiftMode): boolean;
	var
		i, j, prevBoard, newBid, loadProgress: integer;
		movedData: TExtMemBlock;
		movedLen: word;
	begin
		EditorShiftBoard := true;

		if (bidFrom = bidTo) then exit;

		SidebarClearLine(4);
		SidebarClearLine(5);
		VideoWriteText(VideoSidebarX + 2, 5, $1F, 'Editing.....');
		loadProgress := 0;

		prevBoard := IdShiftApply(mode, bidFrom, bidTo, World.Info.CurrentBoard);
		if prevBoard < 0 then begin
			prevBoard := 0;
		end;

		for i := 0 to World.BoardCount do begin
			{ Skip boards about to be deleted. }
			if IdShiftApply(mode, bidFrom, bidTo, i) < 0 then begin end;

			SidebarAnimateLoading(loadProgress);
			BoardChange(i);
			for j := 0 to 3 do begin
				newBid := IdShiftApply(mode, bidFrom, bidTo, Board.Info.NeighborBoards[j]);
				if newBid < 0 then begin
					newBid := 0;
				end;
				Board.Info.NeighborBoards[j] := newBid;
			end;
			for j := 1 to Board.StatCount do with Board.Stats[j] do begin
				if Board.Tiles[X][Y].Element = E_PASSAGE then begin
					newBid := IdShiftApply(mode, bidFrom, bidTo, P3);
					if newBid < 0 then begin
						newBid := 0;
						EditorShiftBoard := false;
					end;
					P3 := newBid;
				end;
			end;
		end;

		case mode of
		IdShiftDelete: begin
			SidebarAnimateLoading(loadProgress);
			BoardClose;
			ExtMemFree(WorldExt.BoardData[bidFrom], WorldExt.BoardLen[bidFrom]);
			Dec(World.BoardCount);
			for i := bidFrom to World.BoardCount do begin
				ExtMemMoveBlockPtr(WorldExt.BoardData[i + 1], WorldExt.BoardData[i]);
				WorldExt.BoardLen[i] := WorldExt.BoardLen[i + 1];
			end;
			BoardOpen(prevBoard);
		end;
		IdShiftAdd: begin
			RunError(200); { TODO }
		end;
		IdShiftMove: begin
			SidebarAnimateLoading(loadProgress);
			BoardClose;

			ExtMemMoveBlockPtr(WorldExt.BoardData[bidFrom], movedData);
			movedLen := WorldExt.BoardLen[bidFrom];

			if bidFrom > bidTo then begin
				for i := (bidTo + 1) to bidFrom do begin
					ExtMemMoveBlockPtr(WorldExt.BoardData[i - 1], WorldExt.BoardData[i]);
					WorldExt.BoardLen[i] := WorldExt.BoardLen[i - 1];
				end;
			end else begin
				for i := bidFrom to (bidTo - 1) do begin
					ExtMemMoveBlockPtr(WorldExt.BoardData[i + 1], WorldExt.BoardData[i]);
					WorldExt.BoardLen[i] := WorldExt.BoardLen[i + 1];
				end;
			end;

			ExtMemMoveBlockPtr(movedData, WorldExt.BoardData[bidTo]);
			WorldExt.BoardLen[bidTo] := movedLen;

			BoardOpen(prevBoard);
		end;
		end;
	end;

function EditorShiftStat(idFrom, idTo: integer; mode: TIdShiftMode): boolean;
	var
		i: integer;
		movedStat: TStat;
	begin
		EditorShiftStat := true;

		if (idFrom = idTo) then exit;
		if (idFrom = 0) or (idTo = 0) then exit;

		for i := 0 to Board.StatCount do begin
			{ Skip stats about to be deleted. }
			if IdShiftApply(mode, idFrom, idTo, i) < 0 then begin end;

			with Board.Stats[i] do begin
				if Follower >= 0 then begin
					Follower := IdShiftApply(mode, idFrom, idTo, Follower);
					if Follower < 0 then EditorShiftStat := false;
				end;
				if Leader >= 0 then begin
					Leader := IdShiftApply(mode, idFrom, idTo, Leader);
					if Leader < 0 then EditorShiftStat := false;
				end;
			end;
		end;

		case mode of
		IdShiftDelete: begin
			FreeStatDataMem(idFrom, false);
			with Board.Stats[idFrom] do begin
				if not EditorLowLevelEnable then
					Board.Tiles[X][Y] := Under;
			end;

			for i := (idFrom + 1) to Board.StatCount do
				Board.Stats[i - 1] := Board.Stats[i];
			Dec(Board.StatCount);
		end;
		IdShiftAdd: begin
			RunError(200); { TODO }
		end;
		IdShiftMove: begin
			movedStat := Board.Stats[idFrom];

			if idFrom > idTo then begin
				for i := (idTo + 1) to idFrom do
					Board.Stats[i] := Board.Stats[i - 1];
			end else begin
				for i := idFrom to (idTo - 1) do
					Board.Stats[i] := Board.Stats[i + 1];
			end;

			Board.Stats[idTo] := movedStat;
		end;
		end;
	end;

procedure EditorAppendBoard;
	begin
		if World.BoardCount < MAX_BOARD then begin
			BoardClose;

			Inc(World.BoardCount);
			World.Info.CurrentBoard := World.BoardCount;
			WorldExt.BoardLen[World.BoardCount] := 0;
			BoardCreate;

			TransitionDrawToBoard;

			repeat
				PopupPromptString('Room'#39's Title:', Board.Name, MAX_BOARD_NAME_LENGTH);
			until Length(Board.Name) <> 0;

			TransitionDrawToBoard;
		end;
	end;

{$IFDEF EDITOR}
procedure EditorCopyStat(var fromStat: TStat; var toStat: TStat);
	begin
		Move(fromStat, toStat, SizeOf(TStat));
		if toStat.DataLen > 0 then begin
			GetMem(toStat.Data, toStat.DataLen);
			Move(fromStat.Data^, toStat.Data^, toStat.DataLen);
		end else begin
			toStat.DataLen := 0;
		end;
	end;

procedure EditorDrawSidebar345(clear: boolean);
	begin
		if clear then begin
			SidebarClearLine(3);
			SidebarClearLine(4);
			SidebarClearLine(5);
		end;
		VideoWriteText(VideoSidebarX + 1, 4, $70, ' L ');
		VideoWriteText(VideoSidebarX + 4, 4, $1F, ' Load');
		VideoWriteText(VideoSidebarX + 1, 5, $30, ' S ');
		VideoWriteText(VideoSidebarX + 4, 5, $1F, ' Save');
		VideoWriteText(VideoSidebarX + 10, 4, $70, ' H ');
		VideoWriteText(VideoSidebarX + 13, 4, $1F, ' Help');
		VideoWriteText(VideoSidebarX + 10, 5, $30, ' Q ');
		VideoWriteText(VideoSidebarX + 13, 5, $1F, ' Quit');
	end;

procedure EditorLoop;
	var
		selectedCategory: integer;
		wasModified: boolean;
		editorExitRequested: boolean;
		drawMode: TDrawMode;
		startingBoard, tmpBoard: integer;
		lastCursorX, lastCursorY: integer;
		cursorX, cursorY: integer;
		cursorPattern, cursorColor: integer;
		colorIgnoreDefaults: boolean;
		i, iElem: integer;
		canModify: boolean;
		copiedTiles: array[1 .. COPIED_TILES_COUNT] of TEditorCopiedTile;
		cursorBlinker: integer;
		iBg, inputByte: byte;
		viewMode: integer;
		showingBoardName: boolean;
		copyBuffer: TEditorCopyBuffer;

	procedure EditorOnWorldOpen;
		begin
			InitElementsEditor;
			startingBoard := World.Info.CurrentBoard;
		end;

	procedure EditorWorldCanOpenCheck(closeSavesSilently: boolean);
		var
			isSecret: boolean;
		begin
			{ Secret worlds: warn always }
			{ Savegames: error if non-debug, warn if debug }
			isSecret := (WorldGetFlagPosition('SECRET') >= 0);
			if (World.Info.IsSave and (not closeSavesSilently)) or isSecret then begin
				SidebarClearLine(3);
				SidebarClearLine(4);
				SidebarClearLine(5);
				VideoWriteText(VideoSidebarX + 3, 4, $1E, 'World marked as');
				if World.Info.IsSave then
					VideoWriteText(VideoSidebarX + 3, 5, $1E, ' a saved game!')
				else
					VideoWriteText(VideoSidebarX + 3, 5, $1E, '    locked!');
				PauseOnError;
			end;
			if World.Info.IsSave and (not DebugEnabled) then begin
				WorldUnload;
				WorldCreate;
				EditorOnWorldOpen;
			end;
		end;

	function EditorGetStartingBoard: integer;
		begin
			if (EditorSeparateStartingBoard) and (startingBoard >= 0) then
				EditorGetStartingBoard := startingBoard
			else
				EditorGetStartingBoard := World.Info.CurrentBoard;
		end;

	procedure EditorDrawCursor;
		begin
			VideoWriteText(
{$IFDEF E_SUPERZ}
				cursorX + BOARD_DRAW_X - Board.Info.DrawXOffset,
				cursorY + BOARD_DRAW_Y - Board.Info.DrawYOffset,
{$ELSE}
				cursorX - 1,
				cursorY - 1,
{$ENDIF}
				$0F, #197
			);
		end;

	function EditorGetDrawingColor(eid: integer): integer;
		begin
			if eid = E_PLAYER then
				EditorGetDrawingColor := ElementDefs[eid].Color
			else if colorIgnoreDefaults or (ElementDefs[eid].Color = COLOR_CHOICE_ON_BLACK) then
				EditorGetDrawingColor := cursorColor
			else if ElementDefs[eid].Color = COLOR_WHITE_ON_CHOICE then
				EditorGetDrawingColor := ((cursorColor and $07) shl 4) + $0F
			else if ElementDefs[eid].Color = COLOR_CHOICE_ON_CHOICE then
				EditorGetDrawingColor := ((cursorColor and $07) * $11) + 8
			else
				EditorGetDrawingColor := ElementDefs[eid].Color;
		end;

	procedure EditorUpdateCursorColor;
		var
			colorBg, colorFg: byte;
		begin
			VideoWriteText(VideoSidebarX + 12, 19, $1E, ColorNames[cursorColor and $0F]);
			if VideoGetBlinkMode = BlinkModeOn then
				VideoWriteText(VideoSidebarX + 16, 19, $1E or (cursorColor shr 7),
					ColorNames[(cursorColor shr 4) and 7])
			else
				VideoWriteText(VideoSidebarX + 16, 19, $1E, ColorNames[cursorColor shr 4]);

			VideoWriteText(VideoSidebarX + 1, VideoRows - 1, $1F, '                ');

			colorBg := cursorColor shr 4;
			colorFg := cursorColor and $0F;

			if colorBg = colorFg then begin
				VideoWriteText(VideoSidebarX + 1 + colorBg, VideoRows - 1, $9F, #30);
			end else begin
				VideoWriteText(VideoSidebarX + 1 + colorFg, VideoRows - 1, $1F, #24);
				VideoWriteText(VideoSidebarX + 1 + colorBg, VideoRows - 1, $1F, '^');
			end;
		end;

	procedure EditorUpdateCursorPattern;
		begin
			VideoWriteText(VideoSidebarX + 1, VideoRows - 3, $1F, '                ');
			VideoWriteText(VideoSidebarX + 0 + cursorPattern, VideoRows - 3, $1F, #30);
		end;

	procedure EditorUpdateDrawMode;
		begin
			case drawMode of
				DrawingOn: VideoWriteText(VideoSidebarX + 15, 16, $9E, 'Draw');
				TextEntry: VideoWriteText(VideoSidebarX + 15, 16, $9E, 'Text');
				DrawingOff: VideoWriteText(VideoSidebarX + 15, 16, $1E, 'None');
			end;

			if drawMode = TextEntry then begin
				VideoWriteText(VideoSidebarX + 1, 15, $70, '  f10  ');
				VideoWriteText(VideoSidebarX + 8, 15, $1F, ' Custom');
			end else begin
				VideoWriteText(VideoSidebarX + 1, 15, $70, ' Space ');
				VideoWriteText(VideoSidebarX + 8, 15, $1F, ' Plot  ');
			end;
		end;

	procedure EditorUpdateColorIgnoreDefaults;
		begin
			if colorIgnoreDefaults then
				VideoWriteText(VideoSidebarX + 18, VideoRows - 2, $1F, 'd')
			else
				VideoWriteText(VideoSidebarX + 18, VideoRows - 2, $1F, 'D')
		end;

	procedure EditorUpdateCopiedPatterns;
		var
			i: integer;
		begin
			for i := 1 to COPIED_TILES_COUNT do
				with copiedTiles[i] do
					VideoWriteText(VideoSidebarX + 0 + EditorPatternCount + i, VideoRows - 4, previewColor, Chr(previewChar));
		end;

	procedure EditorClearPattern(var copied: TEditorCopiedTile; first: boolean);
		begin
			with copied do begin
				hasStat := false;
				isMainPlayer := false;
				tile.Element := 0;
				tile.Color := $0F;
				previewChar := 0;
				previewColor := $0F;
				if first then stat.Data := nil
				else if stat.Data <> nil then FreeMem(stat.Data, stat.DataLen);
			end;
		end;

	{ TODO: Unify with BoardDrawTile? }
	procedure EditorCopyPattern(x, y: integer; var copied: TEditorCopiedTile);
		var
			statId: integer;
		begin
			statId := GetStatIdAt(x, y);

			EditorClearPattern(copied, false);
			with copied do begin
				tile := Board.Tiles[cursorX][cursorY];
				hasStat := statId > 0;
				isMainPlayer := statId = 0;
				if hasStat then
					EditorCopyStat(Board.Stats[statId], stat);
				if ElementDefs[tile.Element].HasDrawProc then
					ElementDefs[tile.Element].DrawProc(x, y, previewChar)
				else if tile.Element < E_TEXT_MIN then
					previewChar := Ord(ElementDefs[tile.Element].Character)
				else
					previewChar := tile.Color;

				if tile.Element < E_TEXT_MIN then
					previewColor := tile.Color
				else if tile.Element = E_TEXT_WHITE then
					previewColor := $0F
				else
					previewColor := (((tile.Element - E_TEXT_MIN) + 1) shl 4) + $0F;
			end;
		end;

	procedure EditorCopyPatternToCurrent(x, y: integer);
		var
			i: integer;
		begin
			if EditorAutoAppendPats then begin
				for i := COPIED_TILES_COUNT downto 2 do
					copiedTiles[i] := copiedTiles[i - 1];
				EditorCopyPattern(x, y, copiedTiles[1]);
			end else begin
				if cursorPattern > EditorPatternCount then
					EditorCopyPattern(x, y, copiedTiles[cursorPattern - EditorPatternCount]);
			end;
		end;

	procedure EditorDrawCursorPos;
		var
			ctX, ctY: integer;
			numStr: string[20];
		begin
			if VideoRows >= 43 then begin
				ctX := VideoSidebarX + 11;
				ctY := 36;
			end else begin
				ctX := VideoSidebarX + 12;
				ctY := 20;
			end;

			VideoWriteText(ctX, ctY, $1E, '(  ,  )');
			Str(cursorX, numStr);
			VideoWriteText(ctX + 3 - Length(numStr), ctY, $1F, numStr);
			Str(cursorY, numStr);
			VideoWriteText(ctX + 6 - Length(numStr), ctY, $1F, numStr);
		end;

	procedure EditorDrawBufferState;
		var
			numStr: string[20];
		begin
			if VideoRows >= 43 then begin
				if copyBuffer.width <= 0 then
					VideoWriteText(VideoSidebarX + 9, 31, $1E, 'Empty')
				else begin
					VideoWriteText(VideoSidebarX + 9, 31, $1E, '  x  ');
					Str(copyBuffer.width, numStr);
					VideoWriteText(VideoSidebarX + 11 - Length(numStr), 31, $1F, numStr);
					Str(copyBuffer.height, numStr);
					VideoWriteText(VideoSidebarX + 14 - Length(numStr), 31, $1F, numStr);
				end;
			end;
		end;

	procedure EditorDrawStatsState;
		var
			numStr: string[20];
			numStr2: string[20];
		begin
			if VideoRows >= 43 then begin
				Str(Board.StatCount, numStr);
				Str(MAX_STAT, numStr2);

				VideoWriteText(VideoSidebarX + 8, 37, $1F, numStr);
				VideoWriteText(VideoSidebarX + 8 + Length(numStr), 37, $1E, '/');
				VideoWriteText(VideoSidebarX + 8 + Length(numStr) + 1, 37, $1F, numStr2);
				VideoWriteText(VideoSidebarX + 8 + Length(numStr) + 1 + Length(numStr2), 37, $1F, '     ');
			end;
		end;

	procedure EditorDrawSidebar;
		var
			i: integer;
			copiedChr: byte;
		begin
			{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
			SidebarClear;
			SidebarClearLine(1);
			VideoWriteText(VideoSidebarX + 1, 0, $1F, '     - - - -       ');
			VideoWriteText(VideoSidebarX + 2, 1, $70, '  ZZT* Editor  ');
			VideoWriteText(VideoSidebarX + 1, 2, $1F, '     - - - -       ');
			EditorDrawSidebar345(false);
			VideoWriteText(VideoSidebarX + 1, 7, $70, ' B ');
			VideoWriteText(VideoSidebarX + 4, 7, $1F, ' Switch boards');
			VideoWriteText(VideoSidebarX + 1, 8, $30, ' I ');
			VideoWriteText(VideoSidebarX + 4, 8, $1F, ' Board Info');
			VideoWriteText(VideoSidebarX + 1, 10, $70, '  f1   ');
			VideoWriteText(VideoSidebarX + 8, 10, $1F, ' Item');
			VideoWriteText(VideoSidebarX + 1, 11, $30, '  f2   ');
			VideoWriteText(VideoSidebarX + 8, 11, $1F, ' Creature');
			VideoWriteText(VideoSidebarX + 1, 12, $70, {$IFDEF E_SUPERZ}'  f3-4 '{$ELSE}'  f3   '{$ENDIF});
			VideoWriteText(VideoSidebarX + 8, 12, $1F, ' Terrain');
			VideoWriteText(VideoSidebarX + 1, 13, $30, {$IFDEF E_SUPERZ}'  f6   '{$ELSE}'  f4   '{$ENDIF});
			VideoWriteText(VideoSidebarX + 8, 13, $1F, ' Enter text');
			VideoWriteText(VideoSidebarX + 1, 16, $30, '  Tab  ');
			VideoWriteText(VideoSidebarX + 8, 16, $1F, ' Mode:');
			VideoWriteText(VideoSidebarX + 1, 18, $70, ' P ');
			VideoWriteText(VideoSidebarX + 4, 18, $1F, ' Pattern');
			VideoWriteText(VideoSidebarX + 1, 19, $30, ' C ');
			VideoWriteText(VideoSidebarX + 4, 19, $1F, ' Color:');
			VideoWriteText(VideoSidebarX + 15, 19, $1F, #26);

			if VideoRows >= 43 then begin
				{ Extra help }
				VideoWriteText(VideoSidebarX + 1, 21, $70, '  f5   ');
				VideoWriteText(VideoSidebarX + 8, 21, $1F, ' Advanced');
				VideoWriteText(VideoSidebarX + 1, 22, $30, ' Enter ');
				VideoWriteText(VideoSidebarX + 8, 22, $1F, ' Modify');
				VideoWriteText(VideoSidebarX + 1, 23, $70, '  Del  ');
				VideoWriteText(VideoSidebarX + 8, 23, $1F, ' Erase');

				VideoWriteText(VideoSidebarX + 1, 25, $30, ' X ');
				VideoWriteText(VideoSidebarX + 4, 25, $1F, ' Flood Fill');
				VideoWriteText(VideoSidebarX + 1, 26, $70, {$IFDEF E_SUPERZ}' O '{$ELSE}' A '{$ENDIF});
				VideoWriteText(VideoSidebarX + 4, 26, $1F, ' Options');
				VideoWriteText(VideoSidebarX + 1, 27, $30, ' W ');
				VideoWriteText(VideoSidebarX + 4, 27, $1F, ' World Info');
				VideoWriteText(VideoSidebarX + 1, 28, $70, ' T ');
				VideoWriteText(VideoSidebarX + 4, 28, $1F, ' Transfer');
				VideoWriteText(VideoSidebarX + 1, 29, $30, ' ! ');
				VideoWriteText(VideoSidebarX + 4, 29, $1F, ' Text Editor');

				VideoWriteText(VideoSidebarX + 1, 31, $1F, 'Buffer: ');
				VideoWriteText(VideoSidebarX + 1, 32, $70, ' Ctrl-X ');
				VideoWriteText(VideoSidebarX + 9, 32, $1F, ' Cut');
				VideoWriteText(VideoSidebarX + 1, 33, $30, ' Ctrl-C ');
				VideoWriteText(VideoSidebarX + 9, 33, $1F, ' Copy');
				VideoWriteText(VideoSidebarX + 1, 34, $70, ' Ctrl-V ');
				VideoWriteText(VideoSidebarX + 9, 34, $1F, ' Paste');

				VideoWriteText(VideoSidebarX + 1, 36, $1F, 'Position: ');
				VideoWriteText(VideoSidebarX + 1, 37, $1F, 'Stats: ');

				EditorDrawBufferState;
				EditorDrawStatsState;

				if VideoRows >= 50 then begin
					VideoWriteText(VideoSidebarX + 1, 39, $30, ' N ');
					VideoWriteText(VideoSidebarX + 4, 39, $1F, ' New World');
					VideoWriteText(VideoSidebarX + 1, 40, $70, ' Z ');
					VideoWriteText(VideoSidebarX + 4, 40, $1F, ' Clear all');
{$IFDEF E_SUPERZ}
					VideoWriteText(VideoSidebarX + 1, 41, $30, ' V ');
					VideoWriteText(VideoSidebarX + 4, 41, $1F, ' Blink/View');
{$ENDIF}
				end;
			end;

			{ Colors }
			for i := 0 to 15 do
				VideoWriteText(VideoSidebarX + 1 + i, VideoRows - 2, $10 + i, #219);
			EditorUpdateCursorColor;
			EditorUpdateColorIgnoreDefaults;

			{ Patterns }
			for i := 1 to EditorPatternCount do
				VideoWriteText(VideoSidebarX + 0 + i, VideoRows - 4, $0F, ElementDefs[EditorPatterns[i]].Character);
			EditorUpdateCopiedPatterns;
			EditorUpdateCursorPattern;

			EditorUpdateDrawMode;
			EditorDrawCursorPos;
			{$IFDEF BASICSYS} VideoUnlockScreenUpdate(VideoSidebarX, 0, VideoSidebarX + 19, 24); {$ENDIF}
		end;

	procedure EditorDrawTileAndNeighborsAt(x, y: integer);
		var
			i, ix, iy: integer;
		begin
			BoardDrawTile(x, y);
			for i := 0 to 3 do begin
				ix := x + NeighborDeltaX[i];
				iy := y + NeighborDeltaY[i];
				if (ix >= 1) and (ix <= BOARD_WIDTH) and (iy >= 1) and (iy <= BOARD_HEIGHT) then
					BoardDrawTile(ix, iy);
			end;
			EditorDrawStatsState;
		end;

	procedure EditorDrawRefresh;
		var
			boardNumStr: string[20];
		begin	
			{$IFDEF E_ZZT} BoardDrawBorder; {$ENDIF}
			EditorDrawSidebar;
			Str(World.Info.CurrentBoard, boardNumStr);
			{$IFDEF E_SUPERZ} DrawPlayfieldBorder(false); {$ENDIF}
			TransitionDrawToBoard;

{$IFDEF E_SUPERZ}
			VideoWriteText(0, 0, $1F,
				'                    '
				+'                    '
				+'                    ');
{$ENDIF}

			if Length(Board.Name) <> 0 then
{$IFDEF WIDECHAR}
				VideoWriteTextWide(((VideoSidebarX - 1) - Length(Board.Name)) shr 1, 0, $70, ' ' + Board.Name + ' ')
{$ELSE}
				VideoWriteText(((VideoSidebarX - 1) - Length(Board.Name)) shr 1, 0, $70, ' ' + Board.Name + ' ')
{$ENDIF}
			else
				VideoWriteText((VideoSidebarX - 34), 0, $70, ' Untitled ');
			showingBoardName := true;
		end;

	procedure EditorSetTile(x, y, newElement, newColor: byte);
		begin
			with Board.Tiles[x][y] do begin
				Element := newElement;
				Color := newColor;
			end;
			EditorDrawTileAndNeighborsAt(x, y);
		end;

	procedure EditorSetAndCopyTile(x, y, element, color: byte);
		begin
			EditorSetTile(x, y, element, color);

			EditorCopyPatternToCurrent(x, y);
			EditorUpdateCopiedPatterns;
		end;

	function EditorSaveWorld: boolean;
		begin
			SidebarClearLine(4);
			SidebarClearLine(5);
			if EditorSeparateStartingBoard and (startingBoard >= 0) then begin
				tmpBoard := World.Info.CurrentBoard;
				BoardChange(startingBoard);
			end;
{$IFDEF E_SUPERZ}
			GameWorldSave('Save world:', LoadedGameFileName, '.SZT');
{$ELSE}
			GameWorldSave('Save world:', LoadedGameFileName, '.ZZT');
{$ENDIF}
			if EditorSeparateStartingBoard and (startingBoard >= 0) then begin
				BoardChange(tmpBoard);
			end;
			EditorSaveWorld := InputKeyPressed <> KEY_ESCAPE;
		end;

	procedure EditorAskSaveChanged;
		begin
			InputKeyPressed := #0;
			if wasModified then begin
				if SidebarPromptYesNo('Save first? ', true) then begin
					if InputKeyPressed <> KEY_ESCAPE then
						if EditorSaveWorld then begin end;
				end;
			end;
			World.Info.Name := LoadedGameFileName;
		end;

	function EditorPrepareModifyTile(x, y: integer): boolean;
		begin
			wasModified := true;
			EditorPrepareModifyTile := BoardPrepareTileForPlacement(x, y);
			EditorDrawTileAndNeighborsAt(x, y);
		end;

	function EditorPrepareModifyStatAtCursor: boolean;
		begin
			if Board.StatCount < MAX_STAT then
				EditorPrepareModifyStatAtCursor := EditorPrepareModifyTile(cursorX, cursorY)
			else
				EditorPrepareModifyStatAtCursor := false;
		end;

	procedure EditorPlaceTile(x, y: integer);
		begin
			with Board.Tiles[x][y] do begin
				if cursorPattern <= EditorPatternCount then begin
					if EditorPrepareModifyTile(x, y) then begin
						Element := EditorPatterns[cursorPattern];
						Color := cursorColor;
					end;
				end else with copiedTiles[cursorPattern - EditorPatternCount] do begin
					if isMainPlayer then begin
						if EditorPrepareModifyTile(x, y) then
							MoveStat(0, x, y);
					end else if hasStat then begin
						if EditorPrepareModifyStatAtCursor then begin
							AddStat(x, y, tile.Element, tile.Color, stat.Cycle, stat);
						end
					end else begin
						if EditorPrepareModifyTile(x, y) then begin
							Board.Tiles[x][y] := tile;
						end;
					end;
				end;

				EditorDrawTileAndNeighborsAt(x, y);
			end;
		end;

	procedure EditorRemoveTile(x, y: integer);
		var
			statId: integer;
		begin
			statId := GetStatIdAt(x, y);
			if statId > 0 then
				RemoveStat(statId)
			else if statId < 0 then
				Board.Tiles[x][y].Element := E_EMPTY
			else exit; { statId = 0 (player) cannot be modified }
			BoardDrawTile(x, y);
			EditorDrawStatsState;
		end;

	procedure EditorEditBoardInfo;
		var
			state: TTextWindowState;
			i: integer;
			numStr: string[20];
			numStrTwo: string[20];
			exitRequested: boolean;

		function BoolToString(val: boolean): string;
			begin
				if val then
					BoolToString := 'Yes'
				else
					BoolToString := 'No ';
			end;

		begin
			state.Title := 'Board Information';
			TextWindowDrawOpen(state);
			state.LinePos := 1;
			exitRequested := false;

			repeat
				state.Selectable := true;
				state.LineCount := 12;
				for i := 1 to state.LineCount do
					New(state.Lines[i]);

				state.Lines[1]^ := '         Title: ' + Board.Name;

				Str(Board.Info.MaxShots, numStr);
				state.Lines[2]^ := '      Can fire: ' + numStr + ' shots.';

{$IFDEF E_SUPERZ}
				{ TODO: Remove completely. }
				state.Lines[3]^ := ' Board is dark: No';
{$ELSE}
				state.Lines[3]^ := ' Board is dark: ' + BoolToString(Board.Info.IsDark);
{$ENDIF}

				for i := 4 to 7 do begin
					state.Lines[i]^ := NeighborBoardStrs[i - 4] + ': ' +
						EditorGetBoardName(Board.Info.NeighborBoards[i - 4], true);
				end;

				state.Lines[8]^ := 'Re-enter when zapped: ' + BoolToString(Board.Info.ReenterWhenZapped);

				Str(Board.Info.TimeLimitSec, numStr);
				state.Lines[9]^ := '  Time limit, 0=None: ' + numStr + ' sec.';

				state.Lines[10]^ := '';
				Str(BoardCurrentStorageSize, numStr);
{$IFDEF DEBUGWND}
				if DebugCompatEnabled then
					Str(ZZT_32_BOARD_MAX_SIZE, numStrTwo)
				else
{$ENDIF}
					Str(IO_BUFFER_MAXIMUM_SIZE, numStrTwo);
				state.Lines[11]^ := 'Board size: ' + numStr + '/' + numStrTwo + ' bytes.';
				state.Lines[12]^ := '!;Exit';

				TextWindowSelect(state, TWS_HYPERLINK_AS_SELECT);
				if (InputKeyPressed = KEY_ENTER) and (state.LinePos <> 12) then begin
					wasModified := true;
					case state.LinePos of
						1: begin
							PopupPromptString('New title for board:', Board.Name, MAX_BOARD_NAME_LENGTH);
							exitRequested := true;
							TextWindowDrawClose(state);
						end;
						2: begin
							i := Board.Info.MaxShots;
							SidebarPromptNumericAsString('Maximum shots?', '', 0, 255, i);
							Board.Info.MaxShots := i;
							EditorDrawSidebar;
						end;
						3: begin
{$IFDEF E_ZZT}
							Board.Info.IsDark := not Board.Info.IsDark;
{$ENDIF}
						end;
						4, 5, 6, 7: begin
							i := EditorSelectBoard(
								NeighborBoardStrs[state.LinePos - 4],
								Board.Info.NeighborBoards[state.LinePos - 4],
								true, true, true, false
							);
							if not TextWindowRejected then begin
								if i > World.BoardCount then begin
									EditorAppendBoard;
									exitRequested := true;
								end else begin
									Board.Info.NeighborBoards[state.LinePos - 4] := i;
								end;
							end;
						end;
						8: begin
							Board.Info.ReenterWhenZapped := not Board.Info.ReenterWhenZapped;
						end;
						9: begin
							SidebarPromptNumericAsString('Time limit?', ' Sec',  -32768, 32767, Board.Info.TimeLimitSec);
							EditorDrawSidebar;
						end;
					end
				end else begin
					exitRequested := true;
					TextWindowDrawClose(state);
				end;

				TextWindowFreeEdit(state);
			until exitRequested;
		end;

	procedure EditorEditWorldInfo;
		var
			state: TTextWindowState;
			i: integer;
			numStr: string[20];
			exitRequested: boolean;
		begin
			state.Title := 'World Information';
			TextWindowDrawOpen(state);
			state.LinePos := 1;
			exitRequested := false;

			repeat
				state.Selectable := true;
				state.LineCount := 4;
				for i := 1 to state.LineCount do
					New(state.Lines[i]);

				Str(World.Info.Health, numStr);
				state.Lines[1]^  := ' Starting health: ' + numStr;
				state.Lines[2]^  := '  Starting board: ' + EditorGetBoardName(EditorGetStartingBoard, false);
				state.Lines[3]^ := '';
				state.Lines[4]^ := '!;Exit';

				TextWindowSelect(state, TWS_HYPERLINK_AS_SELECT);
				if (InputKeyPressed = KEY_ENTER) and (state.LinePos <> 4) then begin
					case state.LinePos of
						1: begin
							SidebarPromptNumericAsString('Health?', '', -32768, 32767, World.Info.Health);
							EditorDrawSidebar;
							wasModified := true;
						end;
						2: if EditorSeparateStartingBoard then begin
							i := EditorSelectBoard('Starting board',
								startingBoard, false, true, false, false);
							if not TextWindowRejected then begin
								startingBoard := i;
								wasModified := true;
							end;
						end;
					end
				end else begin
					exitRequested := true;
					TextWindowDrawClose(state);
				end;

				TextWindowFreeEdit(state);
			until exitRequested;
		end;

	procedure EditorEditStatText(statId: integer; prompt: string);
		var
			state: TTextWindowState;
			i, iLine, iChar, iStat: integer;
			affectedStats: array[0 .. MAX_STAT + 1] of boolean;
		begin
			with Board.Stats[statId] do begin
				state.Title := prompt;
				TextWindowDrawOpen(state);
				state.Selectable := false;
				CopyStatDataToTextWindow(statId, state);

				if DataLen > 0 then begin
					{ Mark every other object that uses our data so that
					  we can update its DataLen afterwards. }
					for iStat := 0 to Board.StatCount do
						affectedStats[iStat] := (Board.Stats[iStat].Data = Data);
					FreeMem(Data, DataLen);
					DataLen := 0;
				end else begin
					{ No other stats are affected. }
					FillChar(affectedStats, Board.StatCount + 1, false);
				end;

{$IFDEF SDL2}
				EditorOpenEditTextWindow(state, '.OBJ;.TXT', EditorSyntaxHighlightEnable, true);
{$ELSE}
				EditorOpenEditTextWindow(state, '.TXT', EditorSyntaxHighlightEnable, false);
{$ENDIF}

				for iLine := 1 to state.LineCount do
					Inc(DataLen, Length(state.Lines[iLine]^) + 1);

				if DataLen > 0 then begin
					GetMem(Data, DataLen);
				end;

				{ Update every bound object to have our possibly new pointer
					and new DataLen. }
				for iStat := 0 to Board.StatCount do
					if (iStat <> statId) and affectedStats[iStat] then begin
						Board.Stats[iStat].Data := Data;
						Board.Stats[iStat].DataLen := DataLen;
					end;

				i := 0;
				for iLine := 1 to state.LineCount do begin
					for iChar := 1 to Length(state.Lines[iLine]^) do begin
						{$IFNDEF FPC}
						{ On Turbo Pascal, the array pointer is actually }
						{ a poiter to a string. }
						Data^[i] := state.Lines[iLine]^[iChar];
						{$ELSE}
						Data[i] := state.Lines[iLine]^[iChar];
						{$ENDIF}
						Inc(i);
					end;

					{$IFNDEF FPC}
					{ On Turbo Pascal, the array pointer is actually }
					{ a poiter to a string. }
					Data^[i] := #13;
					{$ELSE}
					Data[i] := #13;
					{$ENDIF}
					Inc(i);
				end;

				TextWindowDrawClose(state);
				TextWindowFreeEdit(state);
				InputKeyPressed := #0;
			end;
		end;

	procedure EditorEditTileLowLevel(tx, ty, statId: integer);
		var
			state: TTextWindowState;
			i: integer;
			numStr: string[20];
			numStr2: string[20];
			actionMap: array[1 .. 32] of TLLEditAction;
			exitRequested: boolean;
			choiceResult: byte;
		function GetStatBoundToId: integer;
			var
				k: integer;
			begin
				for k := 0 to Board.StatCount do begin
					if (k <> statId) and (Board.Stats[k].Data = Board.Stats[statId].Data) then begin
						GetStatBoundToId := k;
						exit;
					end;
				end;
				GetStatBoundToId := -1;
			end;
		function GetStatName(newStatId: integer): string;
			var
				k: integer;
				statStr: string;
				xStr, yStr, idStr: string[20];
			begin
				if (newStatId < 0) then
					GetStatName := 'None'
				else if (newStatId > Board.StatCount) then begin
					Str(newStatId, idStr);
					GetStatName := idStr + ' ???';
				end else with Board.Stats[newStatId] do begin
					Str(X, xStr);
					EditorPadSpaces(xStr, 2);
					Str(Y, yStr);
					EditorPadSpaces(yStr, 2);
					Str(newStatId, idStr);
					statStr := idStr + ' ( ' + xStr + ', ' + yStr + ')';
					if (Data <> nil) and (DataLen > 0) then begin
						k := 0;
						OopReadChar(newStatId, k);
						if OopChar = '@' then
							statStr := statStr + ' ' + OopReadLineToEnd(newStatId, k);
					end;
					GetStatName := statStr;
				end;
			end;
		procedure AppendAction(action: TLLEditAction; name, value: string);
			var
				ccStr: TString50;
			begin
				Inc(state.LineCount);
				actionMap[state.LineCount] := action;
				New(state.Lines[state.LineCount]);
				ccStr := name + value;
				if Length(ccStr) > (TextWindowWidth - 9) then
					ccStr := Copy(ccStr, 1, (TextWindowWidth - 12)) + '...';
				state.Lines[state.LineCount]^ := ccStr;
			end;
{$IFDEF SDL2}
		procedure LongIntToHex(v: longint; var ns: string);
			const
				HEX_STR: array[0 .. 15] of char =
					('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
			begin
				ns[0] := Chr(11);
				ns[1] := HEX_STR[(v shr 4) and 15];
				ns[2] := HEX_STR[(v shr 0) and 15];
				ns[3] := ' ';
				ns[4] := HEX_STR[(v shr 12) and 15];
				ns[5] := HEX_STR[(v shr 8) and 15];
				ns[6] := ' ';
				ns[7] := HEX_STR[(v shr 20) and 15];
				ns[8] := HEX_STR[(v shr 16) and 15];
				ns[9] := ' ';
				ns[10] := HEX_STR[(v shr 28) and 15];
				ns[11] := HEX_STR[(v shr 24) and 15];
			end;
{$ENDIF}
		begin
			state.Title := 'Low-Level Tile Data';
			TextWindowDrawOpen(state);
			state.LinePos := 1;
			exitRequested := false;

			repeat
				for i := 1 to 32 do
					actionMap[i] := LLEditNone;
				state.Selectable := true;
				state.LineCount := 0;

				if (tx > 0) and (ty > 0) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then
				with Board.Tiles[tx][ty] do begin
					AppendAction(LLEditNone, '$Tile', '');
					if statId < 0 then begin
						Str(tx, numStr);
						AppendAction(LLEditNone, '            X: ', numStr);
						Str(ty, numStr);
						AppendAction(LLEditNone, '            Y: ', numStr);
					end;
					AppendAction(LLEditElement, '   Element: ', EditorGetElementName(Element));
					AppendAction(LLEditColor, '     Color: ', EditorGetColorName(Color));
					AppendAction(LLEditNone, '', '');
				end;

				if statId >= 0 then with Board.Stats[statId] do begin
					AppendAction(LLEditNone, '$Stat', '');
					Str(statId, numStr);
					AppendAction(LLEditNone, '     Index: ', numStr);
					Str(X, numStr);
					AppendAction(LLEditX, '         X: ', numStr);
					Str(Y, numStr);
					AppendAction(LLEditY, '         Y: ', numStr);
					Str(StepX, numStr);
					AppendAction(LLEditStepX, '    Step X: ', numStr);
					Str(StepY, numStr);
					AppendAction(LLEditStepY, '    Step Y: ', numStr);
					Str(Cycle, numStr);
					AppendAction(LLEditCycle, '     Cycle: ', numStr);
					Str(P1, numStr);
					AppendAction(LLEditP1, '   Param 1: ', numStr);
					Str(P2, numStr);
					AppendAction(LLEditP2, '   Param 2: ', numStr);
					Str(P3, numStr);
					AppendAction(LLEditP3, '   Param 3: ', numStr);
					AppendAction(LLEditFollower, '  Follower: ', GetStatName(Follower));
					AppendAction(LLEditLeader, '    Leader: ', GetStatName(Leader));
					AppendAction(LLEditUnderElement, ' '#25' Element: ', EditorGetElementName(Under.Element));
					AppendAction(LLEditUnderColor, ' '#25'   Color: ', EditorGetColorName(Under.Color));
					AppendAction(LLEditNone, '', '');
					if DataLen > 0 then begin
						Str(DataLen, numStr);
						AppendAction(LLEditData, '      Data: ', numStr + ' bytes');
					end else begin
						AppendAction(LLEditData, '      Data: ', 'None');
					end;
					Str(DataPos, numStr);
					AppendAction(LLEditDataPos, '       Pos: ', numStr);
					AppendAction(LLEditDataBound, '  Bound to: ', GetStatName(GetStatBoundToId));
					AppendAction(LLEditNone, '', '');
{$IFDEF SDL2}
					LongIntToHex(UnusedData, numStr);
					AppendAction(LLEditNone, ' Ptr bytes: ', numStr);
{$IFDEF E_ZZT}
					LongIntToHex(Unused1, numStr);
					LongIntToHex(Unused2, numStr2);
					AppendAction(LLEditNone, ' Ext bytes: ', numStr + ' ' + numStr2);
{$ENDIF}
					AppendAction(LLEditNone, '', '');
{$ENDIF}
					if Board.StatCount > 0 then begin
						AppendAction(LLEditDeleteStat, '!;Delete', '');
					end;
				end;

				AppendAction(LLEditNone, '!;Exit', '');

				TextWindowSelect(state, TWS_HYPERLINK_AS_SELECT);
				if (InputKeyPressed = KEY_ENTER) and (state.LinePos <> state.LineCount) then begin
					if (tx > 0) and (ty > 0) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then
					with Board.Tiles[tx][ty] do case actionMap[state.LinePos] of
						LLEditElement: begin
							EditorSelectElement('Element?', Element, true);
							wasModified := true;
						end;
						LLEditColor: begin
							Color := cursorColor;
							wasModified := true;
						end;
					end;

					if statId >= 0 then with Board.Stats[statId] do case actionMap[state.LinePos] of
						LLEditX: begin
							i := X;
							SidebarPromptNumericAsString('X?', '', 0, 255, i);
							X := i; tx := i;
							wasModified := true;
						end;
						LLEditY: begin
							i := Y;
							SidebarPromptNumericAsString('Y?', '', 0, 255, i);
							Y := i; ty := i;
							wasModified := true;
						end;
						LLEditStepX: begin
							SidebarPromptNumericAsString('Step X?', '', -32768, 32767, StepX);
							wasModified := true;
						end;
						LLEditStepY: begin
							SidebarPromptNumericAsString('Step Y?', '', -32768, 32767, StepY);
							wasModified := true;
						end;
						LLEditCycle: begin
							SidebarPromptNumericAsString('Cycle?', '', -32768, 32767, Cycle);
							wasModified := true;
						end;
						LLEditP1: begin
							i := P1;
							SidebarPromptNumericAsString('Param 1?', '', 0, 255, i);
							P1 := i;
							wasModified := true;
						end;
						LLEditP2: begin
							i := P2;
							SidebarPromptNumericAsString('Param 2?', '', 0, 255, i);
							P2 := i;
							wasModified := true;
						end;
						LLEditP3: begin
							i := P3;
							SidebarPromptNumericAsString('Param 3?', '', 0, 255, i);
							P3 := i;
							wasModified := true;
						end;
						LLEditFollower: begin
							i := EditorSelectStat('Follower?', Follower, true, true, false, false);
							if not TextWindowRejected then begin
								Follower := i;
								wasModified := true;
							end;
						end;
						LLEditLeader: begin
							i := EditorSelectStat('Leader?', Leader, true, true, false, false);
							if not TextWindowRejected then begin
								Leader := i;
								wasModified := true;
							end;
						end;
						LLEditUnderElement: begin
							EditorSelectElement('Element?', Under.Element, true);
							wasModified := true;
						end;
						LLEditUnderColor: begin
							Under.Color := cursorColor;
							wasModified := true;
						end;
						LLEditData: begin
							EditorEditStatText(statId, ElementDefs[Board.Tiles[X][Y].Element].ParamTextName);
						end;
						LLEditDataBound: begin
							i := EditorSelectStat('Bound to?', GetStatBoundToId, true, true, false, false);
							if not TextWindowRejected then begin
								FreeStatDataMem(statId, true);
								if (i >= 0) and (i <> statId) then begin
									Data := Board.Stats[i].Data;
									DataLen := Board.Stats[i].DataLen;
								end else begin
									DataLen := 0;
								end;
								wasModified := true;
							end;
						end;
						LLEditDataPos: begin
							{ -1 .. DataLen }
							SidebarPromptNumericAsString('Pos?', '', -32768, 32767, DataPos);
						end;
						LLEditDeleteStat: begin
							if Board.StatCount > 0 then begin
								choiceResult := 1;
								SidebarPromptChoice(true, 3, 'Confirm delete:', 'Yes No', choiceResult);
								if choiceResult = 0 then begin
									if not EditorShiftStat(
										statId,
										-1,
										IdShiftDelete) then begin end;
									statId := -1;
								end;
							end;
						end;
					end
				end else begin
					exitRequested := true;
					TextWindowDrawClose(state);
				end;

				TextWindowFreeEdit(state);
			until exitRequested;
		end;

	procedure EditorEditStat(statId: integer);
		var
			element: byte;
			i: integer;
			categoryName: string;
			selectedBoard: byte;
			iy: integer;
			promptByte: byte;

		procedure EditorEditStatSettings(selected: boolean);
			begin
				with Board.Stats[statId] do begin
					InputKeyPressed := #0;
					iy := 9;

					if Length(ElementDefs[element].Param1Name) <> 0 then begin
						if Length(ElementDefs[element].ParamTextName) = 0 then begin
							SidebarPromptSlider(selected, VideoSidebarX + 3, iy, ElementDefs[element].Param1Name, P1);
						end else begin
							if P1 = 0 then
								P1 := World.EditorStatSettings[element].P1;
							BoardDrawTile(X, Y);
							SidebarPromptCharacter(selected, VideoSidebarX + 3, iy, ElementDefs[element].Param1Name, P1);
							BoardDrawTile(X, Y);
						end;
						if selected then
							World.EditorStatSettings[element].P1 := P1;
						Inc(iy, 4);
					end;

					{ if element = E_OBJECT then begin
						SidebarPromptNumeric(selected, VideoSidebarX + 3, iy, 'Initial cycle?', 1, 420, Cycle);
						Inc(iy, 4);
					end; }

					if (element = E_BULLET) or (element = E_STAR) then
						P2 := 100; { unused on bullet, lifetime on star }

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamTextName) <> 0) then
					begin
						if selected then
							EditorEditStatText(statId, ElementDefs[element].ParamTextName);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].Param2Name) <> 0) then
					begin
						promptByte := (P2 and $7F);
						SidebarPromptSlider(selected, VideoSidebarX + 3, iy, ElementDefs[element].Param2Name, promptByte);
						if selected then begin
							P2 := (P2 and $80) + promptByte;
							World.EditorStatSettings[element].P2 := P2;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamBulletTypeName) <> 0) then
					begin
						promptByte := P2 shr 7;
						SidebarPromptChoice(selected, iy, ElementDefs[element].ParamBulletTypeName,
							'Bullets Stars', promptByte);
						if selected then begin
							P2 := (P2 and $7F) + (promptByte shl 7);
							World.EditorStatSettings[element].P2 := P2;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(element = E_BULLET) then
					begin
						promptByte := (P1 and 1);
						SidebarPromptChoice(selected, iy, 'Source?', 'Player Creature', promptByte);
						if selected then begin
							P1 := promptByte;
							World.EditorStatSettings[element].P1 := P1;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamDirName) <> 0) then
					begin
						SidebarPromptDirection(selected, iy, ElementDefs[element].ParamDirName,
							StepX, StepY);
						if selected then begin
							World.EditorStatSettings[element].StepX := StepX;
							World.EditorStatSettings[element].StepY := StepY;
						end;
						Inc(iy, 4);
					end;

					if (InputKeyPressed <> KEY_ESCAPE) and
						(Length(ElementDefs[element].ParamBoardName) <> 0) then
					begin
						if selected then begin
							selectedBoard := EditorSelectBoard(ElementDefs[element].ParamBoardName, P3,
								false, false, true, false);
							if (not TextWindowRejected) then begin
								P3 := selectedBoard;
								World.EditorStatSettings[element].P3 := World.Info.CurrentBoard;
								if P3 > World.BoardCount then begin
									EditorAppendBoard;
									{ TODO: is this still necessary? }
									{ copiedHasStat := false;
									copiedTile.Element := 0;
									copiedTile.Color := $0F; }
								end;
								World.EditorStatSettings[element].P3 := P3;
							end else begin
								InputKeyPressed := KEY_ESCAPE;
							end;
							Inc(iy, 4);
						end else begin
							VideoWriteText(VideoSidebarX + 3, iy, $1F, 'Room: ' + Copy(EditorGetBoardName(P3, true), 1, 10));
						end;
					end;
				end;
			end;

		begin
			with Board.Stats[statId] do begin
				SidebarClear;

				element := Board.Tiles[X][Y].Element;
				wasModified := true;

				categoryName := '';
				for i := 0 to element do begin
					if (ElementDefs[i].EditorCategory = ElementDefs[element].EditorCategory)
						and (Length(ElementDefs[i].CategoryName) <> 0) then
					begin
						categoryName := ElementDefs[i].CategoryName;
					end;
				end;

				VideoWriteText(VideoSidebarX + 4, 6, $1E, categoryName);
				VideoWriteText(VideoSidebarX + 4, 7, $1F, ElementDefs[element].Name);

				EditorEditStatSettings(false);
				EditorEditStatSettings(true);

				if InputKeyPressed <> KEY_ESCAPE then begin
					EditorCopyPatternToCurrent(X, Y);
				end;
			end;
		end;

	procedure EditorTransferBoard;
		var
			i: byte;
			f: file;
			memoryError: boolean;
		label TransferEnd;
		begin
			i := 1;
			memoryError := false;
			SidebarPromptChoice(true, 3, 'Transfer board:', 'Import Export', i);
			if InputKeyPressed <> KEY_ESCAPE then begin
				if i = 0 then begin
					SavedBoardFileName := FileSelect('ZZT Boards', '.BRD', FileBoardCachedLinePos);
					if (InputKeyPressed <> KEY_ESCAPE) and (Length(SavedBoardFileName) <> 0) then begin
						AssignFSys(f, SavedBoardFileName + '.BRD');
						Reset(f, 1);
						if DisplayIOError then begin
							Close(f);
							goto TransferEnd;
						end;

						BoardClose;
						ExtMemFree(WorldExt.BoardData[World.Info.CurrentBoard], WorldExt.BoardLen[World.Info.CurrentBoard]);
						BlockRead(f, WorldExt.BoardLen[World.Info.CurrentBoard], 2);
{$IFDEF ENDIAN_BIG}
						WorldExt.BoardLen[World.Info.CurrentBoard] := LEtoN(WorldExt.BoardLen[World.Info.CurrentBoard]);
{$ENDIF}
						if not DisplayIOError then begin
							case EnsureIoTmpBufSize(WorldExt.BoardLen[World.Info.CurrentBoard]) of
								2: memoryError := true;
								0, 1: begin
									if ExtMemGet(WorldExt.BoardData[World.Info.CurrentBoard],
									WorldExt.BoardLen[World.Info.CurrentBoard]) then begin
										BlockRead(f, IoTmpBuf^,
											  WorldExt.BoardLen[World.Info.CurrentBoard]);
										ExtMemWrite(WorldExt.BoardData[World.Info.CurrentBoard], IoTmpBuf^,
											  WorldExt.BoardLen[World.Info.CurrentBoard]);
									end else memoryError := true;
								end;
							end;
						end;

						Close(f);

						if DisplayIOError or memoryError then begin
							{ TODO: Show out of memory error. }
							WorldExt.BoardLen[World.Info.CurrentBoard] := 0;
							BoardCreate;
							EditorDrawRefresh;
						end else begin
							BoardOpen(World.Info.CurrentBoard);
							EditorDrawRefresh;
							for i := 0 to 3 do
								Board.Info.NeighborBoards[i] := 0;
						end;
					end;
				end else if i = 1 then begin
					SidebarPromptFilename('Export board', '.BRD', SavedBoardFileName, PROMPT_ALPHANUM);
					if (InputKeyPressed <> KEY_ESCAPE) and (Length(SavedBoardFileName) <> 0)
					and (OverwriteCheck(SavedBoardFilename + '.BRD')) then begin
						case EnsureIoTmpBufSize(WorldExt.BoardLen[World.Info.CurrentBoard]) of
							0, 1: begin
								AssignFSys(f, SavedBoardFileName + '.BRD');
								Rewrite(f, 1);
								if DisplayIOError then begin
									Close(f);
									goto TransferEnd;
								end;

								BoardClose;
{$IFDEF ENDIAN_BIG}
								BlockWrite(f, NtoLE(WorldExt.BoardLen[World.Info.CurrentBoard]), 2);
{$ELSE}
								BlockWrite(f, WorldExt.BoardLen[World.Info.CurrentBoard], 2);
{$ENDIF}
								ExtMemRead(WorldExt.BoardData[World.Info.CurrentBoard], IoTmpBuf^,
									WorldExt.BoardLen[World.Info.CurrentBoard]);
								BlockWrite(f, IoTmpBuf^,
									WorldExt.BoardLen[World.Info.CurrentBoard]);
								BoardOpen(World.Info.CurrentBoard);

								Close(f);

								if DisplayIOError then begin end;
							end;
							2: begin end; { TODO: Show out of memory error. }
						end;
					end;
				end;
			end;
		TransferEnd:
			EditorDrawSidebar;
		end;

	procedure EditorMoveCursor(newX, newY: integer; redraw: boolean);
		var
			i: integer;
		begin
			if newX < 1 then
				newX := 1
			else if newX > BOARD_WIDTH then
				newX := BOARD_WIDTH;
			if newY < 1 then
				newY := 1
			else if newY > BOARD_HEIGHT then
				newY := BOARD_HEIGHT;

{$IFDEF E_SUPERZ}
			if (newX < Board.Info.DrawXOffset)
				or ((Board.Info.DrawXOffset + BOARD_DRAW_WIDTH) <= newX)
				or (Board.Info.DrawXOffset < BOARD_DRAW_OX_MIN)
				or (Board.Info.DrawXOffset > BOARD_DRAW_OX_MAX)
			then begin
				redraw := true;
				Board.Info.DrawXOffset := newX - (BOARD_DRAW_WIDTH shr 1);
				if Board.Info.DrawXOffset < BOARD_DRAW_OX_MIN then
					Board.Info.DrawXOffset := BOARD_DRAW_OX_MIN
				else if Board.Info.DrawXOffset > BOARD_DRAW_OX_MAX then
					Board.Info.DrawXOffset := BOARD_DRAW_OX_MAX;
			end;

			if (newY < Board.Info.DrawYOffset)
				or ((Board.Info.DrawYOffset + BOARD_DRAW_HEIGHT) <= newY)
				or (Board.Info.DrawYOffset < BOARD_DRAW_OY_MIN)
				or (Board.Info.DrawYOffset > BOARD_DRAW_OY_MAX)
			then begin
				redraw := true;
				Board.Info.DrawYOffset := newY - (BOARD_DRAW_HEIGHT shr 1);
				if Board.Info.DrawYOffset < BOARD_DRAW_OY_MIN then
					Board.Info.DrawYOffset := BOARD_DRAW_OY_MIN
				else if Board.Info.DrawYOffset > BOARD_DRAW_OY_MAX then
					Board.Info.DrawYOffset := BOARD_DRAW_OY_MAX;
			end;
{$ENDIF}

			cursorX := newX;
			cursorY := newY;
			if redraw then begin
				TransitionDrawToBoard;
				showingBoardName := false;
			end else begin
{$IFDEF E_ZZT}
				if showingBoardName and (cursorY = 1) then begin
					for i := 1 to BOARD_WIDTH do
						BoardDrawTile(i, 1);
					showingBoardName := false;
				end;
{$ENDIF}
			end;

			EditorDrawCursorPos;
		end;

	procedure EditorResetCursor;
		begin
{$IFDEF E_ZZT}
			EditorMoveCursor(30, 12, false);
{$ELSE}
			EditorMoveCursor(Board.Stats[0].X, Board.Stats[0].Y, false);
{$ENDIF}
		end;

	procedure EditorBoardChange(boardId: integer);
		begin
			if BoardCurrentStorageSize > IO_BUFFER_MAXIMUM_SIZE then begin
				SidebarClearLine(3);
				SidebarClearLine(4);
				SidebarClearLine(5);
				VideoWriteText(VideoSidebarX + 2, 4, $1E, 'Board too large!');
				PauseOnError;
				EditorDrawSidebar;
				exit;
			end;

			BoardChange(boardId);
			EditorMoveCursor(Board.Stats[0].X, Board.Stats[0].Y, false);
			if not EditorSeparateStartingBoard then
				startingBoard := World.Info.CurrentBoard;
		end;

	procedure EditorUpdateCursorPos(drawCursor: boolean);
		begin
			if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
{				EditorMoveCursor(
					((Integer(KeysAltHeld) * ((BOARD_DRAW_WIDTH shr 1) - 1)) + 1) * InputDeltaX + cursorX,
					((Integer(KeysAltHeld) * ((BOARD_DRAW_HEIGHT shr 1) - 1)) + 1) * InputDeltaY + cursorY,
					false
				); }
				EditorMoveCursor(
					((Integer(KeysAltHeld) * 9) + 1) * InputDeltaX + cursorX,
					((Integer(KeysAltHeld) * 4) + 1) * InputDeltaY + cursorY,
					false
				);

				if drawCursor then
					EditorDrawCursor;
				if (InputKeyPressed = #0) and InputJoystickMoved then
					AccurateDelay(70);
				InputShiftAccepted := false;
			end;
		end;

	procedure EditorFreeCopyBuffer;
		var
			i: integer;
		begin
			with copyBuffer do begin
				if width <= 0 then exit;

				FreeMem(tiles, Integer(width) * Integer(height) * SizeOf(TTile));
				width := 0;

				if statCount > 0 then begin
					for i := 1 to statCount do begin
						with stats^[i] do begin
							if Data <> nil then FreeMem(Data, DataLen);
						end;
					end;
					FreeMem(stats, statCount * SizeOf(TStat));
				end;
			end;
		end;

	procedure EditorRefreshCopyBuffer(ox, oy, width, height: integer);
		var
			ix, iy, tx, ty: integer;
		begin
			{ Refresh }
			for iy := -1 to (height + 1) do begin
				for ix := -1 to (width + 1) do begin
					tx := ox + ix;
					ty := oy + iy;
					if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then
						BoardDrawTile(tx, ty);
				end;
			end;
			EditorDrawStatsState;
		end;

	procedure EditorPasteCopyBuffer(ox, oy: integer);
		var
			ix, iy, ip, ist, tx, ty: integer;
		begin
			Dec(ox);
			Dec(oy);

			with copyBuffer do begin
				if width <= 0 then exit;

				{ Paste - Tiles }
				ip := 0;
				for iy := 1 to height do begin
					for ix := 1 to width do begin
						tx := ox + ix;
						ty := oy + iy;
						if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
							ist := GetStatIdAt(tx, ty);
							while ist > 0 do begin
								RemoveStat(ist);
								ist := GetStatIdAt(tx, ty);
							end;
							if ist < 0 then begin
								Board.Tiles[tx][ty] := tiles^[ip];
							end;
						end;
						Inc(ip);
					end;
				end;

				{ Paste - Stats }
				for ix := 1 to statCount do begin
					with stats^[ix] do begin
						tx := ox + X;
						ty := oy + Y;
					end;
					if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
						if Board.StatCount < MAX_STAT then begin
							Inc(Board.StatCount);
							EditorCopyStat(stats^[ix], Board.Stats[Board.StatCount]);
							with Board.Stats[Board.StatCount] do begin
								Inc(X, ox);
								Inc(Y, oy);
							end;
						end else begin
							ist := GetStatIdAt(tx, ty);
							if ist < 0 then begin
								Board.Tiles[tx][ty].Element := E_EMPTY;
							end;
						end;
					end;
				end;

				EditorRefreshCopyBuffer(ox + 1, oy + 1, width, height);
			end;
		end;

	procedure EditorBoardInvert(x1, y1, x2, y2: integer);
		var
			ix: integer;
{$IFDEF E_SUPERZ}
			sx1, sy1, sx2, sy2: integer;
{$ENDIF}
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

{$IFDEF E_SUPERZ}
			sx1 := x1 + BOARD_DRAW_X - Board.Info.DrawXOffset;
			sy1 := y1 + BOARD_DRAW_Y - Board.Info.DrawYOffset;
			sx2 := x2 + BOARD_DRAW_X - Board.Info.DrawXOffset;
			sy2 := y2 + BOARD_DRAW_Y - Board.Info.DrawYOffset;

			if sx1 < BOARD_DRAW_X then
				sx1 := BOARD_DRAW_X
			else if sx1 >= (BOARD_DRAW_X + BOARD_DRAW_WIDTH) then
				exit;

			if sx2 < BOARD_DRAW_X then
				exit
			else if sx2 >= (BOARD_DRAW_X + BOARD_DRAW_WIDTH) then
				sx2 := BOARD_DRAW_X + BOARD_DRAW_WIDTH - 1;

			if sy1 < BOARD_DRAW_Y then
				sy1 := BOARD_DRAW_Y
			else if sy1 >= (BOARD_DRAW_Y + BOARD_DRAW_HEIGHT) then
				exit;

			if sy2 < BOARD_DRAW_Y then
				exit
			else if sy2 >= (BOARD_DRAW_Y + BOARD_DRAW_HEIGHT) then
				sy2 := BOARD_DRAW_Y + BOARD_DRAW_HEIGHT - 1;

			VideoInvert(sx1, sy1, sx2, sy2);
{$ELSE}
			VideoInvert(x1 - 1, y1 - 1, x2 - 1, y2 - 1);
{$ENDIF}
		end;

	procedure EditorAskAndPasteCopyBuffer(ox, oy: integer);
		procedure InvertSel;
			var
				maxX, maxY: integer;
			begin
				maxX := ox + copyBuffer.width - 1;
				maxY := oy + copyBuffer.height - 1;
				if maxX >= BOARD_WIDTH then maxX := BOARD_WIDTH - 1;
				if maxY >= BOARD_HEIGHT then maxY := BOARD_HEIGHT - 1;
				EditorBoardInvert(ox, oy, maxX, maxY);
			end;
		begin
			InvertSel;
			while true do begin
				InputReadWaitKey;
				case InputKeyPressed of
					KEY_ENTER: begin
						InvertSel;
						EditorPasteCopyBuffer(ox, oy);
						exit;
					end;
					KEY_ESCAPE: begin
						InvertSel;
						exit;
					end;
				end;
			end;
		end;

	procedure EditorCopyCopyBuffer(ox1, oy1, ox2, oy2: integer; doCopy, doCut: boolean);
		var
			ix, iy, ip, ist, tx, ty, iw, ih: integer;
		begin
			EditorFreeCopyBuffer;
			if ox2 < ox1 then begin
				ix := ox1;
				ox1 := ox2;
				ox2 := ix;
			end;
			if oy2 < oy1 then begin
				ix := oy1;
				oy1 := oy2;
				oy2 := ix;
			end;

			Dec(ox1);
			Dec(oy1);

			iw := ox2 - ox1;
			ih := oy2 - oy1;

			if doCopy then with copyBuffer do begin
				width := iw;
				height := ih;
				statCount := 0;

				{ Copy - Tiles }
				GetMem(tiles, Integer(width) * Integer(height) * SizeOf(TTile));
				ip := 0;
				for iy := 1 to height do begin
					for ix := 1 to width do begin
						tx := ox1 + ix;
						ty := oy1 + iy;

						with tiles^[ip] do begin
							Element := E_EMPTY;
							Color := $0F;
						end;

						if (tx >= 1) and (ty >= 1) and (tx <= BOARD_WIDTH) and (ty <= BOARD_HEIGHT) then begin
							if (tx <> Board.Stats[0].X) or (ty <> Board.Stats[0].Y) then begin
								tiles^[ip] := Board.Tiles[tx][ty];
							end;
						end;

						Inc(ip);
					end;
				end;

				{ Copy - Stats, count }
				for ist := 1 to Board.StatCount do begin
					with Board.Stats[ist] do begin
						if (X > ox1) and (Y > oy1) and (X <= (ox1 + width)) and (Y <= (oy1 + height)) then begin
							Inc(statCount);
						end;
					end;
				end;

				{ Copy - Stats }
				if statCount > 0 then begin
					GetMem(stats, statCount * SizeOf(TStat));
					ip := 0;
					for ist := 1 to Board.StatCount do begin
						with Board.Stats[ist] do begin
							if (X > ox1) and (Y > oy1) and (X <= (ox1 + width)) and (Y <= (oy1 + height)) then begin
								Inc(ip);
								EditorCopyStat(Board.Stats[ist], stats^[ip]);
								with stats^[ip] do begin
									Dec(X, ox1);
									Dec(Y, oy1);
								end;
							end;
						end;
					end;
					if ip <> statCount then RunError(201);
				end;

				if doCut then begin
					for iy := 1 to height do
						for ix := 1 to width do
							EditorPlaceTile(ox1 + ix, oy1 + iy);
				end;
			end;

			EditorRefreshCopyBuffer(ox1, oy1, iw, ih);
		end;

	procedure EditorSelectAndCopyCopyBuffer(ox1, oy1: integer; doCut: boolean);
		var
			ix, iy, oldCx, oldCy: integer;
			doCopy: boolean;
			running: boolean;
		procedure InvertLocal;
			begin
				EditorBoardInvert(ox1, oy1, oldCx, oldCy);
			end;
		begin
			running := true;
			doCopy := false;

			oldCx := cursorX;
			oldCy := cursorY;

			BoardDrawTile(ox1, oy1);
			InvertLocal;

			while running do begin
				InputUpdate;

				if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
					InvertLocal;
					EditorUpdateCursorPos(false);
					oldCx := cursorX;
					oldCy := cursorY;
					InvertLocal;
				end;

				case InputKeyPressed of
					KEY_ESCAPE: begin
						running := false;
					end;
					KEY_ENTER: begin
						doCopy := true;
						running := false;
					end;
				end;
			end;

			EditorCopyCopyBuffer(ox1, oy1, oldCx, oldCy, doCopy, doCut);
			EditorDrawBufferState;

			if cursorX > ox1 then cursorX := ox1;
			if cursorY > oy1 then cursorY := oy1;
		end;

	procedure EditorTypeCharacter(ch: byte);
		var
			i: integer;
		begin
			if EditorPrepareModifyTile(cursorX, cursorY) then begin
				i := (cursorColor and $07) + (E_TEXT_MIN - 1);
				if i < E_TEXT_MIN then i := E_TEXT_MIN + 6;
				with Board.Tiles[cursorX][cursorY] do begin
					Element := i;
					Color := ch;
				end;
				EditorDrawTileAndNeighborsAt(cursorX, cursorY);
				InputDeltaX := 1;
				InputDeltaY := 0;
			end;
		end;

	procedure EditorPlaceElementNoStat(newElem, newColor: byte);
		begin
			if EditorPrepareModifyTile(cursorX, cursorY) then
				EditorSetAndCopyTile(cursorX, cursorY, newElem, newColor);
		end;

	procedure EditorPlaceElement(newElem, newColor: byte);
		var
			statSetting: TEditorStatSetting;
		begin
			if ElementDefs[newElem].Cycle = -1 then begin
				EditorPlaceElementNoStat(newElem, newColor);
			end else begin
				if EditorPrepareModifyStatAtCursor then begin
					AddStat(cursorX, cursorY, newElem, newColor,
						ElementDefs[newElem].Cycle, StatTemplateDefault);
					with Board.Stats[Board.StatCount] do begin
						statSetting := World.EditorStatSettings[newElem];
						if Length(ElementDefs[newElem].Param1Name) <> 0 then
							P1 := statSetting.P1;
						if Length(ElementDefs[newElem].Param2Name) <> 0 then
							P2 := statSetting.P2;
						if Length(ElementDefs[newElem].ParamDirName) <> 0 then begin
							StepX := statSetting.StepX;
							StepY := statSetting.StepY;
						end;
						if Length(ElementDefs[newElem].ParamBoardName) <> 0 then
							P3 := statSetting.P3;
					end;
					EditorEditStat(Board.StatCount);
					if InputKeyPressed = KEY_ESCAPE then
						RemoveStat(Board.StatCount);
				end;
			end;
		end;

	procedure EditorFloodFill(x, y: integer; from: TTile);
		var
			i: integer;
			tileAt, tilePlaced: TTile;
			toFill, filled: integer;
			xPosition: array[0 .. 511] of shortint;
			yPosition: array[0 .. 511] of shortint;
		begin
			toFill := 1;
			filled := 0;
			while toFill <> filled do begin
				tileAt := Board.Tiles[x][y];
				EditorPlaceTile(x, y);
				tilePlaced := Board.Tiles[x][y];
				if (tilePlaced.Element <> tileAt.Element)
					or (tilePlaced.Color <> tileAt.Color) then
					for i := 0 to 3 do
					with Board.Tiles[x + NeighborDeltaX[i]][y + NeighborDeltaY[i]] do begin
							if (Element = from.Element)
								and ((from.Element = 0) or (Color = from.Color)) then
							begin
								xPosition[toFill] := x + NeighborDeltaX[i];
								yPosition[toFill] := y + NeighborDeltaY[i];
								toFill := (toFill + 1) and $1FF;
							end;
						end;

				filled := (filled + 1) and $1FF;
				x := xPosition[filled];
				y := yPosition[filled];
			end;
		end;

{$IFDEF E_SUPERZ}
	procedure EditorSetViewMode(mode: integer);
		begin
			viewMode := mode;
			if viewMode = VIEW_EDITOR_LARGE then begin
{$IFDEF SDL2}
				if not GameVideoInstall(VIDEO_MODE_RESIZABLE, viewMode) then
{$ENDIF}
				if not GameVideoInstall(VIDEO_MODE_80X50, viewMode) then
				if not GameVideoInstall(VIDEO_MODE_80X43, viewMode) then
					if GameVideoInstall(VIDEO_MODE_80X25, viewMode) then begin end;	
			end else begin
				if GameVideoInstall(VIDEO_MODE_80X25, viewMode) then begin end;	
			end;
		end;
{$ENDIF}

	procedure EditorPlaceCursor(cx, cy: integer);
		begin
			with Board.Tiles[cx][cy] do begin
				if InputShiftPressed or (InputKeyPressed = ' ') then begin
					InputShiftAccepted := true;
					canModify := (Element = 0) or (InputDeltaX <> 0) or (InputDeltaY <> 0);
					if not canModify and ElementDefs[Element].PlaceableOnTop and (cursorPattern > EditorPatternCount) then begin
						{ Place stats -> Under }
						canModify := copiedTiles[cursorPattern - EditorPatternCount].hasStat;
					end;

					if canModify then begin
						EditorPlaceTile(cx, cy);
					end else begin
						canModify := EditorPrepareModifyTile(cx, cy);
						if canModify then
							Board.Tiles[cx][cy].Element := 0;
					end;
				end else if (InputKeyPressed = KEY_DELETE) then begin
					EditorRemoveTile(cx, cy);
				end else if drawMode = DrawingOn then begin
					EditorPlaceTile(cx, cy);
				end;
			end;
		end;

	label DrawNextCategory;
	label CheckNextCategory;
	label PlacementDone;
	begin
		EditorWorldCanOpenCheck(true);
{$IFDEF E_SUPERZ}
		EditorSetViewMode(VIEW_EDITOR);
{$ENDIF}

		InitElementsEditor;
		CurrentTick := 0;
		wasModified := false;
		drawMode := DrawingOff;
		cursorPattern := 1;
		cursorColor := $0E;
		colorIgnoreDefaults := false;
		cursorBlinker := 0;
		inputByte := 0;

		for i := 1 to COPIED_TILES_COUNT do
			EditorClearPattern(copiedTiles[i], true);
		FillChar(copyBuffer, SizeOf(TEditorCopyBuffer), 0);

		if World.Info.CurrentBoard <> 0 then
			BoardChange(World.Info.CurrentBoard);

		EditorResetCursor;
		EditorDrawRefresh;

		if World.BoardCount = 0 then begin
			EditorAppendBoard;
			EditorResetCursor;
			EditorDrawRefresh;
		end;

		EditorOnWorldOpen;

		editorExitRequested := false;
		repeat
{$IFDEF SDL2}
{$IFDEF E_SUPERZ}
			if VideoScaleChanged then begin
				if not GameVideoInstall(VIDEO_MODE_RESIZABLE, viewMode) then begin end;
				TextWindowInitXY(
					(VideoColumns - TextWindowWidth) div 2,
					(VideoRows - TextWindowHeight) div 2
				);
				EditorMoveCursor(cursorX, cursorY, false);
				EditorDrawRefresh;
				VideoScaleChanged := false;
			end;
{$ENDIF}
{$ENDIF}
			InputUpdate;
			if (InputKeyPressed = #0) and (InputDeltaX = 0) and (InputDeltaY = 0) and not InputShiftPressed then begin
				if SoundHasTimeElapsed(TickTimeCounter, 15) then
					cursorBlinker := (cursorBlinker + 1) mod 3;
				if cursorBlinker = 0  then
					BoardDrawTile(cursorX, cursorY)
				else
					EditorDrawCursor;
			end else begin
				BoardDrawTile(cursorX, cursorY);
			end;

			if drawMode = TextEntry then begin
				if (InputKeyPressed >= #32) and (InputKeyPressed < #128) then begin
					EditorTypeCharacter(Ord(InputKeyPressed));
				end else if (InputKeyPressed = KEY_BACKSPACE) and (cursorX > 1)
					and EditorPrepareModifyTile(cursorX - 1, cursorY) then
				begin
					EditorMoveCursor(cursorX - 1, cursorY, false);
				end else if (InputKeyPressed = KEY_ENTER) or (InputKeyPressed = KEY_ESCAPE) then begin
					drawMode := DrawingOff;
					EditorUpdateDrawMode;
				end else if (InputKeyPressed = KEY_F10) then begin
					SidebarPromptCharacter(true, VideoSidebarX + 3, 3, 'Character?', inputByte);
					EditorTypeCharacter(inputByte);
					EditorDrawSidebar;
				end;
				InputKeyPressed := #0;
			end;

			lastCursorX := cursorX;
			lastCursorY := cursorY;
			EditorUpdateCursorPos(true);
			if (lastCursorX = cursorX) and (lastCursorY = cursorY) then
				EditorPlaceCursor(lastCursorX, lastCursorY)
			else if (lastCursorX <> cursorX) and (lastCursorY <> cursorY) then
				EditorPlaceCursor(lastCursorX, lastCursorY)
			else if (lastCursorX < cursorX) then begin
				for i := lastCursorX to (cursorX - 1) do
					EditorPlaceCursor(i, cursorY);
			end else if (lastCursorX > cursorX) then begin
				for i := (cursorX + 1) to lastCursorX do
					EditorPlaceCursor(i, cursorY);
			end else if (lastCursorY < cursorY) then begin
				for i := lastCursorY to (cursorY - 1) do
					EditorPlaceCursor(cursorX, i);
			end else if (lastCursorY > cursorY) then begin
				for i := (cursorY + 1) to lastCursorY do
					EditorPlaceCursor(cursorX, i);
			end;

			with Board.Tiles[cursorX][cursorY] do begin
				case UpCase(InputKeyPressed) of
					'0'..'9': begin
						if InputKeyPressed = '0' then
							i := 10
						else
							i := Ord(InputKeyPressed) - 48;
						if i <= COPIED_TILES_COUNT then begin
							cursorPattern := EditorPatternCount + i;
							EditorUpdateCursorPattern;
						end;
					end;
					'`': EditorDrawRefresh;
					'P': begin
						if InputKeyPressed = 'P' then begin
							if cursorPattern > 1 then
								Dec(cursorPattern)
							else
								cursorPattern := EditorPatternCount + COPIED_TILES_COUNT;
						end else begin
							if cursorPattern < (EditorPatternCount + COPIED_TILES_COUNT) then
								Inc(cursorPattern)
							else
								cursorPattern := 1;
						end;
						EditorUpdateCursorPattern;
					end;
					'C': begin
						if InputKeyPressed = 'C' then begin
							if VideoGetBlinkMode = BlinkModeHigh then
								cursorColor := ((cursorColor + 16) and $FF)
							else
								cursorColor := (cursorColor and $8F) or ((cursorColor + 16) and $70);
						end else
							cursorColor := (cursorColor and $F0) or ((cursorColor + 1) and $0F);
						EditorUpdateCursorColor;
					end;
					'D': begin
						colorIgnoreDefaults := not colorIgnoreDefaults;
						EditorUpdateColorIgnoreDefaults;
					end;
					'L': begin
						SidebarClearLine(4);
						SidebarClearLine(5);
						EditorAskSaveChanged;
{$IFDEF E_SUPERZ}
						if (InputKeyPressed <> KEY_ESCAPE) and GameWorldLoad('.SZT') then begin
{$ELSE}
						if (InputKeyPressed <> KEY_ESCAPE) and GameWorldLoad('.ZZT') then begin
{$ENDIF}
							EditorOnWorldOpen;
							EditorWorldCanOpenCheck(false);
							wasModified := false;
							EditorMoveCursor(cursorX, cursorY, false);
							EditorDrawRefresh;
						end else begin
							EditorDrawSidebar;
						end;
					end;
					'S': begin
						if EditorSaveWorld then
							wasModified := false;
						EditorDrawSidebar;
					end;
					'Z': begin
						if SidebarPromptYesNo('Clear board? ', false) then begin
							for i := Board.StatCount downto 1 do
								RemoveStat(i);
							BoardCreate;
							EditorDrawRefresh;
						end else begin
							EditorDrawSidebar;
						end;
					end;
					'N': begin
						if SidebarPromptYesNo('Make new world? ', false) and (InputKeyPressed <> KEY_ESCAPE) then begin
							EditorAskSaveChanged;
							if (InputKeyPressed <> KEY_ESCAPE) then begin
								WorldUnload;
								WorldCreate;
								EditorOnWorldOpen;
								EditorDrawRefresh;
								wasModified := false;
							end;
						end;
						EditorDrawSidebar;
					end;
					'Q', KEY_ESCAPE: begin
						editorExitRequested := true;
					end;
					KEY_PAGE_UP: begin
						i := World.Info.CurrentBoard - 1;
						if i >= 0 then begin
							EditorBoardChange(i);
							EditorDrawRefresh;
						end;
					end;
					KEY_PAGE_DOWN: begin
						i := World.Info.CurrentBoard + 1;
						if i <= World.BoardCount then begin
							EditorBoardChange(i);
							EditorDrawRefresh;
						end;
					end;
					'B': begin
						i := EditorSelectBoard('Switch boards', World.Info.CurrentBoard, false, false, true, true);
						if (not TextWindowRejected) then begin
							if (i > World.BoardCount) then
								if SidebarPromptYesNo('Add new board? ', false) then
									EditorAppendBoard;
							EditorBoardChange(i);
							EditorDrawRefresh;
						end else begin
							EditorDrawSidebar;
						end;
					end;
					'V': begin
{$IFDEF E_SUPERZ}
						if InputKeyPressed = 'V' then begin
							if viewMode = VIEW_EDITOR then
								EditorSetViewMode(VIEW_EDITOR_LARGE)
							else
								EditorSetViewMode(VIEW_EDITOR);
							EditorMoveCursor(cursorX, cursorY, false);
							EditorDrawRefresh;
						end else begin
{$ENDIF}
							cursorColor := cursorColor xor $80;
							EditorUpdateCursorColor;
{$IFDEF E_SUPERZ}
						end;
{$ENDIF}
					end;
					'?': begin
						GameDebugPrompt;
						EditorDrawSidebar;
					end;
					KEY_TAB: begin
						if drawMode = DrawingOff then
							drawMode := DrawingOn
						else
							drawMode := DrawingOff;
						EditorUpdateDrawMode;
					end;
					KEY_F5: begin
						EditorDrawCursor;

						{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}

						for i := 3 to (VideoRows - 5) do
							SidebarClearLine(i);

						i := 4;
						iBg := $70;
						VideoWriteText(VideoSidebarX + 5, i, $1E, 'Advanced:');
						Inc(i, 1);

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' E ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Board edge');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, 'E');
						Inc(i, 1);
						iBg := iBg xor $40;

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' H ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Hori. blink');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, #205);
						Inc(i, 1);
						iBg := iBg xor $40;

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' V ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Vert. blink');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, #186);
						Inc(i, 1);
						iBg := iBg xor $40;

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' C ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Player clone');
						VideoWriteText(VideoSidebarX + 18, i, $1F, #2);
						Inc(i, 1);
						iBg := iBg xor $40;

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' F ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Fake player');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, #2);
						Inc(i, 1);
						iBg := iBg xor $40;

{$IFDEF E_SUPERZ}
						VideoWriteText(VideoSidebarX + 1, i, iBg, ' P ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Pairer');
						VideoWriteText(VideoSidebarX + 18, i, EditorGetDrawingColor(E_PAIRER), ElementDefs[E_PAIRER].Character);
						Inc(i, 1);
						iBg := iBg xor $40;
{$ENDIF}

						Inc(i, 1);
						VideoWriteText(VideoSidebarX + 5, i, $1E, 'Projectiles:');
						Inc(i, 1);

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' U ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Bullet');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, #248);
						Inc(i, 1);
						iBg := iBg xor $40;

						VideoWriteText(VideoSidebarX + 1, i, iBg, ' A ');
						VideoWriteText(VideoSidebarX + 5, i, $1F, 'Star');
						VideoWriteText(VideoSidebarX + 18, i, cursorColor, '/');
						Inc(i, 1);
						iBg := iBg xor $40;

						{$IFDEF BASICSYS} VideoUnlockScreenUpdate(VideoSidebarX, 3, VideoSidebarX + 19, 20); {$ENDIF}

						InputReadWaitKey;
						case UpCase(InputKeyPressed) of
							'E': begin
								EditorPlaceElement(E_BOARD_EDGE, cursorColor);
							end;
							'H': begin
								EditorPlaceElement(E_BLINK_RAY_EW, cursorColor);
							end;
							'V': begin
								EditorPlaceElement(E_BLINK_RAY_NS, cursorColor);
							end;
							'C': begin
								EditorPlaceElement(E_PLAYER, $1F);
							end;
							'F': begin
								EditorPlaceElementNoStat(E_PLAYER, cursorColor);
							end;
							'U': begin
								EditorPlaceElement(E_BULLET, cursorColor);
							end;
							'A': begin
								EditorPlaceElement(E_STAR, cursorColor);
							end;
{$IFDEF E_SUPERZ}
							'P': begin
								EditorPlaceElement(E_PAIRER, EditorGetDrawingColor(E_PAIRER));
							end;
{$ENDIF}
						end;
						EditorDrawSidebar;
					end;
					KEY_F1, KEY_F2, KEY_F3{$IFDEF E_SUPERZ}, KEY_F4{$ENDIF}: begin
						EditorDrawCursor;
						{$IFDEF BASICSYS} VideoLockScreenUpdate; {$ENDIF}
						for i := 3 to (VideoRows - 5) do
							SidebarClearLine(i);
						case InputKeyPressed of
							KEY_F1: selectedCategory := CATEGORY_ITEM;
							KEY_F2: selectedCategory := CATEGORY_CREATURE;
							KEY_F3: selectedCategory := CATEGORY_TERRAIN;
{$IFDEF E_SUPERZ}
							KEY_F4: selectedCategory := CATEGORY_TERRAIN2;
{$ENDIF}
						end;
						i := 3; { Y position for text writing }
DrawNextCategory:
						for iElem := 1 to MAX_ELEMENT do begin
							if ElementDefs[iElem].EditorCategory = selectedCategory then begin
								if Length(ElementDefs[iElem].CategoryName) <> 0 then begin
									Inc(i);
									VideoWriteText(VideoSidebarX + 5, i, $1E, ElementDefs[iElem].CategoryName);
									Inc(i);
								end;

								VideoWriteText(VideoSidebarX + 1, i, ((i and 1) shl 6) + $30, ' ' + ElementDefs[iElem].EditorShortcut + ' ');
								VideoWriteText(VideoSidebarX + 5, i, $1F, ElementDefs[iElem].Name);
								VideoWriteText(VideoSidebarX + 18, i, EditorGetDrawingColor(iElem), ElementDefs[iElem].Character);

								Inc(i);
							end;
						end;
						{$IFDEF BASICSYS} VideoUnlockScreenUpdate(VideoSidebarX, 3, VideoSidebarX + 19, 20); {$ENDIF}
{$IFDEF E_SUPERZ}
						if selectedCategory = CATEGORY_CREATURE then begin
							selectedCategory := CATEGORY_CENTIPEDE;
							goto DrawNextCategory;
						end;
						if selectedCategory = CATEGORY_ITEM then begin
							selectedCategory := CATEGORY_CONVEYOR;
							goto DrawNextCategory;
						end;
{$ENDIF}
						InputReadWaitKey;
CheckNextCategory:
						for iElem := 1 to MAX_ELEMENT do begin
							if (ElementDefs[iElem].EditorCategory = selectedCategory)
								and (ElementDefs[iElem].EditorShortcut = UpCase(InputKeyPressed)) then
							begin
								if iElem = E_PLAYER then begin
									if EditorPrepareModifyTile(cursorX, cursorY) then
										MoveStat(0, cursorX, cursorY);
								end else begin
									EditorPlaceElement(iElem, EditorGetDrawingColor(iElem));
								end;
							end;
						end;
{$IFDEF E_SUPERZ}
						if selectedCategory = CATEGORY_CENTIPEDE then begin
							selectedCategory := CATEGORY_CREATURE;
							goto CheckNextCategory;
						end;
						if selectedCategory = CATEGORY_CONVEYOR then begin
							selectedCategory := CATEGORY_ITEM;
							goto CheckNextCategory;
						end;
{$ENDIF}
PlacementDone:
						EditorDrawSidebar;
					end;
					{$IFDEF E_SUPERZ}KEY_F6{$ELSE}KEY_F4{$ENDIF}: begin
						if drawMode <> TextEntry then
							drawMode := TextEntry
						else
							drawMode := DrawingOff;
						EditorUpdateDrawMode;
					end;
					'H': begin
						TextWindowDisplayFile('editor.hlp', 'World editor help');
					end;
					'X': begin
						EditorFloodFill(cursorX, cursorY, Board.Tiles[cursorX][cursorY]);
					end;
					'!': begin
						EditorEditTextFile;
						EditorDrawSidebar;
					end;
					'T': begin
						EditorTransferBoard;
					end;
					KEY_ENTER: begin
						i := GetStatIdAt(cursorX, cursorY);
						if KeysAltHeld and EditorLowLevelEnable then begin
							EditorEditTileLowLevel(cursorX, cursorY, i);
							TransitionDrawToBoard;
						end else if i >= 0 then begin
							EditorEditStat(i);
						end else begin
							EditorCopyPatternToCurrent(cursorX, cursorY);
							EditorUpdateCopiedPatterns;
						end;
						EditorDrawSidebar;
					end;
					KEY_CTRL_T: begin
						if EditorLowLevelEnable then begin
							i := GetStatIdAt(cursorX, cursorY);
							EditorEditTileLowLevel(cursorX, cursorY, i);
							TransitionDrawToBoard;
							EditorDrawSidebar;
						end;
					end;
					'I': begin
						EditorEditBoardInfo;
						TransitionDrawToBoard;
					end;
					'W': begin
						EditorEditWorldInfo;
						TransitionDrawToBoard;
					end;
					KEY_CTRL_X: begin
						EditorSelectAndCopyCopyBuffer(cursorX, cursorY, true);
					end;
					KEY_CTRL_C: begin
						EditorSelectAndCopyCopyBuffer(cursorX, cursorY, false);
					end;
					KEY_CTRL_V: begin
						EditorAskAndPasteCopyBuffer(cursorX, cursorY);
					end;
					KEY_CTRL_S: begin
						i := EditorSelectStat('Stats', 0, false, false, false, true);
						if (not TextWindowRejected) then begin
							with Board.Stats[i] do begin
								EditorMoveCursor(X, Y, false);
								if EditorLowLevelEnable then begin
									EditorEditTileLowLevel(X, Y, i);
								end else begin
									EditorEditStat(i);
								end;
								TransitionDrawToBoard;
								EditorDrawSidebar;
							end;
						end;
					end;
					{$IFDEF E_SUPERZ}'O'{$ELSE}'A'{$ENDIF}: begin
						GameOptionsScreen(false);
						EditorDrawRefresh;
					end;
				end;
			end;

			if editorExitRequested then begin
				EditorAskSaveChanged;
				if InputKeyPressed = KEY_ESCAPE then begin
					editorExitRequested := false;
					EditorDrawSidebar;
				end;
			end;
		until editorExitRequested;

		EditorFreeCopyBuffer;
		for i := 1 to COPIED_TILES_COUNT do
			EditorClearPattern(copiedTiles[i], false);
		InputKeyPressed := #0;
		InitElementsGame;

		if (EditorSeparateStartingBoard) and (startingBoard >= 0) and (not DebugEnabled) then
			BoardChange(startingBoard);
	end;
{$ENDIF}

procedure HighScoresLoad;
	var
		f: file of THighScoreList;
		i: integer;
	begin
{$IFNDEF MSDOS}
		AssignFSys(f, World.Info.Name + {$IFDEF E_SUPERZ}'.HGS'{$ELSE}'.HI'{$ENDIF});
{$ELSE}
		Assign(f, World.Info.Name + {$IFDEF E_SUPERZ}'.HGS'{$ELSE}'.HI'{$ENDIF});
{$ENDIF}
		Reset(f);
		if IOResult = 0 then begin
			Read(f, HighScoreList);
		end;
		Close(f);
		if IOResult <> 0 then begin
			for i := 1 to HIGH_SCORE_COUNT do begin
				HighScoreList[i].Name := '';
				HighScoreList[i].Score := -1;
			end;
		end;
	end;

procedure HighScoresSave;
	var
		f: file of THighScoreList;
	begin
{$IFNDEF MSDOS}
		AssignFSys(f, World.Info.Name + {$IFDEF E_SUPERZ}'.HGS'{$ELSE}'.HI'{$ENDIF});
{$ELSE}
		Assign(f, World.Info.Name + {$IFDEF E_SUPERZ}'.HGS'{$ELSE}'.HI'{$ENDIF});
{$ENDIF}
		Rewrite(f);
		Write(f, HighScoreList);
		Close(f);
		if DisplayIOError then begin end;
	end;

{$F+}

procedure HighScoresInitTextWindow(var state: TTextWindowState);
	var
		i: integer;
		scoreStr: string;
	begin
		TextWindowInitState(state);
		TextWindowAppend(state, 'Score  Name');
{$IFDEF E_SUPERZ}
		TextWindowAppend(state, '-----  --------------------');
{$ELSE}
		TextWindowAppend(state, '-----  ----------------------------------');
{$ENDIF}
		for i := 1 to HIGH_SCORE_COUNT do begin
			if Length(HighScoreList[i].Name) <> 0 then begin
				Str(HighScoreList[i].Score:5, scoreStr);
				TextWindowAppend(state, scoreStr + '  ' + HighScoreList[i].Name);
			end;
		end;
	end;

procedure HighScoresDisplay(linePos: integer);
	var
		state: TTextWindowState;
	begin
		HighScoresInitTextWindow(state);
		state.LinePos := linePos + 2;
		if (state.LineCount > 2) then begin
			state.Title := 'High scores for ' + World.Info.Name;
			TextWindowDrawOpen(state);
			TextWindowSelect(state, TWS_VIEWING_FILE);
			TextWindowDrawClose(state);
		end;
		TextWindowFree(state);
	end;

{$IFDEF EDITOR}
procedure EditorOpenEditTextWindow(var state: TTextWindowState; extension: TExtensionString;
	syntaxHighlighting, multiExtension: boolean);
	begin
		SidebarClear;
		VideoWriteText(VideoSidebarX + 1, 7, $30, ' Return ');
		VideoWriteText(VideoSidebarX + 9, 7, $1F, ' New line');
		VideoWriteText(VideoSidebarX + 1, 8, $70, ' Ctrl-Y ');
		VideoWriteText(VideoSidebarX + 9, 8, $1F, ' Del line');
		VideoWriteText(VideoSidebarX + 1, 10, $30, ' '#24#25#27#26' ');
		VideoWriteText(VideoSidebarX + 7, 10, $1F, ' Move cursor');
		VideoWriteText(VideoSidebarX + 1, 12, $70, ' Ins ');
		VideoWriteText(VideoSidebarX + 6, 12, $1F, ' Insert: ');
		VideoWriteText(VideoSidebarX + 1, 13, $30, ' Del ');
		VideoWriteText(VideoSidebarX + 6, 13, $1F, ' Delete char');
{$IFNDEF WIDECHAR}
		VideoWriteText(VideoSidebarX + 1, 14, $70, ' f10 ');
		VideoWriteText(VideoSidebarX + 6, 14, $1F, ' Custom char');
{$ENDIF}
		VideoWriteText(VideoSidebarX + 1, 16, $30, ' Shift  ');
		VideoWriteText(VideoSidebarX + 9, 16, $1F, ' Select');
		VideoWriteText(VideoSidebarX + 1, 17, $70, ' Ctrl-X ');
		VideoWriteText(VideoSidebarX + 9, 17, $1F, ' Cut');
		VideoWriteText(VideoSidebarX + 1, 18, $30, ' Ctrl-C ');
		VideoWriteText(VideoSidebarX + 9, 18, $1F, ' Copy');
		VideoWriteText(VideoSidebarX + 1, 19, $70, ' Ctrl-V ');
		VideoWriteText(VideoSidebarX + 9, 19, $1F, ' Paste');
		VideoWriteText(VideoSidebarX + 1, 21, $30, ' Ctrl-O ');
		VideoWriteText(VideoSidebarX + 9, 21, $1F, ' Open file');
		VideoWriteText(VideoSidebarX + 1, 22, $70, ' Ctrl-S ');
		VideoWriteText(VideoSidebarX + 9, 22, $1F, ' Save file');
		VideoWriteText(VideoSidebarX + 1, 23, $30, ' Esc ');
		VideoWriteText(VideoSidebarX + 6, 23, $1F, ' Exit editor');
		TextWindowEdit(state, extension, syntaxHighlighting, multiExtension);
	end;

procedure EditorEditTextFile;
	var
		textWindow: TTextWindowState;
		filename: TFilenameString;
		extension: TExtensionString;
		i: integer;
	begin
		TextWindowInitState(textWindow);
		TextWindowPromptFilename('File to open?', filename);

		if Length(filename) <> 0 then
			TextWindowOpenFile('*' + filename, textWindow, true, true);

		extension := '.HLP';
		for i := Length(filename) downto (Length(filename) - 4) do begin
			if (i >= 1) and (filename[i] = '.') then begin
				extension := Copy(filename, i, 4);
			end;
		end;

		textWindow.Title := filename;
		TextWindowDrawOpen(textWindow);
		EditorOpenEditTextWindow(textWindow, extension, false, false);
		TextWindowDrawClose(textWindow);
		TextWindowFreeEdit(textWindow);
	end;
{$ENDIF}

procedure HighScoresAdd(score: integer);
	var
		textWindow: TTextWindowState;
		name: TSmallString;
		i, listPos: integer;
	begin
		{ Don't record the player inputting their name as we can't
		  be sure the box will show up next time. }
		if DemoIsRecording then
			DemoIgnoreKeypresses;

		listPos := 1;
		while (listPos <= HIGH_SCORE_COUNT) and (score < HighScoreList[listPos].Score) do
			Inc(listPos);
		if (listPos <= HIGH_SCORE_COUNT) and (score > 0) then begin
			for i := (HIGH_SCORE_COUNT - 1) downto listPos do
				HighScoreList[i + 1] := HighScoreList[i];
			HighScoreList[listPos].Score := score;
{$IFDEF E_SUPERZ}
			TextWindowInitState(textWindow);
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, ' Enter your name:');
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, '');
			textWindow.LinePos := textWindow.LineCount - 1;
			textWindow.Title := 'New high score for ' + World.Info.Name;

			TextWindowDrawOpen(textWindow);
			TextWindowDraw(textWindow, false, false);

			name := '';
			PromptString(
				TextWindowX + 11,
				(TextWindowHeight shr 1) + TextWindowY + 2,
				$1F, $1E, MAX_HIGH_SCORE_NAME_LENGTH, MAX_HIGH_SCORE_NAME_LENGTH, PROMPT_ANY, name
			);
{$ELSE}
			HighScoreList[listPos].Name := '-- You! --';

			HighScoresInitTextWindow(textWindow);
			textWindow.LinePos := listPos;
			textWindow.Title := 'New high score for ' + World.Info.Name;

			TextWindowDrawOpen(textWindow);
			TextWindowDraw(textWindow, false, false);

			name := '';
			PopupPromptString('Congratulations!  Enter your name:', name, MAX_HIGH_SCORE_NAME_LENGTH);
{$ENDIF}
                        HighScoreList[listPos].Name := name;
                        HighScoresSave;

			if DemoIsRecording then
				DemoAddPlayerName(name);

			TextWindowDrawClose(textWindow);
			TransitionDrawToBoard;
			TextWindowFree(textWindow);
{$IFDEF E_SUPERZ}
			HighScoresDisplay(listPos);
{$ENDIF}
		end;

		if DemoIsRecording then
			DemoReenableKeypresses;
	end;

function EditorAppendSizeToLine(s: TSmallString; dl: word): TSmallString;
	var
		s1, s2: string[20];
		s3: TSmallString;
		i, mw: integer;
	begin
		Str(dl, s1);
		s2 := ' (' + s1 + ' b.)';
		mw := TextWindowWidth - 9 - Length(s2);
		if Length(s) > mw then
			EditorAppendSizeToLine := Copy(s, 1, mw - 3) + '...' + s2
		else begin
			s3[0] := Chr(mw - Length(s));
			for i := 1 to Ord(s3[0]) do
				s3[i] := ' ';
			EditorAppendSizeToLine := s + s3 + s2;
		end
	end;

function EditorGetBoardName(boardId: integer; titleScreenIsNone: boolean): TSmallString;
	var
		copiedName: TSmallString;
	begin
		if (boardId = 0) and titleScreenIsNone then
			EditorGetBoardName := 'None'
		else if (boardId = World.Info.CurrentBoard) then
			EditorGetBoardName := Board.Name
		else begin
			ExtMemRead(WorldExt.BoardData[boardId], copiedName, SizeOf(copiedName));
			EditorGetBoardName := copiedName;
		end;
	end;

function EditorSelectBoard(title: string; currentBoard: integer; titleScreenIsNone: boolean;
	windowAlreadyOpen: boolean; showAddNewBoard: boolean; editable: boolean): integer;
	var
		i: integer;
		textWindow: TTextWindowState;
		running: boolean;
		choiceResult: byte;
	procedure PopulateBoards;
		var
			j, padSize, mw: integer;
			s1: string[12];
			s: TSmallString;
			bs: word;
		begin
			TextWindowFree(textWindow);
			for j := 0 to World.BoardCount do begin
				s := EditorGetBoardName(j, titleScreenIsNone);
				if EditorLowLevelEnable then begin
					padSize := 1;
					if World.BoardCount >= 10 then padSize := 2;
					if World.BoardCount >= 100 then padSize := 3;

					Str(j, s1);
					while Length(s1) < padSize do s1 := ' ' + s1;

					s := '[' + s1 + '] ' + s;
				end;
				if (EditorShowDataSizes) and (not (titleScreenIsNone and (j = 0))) then begin
					if j = World.Info.CurrentBoard then
						bs := BoardCurrentStorageSize
					else
						bs := WorldExt.BoardLen[j];
					TextWindowAppend(textWindow, EditorAppendSizeToLine(s, bs));
				end else begin
					mw := TextWindowWidth - 9;
					if Length(s) > mw then
						s := Copy(s, 1, mw - 3) + '...';
					TextWindowAppend(textWindow, s);
				end;
			end;
			if showAddNewBoard then begin
				if World.BoardCount < MAX_BOARD then begin
					TextWindowAppend(textWindow, 'Add new board');
				end;
			end;
		end;
	begin
		TextWindowInitState(textWindow);
		textWindow.Title := title;
		textWindow.LinePos := currentBoard + 1;
		textWindow.Selectable := true;
		if not windowAlreadyOpen then TextWindowDrawOpen(textWindow);
{$IFDEF EDITOR}
		if editable then begin
			running := true;
			while running do begin
				EditorDrawSidebar345(true);
				PopulateBoards;
				TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS or TWS_EXIT_MINUS_PLUS_DEL);
				if InputKeyPressed = '-' then begin
					if textWindow.LinePos > 1 then begin
						if EditorShiftBoard(
							textWindow.LinePos - 1,
							textWindow.LinePos - 2,
							IdShiftMove) then begin end;
						Dec(textWindow.LinePos);
					end;
				end else if InputKeyPressed = '+' then begin
					if textWindow.LinePos <= World.BoardCount then begin
						if EditorShiftBoard(
							textWindow.LinePos - 1,
							textWindow.LinePos,
							IdShiftMove) then begin end;
						Inc(textWindow.LinePos);
					end;
				end else if InputKeyPressed = KEY_DELETE then begin
					if World.BoardCount > 0 then begin
						choiceResult := 1;
						SidebarPromptChoice(true, 3, 'Confirm delete:', 'Yes No', choiceResult);
						if choiceResult = 0 then if not EditorShiftBoard(
								textWindow.LinePos - 1,
								-1,
								IdShiftDelete) then begin
							TextWindowFree(textWindow);
							textWindow.LineCount := 4;
							for i := 1 to textWindow.LineCount do
								New(textWindow.Lines[i]);

							textWindow.Lines[1]^ := '$Warning';
							textWindow.Lines[2]^ := '';
							textWindow.Lines[3]^ := 'Some board exits and/or passages have had';
							textWindow.Lines[4]^ := 'their destinations reset.';

							TextWindowSelect(textWindow, 0);
						end;
					end;
				end else running := false;
			end;
		end else begin
{$ENDIF}
		PopulateBoards;
		TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS);
{$IFDEF EDITOR}
		end;
{$ENDIF}
		if not windowAlreadyOpen then TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);

		EditorSelectBoard := textWindow.LinePos - 1;
	end;

{$IFDEF EDITOR}
function EditorGetElementName(elemId: integer): TString50;
	var
		elemStr: TString50;
	begin
		elemStr := ElementDefs[elemId].Name;
		if Length(elemStr) = 0 then begin
			case elemId of
			E_BOARD_EDGE: elemStr := 'Board Edge';
			E_MESSAGE_TIMER: elemStr := 'Message Timer';
			E_BLINK_RAY_EW: elemStr := 'Horizontal Blink';
			E_BLINK_RAY_NS: elemStr := 'Vertical Blink';
			E_TEXT_BLUE: elemStr := 'Blue Text';
			E_TEXT_GREEN: elemStr := 'Green Text';
			E_TEXT_CYAN: elemStr := 'Cyan Text';
			E_TEXT_RED: elemStr := 'Red Text';
			E_TEXT_PURPLE: elemStr := 'Purple Text';
			E_TEXT_YELLOW: elemStr := 'Yellow Text';
			E_TEXT_WHITE: elemStr := 'White Text';
			else begin
				Str(elemId, elemStr);
				elemStr := 'Element #' + elemStr;
			end end;
		end;
		EditorGetElementName := elemStr;
	end;

function EditorGetColorName(color: byte): TString50;
	begin
		EditorGetColorName := LongColorNames[color and $0F] + ' on ' + LongColorNames[color shr 4];
	end;

procedure EditorSelectElement(title: string; var element: byte; windowAlreadyOpen: boolean);
	var
		i: integer;
		textWindow: TTextWindowState;
	begin
		TextWindowInitState(textWindow);
		textWindow.Title := title;
		textWindow.LinePos := element + 1;
		textWindow.Selectable := true;
		for i := 0 to SAFE_MAX_ELEMENT do
			TextWindowAppend(textWindow, EditorGetElementName(i));
		if not windowAlreadyOpen then TextWindowDrawOpen(textWindow);
		TextWindowSelect(textWindow, 0);
		if not windowAlreadyOpen then TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);

		if not TextWindowRejected then
			element := textWindow.LinePos - 1;
	end;

function EditorSelectStat(title: string; currentStat: integer; showNone: boolean;
	windowAlreadyOpen: boolean; showAddNewStat: boolean; editable: boolean): integer;
	var
		i: integer;
		textWindow: TTextWindowState;
		running: boolean;
		choiceResult: byte;
	procedure PopulateStats;
		var
			j, k: integer;
			statStr: string;
			bound: boolean;
			xStr, yStr, idStr: string[20];
		label AppendedName;
		begin
			TextWindowFree(textWindow);
			if showNone then
				TextWindowAppend(textWindow, 'None');
			for j := 0 to Board.StatCount do with Board.Stats[j] do begin
				Str(X, xStr);
				EditorPadSpaces(xStr, 2);
				Str(Y, yStr);
				EditorPadSpaces(yStr, 2);
				Str(j, idStr);
				EditorPadSpaces(idStr, 3);
				statStr := idStr + ' ( ' + xStr + ', ' + yStr + ') '
					+ EditorGetElementName(Board.Tiles[X][Y].Element);
				bound := false;
				if (Data <> nil) and (DataLen > 0) then begin
					for k := 0 to (j - 1) do begin
						if Board.Stats[k].Data = Data then begin
							Str(k, idStr);
							statStr := statStr + ' <- ' + idStr;
							bound := true;
							goto AppendedName;
						end;
					end;
	AppendedName:
					k := 0;
					OopReadChar(j, k);
					if OopChar = '@' then
						statStr := statStr + ': ' + OopReadLineToEnd(j, k);
				end;
				if (EditorShowDataSizes) and (DataLen > 0) and (not bound) then begin
					TextWindowAppend(textWindow, EditorAppendSizeToLine(statStr, DataLen));
				end else begin
					if Length(statStr) >= (TextWindowWidth - 9) then
						statStr := Copy(statStr, 1, (TextWindowWidth - 12)) + '...';
					TextWindowAppend(textWindow, statStr);
				end;
			end;
			if showAddNewStat then begin
				if Board.StatCount < MAX_STAT then begin
					TextWindowAppend(textWindow, 'Add new stat');
				end;
			end;
		end;
	begin
		TextWindowInitState(textWindow);
		textWindow.Title := title;
		textWindow.LinePos := currentStat + 1;
		textWindow.Selectable := true;
		if not windowAlreadyOpen then TextWindowDrawOpen(textWindow);
		if editable then begin
			running := true;
			while running do begin
				EditorDrawSidebar345(true);
				PopulateStats;
				if showNone then Inc(textWindow.LinePos);
				TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS or TWS_EXIT_MINUS_PLUS_DEL);
				if showNone then Dec(textWindow.LinePos);
				if InputKeyPressed = '-' then begin
					if textWindow.LinePos > 2 then begin
						if EditorShiftStat(
							textWindow.LinePos - 1,
							textWindow.LinePos - 2,
							IdShiftMove) then begin end;
						Dec(textWindow.LinePos);
					end;
				end else if InputKeyPressed = '+' then begin
					if (textWindow.LinePos > 1) and (textWindow.LinePos <= Board.StatCount) then begin
						if EditorShiftStat(
							textWindow.LinePos - 1,
							textWindow.LinePos,
							IdShiftMove) then begin end;
						Inc(textWindow.LinePos);
					end;
				end else if InputKeyPressed = KEY_DELETE then begin
					if EditorLowLevelEnable and (Board.StatCount > 0) then begin
						choiceResult := 1;
						SidebarPromptChoice(true, 3, 'Confirm delete:', 'Yes No', choiceResult);
						if choiceResult = 0 then if not EditorShiftStat(
								textWindow.LinePos - 1,
								-1,
								IdShiftDelete) then begin
						end;
					end;
				end else running := false;
			end;
		end else begin
			PopulateStats;
			if showNone then Inc(textWindow.LinePos);
			TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS or TWS_EXIT_MINUS_PLUS_DEL);
			if showNone then Dec(textWindow.LinePos);
		end;

		if not windowAlreadyOpen then TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);

		EditorSelectStat := textWindow.LinePos - 1;
	end;
{$ENDIF}

begin
	EditorAutoAppendPats := false;
	EditorSeparateStartingBoard := false;
	EditorLowLevelEnable := false;
	EditorSyntaxHighlightEnable := true;
	EditorShowDataSizes := false;
end.
