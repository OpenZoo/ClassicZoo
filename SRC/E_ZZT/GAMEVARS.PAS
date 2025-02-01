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

{$IFDEF FPC}
{$IFDEF RAWMEM}
{$PACKRECORDS 1}
{$ENDIF}
{$ENDIF}

unit GameVars;

interface
	uses ExtMem;
	const
		MAX_STAT = 150;
		SAFE_MAX_ELEMENT = 53;
{$IFDEF SDL2}
		MAX_ELEMENT = 255;
{$ELSE}
		MAX_ELEMENT = 53;
{$ENDIF}
		MAX_BOARD = 255;
		MAX_FLAG = 10;
		BOARD_WIDTH = 60;
		BOARD_HEIGHT = 25;
		WORLD_FILE_HEADER_SIZE = 512;
		HIGH_SCORE_COUNT = 50;
		TORCH_DURATION = 200;
		TORCH_DX = 8;
		TORCH_DY = 5;
		TORCH_DIST_SQR = 50;
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
		STAT_SIZE_BYTES = 33;
		BOARD_INFO_BYTES = 86;
		{ UI-only }
		MAX_BOARD_NAME_LENGTH = 42;
		MAX_HIGH_SCORE_NAME_LENGTH = 34;
		EditorPatternCount = 6;
{$IFNDEF PLAYSTEP}
		PlayerStepEnabled = false;
{$ENDIF}
	type
		TString50 = string[50];
		TSmallString = string[50];
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
			VisibleInDark: boolean;
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
			Unused1, Unused2: longint;
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
			Unused1, Unused2: longint;
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
			IsDark: boolean;
			NeighborBoards: array[0 .. 3] of byte;
			ReenterWhenZapped: boolean;
			Message: string[58];
			StartPlayerX: byte;
			StartPlayerY: byte;
			TimeLimitSec: integer;
			unkPad: array[70 .. 85] of byte;
		end;
		TWorldInfo = record
			Ammo: integer;
			Gems: integer;
			Keys: array [1..7] of boolean;
			Health: integer;
			CurrentBoard: integer;
			Torches: integer;
			TorchTicks: integer;
			EnergizerTicks: integer;
			unk1: integer;
			Score: integer;
			Name: string[20];
			Flags: array[1 .. MAX_FLAG] of string[20];
			BoardTimeSec: integer;
			BoardTimeHsec: integer;
			IsSave: boolean;
			unkPad: array[0 .. 13] of byte;
		end;
{$ELSE}
		TBoardInfo = record
			MaxShots: byte;
			IsDark: boolean;
			NeighborBoards: array[0 .. 3] of byte;
			ReenterWhenZapped: boolean;
			Message: string[58];
			StartPlayerX: byte;
			StartPlayerY: byte;
			TimeLimitSec: integer;
{$IFDEF SDL2}
			unk1: array[70 .. 85] of byte;
{$ENDIF}
		end;
		TWorldInfo = record
			Ammo: integer;
			Gems: integer;
			Keys: array [1..7] of boolean;
			Health: integer;
			CurrentBoard: integer;
			Torches: integer;
			TorchTicks: integer;
			EnergizerTicks: integer;
			Score: integer;
			Name: string[20];
			Flags: array[1 .. MAX_FLAG] of string[20];
			BoardTimeSec: integer;
			BoardTimeHsec: integer;
			IsSave: boolean;
{$IFDEF SDL2}
			unk1: integer;
			unkPad: array[0 .. 13] of byte;
{$ENDIF}
		end;
{$ENDIF}
		TEditorStatSetting = record
			P1, P2, P3: byte;
			StepX, StepY: integer;
		end;
		TBoard = record
			Name: TString50;
			Tiles: array[0 .. BOARD_WIDTH + 1] of array[0 .. BOARD_HEIGHT + 1] of TTile;
			StatCount: integer;
{$IFDEF MEMBOUND}
			{ On platforms with different memory layouts, add a faux stat -1. }
			Stats: array[-1 .. MAX_STAT + 1] of TStat;
{$ELSE}
			Stats: array[0 .. MAX_STAT + 1] of TStat;
{$ENDIF}
			Info: TBoardInfo;      
		end;
		TWorld = record
			BoardCount: integer;
{$IFDEF RAWMEM}
			BoardDataOld: array[0 .. 100] of pointer;
			BoardLenOld: array[0 .. 100] of word;
{$ENDIF}
			Info: TWorldInfo;
			EditorStatSettings: array[0 .. MAX_ELEMENT] of TEditorStatSetting;
		end;
		TWorldExt = record
			BoardData: array[0 .. MAX_BOARD] of TExtMemBlock;
			BoardLen: array[0 .. MAX_BOARD] of word;
		end;
		THighScoreEntry = {$IFDEF FPC}packed{$ENDIF} record
			Name: TString50;
			Score: integer;
		end;
		THighScoreList = {$IFDEF FPC}packed{$ENDIF} array[1 .. HIGH_SCORE_COUNT] of THighScoreEntry;
	var
		PlayerDirX: integer;
		PlayerDirY: integer;
{$IFDEF RAWMEM}
		unkVar_0476: integer;
		unkVar_0478: integer;
{$ENDIF}

{$IFDEF RAWMEM}
		LoadedGameFileName: TString50;
		SavedGameFileName: TString50;
		SavedBoardFileName: TString50;
		StartupWorldFileName: TString50;
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
		MessageTorchNotShown: boolean;
		MessageOutOfTorchesNotShown: boolean;
		MessageRoomNotDarkNotShown: boolean;
		MessageHintTorchNotShown: boolean;
		MessageForestNotShown: boolean;
		MessageFakeNotShown: boolean;
		MessageGemNotShown: boolean;
		MessageEnergizerNotShown: boolean;

		IoTmpBufSize: word; { Borrowed: unkVar_4ABA[0..1] }
		FileWorldCachedLinePos: integer; { Borrowed: unkVar_4ABA[2..3] }
		FileSaveCachedLinePos: integer; { Borrowed: unkVar_4ABA[4..5] }
{$IFDEF RAWMEM}
		unkVar_4ABA: array[6 .. 14] of byte;
{$ENDIF}

		GameTitleExitRequested: boolean;
		GamePlayExitRequested: boolean;
		GameStateElement: integer;
		ReturnBoardId: integer;

		TickSpeed: byte;

		IoTmpBuf: pointer;

		ElementDefs: array[0 .. MAX_ELEMENT] of TElementDef;
		{ Anything after ElementDefs cannot be reached by the die-move trick. }

{$IFDEF EDITOR}
		EditorPatterns: array[1 .. EditorPatternCount] of byte;
{$ENDIF}

		TickTimeDuration: integer;
		CurrentTick: integer;
		CurrentStatTicked: integer;
		GamePaused: boolean;
		GameRestartNeeded: boolean;
		TickTimeCounter: integer;

		ForceDarknessOff: boolean;
		{ InitialTextAttr: byte; }

		OopChar: char;
		OopWord: string[OOP_TOKEN_LENGTH];
		OopValue: integer;

		DebugEnabled: boolean;

		HighScoreList: THighScoreList;
		{ ConfigRegistration: string; }
		{ ConfigWorldFile: TString50; }
		EditorEnabled: boolean;
		{ GameVersion: string[20]; }
		{ ParsingConfigFile: boolean; }
		{ ResetConfig: boolean; } { This flag is a remnant from ZZT 3.0. }
		JustStarted: boolean;

		WorldExt: TWorldExt;

		GameControllerHasTicked: boolean;
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
{$IFDEF DEBUGWND}
		DebugCompatEnabled: boolean;
		DebugUndefEnabled: boolean;
{$ENDIF}
{$IFDEF EDITOR}
		FileBoardCachedLinePos: integer;
		FileTextCachedLinePos: integer;
{$ENDIF}
{$IFDEF FASTVID}
		TransitionBlocksPerFrame: integer;
		TransitionTextWindowDelay: integer;
{$ENDIF}
	const
		E_EMPTY = 0;
		E_BOARD_EDGE = 1;
		E_MESSAGE_TIMER = 2;
		E_MONITOR = 3; { State - Title screen }
		E_PLAYER = 4; { State - Playing }
		E_AMMO = 5;
		E_TORCH = 6;
		E_GEM = 7;
		E_KEY = 8;
		E_DOOR = 9;
		E_SCROLL = 10;
		E_PASSAGE = 11;
		E_DUPLICATOR = 12;
		E_BOMB = 13;
		E_ENERGIZER = 14;
		E_STAR = 15;
		E_CONVEYOR_CW = 16;
		E_CONVEYOR_CCW = 17;
		E_BULLET = 18;
		E_WATER = 19;
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
		E_BLINK_RAY_EW = 33;
		E_BEAR = 34;
		E_RUFFIAN = 35;
		E_OBJECT = 36;
		E_SLIME = 37;
		E_SHARK = 38;
		E_SPINNING_GUN = 39;
		E_PUSHER = 40;
		E_LION = 41;
		E_TIGER = 42;
		E_BLINK_RAY_NS = 43;
		E_CENTIPEDE_HEAD = 44;
		E_CENTIPEDE_SEGMENT = 45;
		E_TEXT_BLUE = 47;
		E_TEXT_GREEN = 48;
		E_TEXT_CYAN = 49;
		E_TEXT_RED = 50;
		E_TEXT_PURPLE = 51;
		E_TEXT_YELLOW = 52;
		E_TEXT_WHITE = 53;
		{}
		E_TEXT_MIN = E_TEXT_BLUE;
		{}
		CATEGORY_ITEM = 1;
		CATEGORY_CREATURE = 2;
		CATEGORY_TERRAIN = 3;
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
