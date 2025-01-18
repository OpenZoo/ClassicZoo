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

{$IFDEF FPC}
{$IFDEF RAWMEM}
{$PACKRECORDS 1}
{$ENDIF}
{$ENDIF}

unit GameVars;

interface
	uses ExtMem;
	const
		DEFAULT_MAX_STAT = 128;
		ACTUAL_MAX_STAT = {$IFDEF SDL2}254{$ELSE}128{$ENDIF};

		SAFE_MAX_ELEMENT = 79;
{$IFDEF SDL2}
		MAX_ELEMENT = 255;
{$ELSE}
		MAX_ELEMENT = 79;
{$ENDIF}
		MAX_FLAG = 16;
		MAX_BOARD = 255;
		BOARD_WIDTH = 96;
		BOARD_HEIGHT = 80;
		BOARD_DRAW_OX_MIN = 1;
		BOARD_DRAW_OY_MIN = 1;
		WORLD_FILE_HEADER_SIZE = 1024;
		WORLD_FILE_DESC_COUNT = 3;
		HIGH_SCORE_COUNT = 30;
		TORCH_DX = 8;
		TORCH_DY = 8;
		TORCH_DIST_SQR = 64 { 8 * 8 };
		OOP_TOKEN_LENGTH = 20;
		ZZT_32_BOARD_MAX_SIZE = 20000;
{$IFDEF SDL2}
		IO_BUFFER_DEFAULT_SIZE = 65535;
		IO_BUFFER_MAXIMUM_SIZE = 65535;
{$ELSE}
		IO_BUFFER_DEFAULT_SIZE = 20000;
		IO_BUFFER_MAXIMUM_SIZE = 65500;
{$ENDIF}
		IO_BUFFER_SIZE_INCREMENT = 500;
		STAT_SIZE_BYTES = 25;
		BOARD_INFO_BYTES = 28;
		{ UI-only }
		MAX_BOARD_NAME_LENGTH = 42;
		MAX_HIGH_SCORE_NAME_LENGTH = 15;
		EditorPatternCount = 6;
{$IFNDEF PLAYSTEP}
		PlayerStepEnabled = false;
{$ENDIF}
	type
		TString50 = string[50];
		TSmallString = string[60];
{$IFNDEF NODIRS}
{$IFDEF SDL2}
		TFilenameString = string;
{$ELSE}
		TFilenameString = string[128];
{$ENDIF}
{$ELSE}
		TFilenameString = string[20];
{$ENDIF}
		TCoord = record
			X: integer;
			Y: integer;
		end;
		TTile = record
			Element: byte;
			Color: byte;
		end;
		TElementDrawProc = procedure(x, y: integer; var ch: byte);
		TElementTickProc = procedure(statId: integer);
		TElementTouchProc = procedure(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
		TElementDef = record
			Character: char;
			Color: byte;
			Destructible: boolean;
			Pushable: boolean;
			PlaceableOnTop: boolean;
			Walkable: boolean;
			HasDrawProc: boolean;
			DrawProc: TElementDrawProc;
			Cycle: integer;
			TickProc: TElementTickProc;
			TouchProc: TElementTouchProc;
			EditorCategory: integer;
			EditorShortcut: char;
			Name: string[20];
			CategoryName: string[20];
			Param1Name: string[20];
			Param2Name: string[20];
			ParamBulletTypeName: string[20];
			ParamBoardName: string[20];
			ParamDirName: string[20];
			ParamTextName: string[20];
			ScoreValue: integer;
		end;
{$IFDEF RAWMEM}
		TStat = record
			X, Y: byte;
			StepX, StepY: integer;
			Cycle: integer;
			P1, P2, P3: byte;
			Follower: integer;
			Leader: integer;
			Under: TTile;
			{$IFDEF CPU64}
			{ Workaround for 64-bit CPUs, which have 8-byte pointers. }
			UnusedData: longint;
			{$ELSE}
			{$IFNDEF FPC}
			Data: ^string;
			{$ELSE}
			{ Free Pascal allows pointers to act as arrays. }
			Data: ^char;
			{$ENDIF}
			{$ENDIF}
			DataPos: integer;
			DataLen: integer;
			{$IFDEF CPU64}
			Data: ^char;
			{$ENDIF}
		end;
{$ELSE}
		TStat = record
			X, Y: byte;
			StepX, StepY: integer;
			Cycle: integer;
			P1, P2, P3: byte;
			Follower: integer;
			Leader: integer;
			Under: TTile;
			{$IFNDEF FPC}
			Data: ^string;
			{$ELSE}
			Data: ^char;
			{$ENDIF}
			DataPos: integer;
			DataLen: integer;
{$IFDEF SDL2}
			UnusedData: longint;
{$ENDIF}
		end;
{$ENDIF}
		TRleTile = record
			Count: byte;
			Tile: TTile;
		end;
{$IFDEF RAWMEM}
		TBoardInfo = record
			MaxShots: byte;
			NeighborBoards: array[0 .. 3] of byte;
			ReenterWhenZapped: boolean;
			StartPlayerX: byte;
			StartPlayerY: byte;
			DrawXOffset: integer;
			DrawYOffset: integer;
			TimeLimitSec: integer;
			unk1: array[14 .. 27] of byte;
		end;
		TWorldInfo = record
			Ammo: integer;
			Gems: integer;
			Keys: array [1..7] of boolean;
			Health: integer;
			CurrentBoard: integer;
			unk1: integer;
			EnergizerTicks: integer;
			unk2: integer;
			Score: integer;
			Name: string[20];
			Flags: array[1 .. MAX_FLAG] of string[20];
			BoardTimeSec: integer;
			BoardTimeHsec: integer;
			IsSave: boolean;
			StonesOfPower: integer;
			unk3: array[387 .. 398] of byte;
		end;
{$ELSE}
		TBoardInfo = record
			MaxShots: byte;
			NeighborBoards: array[0 .. 3] of byte;
			ReenterWhenZapped: boolean;
			StartPlayerX: byte;
			StartPlayerY: byte;
			DrawXOffset: integer;
			DrawYOffset: integer;
			TimeLimitSec: integer;
{$IFDEF SDL2}
			unk1: array[14 .. 27] of byte;
{$ENDIF}
		end;
		TWorldInfo = record
			Ammo: integer;
			Gems: integer;
			Keys: array [1..7] of boolean;
			Health: integer;
			CurrentBoard: integer;
			EnergizerTicks: integer;
			Score: integer;
			Name: string[20];
			Flags: array[1 .. MAX_FLAG] of string[20];
			BoardTimeSec: integer;
			BoardTimeHsec: integer;
			IsSave: boolean;
			StonesOfPower: integer;
{$IFDEF SDL2}
			unk1: integer;
			unk2: integer;
			unk3: array[387 .. 398] of byte;
{$ENDIF}
		end;
{$ENDIF}
		TEditorStatSetting = record
			P1, P2, P3: byte;
			StepX, StepY: integer;
		end;
		TBoard = record
			Name: TSmallString;
			Tiles: array[0 .. BOARD_WIDTH + 1] of array[0 .. BOARD_HEIGHT + 1] of TTile;
			StatCount: integer;
{$IFDEF MEMBOUND}
			{ On platforms with different memory layouts, add a faux stat -1. }
			Stats: array[-1 .. ACTUAL_MAX_STAT + 1] of TStat;
{$ELSE}
			Stats: array[0 .. ACTUAL_MAX_STAT + 1] of TStat;
{$ENDIF}
			Info: TBoardInfo;
		end;
		TWorld = record
			BoardCount: integer;
			BoardData: array[0 .. MAX_BOARD] of TExtMemBlock;
			BoardLen: array[0 .. MAX_BOARD] of integer;
			Info: TWorldInfo;
			EditorStatSettings: array[0 .. MAX_ELEMENT] of TEditorStatSetting;
		end;
		THighScoreEntry = {$IFDEF FPC}packed{$ENDIF} record
			Name: string[60];
			Score: integer;
		end;
		THighScoreList = {$IFDEF FPC}packed{$ENDIF} array[1 .. HIGH_SCORE_COUNT] of THighScoreEntry;
	var
		ForestSoundTableIdx: integer;

{$IFDEF RAWMEM}
		LoadedGameFileName: TSmallString;
		SavedGameFileName: TSmallString;
		SavedBoardFileName: TSmallString;
		StartupWorldFileName: TSmallString;
{$ELSE}
		LoadedGameFileName: string[20];
		SavedGameFileName: string[20];
{$IFDEF EDITOR}
		SavedBoardFileName: string[20];
		StartupWorldFileName: string[20];
{$ENDIF}
{$ENDIF}

		Board: TBoard;
		World: TWorld;
		MessageAmmoNotShown: boolean;
		MessageOutOfAmmoNotShown: boolean;
		MessageNoShootingNotShown: boolean;
		MessageForestNotShown: boolean;
		MessageFakeNotShown: boolean;
		MessageGemNotShown: boolean;
		MessageEnergizerNotShown: boolean;
		IoTmpBufSize: word; { Borrowed: unkVar_7c12[0..1] }
		BOARD_DRAW_X: integer; { Borrowed: unkVar_7c12[2..13] }
		BOARD_DRAW_Y: integer;
		BOARD_DRAW_WIDTH: integer;
		BOARD_DRAW_HEIGHT: integer;
		BOARD_DRAW_OX_MAX: byte;
		BOARD_DRAW_OY_MAX: byte;
		LfsrAndConst: byte;
		LfsrShrConst: byte;
		LfsrTapConst: integer; { Borrowed: unkVar_7c12[14..15] }

		MessageLine1: TSmallString;
		MessageLine2: TSmallString;

		GameTitleExitRequested: boolean;
		GamePlayExitRequested: boolean;
		GamePlayStartRequested: boolean;
		GameStateElement: integer;
		ReturnBoardId: integer;

		TickSpeed: byte;

		IoTmpBuf: pointer;

		ElementDefs: array[0 .. MAX_ELEMENT] of TElementDef;
		EditorPatterns: array[1 .. EditorPatternCount] of byte;

		TickTimeDuration: integer;
		CurrentTick: integer;
		CurrentStatTicked: integer;
		GamePaused: boolean;
		TickTimeCounter: integer;

		ForceDarknessOff: boolean;
		InitialTextAttr: byte;

		OopChar: char;
		OopWord: string[OOP_TOKEN_LENGTH];
		OopValue: integer;

		DebugEnabled: boolean;

		HighScoreList: THighScoreList;

		EditorEnabled: boolean;
		ResetConfig: boolean;
		JustStarted: boolean;

{$IFDEF WORLDDSC}
		WorldFileDescCount: integer;
		WorldFileDescKeys: array[1 .. WORLD_FILE_DESC_COUNT] of TSmallString;
		WorldFileDescValues: array[1 .. WORLD_FILE_DESC_COUNT] of TSmallString;
{$ENDIF}

		{ WorldFileMenuScrPtrs: array[-1 .. WORLD_FILE_DESC_COUNT] of pointer;
		WorldFileMenuScrLens: array[-1 .. WORLD_FILE_DESC_COUNT] of word;
		MenuScrPointer: pointer;
		MenuScrLen: word; }
		UseCustomFont: boolean;

		MAX_STAT: integer;

		GameControllerHasTicked: boolean;
{$IFDEF DEBUGWND}
		DebugCompatEnabled: boolean;
		DebugUndefEnabled: boolean;
{$ENDIF}
{$IFDEF PLAYSTEP}
		PlayerStepEnabled: boolean;
{$ENDIF}
{$IFDEF EXTCHEAT}
		CheatColorModifiers: array[0 .. MAX_ELEMENT] of byte;
		CheatCharModifiers: array[0 .. MAX_ELEMENT] of char;
		CheatNoClip: boolean;
		CheatNoShoot: boolean;
		CheatNoStar: boolean;
		CheatFreeze: boolean;
{$ENDIF}
		FileBoardCachedLinePos: integer;
		FileTextCachedLinePos: integer;
		FileWorldCachedLinePos: integer;
		FileSaveCachedLinePos: integer;
{$IFDEF FASTVID}
		TransitionBlocksPerFrame: integer;
		TransitionTextWindowDelay: integer;
{$ENDIF}
	const
		E_EMPTY = 0;
		E_BOARD_EDGE = 1;
		E_MESSAGE_TIMER = 2;
		E_MONITOR = 3;
		E_PLAYER = 4;
		E_AMMO = 5;
		E_GEM = 7;
		E_KEY = 8;
		E_DOOR = 9;
		E_SCROLL = 10;
		E_PASSAGE = 11;
		E_DUPLICATOR = 12;
		E_BOMB = 13;
		E_ENERGIZER = 14;
		E_CONVEYOR_CW = 16;
		E_CONVEYOR_CCW = 17;
		E_LAVA = 19;
		E_FOREST = 20;
		E_SOLID = 21;
		E_NORMAL = 22;
		E_BREAKABLE = 23;
		E_BOULDER = 24;
		E_SLIDER_NS = 25;
		E_SLIDER_EW = 26;
		E_FAKE = 27;
		E_INVISIBLE = 28;
		E_BLINK_WALL = 29;
		E_TRANSPORTER = 30;
		E_LINE = 31;
		E_RICOCHET = 32;
		E_BEAR = 34;
		E_RUFFIAN = 35;
		E_OBJECT = 36;
		E_SLIME = 37;
		E_SPINNING_GUN = 39;
		E_PUSHER = 40;
		E_LION = 41;
		E_TIGER = 42;
		E_CENTIPEDE_HEAD = 44;
		E_CENTIPEDE_SEGMENT = 45;
		E_FLOOR = 47;
		E_WATER_N = 48;
		E_WATER_S = 49;
		E_WATER_W = 50;
		E_WATER_E = 51;
		E_ROTON = 59;
		E_DRAGON_PUP = 60;
		E_PAIRER = 61;
		E_SPIDER = 62;
		E_WEB = 63;
		E_STONE = 64;
		E_BULLET = 69;
		E_BLINK_RAY_EW = 70;
		E_BLINK_RAY_NS = 71;
		E_STAR = 72;
		{}
		E_TEXT_MIN = 73;
		E_TEXT_BLUE = (E_TEXT_MIN);
		E_TEXT_GREEN = (E_TEXT_MIN + 1);
		E_TEXT_CYAN = (E_TEXT_MIN + 2);
		E_TEXT_RED = (E_TEXT_MIN + 3);
		E_TEXT_PURPLE = (E_TEXT_MIN + 4);
		E_TEXT_YELLOW = (E_TEXT_MIN + 5);
		E_TEXT_WHITE = (E_TEXT_MIN + 6);
		{}
		CATEGORY_ITEM = 1;
		CATEGORY_CREATURE = 2;
		CATEGORY_TERRAIN = 3;
		CATEGORY_TERRAIN2 = 4;
		CATEGORY_CENTIPEDE = 5;
		CATEGORY_CONVEYOR = 6;
		{}
		COLOR_SPECIAL_MIN = $F0;
		COLOR_CHOICE_ON_BLACK = $FF;
		COLOR_WHITE_ON_CHOICE = $FE;
		COLOR_CHOICE_ON_CHOICE = $FD;
		{}
		SHOT_SOURCE_PLAYER = 0;
		SHOT_SOURCE_ENEMY = 1;

implementation

begin
{$IFDEF MEMBOUND}
	with Board.Stats[-1] do begin
		X := 0;
		Y := 1;
		StepX := 256;
		StepY := 256;
		Cycle := 256;
		P1 := 0;
		P2 := 1;
		P3 := 0;
		Follower := 1;
		Leader := 1;
		Under.Element := E_BOARD_EDGE;
		Under.Color := $00;
		DataPos := 1;
		DataLen := 1;
	end;
{$ENDIF}
{$IFDEF PLAYSTEP}
	PlayerStepEnabled := false;
{$ENDIF}
{$IFDEF EXTCHEAT}
	FillChar(CheatColorModifiers, SizeOf(CheatColorModifiers), 0);
	FillChar(CheatCharModifiers, SizeOf(CheatCharModifiers), 0);
	CheatNoClip := false;
	CheatNoShoot := false;
	CheatNoStar := false;
	CheatFreeze := false;
{$ENDIF}
{$IFDEF DEBUGWND}
	DebugCompatEnabled := false;
	DebugUndefEnabled := false;
{$ENDIF}
end.
