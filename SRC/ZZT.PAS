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
{$IFNDEF FPC}
{$IFDEF E_SUPERZ}
{$M 28672,65536,655360}
{$ELSE}
{$IFDEF NEC98}
{$M 28672,65536,655360}
{$ELSE}
{$M 24576,65536,655360}
{$ENDIF}
{$ENDIF}
{$ENDIF}
program ZZT;
uses 
{$IFDEF NEC98}
Pc98,
{$ELSE}
{$IFDEF MSDOS}
Crt,
{$ENDIF}
{$ENDIF}
{$IFDEF SDL2}
SysUtils, FileSel,
{$ENDIF}
{$IFDEF UNIX}
cwstring,
{$ENDIF}
Dos, ExtMem, FileSys, ZVideo, Keys, Sounds, TimerSys, ZInput, ZDemo, TxtWind,
GameConf, GameVars, Elements, Editor, Oop, Game;

{$IFDEF SDL2}
function FileNameFromProgramName(const ext: string; checkExists: boolean): string;
	var
		s: string;
	begin
		if (Length(ParamStr(0)) <= 0) or (not FileExists(ParamStr(0))) then begin
			s := FExpand('%ENGINE%' + ext);
		end else begin
			s := FExpand(ChangeFileExt(ExtractFileName(ParamStr(0)), ext));
			if checkExists and not FileExists(s) then s := FExpand('%ENGINE%' + ext);
		end;
		FileNameFromProgramName := s;
	end;
{$ENDIF}

procedure ParseArguments;
	var
		i: integer;
		pArg: string;
		enableEms: boolean;
		enableXms: boolean;
	begin
{$IFNDEF NOEXTMEM}
		enableEms := true;
		enableXms := true;
{$ENDIF}

		for i := 1 to ParamCount do begin
			pArg := ParamStr(i);
			if pArg[1] = '/' then begin
				pArg := UpCaseString(pArg);
{$IFDEF SDL2}
				if pArg = '/SOFTWARE' then
					VideoForceSoftware := true;
{$ENDIF}
{$IFDEF MSDOS}
{$IFNDEF NEC98}
				if pArg[2] = 'V' then
					VideoSafetyLevel := Ord(pArg[3]) - 48;
{$IFDEF E_SUPERZ}
				if pArg = '/NOFONT' then
					UseCustomFont := false;
{$ENDIF}
{$ENDIF}
{$ENDIF}
{$IFNDEF NOEXTMEM}
				if pArg = '/NOEMS' then
					enableEms := false
				else if pArg = '/NOXMS' then
					enableXms := false;
{$ENDIF}
			end else begin
				StartupWorldFileName := pArg;
				if (Length(StartupWorldFileName) > 4) and (StartupWorldFileName[Length(StartupWorldFileName) - 3] = '.') then begin
					StartupWorldFileName := Copy(StartupWorldFileName, 1, Length(StartupWorldFileName) - 4);
				end;
			end;
		end;

		ExtMemInstall(enableEms, enableXms);
	end;

begin
	Randomize;
	TimerSysInstall;

	StartupWorldFileName := '';
{$IFDEF SDL2}
	ResourceDataFileName := FileNameFromProgramName('.DAT', true);
	ConfigFileName := FileNameFromProgramName('.INI', false);
{$ELSE}
{$IFNDEF NODIRS}
	ResourceDataFileName := FExpand('%ENGINE%.DAT');
	ConfigFileName := FExpand('%ENGINE%.INI');
{$ELSE}
	ResourceDataFileName := '%ENGINE%.DAT';
	ConfigFileName := '%ENGINE%.INI';
{$ENDIF}
{$ENDIF}
	DemoEngineName := '%NAME% %VERSION%';
	GameTitleExitRequested := false;
	IoTmpBufSize := IO_BUFFER_DEFAULT_SIZE;

	EditorEnabled := true;
	InputInitDevices;

{$IFDEF PLAYSTEP}
	PlayerStepEnabled := false;
{$ENDIF}
{$IFDEF FASTVID}
	TransitionBlocksPerFrame := 32767;
	TransitionTextWindowDelay := {$IFDEF HASAMIGA} 0 {$ELSE} 25 {$ENDIF};
{$ENDIF}
	TickSpeed := 4;
	DebugEnabled := false;
	HighCompat := false;
	HighCompatAuto := true;
	CleenMode := false;
	CleenModeAuto := true;
	NeuromotorAssist := false;
{$IFDEF EXTCHEAT}
	CheatNoClip := false;
	CheatFreeze := false;
{$ENDIF}
{$IFDEF DEBUGWND}
	DebugCompatEnabled := false;
	DebugUndefEnabled := false;
{$ENDIF}

	GameConfigInit;
	if not GameConfigLoad then begin
		if not GameConfigSave then begin end;
		JustStarted := true;
	end else begin
		JustStarted := false;
	end;
{$IFDEF E_SUPERZ}
	UseCustomFont := true;
{$ENDIF}
	ParseArguments;

{$IFDEF E_ZZT}
	if VideoInstall(VIDEO_MODE_80X25, nil, 0, 1) then begin end;
{$ENDIF}
{$IFDEF E_SUPERZ}
	if GameVideoInstall(VIDEO_MODE_80X25, VIEW_TITLE) then begin end;
{$ENDIF}

	if not GameTitleExitRequested then begin
		TextWindowInit(5, 3, 50, 18);
		GetMem(IoTmpBuf, IoTmpBufSize);

{$IFDEF SDL2}
		{ SDL2 - Fixes initial window size }
		InputUpdate;
{$ENDIF}
		SavedGameFileName := 'SAVED';
		SavedBoardFileName := 'TEMP';
		ResetCachedLinePos;
		WorldCreate;

		GameTitleLoop;

		FreeMem(IoTmpBuf, IoTmpBufSize);
		ExtMemUninstall;
	end;

	if not GameConfigSave then begin end;

	SoundClearQueue;

	VideoUninstall;
	SoundUninstall;
end.
