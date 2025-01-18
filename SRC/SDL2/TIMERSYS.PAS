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

{$MODE OBJFPC}
unit TimerSys;

{$DEFINE NO_CONST_FREQS}

interface
	uses SDL2;
	type
		TIdleMode = (IMUntilPit, IMUntilFrame);
		TDrumData = record
			Len: integer;
			Data: array[1 .. 15] of word;
		end;
{$I SNDFREQ.INC}
		SOUND_FREQ_PRECISION = 8; { TODO: Depends on magic values in AudioSim }
	var
		SoundFreqTable: array[0 .. 255] of longint;
		EventMutex: PSDL_Mutex;
		TimerTicks: word;
	procedure AccurateDelay(ms: word);
	procedure TimerSysIdle(mode: TIdleMode);
	procedure TimerSysWake(mode: TIdleMode);
	procedure TimerSysLockSoundBuffer;
	procedure TimerSysUnlockSoundBuffer;
	procedure TimerSysStopSound;
	procedure TimerSysQueueSound(pattern: string; isForce: boolean);
	function TimerSysGetHsecs: word;
	procedure TimerSysInstall;
	procedure TimerSysUninstall;
	procedure TimerSysAudioOpen;
	procedure TimerSysAudioClose;
	procedure SoundInitFreqTable(highQuality: boolean);

implementation
uses AudioSim, CTypes, Math, Sounds;

const
	PIT_SPEED_MS = 55;
var
	PitTimerId: TSDL_TimerID;
	TimerHsecs: word;
	SoundBufferMutex: PSDL_Mutex;
	TimerMutexes: array [Low(TIdleMode)..High(TIdleMode)] of PSDL_Mutex;
	TimerConds: array [Low(TIdleMode)..High(TIdleMode)] of PSDL_Cond;
	{ }
	AudioDevice: TSDL_AudioDeviceID;
	AudioSpec: TSDL_AudioSpec;

procedure AccurateDelay(ms: word);
	begin
		SDL_Delay(ms);
	end;

procedure AudioCallback(userdata: pointer; stream: PCUint8; len: Int32); cdecl;
	begin
		AudioSimulate(TAudioSampleArray(stream), len);
	end;

procedure TimerSysIdle(mode: TIdleMode);
	begin
		SDL_LockMutex(TimerMutexes[mode]);
		SDL_CondWait(TimerConds[mode], TimerMutexes[mode]);
		SDL_UnlockMutex(TimerMutexes[mode]);
	end;

procedure TimerSysWake(mode: TIdleMode);
	begin
		SDL_LockMutex(TimerMutexes[mode]);
		SDL_CondBroadcast(TimerConds[mode]);
		SDL_UnlockMutex(TimerMutexes[mode]);
	end;

procedure TimerSysLockSoundBuffer;
	begin
		SDL_LockMutex(SoundBufferMutex);
	end;

procedure TimerSysUnlockSoundBuffer;
	begin
		if (not SoundEnabled) or (not SoundIsPlaying) then
			AudioSimulateClear;
		SDL_UnlockMutex(SoundBufferMutex);
	end;

procedure TimerSysStopSound;
	begin
		SDL_LockMutex(SoundBufferMutex);
		AudioSimulateClear;
		SDL_UnlockMutex(SoundBufferMutex);
	end;

procedure TimerSysQueueSound(pattern: string; isForce: boolean);
	var
		appendSilence: boolean;
		diffTicks: integer;
	begin
		{ SoundQueue -> We are locked here }
{
		WriteLn('Queue sound Timer=', TimerTicks, ' AudioSimStop=', AudioSimSoundBufferStopTicks);
		WriteLn('AudioSimSB Pos=', AudioSimSoundBufferPos, ' Len=', Length(AudioSimSoundBuffer));
		WriteLn('SB Pos=', SoundBufferPos, ' Len=', Length(SoundBuffer));
}

		if isForce then begin
			AudioSimSoundBuffer := pattern;
			AudioSimSoundBufferPos := 1;
		end else begin
			AudioSimSoundBuffer := Copy(AudioSimSoundBuffer, AudioSimSoundBufferPos, Length(AudioSimSoundBuffer) - AudioSimSoundBufferPos + 1);
			AudioSimSoundBufferPos := 1;
			AudioSimSoundBuffer := AudioSimSoundBuffer + pattern;
		end;

		AudioSimSoundBufferStopTicks := TimerTicks + SoundCountTicks(pattern);
	end;

function TimerSysGetHsecs: word;
	begin
		TimerSysGetHsecs := TimerHsecs shr 1;
	end;

function PitTimerCallback(interval: Uint32; param: Pointer): Uint32; cdecl;
	begin
		Inc(TimerTicks);
		TimerHsecs := TimerHsecs + (PIT_SPEED_MS div 5);

		{ Emulate DOS sound buffer. }
		if not SoundEnabled then begin
			SoundIsPlaying := false;
		end else if SoundIsPlaying then begin
			Dec(SoundDurationCounter);
			if SoundDurationCounter <= 0 then begin
				if SoundBufferPos >= Length(SoundBuffer) then begin
					SoundIsPlaying := false;
				end else begin
					Inc(SoundBufferPos);
					SoundDurationCounter := SoundDurationMultiplier * Ord(SoundBuffer[SoundBufferPos]);
					Inc(SoundBufferPos);
				end;
			end;
		end;

		AudioSimulationAllowed := SoundIsPlaying;

		TimerSysWake(IMUntilPit);
		PitTimerCallback := PIT_SPEED_MS;
	end;

procedure TimerSysInstall;
	var
		mode: TIdleMode;
	begin
		{ https://forum.lazarus.freepascal.org/index.php?topic=69852.15 }
		SetExceptionMask(GetExceptionMask + [exZeroDivide, exInvalidOp, exDenormalized, exOverflow, exUnderflow, exPrecision]);
		SDL_Init(SDL_INIT_EVERYTHING);
		SDL_GameControllerAddMappingsFromFile('gamecontrollerdb.txt');
		SDL_StartTextInput;
		PitTimerId := SDL_AddTimer(PIT_SPEED_MS, @PitTimerCallback, nil);

		EventMutex := SDL_CreateMutex;
		SoundBufferMutex := SDL_CreateMutex;
		for mode in TIdleMode do begin
			TimerMutexes[mode] := SDL_CreateMutex;
			TimerConds[mode] := SDL_CreateCond;
		end;
	end;

procedure TimerSysAudioOpen;
	var
		requestedAudioSpec: TSDL_AudioSpec;
	begin
		requestedAudioSpec := Default(TSDL_AudioSpec);
		requestedAudioSpec.freq := 48000;
{$IFDEF AUD16BIT}
		requestedAudioSpec.format := AUDIO_S16SYS;
{$ELSE}
		requestedAudioSpec.format := AUDIO_U8;
{$ENDIF}
		requestedAudioSpec.channels := 1;
		requestedAudioSpec.samples := 2048;
		requestedAudioSpec.callback := @AudioCallback;

		AudioDevice := SDL_OpenAudioDevice(nil, 0, @requestedAudioSpec, @AudioSpec, 0);
		SDL_PauseAudioDevice(AudioDevice, 0);
	end;

procedure TimerSysAudioClose;
	begin
		if AudioDevice <> 0 then begin
			SDL_CloseAudioDevice(AudioDevice);
			AudioDevice := 0;
		end;
	end;

procedure TimerSysUninstall;
	var
		mode: TIdleMode;
	begin
		for mode in TIdleMode do begin
			SDL_DestroyCond(TimerConds[mode]);
			SDL_DestroyMutex(TimerMutexes[mode]);
		end;
		SDL_DestroyMutex(SoundBufferMutex);
		SDL_DestroyMutex(EventMutex);

		SDL_RemoveTimer(PitTimerId);
		SDL_StopTextInput;
		SDL_Quit;
	end;

procedure SoundInitFreqTable(highQuality: boolean);
	var
		octave, note: integer;
		freqC1, noteStep, noteBase, ln2: real;
	begin
		freqC1 := 32.0;
		ln2 := Ln(2.0);
		noteStep := Exp(ln2 / 12.0);
		for octave := 1 to 15 do begin
			noteBase := Exp(octave * ln2) * freqC1;
			for note := 0 to 11 do begin
				if highQuality then
					SoundFreqTable[octave * 16 + note] := Round(noteBase * (1 shl SOUND_FREQ_PRECISION))
				else
					SoundFreqTable[octave * 16 + note] := Trunc(noteBase) * (1 shl SOUND_FREQ_PRECISION);
				noteBase := noteBase * noteStep;
			end;
		end;
	end;

begin
	TimerTicks := 0;
	TimerHsecs := 0;
end.
