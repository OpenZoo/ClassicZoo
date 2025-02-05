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

unit TimerSys;

interface
	type
		TIdleMode = (IMUntilPit, IMUntilFrame);
		TDrumData = record
			Len: integer;
			Data: array[1 .. 15] of word;
		end;
	var
		TimerTicks: word;
		TimerSubTicks: word;
		SoundFreqDivisor: longint;
		SpeakerActive: boolean;
	procedure AccurateDelayCalibrate;
	procedure AccurateDelay(ms: word);
	procedure TimerSysIdle(mode: TIdleMode);
	procedure TimerSysLockSoundBuffer;
	procedure TimerSysUnlockSoundBuffer;
	procedure TimerSysStopSound;
	function TimerSysGetHsecs: word;
	procedure TimerSysInstall;
	procedure TimerSysUninstall;

implementation
uses ZDemo, Dos, PC98, Sounds;
var
	SoundOldVector: pointer;
	SoundOldVector07: pointer;

{$I SNDFREQ.INC}
	DELAY_LOOP_MAX_ITERATIONS = $7FFFFFFF;

{$IFNDEF FPC}
var
	DelayLoopIterations: longint;

function AccurateDelayLoop(iterations: longint; var monitor: word): longint;
	begin
		inline(
			$8B/$BE/monitor/ { MOV DI, SS:[monitor] }
			$8B/$86/monitor+2/ { MOV AX, SS:[monitor+2] }
			$8E/$C0/ { MOV ES, AX }
			$8B/$86/iterations/ { MOV AX, SS:[iterations] }
			$8B/$96/iterations+2/ { MOV DX, SS:[iterations+2] }
			$8B/$1D/ { MOV BX, [ES:DI] }
		{ loop: }
			$90/$90/ { NOP x 2 }
			$83/$E8/$01/ { SUB AX, 1 }
			$83/$DA/$00/ { SBB DX, 0 }
			$72/$04/ { JC done }
			$3B/$1D/ { CMP BX, [ES:DI] }
			$74/$F2/ { JE loop }
		{ done: }
			$89/$86/AccurateDelayLoop/ { MOV AX, SS:[AccurateDelayLoop] }
			$89/$96/AccurateDelayLoop+2 { MOV DX, SS:[AccurateDelayLoop+2] }
		);
	end;

procedure AccurateDelayCalibrate;
	var
		iterations: longint;
		ticks: word;
	begin
		ticks := TimerTicks;
		repeat until TimerTicks <> ticks;
		iterations := AccurateDelayLoop(DELAY_LOOP_MAX_ITERATIONS, TimerTicks);
		DelayLoopIterations := (DELAY_LOOP_MAX_ITERATIONS - iterations) div 55;
	end;

procedure AccurateDelay(ms: word);
	var
		iterations: longint;
		unchanged: word;
	begin
		iterations := DelayLoopIterations * ms;
		if iterations <> 0 then
			iterations := AccurateDelayLoop(iterations, unchanged);
	end;
{$ELSE}
procedure AccurateDelayCalibrate;
	begin
		{ I'm not sure if Free Pascal lets you do this, though. }
	end;

procedure AccurateDelay(ms: word);
	begin
		{ Free Pascal contains properly calibrated delay logic. }
		Delay(ms);
	end;
{$ENDIF}

procedure SoundUpdateFreqDivisor;
	begin
		if (Mem[0:$0501] and $80) = 0 then begin
			Port[$71] := $D1;
			Port[$71] := $83;
			SoundFreqDivisor := 2457600;
		end else begin
			Port[$71] := $1A;
			Port[$71] := $6B;
			SoundFreqDivisor := 1996800; 
		end;
	end;

procedure TimerSysIdle(mode: TIdleMode);
	begin
		{ no-op? }
	end;

procedure SoundPlayDrum(var drum: TDrumData);
	var
		i: integer;
	begin
		for i := 1 to drum.Len do begin
			Sound(drum.Data[i]);
			AccurateDelay(1);
		end;
		NoSound;
	end;

procedure TimerSysLockSoundBuffer;
	begin
		{ no-op? }
	end;

procedure TimerSysUnlockSoundBuffer;
	begin
		{ no-op? }
	end;

procedure TimerSysStopSound;
	begin
		NoSound;
	end;

function TimerSysGetHsecs: word;
	begin
		TimerSysGetHsecs := Word((LongInt(TimerTicks) * 93) shr 4);
	end;

procedure SoundTimerHandler;
	interrupt;
	var
		regs: Registers;
	begin
		Intr($07, regs);
		SoundUpdateFreqDivisor;

		Inc(TimerSubTicks);
		if (TimerSubTicks and 3) <> 0 then
			Exit;

		Inc(TimerTicks);
		DemoOnPitTick;

		if not SoundEnabled then begin
			SoundIsPlaying := false;
			NoSound;
		end else if SoundIsPlaying then begin
			Dec(SoundDurationCounter);
			if SoundDurationCounter <= 0 then begin
				NoSound;
				if SoundBufferPos >= Length(SoundBuffer) then begin
					NoSound;
					SoundIsPlaying := false;
				end else begin
					if (SoundBuffer[SoundBufferPos] >= #16) and (SoundBuffer[SoundBufferPos] < #112) then
						Sound(SoundFreqTable[Ord(SoundBuffer[SoundBufferPos])])
					else if (SoundBuffer[SoundBufferPos] >= #240) and (SoundBuffer[SoundBufferPos] < #250) then
						SoundPlayDrum(SoundDrumTable[Ord(SoundBuffer[SoundBufferPos]) - 240])
					else
						NoSound;

					Inc(SoundBufferPos);

					SoundDurationCounter := SoundDurationMultiplier * Ord(SoundBuffer[SoundBufferPos]);
					Inc(SoundBufferPos);
				end;
			end;
		end;
	end;

procedure TimerSysInstall;
	begin
		GetIntVec($08, SoundOldVector);
		GetIntVec($07, SoundOldVector07);
		SetIntVec($08, @SoundTimerHandler);
		SetIntVec($07, SoundOldVector);

		{ configure timing }
	{$IFNDEF FPC}
		inline($FA); { CLI }
	{$ELSE}
		asm
			cli
		end;
	{$ENDIF}
		Port[$77] := $36;
		SoundUpdateFreqDivisor;
		Port[$02] := (Port[$02] and $FE);
	{$IFNDEF FPC}
		inline($FB); { STI }
	{$ELSE}
		asm
			sti
		end;
	{$ENDIF}

		NoSound;

{$IFNDEF FPC}
		DelayLoopIterations := 0;
		AccurateDelayCalibrate;
{$ENDIF}
	end;

procedure TimerSysUninstall;
	begin
		SetIntVec($08, SoundOldVector);
		SetIntVec($07, SoundOldVector07);
	end;

begin
	TimerTicks := 0;
	TimerSubTicks := 0;
end.
