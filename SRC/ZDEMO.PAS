{
	Copyright (c) 2021 Adrian Siekierka

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

{
	ZDemo is a prototype implementation of a demo recording hook/call set for ZZT.
	Special thanks to Mr_Alert for the initial proof of concept.
}

{ TODO: Add RNG verification to keyboard inputs; not doing so opens up possibilities
  for undetected desynchronization on the final board. But I'll have to add writeln
  to debug file to trace what's going on, first, and possibly something like "if
  randVerify is either 0 or the current random state, then OK". Or just make it log
	errors to the debug file first, so I can compare the RNG sequence.}

{$I-}
{$V-}
unit ZDemo;

interface
	uses GameVars;
	var
		{ Configuration options }
		DemoFastForward: boolean;
		DemoStopOnEndgame: boolean;
		DemoEngineName: string[30];
		{ Feedback }
		DemoErrorCode: byte;
		DemoCommandsFetched: word;
		DemoFilePos: longint;
		DemoFileSize: longint;
		DemoPitTicks: longint;
		DemoPitTicksFirst: longint;
		DemoPitTicksLast: longint;
		DemoStartSeed: longint;
		DemoScore: word;
		{ File data }
		FullDemoFilename: string;
		FullDemoLogFilename: string;
	{ Helper functions }
	procedure SaveCopyDemoFiles(toFilename: string);
	{ Library }
	procedure DemoFlushFile(var f: text);
	function DemoStartRecord(filename, extension: string): boolean;
	function DemoStartPlay(filename, extension: string): boolean;
	function DemoResumeRecord(filename, extension: string): boolean;
	function DemoStartLogging(filename, extension: string): boolean;
	{ Resume recording from a savegame. filename is only the filename, not the extension. }
	function DemoRestoreRecord(filename: string): boolean;
	procedure DemoFinalize(stop: boolean);
	procedure DemoStop(ignoreErrors: boolean);
	{ The following procedures relate to storing high score data. }
	procedure DemoAddPlayerName(playerName: TString50);
	procedure DemoIgnoreKeypresses;
	procedure DemoReenableKeypresses;

	function DemoGetWorldName: string;

	function DemoIsComplete: boolean;
	function DemoIsPlaying: boolean;
	function DemoIsRecording: boolean;
	{ Hooks }
	procedure DemoReseedCurrentTick; { Replaces CurrentTick := ... }
	procedure DemoInputUpdate(expectedPitCount: word; isGameplaySensitive: boolean); { Replaces InputUpdate; }
	procedure DemoInputReadWaitKey;
	procedure DemoOnPitTick; { Call from SOUNDS.PAS's PIT interrupt handler }
	function DemoSoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	{ Pseudo-hooks. }
	procedure DemoRestartHere;

implementation
uses Dos, Crt, Input, Sounds, FileOps;

type
	DemoMode = (
		DModeNone,
		DModeRecord,
		DModePlay,
		DModeComplete
	);
	DemoCommandType = (
		DCmdInput,								{ Player input. }
		DCmdReseedCurrentTick,		{ Current tick value is reseeded; checks RNG state. }
		DCmdGameStart,						{ Game and demo start. }
		DCmdGameStop,							{ End of a finished demo. }
		DCmdPitTickDelta,					{ ??? }
		DCmdRestartHere,					{ Restart the main gameplay loop as if the game was just started. }
		DCmdNewSavegameName,			{ Register a new savegame name, updating LastSaveName. (See below.)}
		DCmdPlayerName						{ Register the player name for a high score entry. }
	);
	DemoFetchMode = (
		DFetchAny,
		DFetchExpected
	);
	DemoHeader = record
		Magic: word;
		Version: word;
		WorldName: string[20];
		Flags: byte;
		EngineName: string[30];

		{ Contains the last savegame saved before the demo was recorded. This is
		  required because, when saving a game, ZZT shows the previous save game
		  name in its filename field. Contains only the filename, not the
		  extension. }
		LastSaveName: string[20];

		{ Tracks the original demo name when we save a copy of the demo so far to
			a savegame. This lets us use a derived name when the player restores a
			savegame to continue recording. Contains only the filename, not the
			extension. }
		OrigDemoName: string[20];
	end;
	DemoCommand = record
		case cmdType: DemoCommandType of
		DCmdInput: (
			count: word;
			deltaX, deltaY: shortint;
			shiftPressed: boolean;
			keyPressed: char;
		);
		DCmdReseedCurrentTick: (
			randSeed: longint;
		);
		DCmdGameStart: (
			gsRandSeed: longint;
			gsTickSpeed: integer;
		);
		DCmdPitTickDelta: (
			pitTicks: integer;
		);
		DCmdNewSavegameName: (
			NewSaveName: string[20]
		);
		DCmdPlayerName: (
			PlayerName: TString50
		);
	end;

const
	DEMO_MAGIC = $D327;
	DEMO_VERSION = $0003;
	DEMO_BUFFER_SIZE = 512;
	DEMO_COMMAND_OPTIONAL = $01;
	DEMO_COMMAND_VARLEN = $80;
	DemoCommandLengths: array[DCmdInput .. DCmdPlayerName] of byte = (
		7,
		5,
		7,
		1,
		3,
		1,
		22,
		52
	);
	DemoCommandFlags: array[DCmdInput .. DCmdPlayerName] of byte = (
		0,
		{ Should DCmdReseedCurrentTick really be optional? It advances
		  the state of the RNG after all. }
		DEMO_COMMAND_OPTIONAL,
		0,
		0,
		DEMO_COMMAND_OPTIONAL,
		0,
		DEMO_COMMAND_OPTIONAL,
		DEMO_COMMAND_OPTIONAL
	);
var
	DemoBufferPos: integer;
	DemoBuffer: array[1 .. DEMO_BUFFER_SIZE] of byte;
	DemoCurrentCommand: DemoCommand;
	DemoCurrentMode: DemoMode;
	DemoFile: file;
	DemoLastPitTicks: longint;
	DemoRealPitTicks: longint;
	DemoInEndgame: boolean;
	DemoLogFile: text;
	DemoLogActive: boolean;
	DemoLogBoard: integer;
	DemoDoIgnoreKeypresses: boolean;
	WorldName: string[20]; { ditto }

procedure DemoFlushFile(var f: text);
	var
		regs: Registers;
	begin
		{ Seeking on DOS is a nightmare. Especially if you add in emulators. }

		{ Turbo Pascal }
		Flush(f);

		{ DOS 3.3+ - FFLUSH }
		regs.AX := $6800;
		regs.BX := TextRec(f).Handle;
		Intr($21, regs);

		{ DOSBox - forced Seek() }
		regs.AX := $4201;
		regs.BX := TextRec(f).Handle;
		regs.CX := 0;
		regs.DX := 0;
		Intr($21, regs);
	end;

procedure DemoLogEmit(code: string; ticks: longint);
	begin
		if not DemoLogActive then exit;
		Write(DemoLogFile, ticks);
		Write(DemoLogFile, ' ' + code + ' ');
		Write(DemoLogFile, World.Info.CurrentBoard);
		Write(DemoLogFile, ' ');
		Write(DemoLogFile, Board.Name);
		WriteLn(DemoLogFile);
		DemoFlushFile(DemoLogFile);
	end;

function DemoIsPlaying: boolean;
	begin
		DemoIsPlaying := (DemoCurrentMode = DModePlay);
	end;

function DemoIsRecording: boolean;
	begin
		DemoIsRecording := (DemoCurrentMode = DModeRecord);
	end;

function DemoIsComplete: boolean;
	begin
		DemoIsComplete := (DemoCurrentMode = DModeComplete);
	end;

procedure DemoFlushRecordBuffer;
	begin
		BlockWrite(DemoFile, DemoBuffer, DemoBufferPos - 1);
		DemoBufferPos := 1;
	end;

procedure DemoAppendCommand(var cmd: DemoCommand);
	var
		cmdLen: byte;
	begin
		if (cmd.cmdType <> DCmdInput) and (DemoCurrentCommand.Count > 0) then begin
			DemoAppendCommand(DemoCurrentCommand);
			DemoCurrentCommand.Count := 0;
		end;

		cmdLen := DemoCommandLengths[cmd.cmdType];
		if DemoBufferPos > (DEMO_BUFFER_SIZE - cmdLen) then
			DemoFlushRecordBuffer; 
		Move(cmd, DemoBuffer[DemoBufferPos], cmdLen);
		Inc(DemoBufferPos, cmdLen);
		Inc(DemoCommandsFetched);
	end;

function DemoFetchCommand(var cmd: DemoCommand; expectedType: DemoCommandType; fetchMode: DemoFetchMode): boolean;
	var
		startPos: longint;
	label FetchNext;
	begin
		DemoFetchCommand := false;
		if DemoErrorCode <> 0 then exit;

		startPos := FilePos(DemoFile);

	FetchNext:
		if Eof(DemoFile) then begin
			DemoErrorCode := 30 + Ord(expectedType);
			exit;
		end;

		BlockRead(DemoFile, cmd, 1);
		if DemoCommandLengths[cmd.cmdType] > 1 then
			BlockRead(DemoFile, cmd.count, DemoCommandLengths[cmd.cmdType] - 1);
		if IOResult <> 0 then begin
			DemoErrorCode := 1;
			exit;
		end;

		if (fetchMode = DFetchAny) or (cmd.cmdType = expectedType) then begin
			Inc(DemoCommandsFetched);
			DemoFilePos := FilePos(DemoFile);
			DemoFetchCommand := true;
		end else begin
			{ If the fetched command is optional, fetch another command. }
			{ If the expected command is optional, unfetch all and return. }
			{ If the fetched command is GameStop, stop. }
			{ Otherwise, fail. }
			if (DemoCommandFlags[cmd.cmdType] and DEMO_COMMAND_OPTIONAL) <> 0 then
				goto FetchNext
			else if (DemoCommandFlags[expectedType] and DEMO_COMMAND_OPTIONAL) <> 0 then
				Seek(DemoFile, startPos)
			else if (cmd.cmdType = DCmdGameStop) then
				{ TODO: This doesn't interact well with optionality logic below. }		
				DemoCurrentMode := DModeComplete
			else
				DemoErrorCode := 100 + (Ord(expectedType) * 10) + Ord(cmd.cmdType);
		end;
	end;

function DemoFetchAnyCommand(var cmd: DemoCommand): boolean;
	begin
		{ The last parameter isn't actually used and could be anything. }
		DemoFetchAnyCommand := DemoFetchCommand(cmd, DCmdInput, DFetchAny);
	end;

procedure DemoSetMode(mode: DemoMode);
	begin
		DemoCurrentMode := mode;
		DemoBufferPos := 1;
		DemoErrorCode := 0;
		DemoLastPitTicks := 0;
		DemoPitTicks := 0;
		DemoPitTicksFirst := -1;
		DemoPitTicksLast := 0;
		DemoInEndgame := false;
		DemoLogActive := false;
		DemoRealPitTicks := 0;
		DemoCommandsFetched := 0;
		FillChar(DemoCurrentCommand, SizeOf(DemoCurrentCommand), 0);
	end;

procedure SaveCopyDemoFiles(toFilename: string);
	var
		demoLogRawFile: file;
		cmd: DemoCommand;
	begin
		if not DemoIsRecording then Exit;

		{ Mark that a game was saved, as well as its filename. }
		cmd.cmdType := DCmdNewSavegameName;
		cmd.NewSaveName := toFilename;
		DemoAppendCommand(cmd);

		{ Copy the demo and log files. }
		DemoFinalize(false);
		CopyOpenFile(DemoFile, toFilename, '.ZZD');

		{ .ZZL has to be done differently because it's a text file.  }
		Close(DemoLogFile);
		Assign(demoLogRawFile, FullDemoLogFilename);
		Reset(demoLogRawFile, 1);
		CopyOpenFile(demoLogRawFile, toFilename, '.ZZL');
		Close(demoLogRawFile);
		Append(DemoLogFile);
	end;

function DemoStartRecord(filename, extension: string): boolean;
	var
		hdr: DemoHeader;
		cmd: DemoCommand;
	begin
		DemoStartRecord := false;
		DemoDoIgnoreKeypresses := false;

		hdr.Magic := DEMO_MAGIC;
		hdr.Version := DEMO_VERSION;
		hdr.WorldName := World.Info.Name;
		hdr.LastSaveName := SavedGameFileName;
		hdr.Flags := 0;
		hdr.EngineName := DemoEngineName;
		hdr.OrigDemoName := filename;

		WorldName := hdr.WorldName;

		Assign(DemoFile, filename + extension);
		Rewrite(DemoFile, 1);
		if IOResult <> 0 then begin
			Close(DemoFile);
			exit;
		end;

		BlockWrite(DemoFile, hdr, SizeOf(DemoHeader));
		if IOResult <> 0 then begin
			Close(DemoFile);
			exit;
		end;

		DemoSetMode(DModeRecord);
		DemoStartRecord := true;
		FullDemoFilename := filename + extension;

		{ Record the initial commands. }
		cmd.cmdType := DCmdGameStart;
		cmd.gsTickSpeed := TickSpeed;
		cmd.gsRandSeed := RandSeed;
		DemoAppendCommand(cmd);
	end;

function DemoStartPlay(filename, extension: string): boolean;
	var
		hdr: DemoHeader;
		cmd: DemoCommand;
	begin
		DemoStartPlay := false;
		Assign(DemoFile, filename + extension);
		Reset(DemoFile, 1);
		if IOResult <> 0 then begin
			Close(DemoFile);
			exit;
		end;

		BlockRead(DemoFile, hdr, 4);
		if (IOResult <> 0) or (hdr.Magic <> DEMO_MAGIC) then begin
			Close(DemoFile);
			exit;
		end;

		if hdr.Version = $0001 then begin
			BlockRead(DemoFile, hdr.WorldName, 22);
			hdr.EngineName[0] := #0;
		end else if hdr.Version = DEMO_VERSION then begin
			BlockRead(DemoFile, hdr.WorldName, SizeOf(DemoHeader) - 4);
		end else begin
			Close(DemoFile);
			exit;
		end;

		DemoFileSize := FileSize(DemoFile);
		WorldName := hdr.WorldName;

		DemoSetMode(DModePlay);
		DemoStartPlay := true;
		DemoDoIgnoreKeypresses := false;
		FullDemoFilename := filename + extension;

		if not DemoFetchCommand(cmd, DCmdGameStart, DFetchExpected) then exit;

		SavedGameFileName := hdr.LastSaveName;

		DemoStartSeed := cmd.gsRandSeed;
		RandSeed := cmd.gsRandSeed;
		TickSpeed := cmd.gsTickSpeed;
		TickTimeDuration := TickSpeed * 2;

		InputDeltaX := 0;
		InputDeltaY := 0;
		InputShiftPressed := false;
		InputKeyPressed := #0;
	end;

{ Resume recording from the end of the given file. Returns false on error.
  We assume that the game state (player location, stats, etc.) has been set
  by restoring a game; if the game state has diverged from the log we're
  resuming from, weird things may happen upon replaying. }
{ TODO: Give the function a different name once it's working, to help
	distinguish it from DemoRestoreRecord. }
function DemoResumeRecord(filename, extension: string): boolean;
	var
		hdr: DemoHeader;
		cmd: DemoCommand;
	begin
		DemoResumeRecord := false;

		{ First load the file (or try to). This part is like DemoStartPlay. }
		Assign(DemoFile, filename + extension);
		Reset(DemoFile, 1);
		if IOResult <> 0 then begin
			Close(DemoFile);
			exit;
		end;

		BlockRead(DemoFile, hdr, 4);
		if (IOResult <> 0) or (hdr.Magic <> DEMO_MAGIC) then begin
			Close(DemoFile);
			exit;
		end;

		if hdr.Version = $0001 then begin
			BlockRead(DemoFile, hdr.WorldName, 22);
			hdr.EngineName[0] := #0;
		end else if hdr.Version = DEMO_VERSION then begin
			BlockRead(DemoFile, hdr.WorldName, SizeOf(DemoHeader) - 4);
		end else begin
			Close(DemoFile);
			exit;
		end;

		DemoFileSize := FileSize(DemoFile);
		WorldName := hdr.WorldName;

		{ Now "play through" the demo to set the random seed and other
			game-specific variables so the game state will match up.  }

		while not Eof(DemoFile) do begin
			if not DemoFetchAnyCommand(cmd) then begin
				Close(DemoFile);
				Exit; { Something went wrong... Better error handling here? }
			end;

			if cmd.cmdType = DCmdGameStart then begin
				DemoStartSeed := cmd.gsRandSeed;
				RandSeed := cmd.gsRandSeed;
				TickSpeed := cmd.gsTickSpeed;
				TickTimeDuration := TickSpeed * 2;
			end;

			if cmd.cmdType = DCmdReseedCurrentTick then begin
				RandSeed := cmd.RandSeed;
				CurrentTick := Random(100);
			end;

			if cmd.cmdType = DCmdNewSavegameName then
				SavedGameFileName := cmd.NewSaveName;
		end;

		DemoResumeRecord := true;

		DemoSetMode(DModeRecord);
		DemoDoIgnoreKeypresses := false;
		FullDemoFilename := filename + extension;

		{ Append a DCmdRestartHere event since we just restored a game. }
		cmd.cmdType := DCmdRestartHere;
		DemoAppendCommand(cmd);

		InputDeltaX := 0;
		InputDeltaY := 0;
		InputShiftPressed := false;
		InputKeyPressed := #0;
	end;

function DemoStartLogging(filename, extension: string): boolean;
	begin
		DemoStartLogging := false;
		if DemoCurrentMode = DModeNone then exit;

		Assign(DemoLogFile, filename + extension);
		Rewrite(DemoLogFile);
		if IOResult <> 0 then begin
			Close(DemoLogFile);
			exit;
		end;

		DemoLogActive := true;
		DemoLogBoard := -1;
		DemoStartLogging := true;
		FullDemoLogFilename := filename + extension;
	end;

{ Get the original demo name stored in the given demo file. }
function GetOrigDemoName(filename, extension: string): string;
	var
		hdr: DemoHeader;
		f: file;
	begin
		GetOrigDemoName := '';
		Assign(f, filename + extension);
		Reset(f, 1);
		if IOResult <> 0 then begin
			Close(f);
			Exit;
		end;

		BlockRead(f, hdr, 4);
		if (IOResult <> 0) or (hdr.Magic <> DEMO_MAGIC) then begin
			Close(f);
			Exit;
		end;

		if hdr.Version < $0003 then begin
			{ Earlier versions don't have the original demo name recorded. }
			Close(f);
			Exit;
		end;

		BlockRead(f, hdr.WorldName, SizeOf(DemoHeader) - 4);
		GetOrigDemoName := hdr.OrigDemoName;
		Close(f);
	end;

function DemoRestoreRecord(filename: string): boolean;
	var
		newRecordFilename: string;
	begin
		DemoRestoreRecord := false;

		if DemoIsPlaying or DemoIsRecording then
			DemoStop(true);

		if not FileExists(filename + '.ZZD') then
			Exit;

		newRecordFilename := GetOrigDemoName(filename, '.ZZD');
		if newRecordFilename = '' then
			newRecordFilename := 'UNKDEMO';

		newRecordFilename := GetNumberedFilename(newRecordFilename,
			'.ZZD', 1000);

		CopyFile(filename, '.ZZD', newRecordFilename, '.ZZD');

		{ TODO: Open the new record name for recording, dump the header
		  to the unit-wide variables the way StartRecord does, and set
		  the pointer to the very end of the file to be ready to append.

			Remember to copy the ZZL file too. }

		DemoRestoreRecord := DemoResumeRecord(newRecordFilename, '.ZZD');

	end;

{ Dump the current command to file if we have one. This is used for
	finalizing demos accompanying savegames without actually stopping the
	recording. }
procedure DemoFinalize(stop: boolean);
	var
		cmd: DemoCommand;
	begin
		if DemoCurrentCommand.count > 0 then
			DemoAppendCommand(DemoCurrentCommand);

		{ TODO: Somehow append stop commands to savegame demos, so they're all
			proper demos? But then that means we have to strip them when loading...
			ponder this more. }
		if stop then begin
			cmd.cmdType := DCmdGameStop;
			DemoAppendCommand(cmd);
		end;

		DemoFlushRecordBuffer;
	end;

procedure DemoStop(ignoreErrors: boolean);
	var
		cmd: DemoCommand;
	begin
		if DemoCurrentMode = DModeRecord then begin
			DemoFinalize(true);
		end;

		{ Not sure why putting this inside DModePlay doesn't work. -KM }
		if DemoCurrentMode <> DModeNone then
			DemoScore := World.Info.Score;

		if DemoCurrentMode = DModePlay then begin
			if not ignoreErrors then begin
				{ TODO: Catch this case better? }
				if DemoFetchCommand(cmd, DCmdGameStop, DFetchExpected) then begin end;
			end;
		end;

		if DemoCurrentMode <> DModeNone then begin
			Close(DemoFile);
			if DemoLogActive then begin
				DemoLogEmit('STOP', DemoPitTicksLast);
				Close(DemoLogFile);
				DemoLogActive := false;
			end;
			DemoCurrentMode := DModeNone;
		end;
	end;

procedure DemoAddPlayerName(playerName: TString50);
	var
		cmd: DemoCommand;
	begin
		cmd.cmdType := DCmdPlayerName;
		cmd.playerName := playerName;
		DemoAppendCommand(cmd);
	end;

{ We need to keep recording while the player inputs their name for the high
	score, to store that player name as part of the demo. However, whether the
	actual high score dialog appears at the end of a playthrough depends on factors
	we don't know about; thus we can't guarantee that it will, and thus we shouldn't
	record the keypresses the player used when inputting their score, because it
	will desynchronize if the high score box doesn't show later. That's what these
	procedures are for: to disable input recording while in recording mode. }

procedure DemoIgnoreKeypresses;
	begin
		DemoDoIgnoreKeypresses := true;
	end;

procedure DemoReenableKeypresses;
	begin
		DemoDoIgnoreKeypresses := false;
	end;

function DemoGetWorldName: string;
	begin
		DemoGetWorldName := WorldName;
	end;

{$IFDEF FPC}
procedure Sti;
asm sti end;

procedure Cli;
asm cli end;
{$ELSE}
procedure Sti;
inline($fb);

procedure Cli;
inline($fa);
{$ENDIF}

procedure DemoPlaySyncPit;
	begin
		if not DemoFastForward then begin
			Cli;
			if DemoPitTicks < DemoRealPitTicks then
				DemoRealPitTicks := DemoPitTicks;
			Sti;
			while DemoPitTicks > DemoRealPitTicks do begin end;
		end;
	end;

function DemoInputNonZero: boolean;
	begin
		DemoInputNonZero := (InputDeltaX <> 0) or (InputDeltaY <> 0)
			or (InputShiftPressed) or (InputKeyPressed <> #0);
	end;

{
  The isGameplaySensitive flag culls dummy cycles from calls whose idle cycles
  do not affect gameplay.
}

{ I don't really know what's going on here. -KM }
procedure DemoInputUpdate(expectedPitCount: word; isGameplaySensitive: boolean); { Replaces InputUpdate; }
	var
		rkey: char;
		cmd: DemoCommand;
		tickDiff: longint;
	label PlayFoundInput;
	label AfterInput;
	begin
		{ Playback mode. }
		if DemoCurrentMode = DModePlay then begin

			{ Check if the player pressed Q or ESC. If so, stop the demo. }
			while KeyPressed do begin
				rkey := UpCase(readKey);
				if rkey in [#27, 'Q'] then begin
					DemoStop(true);
					InputKeyPressed := rkey;
					exit;
				end;
			end;

			Inc(DemoPitTicks, expectedPitCount);

			if (DemoCurrentCommand.cmdType = DCmdInput) then begin
	PlayFoundInput:
				if DemoCurrentCommand.count > 0 then begin
					InputDeltaX := DemoCurrentCommand.deltaX;
					InputDeltaY := DemoCurrentCommand.deltaY;
					InputShiftPressed := DemoCurrentCommand.shiftPressed;
					InputKeyPressed := DemoCurrentCommand.keyPressed;
					Dec(DemoCurrentCommand.count);
					goto AfterInput;
				end;
			end;

			while DemoFetchCommand(cmd, DCmdPitTickDelta, DFetchExpected) do begin
				Inc(DemoPitTicks, cmd.pitTicks);
				DemoPlaySyncPit;
			end;

			if DemoFetchCommand(DemoCurrentCommand, DCmdInput, DFetchExpected) then begin
				goto PlayFoundInput;
			end;

			goto AfterInput;
		end;

		InputUpdate;

	AfterInput:
		if (DemoCurrentMode = DModePlay) or (DemoCurrentMode = DModeRecord) then begin
			if DemoInEndgame then begin
				if World.Info.Health > 0 then
					DemoInEndgame := false;
			end;

			if (not DemoInEndgame) then begin
				if (DemoInputNonZero) or (World.Info.Health <= 0) then begin
					if DemoPitTicksFirst < 0 then begin
						DemoPitTicksFirst := DemoPitTicks;
						DemoLogEmit('START', DemoPitTicksFirst);
						DemoLogBoard := World.Info.CurrentBoard;
					end;
					DemoPitTicksLast := DemoPitTicks;
					DemoInEndgame := World.Info.Health <= 0;
				end;
			end;

			{ If we entered a new board, record a split and our current PIT counter. }
			if (DemoLogBoard >= 0) and (DemoLogBoard <> World.Info.CurrentBoard) then begin
				DemoLogEmit('SPLIT', DemoPitTicks);
				DemoLogBoard := World.Info.CurrentBoard;
			end;
		end;

		{ Recording mode. }
		if (DemoCurrentMode = DModeRecord) and (not DemoDoIgnoreKeypresses) then begin

			{ Update the demo pit counter??? }
			if isGameplaySensitive or DemoInputNonZero then begin
				Cli;
				tickDiff := (DemoPitTicks - DemoLastPitTicks) - expectedPitCount;
				DemoLastPitTicks := DemoPitTicks;
				Sti;

				if tickDiff <> 0 then begin
					cmd.cmdType := DCmdPitTickDelta;
					cmd.pitTicks := 32767;
					while tickDiff > 32767 do begin
						DemoAppendCommand(cmd);
						Dec(tickDiff, 32767);
					end;
					cmd.pitTicks := -32768;
					while tickDiff < -32768 do begin
						DemoAppendCommand(cmd);
						Inc(tickDiff, 32768);
					end;
					cmd.pitTicks := tickDiff;
					if cmd.pitTicks <> 0 then begin
						DemoAppendCommand(cmd);
					end;
				end;
			end;

			if DemoStopOnEndgame then begin
				if World.Info.Health < 0 then begin
					DemoStop(false);
					exit;
				end;
			end;

			{ If something has changed, record it. }

			if (DemoCurrentCommand.deltaX <> InputDeltaX)
			or (DemoCurrentCommand.deltaY <> InputDeltaY)
			or (DemoCurrentCommand.shiftPressed <> InputShiftPressed)
			or (DemoCurrentCommand.keyPressed <> InputKeyPressed)
			then begin
				if DemoCurrentCommand.count > 0 then
					DemoAppendCommand(DemoCurrentCommand);
				DemoCurrentCommand.deltaX := InputDeltaX;
				DemoCurrentCommand.deltaY := InputDeltaY;
				DemoCurrentCommand.shiftPressed := InputShiftPressed;
				DemoCurrentCommand.keyPressed := InputKeyPressed;
				DemoCurrentCommand.count := 1;
			end else begin
				if (isGameplaySensitive) or (DemoCurrentCommand.count <= 0)
				or (DemoInputNonZero)
				then begin
					if DemoCurrentCommand.count = 65535 then begin
						DemoAppendCommand(DemoCurrentCommand);
						DemoCurrentCommand.count := 1;
					end else begin
						Inc(DemoCurrentCommand.count);
					end;
				end;
			end;
		end;
	end;

procedure DemoInputReadWaitKey;
	begin
		repeat
			DemoInputUpdate(0, false)
		until InputKeyPressed <> #0;
	end;

procedure DemoReseedCurrentTick;
	var
		cmd: DemoCommand;
	begin
		if DemoCurrentMode = DModePlay then begin
			if DemoFetchCommand(cmd, DCmdReseedCurrentTick, DFetchExpected) then begin
				if RandSeed <> cmd.randSeed then begin
					DemoErrorCode := 4;
				end;
			end;
		end else if DemoCurrentMode = DModeRecord then begin
			cmd.cmdType := DCmdReseedCurrentTick;
			cmd.randSeed := RandSeed;
			DemoAppendCommand(cmd);
		end;

		CurrentTick := Random(100);

	end;

procedure DemoOnPitTick;
	begin
		if DemoCurrentMode <> DModePlay then
			Inc(DemoPitTicks);
		Inc(DemoRealPitTicks);
	end;

function DemoSoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	var
		hSecsDiff: word;
		hSecsTotal: integer;
	begin
		if DemoCurrentMode <> DModeNone then begin
			if (DemoCurrentMode = DModePlay) and (DemoFastForward) then
				hSecsTotal := (DemoPitTicks * 11) shr 1
			else
				hSecsTotal := (DemoRealPitTicks * 11) shr 1;
			hSecsDiff := hSecsTotal - counter;

			if hSecsDiff >= duration then begin
				DemoSoundHasTimeElapsed := true;
				counter := hSecsTotal;
			end else begin
				DemoSoundHasTimeElapsed := false;
			end;
		end else DemoSoundHasTimeElapsed := SoundHasTimeElapsed(counter, duration);
	end;

{ Handle the DCmdRestartHere event if present, which sets GameRestartNeeded, thus
	restarting the gameplay loop to reproduce what happens when a game is saved,
	exited, and restored. }

procedure DemoRestartHere;
	var
		cmd: DemoCommand;
	begin
		if DemoCurrentMode = DModePlay then begin
			{ Check if there's an actual restart event in the log. }
			if DemoFetchCommand(cmd, DCmdRestartHere, DFetchExpected) then begin
				GameRestartNeeded := true;
			end;
		end;
	end;

begin
	DemoCurrentMode := DModeNone;
	DemoEngineName[0] := #0;
	DemoErrorCode := 0;
	DemoFastForward := false;
end.
