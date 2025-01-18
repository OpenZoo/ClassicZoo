{
	Copyright (c) 2020 Adrian Siekierka

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
  Known issues:
  - currently hardcoded to 48000Hz unsigned 8-bit samples
}

unit AudioSim;

interface
	uses CTypes;
	type
{$IFDEF AUD16BIT}
		TAudioSample = Int16;
		TAudioSampleArray = PCInt16;
{$ELSE}
		TAudioSample = UInt8;
		TAudioSampleArray = PCUInt8;
{$ENDIF}
	var
		AudioSimRoundSamples: boolean;
		AudioSimSoundBufferStopTicks: integer;
		AudioSimSoundBuffer: string;
		AudioSimSoundBufferPos: integer;
		AudioSimulationAllowed: boolean;
		AudioSimPlayerStep: boolean;
	{ Volume range: 0-127 }
	function AudioGetVolume: byte;
	procedure AudioSetVolume(volume: byte);
	function AudioGetHighQuality: boolean;
	procedure AudioSetHighQuality(value: boolean);
	procedure AudioSimulateClear;
	procedure AudioSimulate(stream: TAudioSampleArray; len: Int32);

implementation
uses Sounds, TimerSys, Math;

type
	TAudioSimNoteToProc = procedure(targetNotePos: Uint32; frequency: Uint32; isDrum: boolean; stream: TAudioSampleArray; var streamPos: Int32; streamLen: Int32);
const
	PIT_DIVISOR = 1193182;
	AUDIO_FREQUENCY = 48000;
	SAMPLES_PER_PIT = 2640;
	SAMPLES_PER_DRUM = 48;
	SAMPLES_NOTE_DELAY = 16;
var
	AudioSampleVolume: byte;
	AudioSampleMin, AudioSampleNone, AudioSampleMax: TAudioSample;
	AudioSimNoteTo: TAudioSimNoteToProc;
	CurrentNote: Int32;
	CurrentNotePos: Uint32;
	CurrentNoteMax: Uint32;
	AudioSimPlayerStepCounter: Uint8;

function AudioGetVolume: byte;
	begin
		AudioGetVolume := AudioSampleVolume;
	end;

procedure AudioSetVolume(volume: byte);
	begin
		if volume > 127 then volume := 127;
		AudioSampleVolume := volume;

		volume := volume shr 2;

{$IFDEF AUD16BIT}
		AudioSampleNone := 0;
		AudioSampleMin := -(volume * 256);
		AudioSampleMax := (volume * 256);
{$ELSE}
		AudioSampleNone := 128;
		AudioSampleMin := 128 - volume;
		AudioSampleMax := 128 + volume;
{$ENDIF}
	end;

procedure AudioSimulateClear;
	begin
		AudioSimPlayerStep := false;
		CurrentNote := -1;
	end;

function AudioSimCalcJump(targetNotePos: Uint32; streamPos: Int32; streamLen: Int32): Uint32;
	var
		maxStreamChange: Int32;
		maxTargetChange: Int32;
	begin
		maxTargetChange := targetNotePos - CurrentNotePos;
		if maxTargetChange < 0 then begin
			AudioSimCalcJump := 0;
			exit;
		end;
		maxStreamChange := streamLen - streamPos;
		if maxTargetChange < maxStreamChange then AudioSimCalcJump := maxTargetChange else AudioSimCalcJump := maxStreamChange;
	end;

procedure AudioSimJumpBy(amount: Uint32; var streamPos: Int32);
	begin
		CurrentNotePos := CurrentNotePos + amount;
		streamPos := streamPos + amount;
		if CurrentNotePos >= CurrentNoteMax then CurrentNote := -1;
	end;

procedure AudioSimNoteToNearest(targetNotePos: Uint32; frequency: Uint32; isDrum: boolean; stream: TAudioSampleArray; var streamPos: Int32; streamLen: Int32);
	var
		i, iMax, samplePos: Uint32;
		samplesPerChange: Uint32;
	begin
		iMax := AudioSimCalcJump(targetNotePos, streamPos, streamLen); 
		if AudioSimRoundSamples or isDrum then begin
			samplesPerChange := (Uint64(AUDIO_FREQUENCY * 256) * (PIT_DIVISOR div (frequency shr 8))) div PIT_DIVISOR;
		end else begin
			samplesPerChange := Uint64(AUDIO_FREQUENCY * 65536) div frequency;
		end;
		if iMax > 0 then for i := 0 to iMax - 1 do begin
			samplePos := (CurrentNotePos + i) * 256;
			if (samplePos mod samplesPerChange) < (samplesPerChange shr 1) then
				stream[streamPos + i] := AudioSampleMin
			else
				stream[streamPos + i] := AudioSampleMax;
		end;
		AudioSimJumpBy(iMax, streamPos);
	end;

const
	BLTrigShift = 14;
	BLTrigMask = (1 shl BLTrigShift) - 1;
	BLCoeffMax = 512;
var
	BLCosTable: array[0 .. ((1 shl BLTrigShift) - 1)] of Int16;
	BLCoeffTable: array[1 .. (BLCoeffMax - 1)] of Int16;

procedure AudioSimInitBandlimit;
	var
		i: integer;
	begin
		for i := 0 to BLTrigMask do begin
			BLCosTable[i] := Trunc(Cos(2.0 * Pi * (i / (1 shl BLTrigShift))) * 16384.0);
		end;
		for i := 1 to (BLCoeffMax - 1) do begin
			BLCoeffTable[i] := Trunc(32768.0 * Sin(0.5 * i * Pi) / (i * Pi));
		end;
	end;

procedure AudioSimNoteToBandlimit(targetNotePos: Uint32; frequency: Uint32; isDrum: boolean; stream: TAudioSampleArray; var streamPos: Int32; streamLen: Int32);
	var
		i, iMax, sample: Int32;
		pos, posFixed: Uint32;
		pitTicks, freqRealFixed: Uint32;
		cosIndice: Uint64;
		coeffPos: Int32;
	begin
		iMax := AudioSimCalcJump(targetNotePos, streamPos, streamLen); 

		if AudioSimRoundSamples or isDrum then begin
			pitTicks := PIT_DIVISOR div (frequency shr 8);
			freqRealFixed := (PIT_DIVISOR shl 6) div pitTicks;
		end else begin
			freqRealFixed := frequency shr 2;
		end;
		posFixed := CurrentNotePos * 256;

		if iMax > 0 then for i := 0 to iMax - 1 do begin
			pos := freqRealFixed;
			cosIndice := (Uint64(freqRealFixed) * Uint64(posFixed)) div AUDIO_FREQUENCY;
			coeffPos := 1;

			sample := 0;
			while ((pos < (AUDIO_FREQUENCY shl (6 - 1))) and (coeffPos < BLCoeffMax)) do begin
				sample := sample + (Int64(BLCoeffTable[coeffPos]) * BLCosTable[(cosIndice * coeffPos) and BLTrigMask]);
				pos := pos + freqRealFixed;
				Inc(coeffPos);
			end;

			{ sample = 0 .. 1 in the .28 range }
			sample := ((((sample div (1 shl 13)) + (1 shl 14)) * (AudioSampleMax - AudioSampleMin)) div (1 shl 15)) + AudioSampleMin;

			if sample < AudioSampleMin then sample := AudioSampleMin
			else if sample > AudioSampleMax then sample := AudioSampleMax;
			stream[streamPos + i] := sample;

			Inc(posFixed, 256);
		end;
		AudioSimJumpBy(iMax, streamPos);
	end;

function AudioGetHighQuality: boolean;
	begin
		AudioGetHighQuality := @AudioSimNoteTo <> @AudioSimNoteToNearest;
	end;

procedure AudioSetHighQuality(value: boolean);
	begin
		if value then begin
			AudioSimNoteTo := AudioSimNoteToBandlimit;
			AudioSimRoundSamples := false;
		end else begin
			AudioSimNoteTo := AudioSimNoteToNearest;
			AudioSimRoundSamples := true;
		end;
		SoundInitFreqTable(value);
	end;

procedure AudioSimSilenceTo(targetNotePos: Uint32; stream: TAudioSampleArray; var streamPos: Int32; streamLen: Int32);
	var
		i, iMax: Uint32;
	begin
		iMax := AudioSimCalcJump(targetNotePos, streamPos, streamLen);
		if iMax > 0 then for i := 0 to iMax - 1 do
			stream[streamPos + i] := AudioSampleNone;
		AudioSimJumpBy(iMax, streamPos);
	end;

procedure AudioSimulate(stream: TAudioSampleArray; len: Int32);
	var
		i, pos: Int32;
		drum: ^TDrumData;
		drumPos: Uint32;
		posStr: string;
	begin
{$IFDEF AUD16BIT}
		len := len div 2;
{$ENDIF}
		TimerSysLockSoundBuffer;

		if (not SoundEnabled) or (not SoundIsPlaying) or (not AudioSimulationAllowed) then begin
			CurrentNote := -1;
			for i := 0 to len - 1 do
				stream[i] := AudioSampleNone;
			if AudioSimPlayerStep then begin
				AudioSimPlayerStep := false;
				Inc(AudioSimPlayerStepCounter);
				if (len >= 1) and ((AudioSimPlayerStepCounter and 4) = 0) then begin
					stream[0] := AudioSampleMin;
				end;
			end;
		end else begin
			AudioSimPlayerStep := false;
			pos := 0;
			while pos < len do begin
				if CurrentNote < 0 then begin
					if AudioSimSoundBufferPos >= Length(AudioSimSoundBuffer) then begin
						SoundIsPlaying := false;
						for i := pos to len - 1 do
							stream[i] := AudioSampleNone;
						break;
					end else begin
						{ pop note }
						CurrentNote := Uint8(AudioSimSoundBuffer[AudioSimSoundBufferPos]);
						CurrentNotePos := 0;
						Inc(AudioSimSoundBufferPos);
						CurrentNoteMax := SoundDurationMultiplier * Uint8(AudioSimSoundBuffer[AudioSimSoundBufferPos]) * SAMPLES_PER_PIT;
						Inc(AudioSimSoundBufferPos);
					end;
				end;
			
				if (CurrentNote >= 0) and (CurrentNote < 240) then begin
					{ note }
					if CurrentNotePos < SAMPLES_NOTE_DELAY then
						AudioSimSilenceTo(SAMPLES_NOTE_DELAY, stream, pos, len)
					else begin
						if SoundFreqTable[CurrentNote] >= 256 then
							AudioSimNoteTo(CurrentNoteMax, SoundFreqTable[CurrentNote], false, stream, pos, len)
						else
							AudioSimSilenceTo(CurrentNoteMax, stream, pos, len);
					end;
				end else if (CurrentNote >= 240) and (CurrentNote < 250) then begin
					{ drum }
					drum := @SoundDrumTable[CurrentNote - 240];
					drumPos := CurrentNotePos div SAMPLES_PER_DRUM;
					if drumPos < drum^.Len then
						AudioSimNoteTo((drumPos + 1) * SAMPLES_PER_DRUM, drum^.Data[drumPos + 1] shl 8, true, stream, pos, len)
					else
						AudioSimSilenceTo(CurrentNoteMax, stream, pos, len);
				end else begin
					{ silence }
					AudioSimSilenceTo(CurrentNoteMax, stream, pos, len);
				end;
			end;
		end;

		TimerSysUnlockSoundBuffer;
	end;

begin
	CurrentNote := -1;
	AudioSimulationAllowed := false;
	AudioSetVolume(48);
	AudioSimInitBandlimit;
	AudioSetHighQuality(true);
end.
