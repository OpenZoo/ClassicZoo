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

{$I-}
{$V-}
unit ZDemo;

interface
	const
		DEMO_MAX_COMMAND_SIZE = 7; { Shouldn't be here }
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
	{ Library }
	procedure DemoFlushFile(var f: text);
	function DemoStartRecord(filename: string): boolean;
	function DemoStartPlay(filename: string): boolean;
	function DemoStartLogging(filename: string): boolean;
	procedure DemoStop(ignoreErrors: boolean);
	function DemoIsComplete: boolean;
	function DemoIsPlaying: boolean;
	function DemoIsRecording: boolean;
	{ Hooks }
	procedure DemoReseedCurrentTick; { Replaces CurrentTick := ... }
	procedure DemoInputUpdate(expectedPitCount: word; isGameplaySensitive: boolean); { Replaces InputUpdate; }
	procedure DemoInputReadWaitKey;
	procedure DemoOnPitTick; { Call from SOUNDS.PAS's PIT interrupt handler }
	function DemoSoundHasTimeElapsed(var counter: integer; duration: integer): boolean;

implementation
uses Dos, Crt, GameVars, Input, Sounds;

type
	DemoMode = (
		DModeNone,
		DModeRecord,
		DModePlay,
		DModeComplete
	);
	DemoCommandType = (
		DCmdInput,
		DCmdReseedCurrentTick,
		DCmdGameStart,
		DCmdGameStop,
		DCmdPitTickDelta
	);
	DemoFetchMode = (
		DFetchAny,
		DFetchExpected
	);
	DemoHeader = record
		Magic: word;
		Version: word;
		Name: string[20];
		Flags: byte;
		EngineName: string[30];
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
	end;

const
	DEMO_MAGIC = $D327;
	DEMO_VERSION = $0002;
	DEMO_BUFFER_SIZE = 512;
	DEMO_COMMAND_OPTIONAL = $01;
	DEMO_COMMAND_VARLEN = $80;
	DemoCommandLengths: array[DCmdInput .. DCmdPitTickDelta] of byte = (
		7,
		5,
		7,
		1,
		3
	);
	DemoCommandFlags: array[DCmdInput .. DCmdPitTickDelta] of byte = (
		0,
		DEMO_COMMAND_OPTIONAL,
		0,
		0,
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
			{ If the fetched command is GameStop, sto. }
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

function DemoStartRecord(filename: string): boolean;
	var
		hdr: DemoHeader;
		cmd: DemoCommand;
	begin
		DemoStartRecord := false;

		hdr.Magic := DEMO_MAGIC;
		hdr.Version := DEMO_VERSION;
		hdr.Name := World.Info.Name;
		hdr.Flags := 0;
		hdr.EngineName := DemoEngineName;

		Assign(DemoFile, filename);
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

		{ Record the initial commands. }
		cmd.cmdType := DCmdGameStart;
		cmd.gsTickSpeed := TickSpeed;
		cmd.gsRandSeed := RandSeed;
		DemoAppendCommand(cmd);
	end;

function DemoStartPlay(filename: string): boolean;
	var
		hdr: DemoHeader;
		cmd: DemoCommand;
	begin
		DemoStartPlay := false;
		Assign(DemoFile, filename);
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
			BlockRead(DemoFile, hdr.Name, 22);
			hdr.EngineName[0] := #0;
		end else if hdr.Version = DEMO_VERSION then begin
			BlockRead(DemoFile, hdr.Name, SizeOf(DemoHeader) - 4);
		end else begin
			Close(DemoFile);
			exit;
		end;

		DemoFileSize := FileSize(DemoFile);

		DemoSetMode(DModePlay);
		DemoStartPlay := true;

		if not DemoFetchCommand(cmd, DCmdGameStart, DFetchExpected) then exit;

		DemoStartSeed := cmd.gsRandSeed;
		RandSeed := cmd.gsRandSeed;
		TickSpeed := cmd.gsTickSpeed;
		TickTimeDuration := TickSpeed * 2;

		InputDeltaX := 0;
		InputDeltaY := 0;
		InputShiftPressed := false;
		InputKeyPressed := #0;
	end;

function DemoStartLogging(filename: string): boolean;
	begin
		DemoStartLogging := false;
		if DemoCurrentMode = DModeNone then exit;

		Assign(DemoLogFile, filename);
		Rewrite(DemoLogFile);
		if IOResult <> 0 then begin
			Close(DemoLogFile);
			exit;
		end;

		DemoLogActive := true;
		DemoLogBoard := -1;
		DemoStartLogging := true;
	end;

procedure DemoStop(ignoreErrors: boolean);
	var
		cmd: DemoCommand;
	begin
		if DemoCurrentMode = DModeRecord then begin
			if DemoCurrentCommand.count > 0 then
				DemoAppendCommand(DemoCurrentCommand);

			cmd.cmdType := DCmdGameStop;
			DemoAppendCommand(cmd);

			DemoFlushRecordBuffer;
		end;

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
procedure DemoInputUpdate(expectedPitCount: word; isGameplaySensitive: boolean); { Replaces InputUpdate; }
	var
		rkey: char;
		cmd: DemoCommand;
		tickDiff: longint;
	label PlayFoundInput;
	label AfterInput;
	begin
		if DemoCurrentMode = DModePlay then begin
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

			if (DemoLogBoard >= 0) and (DemoLogBoard <> World.Info.CurrentBoard) then begin
				DemoLogEmit('SPLIT', DemoPitTicks);
				DemoLogBoard := World.Info.CurrentBoard;
			end;
		end;

		if DemoCurrentMode = DModeRecord then begin
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

begin
	DemoCurrentMode := DModeNone;
	DemoEngineName[0] := #0;
	DemoErrorCode := 0;
	DemoFastForward := false;
end.
