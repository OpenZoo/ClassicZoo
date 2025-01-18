{
	Copyright (c) 2021 Adrian Siekierka

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
{$F+}
unit GameConf;

interface
	uses GameVars;
	var
		ConfigFileName: TFilenameString;
		HighCompat: boolean;
		HighCompatAuto: boolean;
		CleenMode: boolean;
		CleenModeAuto: boolean;
		NeuromotorAssist: boolean;
	procedure GameConfigInit;
	function GameConfigLoad: boolean;
	function GameConfigSave: boolean;
	procedure GameAboutScreen;
	procedure GameOptionsScreen(playingGame: boolean);
{$IFNDEF FPC}
	function ConfigShowValueNone: string;
	function ConfigCustomActionNone: boolean;
	function ConfigCompatibilityGetValue: integer;
	procedure ConfigCompatibilitySetValue(value: integer);
	function ConfigCompatibilityShowValue: string;
	function ConfigEdAutoAppendGetValue: integer;
	procedure ConfigEdAutoAppendSetValue(value: integer);
	function ConfigEdAutoAppendShowValue: string;
	function ConfigEdSepStartBoardGetValue: integer;
	procedure ConfigEdSepStartBoardSetValue(value: integer);
	function ConfigEdSepStartBoardShowValue: string;
	function ConfigEdLowLevelGetValue: integer;
	procedure ConfigEdLowLevelSetValue(value: integer);
	function ConfigEdLowLevelShowValue: string;
	function ConfigEdSyntaxHighlightGetValue: integer;
	procedure ConfigEdSyntaxHighlightSetValue(value: integer);
	function ConfigEdSyntaxHighlightShowValue: string;
	function ConfigEdShowSizesGetValue: integer;
	procedure ConfigEdShowSizesSetValue(value: integer);
	function ConfigEdShowSizesShowValue: string;
	function ConfigCleenModeGetValue: integer;
	procedure ConfigCleenModeSetValue(value: integer);
	function ConfigCleenModeShowValue: string;
	function ConfigNeuromotorAssistGetValue: integer;
	procedure ConfigNeuromotorAssistSetValue(value: integer);
	function ConfigNeuromotorAssistShowValue: string;
	function ConfigVidColorGetValue: integer;
	procedure ConfigVidColorSetValue(value: integer);
	function ConfigVidColorShowValue: string;
	function ConfigInputGetValue: integer;
	procedure ConfigInputSetValue(value: integer);
	function ConfigInputShowValue: string;
	function ConfigSoundGetValue: integer;
	procedure ConfigSoundSetValue(value: integer);
	function ConfigSoundShowValue: string;
{$IFDEF PLAYSTEP}
	function ConfigPlayStepGetValue: integer;
	procedure ConfigPlayStepSetValue(value: integer);
	function ConfigPlayStepShowValue: string;
{$ENDIF}
{$ENDIF}

implementation
uses
{$IFDEF SDL2} AudioSim, {$ENDIF}
{$IFDEF UISCBACK} UiScBack, {$ENDIF}
Editor, Game, Sounds, ZVideo, ZInput, FileSys, TxtWind;

type
	TConfigCategory = (CCEngine, CCFrontend, CCEditor, CCDebugger);
	TConfigGetValueProc = function: integer;
	TConfigSetValueProc = procedure(value: integer);
	TConfigShowValueProc = function: string;
	TConfigCustomActionProc = function: boolean;
	TConfigEntry = record
		Category: TConfigCategory;
		Key: string[8];
		Name: string[25];
		GetValue: TConfigGetValueProc;
		SetValue: TConfigSetValueProc;
		ShowValue: TConfigShowValueProc;
		CustomAction: TConfigCustomActionProc;
		HideWhilePlaying: boolean;
		Changed: boolean;
	end;
	TConfigHiddenEntry = record
		Key: string[8];
		IntPointer: ^integer;
	end;
var
	ConfigEntryInputPos: integer;
	HardEscapeHack: boolean;

function ConfigShowValueNone: string;
	begin
		ConfigShowValueNone := '';
	end;

function ConfigCustomActionNone: boolean;
	begin
		ConfigCustomActionNone := false;
	end;

function ConfigShowOnOffValue(val: boolean): string;
	begin
		if val then
			ConfigShowOnOffValue := 'On'
		else
			ConfigShowOnOffValue := 'Off';
	end;

function ConfigShowYesNoValue(val: boolean): string;
	begin
		if val then
			ConfigShowYesNoValue := 'Yes'
		else
			ConfigShowYesNoValue := 'No';
	end;

{ }

function ConfigCompatibilityGetValue: integer;
	begin
		if HighCompatAuto then
			ConfigCompatibilityGetValue := 0
		else if HighCompat then
			ConfigCompatibilityGetValue := 2
		else
			ConfigCompatibilityGetValue := 1;
	end;

procedure ConfigCompatibilitySetValue(value: integer);
	begin
		if value > 2 then value := 0;
		HighCompatAuto := (value = 0);
		if not HighCompatAuto then
			HighCompat := (value = 2);
	end;

function ConfigCompatibilityShowValue: string;
	begin
		if HighCompatAuto then
			ConfigCompatibilityShowValue := 'Automatic'
		else if HighCompat then
			ConfigCompatibilityShowValue := 'Strict'
		else
			ConfigCompatibilityShowValue := 'Normal';
	end;

function ConfigEdAutoAppendGetValue: integer;
	begin
		ConfigEdAutoAppendGetValue := Byte(EditorAutoAppendPats);
	end;

procedure ConfigEdAutoAppendSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		EditorAutoAppendPats := Boolean(value);
	end;

function ConfigEdAutoAppendShowValue: string;
	begin
		ConfigEdAutoAppendShowValue := ConfigShowYesNoValue(EditorAutoAppendPats);
	end;

function ConfigEdSepStartBoardGetValue: integer;
	begin
		ConfigEdSepStartBoardGetValue := Byte(EditorSeparateStartingBoard);
	end;

procedure ConfigEdSepStartBoardSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		EditorSeparateStartingBoard := Boolean(value);
	end;

function ConfigEdSepStartBoardShowValue: string;
	begin
		ConfigEdSepStartBoardShowValue := ConfigShowYesNoValue(EditorSeparateStartingBoard);
	end;

function ConfigEdLowLevelGetValue: integer;
	begin
		ConfigEdLowLevelGetValue := Byte(EditorLowLevelEnable);
	end;

procedure ConfigEdLowLevelSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		EditorLowLevelEnable := Boolean(value);
	end;

function ConfigEdLowLevelShowValue: string;
	begin
		ConfigEdLowLevelShowValue := ConfigShowOnOffValue(EditorLowLevelEnable);
	end;

function ConfigEdSyntaxHighlightGetValue: integer;
	begin
		ConfigEdSyntaxHighlightGetValue := Byte(EditorSyntaxHighlightEnable);
	end;

procedure ConfigEdSyntaxHighlightSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		EditorSyntaxHighlightEnable := Boolean(value);
	end;

function ConfigEdSyntaxHighlightShowValue: string;
	begin
		ConfigEdSyntaxHighlightShowValue := ConfigShowOnOffValue(EditorSyntaxHighlightEnable);
	end;

function ConfigEdShowSizesGetValue: integer;
	begin
		ConfigEdShowSizesGetValue := Byte(EditorShowDataSizes);
	end;

procedure ConfigEdShowSizesSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		EditorShowDataSizes := Boolean(value);
	end;

function ConfigEdShowSizesShowValue: string;
	begin
		ConfigEdShowSizesShowValue := ConfigShowOnOffValue(EditorShowDataSizes);
	end;

function ConfigCleenModeGetValue: integer;
	begin
		if CleenModeAuto then
			ConfigCleenModeGetValue := 0
		else if CleenMode then
			ConfigCleenModeGetValue := 2
		else
			ConfigCleenModeGetValue := 1;
	end;

procedure ConfigCleenModeSetValue(value: integer);
	begin
		if value > 2 then value := 0;
		CleenModeAuto := (value = 0);
		if not CleenModeAuto then
			CleenMode := (value = 2);
	end;

function ConfigCleenModeShowValue: string;
	begin
		if CleenModeAuto then
			ConfigCleenModeShowValue := 'Automatic'
		else
			ConfigCleenModeShowValue := ConfigShowYesNoValue(CleenMode);
	end;

function ConfigNeuromotorAssistGetValue: integer;
	begin
		ConfigNeuromotorAssistGetValue := Byte(NeuromotorAssist);
	end;

procedure ConfigNeuromotorAssistSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		NeuromotorAssist := Boolean(value);
	end;

function ConfigNeuromotorAssistShowValue: string;
	begin
		ConfigNeuromotorAssistShowValue := ConfigShowYesNoValue(NeuromotorAssist);
	end;

{$IFDEF NEC98}
function ConfigVidColorGetValue: integer;
	begin
		ConfigVidColorGetValue := VideoPc98DrawingMode;
	end;

procedure ConfigVidColorSetValue(value: integer);
	begin
		if value > VideoPc98MaxDrawingMode then value := 0;
		VideoPc98DrawingMode := value;
		VideoRedraw;
	end;

function ConfigVidColorShowValue: string;
	begin
		if VideoPc98DrawingMode = 2 then
			ConfigVidColorShowValue := 'EGC (16-color)'
		else if VideoPc98DrawingMode = 1 then
			ConfigVidColorShowValue := 'GRCG (8-color)'
		else
			ConfigVidColorShowValue := 'Text';
	end;
{$ELSE}
function ConfigVidColorGetValue: integer;
	begin
		ConfigVidColorGetValue := Byte(VideoMonochrome);
	end;

procedure ConfigVidColorSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		VideoMonochrome := Boolean(value);
	end;

function ConfigVidColorShowValue: string;
	begin
		if VideoMonochrome then
			ConfigVidColorShowValue := 'Monochrome'
		else
			ConfigVidColorShowValue := 'Color';
	end;
{$ENDIF}

{$IFDEF MSDOS}
function ConfigInputGetValue: integer;
	begin
		ConfigInputGetValue := Byte(InputMode);
	end;

procedure ConfigInputSetValue(value: integer);
	begin
		if value > 2 then value := 0;
		if (value = 1) and (not InputJoystickPresent) then value := 2;
		{ TODO: HACK - VideoForceSafe disables WriteLn due to DOS/V,
		  and so the calibrator won't work }
		if (value = 1) and (VideoForceSafe) then value := 2;
		if (value = 2) and (not InputMousePresent) then value := 0;
		InputMode := TInputMode(value);
	end;

function ConfigInputShowValue: string;
	begin
		if InputMode = IMMouse then
			ConfigInputShowValue := 'Mouse'
{$IFNDEF NEC98}
		else if InputMode = IMJoystick then
			ConfigInputShowValue := 'Joystick'
{$ENDIF}
		else
			ConfigInputShowValue := 'Keyboard';
	end;

function ConfigSoundGetValue: integer;
	begin
		ConfigSoundGetValue := Byte(SoundEnabled);
	end;

procedure ConfigSoundSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		SoundEnabled := Boolean(value);
	end;

function ConfigSoundShowValue: string;
	begin
		ConfigSoundShowValue := ConfigShowOnOffValue(SoundEnabled);
	end;

function ConfigVideoBlinkGetValue: integer;
	begin
		ConfigVideoBlinkGetValue := Byte(VideoBlink);
	end;

procedure ConfigVideoBlinkSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		VideoSetBlink(Boolean(value));
	end;

function ConfigVideoBlinkShowValue: string;
	begin
		if VideoBlink then
{$IFDEF DSX86}
			ConfigVideoBlinkShowValue := 'Disabled (Low Colors)'
{$ELSE}
			ConfigVideoBlinkShowValue := 'Enabled'
{$ENDIF}
		else
{$IFDEF NEC98}
			ConfigVideoBlinkShowValue := 'Disabled';
{$ELSE}
			ConfigVideoBlinkShowValue := 'Disabled (High Colors)';
{$ENDIF}
	end;
{$ENDIF}

{$IFDEF PLAYSTEP}
function ConfigPlayStepGetValue: integer;
	begin
		ConfigPlayStepGetValue := Byte(PlayerStepEnabled);
	end;

procedure ConfigPlayStepSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		PlayerStepEnabled := Boolean(value);
	end;

function ConfigPlayStepShowValue: string;
	begin
		ConfigPlayStepShowValue := ConfigShowOnOffValue(PlayerStepEnabled);
	end;
{$ENDIF}

{$IFDEF FASTVID}
function ConfigTransitionBlocksPerFrameGetValue: integer;
	begin
		ConfigTransitionBlocksPerFrameGetValue := TransitionBlocksPerFrame;
	end;

procedure ConfigTransitionBlocksPerFrameSetValue(value: integer);
	begin
		if (value < 1) or (value >= (BOARD_WIDTH * BOARD_HEIGHT)) then value := 32767;
		TransitionBlocksPerFrame := value;
	end;

function ConfigTransitionBlocksPerFrameShowValue: string;
	begin
		if TransitionBlocksPerFrame >= (BOARD_WIDTH * BOARD_HEIGHT) then
			ConfigTransitionBlocksPerFrameShowValue := 'Instant'
		else if TransitionBlocksPerFrame >= ((BOARD_WIDTH * BOARD_HEIGHT) div 10) then
			ConfigTransitionBlocksPerFrameShowValue := 'Fast'
		else if TransitionBlocksPerFrame >= ((BOARD_WIDTH * BOARD_HEIGHT) div 30) then
			ConfigTransitionBlocksPerFrameShowValue := 'Medium'
		else
			ConfigTransitionBlocksPerFrameShowValue := 'Slow';
	end;

function ConfigTransitionBlocksPerFrameCustomAction: boolean;
	begin
		{ Instant -> Fast -> Medium -> Slow }
		if TransitionBlocksPerFrame >= (BOARD_WIDTH * BOARD_HEIGHT) then
			TransitionBlocksPerFrame := ((BOARD_WIDTH * BOARD_HEIGHT) div 10)
		else if TransitionBlocksPerFrame >= ((BOARD_WIDTH * BOARD_HEIGHT) div 10) then
			TransitionBlocksPerFrame := ((BOARD_WIDTH * BOARD_HEIGHT) div 30)
		else if TransitionBlocksPerFrame >= ((BOARD_WIDTH * BOARD_HEIGHT) div 30) then
			TransitionBlocksPerFrame := ((BOARD_WIDTH * BOARD_HEIGHT) div 90)
		else
			TransitionBlocksPerFrame := ((BOARD_WIDTH * BOARD_HEIGHT));
		ConfigTransitionBlocksPerFrameCustomAction := true;
	end;

function ConfigTransitionTextWindowDelayGetValue: integer;
	begin
		ConfigTransitionTextWindowDelayGetValue := TransitionTextWindowDelay;
	end;

procedure ConfigTransitionTextWindowDelaySetValue(value: integer);
	begin
		TransitionTextWindowDelay := value;
	end;

function ConfigTransitionTextWindowDelayShowValue: string;
	begin
		if TransitionTextWindowDelay >= 25 then
			ConfigTransitionTextWindowDelayShowValue := 'Classic'
		else if TransitionTextWindowDelay >= 12 then
			ConfigTransitionTextWindowDelayShowValue := 'Faster'
		else
			ConfigTransitionTextWindowDelayShowValue := 'Instant';
	end;

function ConfigTransitionTextWindowDelayCustomAction: boolean;
	begin
		{ Classic -> Faster -> Instant }
		if TransitionTextWindowDelay >= 25 then
			TransitionTextWindowDelay := 12
		else if TransitionTextWindowDelay >= 12 then
			TransitionTextWindowDelay := 0
		else
			TransitionTextWindowDelay := 25;
		ConfigTransitionTextWindowDelayCustomAction := true;
	end;
{$ENDIF}

{$IFDEF UISCBACK}
function ConfigScrollbackSizeGetValue: integer;
	begin
		ConfigScrollbackSizeGetValue := ScrollbackSize;
	end;

procedure ConfigScrollbackSizeSetValue(value: integer);
	begin
		ScrollbackClear(value);
	end;

function ConfigScrollbackSizeShowValue: string;
	begin
		ConfigScrollbackSizeShowValue := ConfigShowOnOffValue(ScrollbackSize > 0);
	end;

function ConfigScrollbackSizeCustomAction: boolean;
	begin
		if ScrollbackSize = 0 then
			ScrollbackClear(SCROLLBACK_MAX_SIZE)
		else
			ScrollbackClear(0);
		ConfigScrollbackSizeCustomAction := true;
	end;
{$ENDIF}

{$IFDEF DEBUGWND}
function ConfigDebugShowValue: string;
	begin
		ConfigDebugShowValue := ConfigShowOnOffValue(DebugEnabled);
	end;

function ConfigDebugCustomAction: boolean;
	begin
		if DebugEnabled then begin
			DebugEnabled := false;
			DebugCompatEnabled := false;
			DebugUndefEnabled := false;
		end else DebugEnabled := true;
		ConfigDebugCustomAction := true;
	end;

function ConfigDCompatShowValue: string;
	begin
		ConfigDCompatShowValue := ConfigShowOnOffValue(DebugCompatEnabled);
	end;

function ConfigDCompatCustomAction: boolean;
	begin
		if DebugEnabled then begin
			DebugCompatEnabled := not DebugCompatEnabled;
		end else DebugCompatEnabled := true;
		ConfigDCompatCustomAction := true;
	end;

function ConfigDUndefShowValue: string;
	begin
		ConfigDUndefShowValue := ConfigShowOnOffValue(DebugUndefEnabled);
	end;

function ConfigDUndefCustomAction: boolean;
	begin
		if DebugEnabled then begin
			DebugUndefEnabled := not DebugUndefEnabled;
		end else DebugUndefEnabled := true;
		ConfigDUndefCustomAction := true;
	end;
{$ENDIF}

{$IFDEF SDL2}
function ConfigVideoBlinkGetValue: integer;
	begin
		ConfigVideoBlinkGetValue := Byte(Ord(VideoGetBlinkMode));
	end;

procedure ConfigVideoBlinkSetValue(value: integer);
	begin
		if value > Ord(High(TVideoBlinkMode)) then value := 0;
		VideoSetSDLBlinkMode(TVideoBlinkMode(value));
	end;

function ConfigVideoBlinkCustomAction: boolean;
	begin
		case VideoGetBlinkMode of
		BlinkModeOn: VideoSetSDLBlinkMode(BlinkModeHigh);
		BlinkModeHigh: VideoSetSDLBlinkMode(BlinkModeOff);
		BlinkModeOff: VideoSetSDLBlinkMode(BlinkModeOn);
		end;
		ConfigVideoBlinkCustomAction := true;
	end;

function ConfigVideoBlinkShowValue: string;
	begin
		case VideoGetBlinkMode of
			BlinkModeOff: ConfigVideoBlinkShowValue := 'Disabled';
			BlinkModeOn: ConfigVideoBlinkShowValue := 'Enabled';
			BlinkModeHigh: ConfigVideoBlinkShowValue := 'Disabled (High Colors)';
		end;
	end;

function ConfigVideoScalingGetValue: integer;
	begin
		ConfigVideoScalingGetValue := Byte(Ord(VideoGetSDLScalingMode));
	end;

procedure ConfigVideoScalingSetValue(value: integer);
	begin
		if value > Ord(High(TSDLScalingMode)) then value := 0;
		VideoSetSDLScalingMode(TSDLScalingMode(value));
	end;

function ConfigVideoScalingShowValue: string;
	begin
		case VideoGetSDLScalingMode of
			SMNone: ConfigVideoScalingShowValue := '1:1';
			SM2x: ConfigVideoScalingShowValue := '2:1';
			SM3x: ConfigVideoScalingShowValue := '3:1';
			SMInteger: ConfigVideoScalingShowValue := 'Integer';
			SMOrigAspect: ConfigVideoScalingShowValue := 'Keep Aspect';
			SM43Aspect: ConfigVideoScalingShowValue := '4:3 Aspect';
			SMIgnoreAspect: ConfigVideoScalingShowValue := 'Ignore';
		end;
	end;

function ConfigHQSoundGetValue: integer;
	begin
		ConfigHQSoundGetValue := Byte(AudioGetHighQuality);
	end;

procedure ConfigHQSoundSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		AudioSetHighQuality(Boolean(value));
	end;

function ConfigHQSoundShowValue: string;
	begin
		ConfigHQSoundShowValue := ConfigShowOnOffValue(AudioGetHighQuality);
	end;

function ConfigFullscreenGetValue: integer;
	begin
		ConfigFullscreenGetValue := Byte(VideoGetSDLWindowed);
	end;

procedure ConfigFullscreenSetValue(value: integer);
	begin
		if value > 1 then value := 0;
		VideoSetSDLWindowed(Boolean(value));
	end;

function ConfigFullscreenShowValue: string;
	begin
		if VideoGetSDLWindowed then
			ConfigFullscreenShowValue := 'Windowed'
		else
			ConfigFullscreenShowValue := 'Fullscreen';
	end;

function ConfigCharsetShowValue: string;
	begin
		if VideoIsCharsetCustom then
			ConfigCharsetShowValue := 'Custom'
		else
			ConfigCharsetShowValue := 'Default';
	end;

function ConfigCharsetCustomAction: boolean;
	begin
		VideoLoadCharsetDialog;
		ConfigCharsetCustomAction := true;
	end;

function ConfigPaletteShowValue: string;
	begin
		if VideoIsPaletteCustom then
			ConfigPaletteShowValue := 'Custom'
		else
			ConfigPaletteShowValue := 'Default';
	end;

function ConfigPaletteCustomAction: boolean;
	begin
		VideoLoadPaletteDialog;
		ConfigPaletteCustomAction := true;
	end;

const
	SoundVolumeTable: array[0 .. 10] of byte =
		(0, 4, 8, 13, 18, 24, 31, 38, 46, 54, 64);

function ConfigSoundVolumeGetValue: integer;
	begin
		ConfigSoundVolumeGetValue := AudioGetVolume;
	end;

procedure ConfigSoundVolumeSetValue(value: integer);
	begin
		if value > 64 then value := 0;
		AudioSetVolume(value);
	end;

function ConfigSoundVolumeShowValue: string;
	var
		i: integer;
		s: string[10];
	begin
		for i := 10 downto 0 do begin
			if AudioGetVolume >= SoundVolumeTable[i] then
				break;
		end;

		if AudioGetVolume > 0 then begin
			Str(i, s);
			ConfigSoundVolumeShowValue := s + '0%'
		end else begin
			ConfigSoundVolumeShowValue := 'Off';
		end;
	end;

function ConfigSoundVolumeCustomAction: boolean;
	var
		i: integer;
	begin
		ConfigSoundVolumeCustomAction := true;
		if AudioGetVolume >= 64 then begin
			AudioSetVolume(0);
		end else begin
			for i := 9 downto 0 do begin
				if AudioGetVolume >= SoundVolumeTable[i] then begin
					AudioSetVolume(SoundVolumeTable[i + 1]);
					exit;
				end;
			end;
		end;
	end;

function ConfigInputShowValue: string;
	var
		s: string;
	begin
		s := InputGetControllerName;
		if Length(s) > 32 then
			s := Copy(s, 1, 29) + '...';
		ConfigInputShowValue := s;
	end;

function ConfigInputCustomAction: boolean;
	begin
		InputSwitchToNextController;
		ConfigInputCustomAction := true;
	end;
{$ENDIF}

const
	ConfigEntryCount = 9
	{$IFDEF MSDOS} + 3 {$ENDIF}
	{$IFDEF PLAYSTEP} + 1 {$ENDIF}
	{$IFDEF FASTVID} + 2 {$ENDIF}
	{$IFDEF DEBUGWND} + 3 {$ENDIF}
	{$IFDEF UISCBACK} + 1 {$ENDIF}
	{$IFDEF SDL2} + 7 {$IFNDEF WINDOWS} + 1 {$ENDIF} {$ENDIF}
	;
	ConfigHiddenEntryCount = 0
{$IFDEF MSDOS}
{$IFNDEF NEC98}
	+ 6
{$ENDIF}
{$ENDIF}
	;
var
	ConfigEntries: array[1 .. ConfigEntryCount] of TConfigEntry;
	ConfigHiddenEntries: array[1 .. ConfigHiddenEntryCount + 1] of TConfigHiddenEntry;

procedure GameConfigInit;
	var
		i: integer;
	begin
		for i := 1 to ConfigEntryCount do
			with ConfigEntries[i] do begin
				Key := '';
				Name := '';
				HideWhilePlaying := false;
{$IFDEF FPC}
				GetValue := nil;
				SetValue := nil;
{$ENDIF}
				ShowValue := ConfigShowValueNone;
				CustomAction := ConfigCustomActionNone;
			end;

		i := 1;

		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'ECompat';
			Name := 'Compatibility';
			GetValue := ConfigCompatibilityGetValue;
			SetValue := ConfigCompatibilitySetValue;
			ShowValue := ConfigCompatibilityShowValue;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEditor;
			Key := 'EdApPats';
{$IFDEF EDITOR}
			Name := 'Auto-Append';
{$ENDIF}
			GetValue := ConfigEdAutoAppendGetValue;
			SetValue := ConfigEdAutoAppendSetValue;
{$IFDEF EDITOR}
			ShowValue := ConfigEdAutoAppendShowValue;
{$ENDIF}
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEditor;
			Key := 'EdSepStB';
{$IFDEF EDITOR}
			Name := 'Separate start board';
{$ENDIF}
			GetValue := ConfigEdSepStartBoardGetValue;
			SetValue := ConfigEdSepStartBoardSetValue;
{$IFDEF EDITOR}
			ShowValue := ConfigEdSepStartBoardShowValue;
{$ENDIF}
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEditor;
			Key := 'EdLowLvl';
{$IFDEF EDITOR}
			Name := 'Show internal data';
{$ENDIF}
			GetValue := ConfigEdLowLevelGetValue;
			SetValue := ConfigEdLowLevelSetValue;
{$IFDEF EDITOR}
			ShowValue := ConfigEdLowLevelShowValue;
{$ENDIF}
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEditor;
			Key := 'EdSyntHl';
{$IFDEF EDITOR}
			Name := 'Syntax highlighting';
{$ENDIF}
			GetValue := ConfigEdSyntaxHighlightGetValue;
			SetValue := ConfigEdSyntaxHighlightSetValue;
{$IFDEF EDITOR}
			ShowValue := ConfigEdSyntaxHighlightShowValue;
{$ENDIF}
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEditor;
			Key := 'EdShSize';
{$IFDEF EDITOR}
			Name := 'Show data sizes';
{$ENDIF}
			GetValue := ConfigEdShowSizesGetValue;
			SetValue := ConfigEdShowSizesSetValue;
{$IFDEF EDITOR}
			ShowValue := ConfigEdShowSizesShowValue;
{$ENDIF}
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'ACleenM';
			Name := 'Reduced messages';
			GetValue := ConfigCleenModeGetValue;
			SetValue := ConfigCleenModeSetValue;
			ShowValue := ConfigCleenModeShowValue;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'ANeuroO';
			Name := 'Neuromotor assist';
			GetValue := ConfigNeuromotorAssistGetValue;
			SetValue := ConfigNeuromotorAssistSetValue;
			ShowValue := ConfigNeuromotorAssistShowValue;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCFrontend;
{$IFDEF NEC98}
			Key := 'FVidRend';
{$ELSE}
			Key := 'FVidMono';
{$ENDIF}
			Name := 'Video';
			GetValue := ConfigVidColorGetValue;
			SetValue := ConfigVidColorSetValue;
			ShowValue := ConfigVidColorShowValue;
		end;
		Inc(i);
{$IFDEF UISCBACK}
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'AMsgScB';
			Name := 'Message scrollback';
			GetValue := ConfigScrollbackSizeGetValue;
			SetValue := ConfigScrollbackSizeSetValue;
			ShowValue := ConfigScrollbackSizeShowValue;
			CustomAction := ConfigScrollbackSizeCustomAction;
		end;
		Inc(i);
{$ENDIF}
{$IFDEF MSDOS}
		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FSoundOn';
			Name := 'Sound';
			GetValue := ConfigSoundGetValue;
			SetValue := ConfigSoundSetValue;
			ShowValue := ConfigSoundShowValue;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FInpMode';
			Name := 'Input';
			GetValue := ConfigInputGetValue;
			SetValue := ConfigInputSetValue;
			ShowValue := ConfigInputShowValue;
		end;
		ConfigEntryInputPos := i;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FVidBlnk';
			Name := 'Blinking';
			GetValue := ConfigVideoBlinkGetValue;
			SetValue := ConfigVideoBlinkSetValue;
			ShowValue := ConfigVideoBlinkShowValue;
		end;
		Inc(i);
{$ENDIF}
{$IFDEF PLAYSTEP}
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'EPlrStep';
			Name := 'Player steps';
			GetValue := ConfigPlayStepGetValue;
			SetValue := ConfigPlayStepSetValue;
			ShowValue := ConfigPlayStepShowValue;
		end;
		Inc(i);
{$ENDIF}
{$IFDEF FASTVID}
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'ETrBlkFr';
			Name := 'Board transition speed';
			GetValue := ConfigTransitionBlocksPerFrameGetValue;
			SetValue := ConfigTransitionBlocksPerFrameSetValue;
			ShowValue := ConfigTransitionBlocksPerFrameShowValue;
			CustomAction := ConfigTransitionBlocksPerFrameCustomAction;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCEngine;
			Key := 'ETrTxtWd';
			Name := 'Text window draw speed';
			GetValue := ConfigTransitionTextWindowDelayGetValue;
			SetValue := ConfigTransitionTextWindowDelaySetValue;
			ShowValue := ConfigTransitionTextWindowDelayShowValue;
			CustomAction := ConfigTransitionTextWindowDelayCustomAction;
		end;
		Inc(i);
{$ENDIF}
{$IFDEF DEBUGWND}
		with ConfigEntries[i] do begin
			Category := CCDebugger;
			Name := 'Enable';
			ShowValue := ConfigDebugShowValue;
			CustomAction := ConfigDebugCustomAction;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCDebugger;
{$IFDEF E_SUPERZ}
			Name := 'SZZT 2.0 compat checks';
{$ELSE}
			Name := 'ZZT 3.2 compat checks';
{$ENDIF}
			ShowValue := ConfigDCompatShowValue;
			CustomAction := ConfigDCompatCustomAction;
		end;
		Inc(i);
		with ConfigEntries[i] do begin
			Category := CCDebugger;
			Name := 'Undefined behavior checks';
			ShowValue := ConfigDUndefShowValue;
			CustomAction := ConfigDUndefCustomAction;
		end;
		Inc(i);
{$ENDIF}
{$IFDEF SDL2}
{$IFNDEF WINDOWS}
		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FVidWin';
			Name := 'Display mode';
			GetValue := ConfigFullscreenGetValue;
			SetValue := ConfigFullscreenSetValue;
			ShowValue := ConfigFullscreenShowValue;
		end;
		Inc(i);
{$ENDIF}

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FVidScal';
			Name := 'Display scaling';
			GetValue := ConfigVideoScalingGetValue;
			SetValue := ConfigVideoScalingSetValue;
			ShowValue := ConfigVideoScalingShowValue;
		end;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FInpMode';
			Name := 'Input';
			ShowValue := ConfigInputShowValue;
			CustomAction := ConfigInputCustomAction;
		end;
		ConfigEntryInputPos := i;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FSndVol';
			Name := 'Volume';
			GetValue := ConfigSoundVolumeGetValue;
			SetValue := ConfigSoundVolumeSetValue;
			ShowValue := ConfigSoundVolumeShowValue;
			CustomAction := ConfigSoundVolumeCustomAction;
		end;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FSndHQ';
			Name := 'HQ Sound';
			GetValue := ConfigHQSoundGetValue;
			SetValue := ConfigHQSoundSetValue;
			ShowValue := ConfigHQSoundShowValue;
		end;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Name := 'Charset';
			ShowValue := ConfigCharsetShowValue;
			CustomAction := ConfigCharsetCustomAction;
		end;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Name := 'Palette';
			ShowValue := ConfigPaletteShowValue;
			CustomAction := ConfigPaletteCustomAction;
		end;
		Inc(i);

		with ConfigEntries[i] do begin
			Category := CCFrontend;
			Key := 'FVidBlnk';
			Name := 'Blinking';
			GetValue := ConfigVideoBlinkGetValue;
			SetValue := ConfigVideoBlinkSetValue;
			ShowValue := ConfigVideoBlinkShowValue;
			CustomAction := ConfigVideoBlinkCustomAction;
		end;
		Inc(i);
{$ENDIF}

		i := 1;
{$IFDEF MSDOS}
{$IFNDEF NEC98}
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyXMin';
			IntPointer := @JoystickXMin;
		end;
		Inc(i);
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyXCtr';
			IntPointer := @JoystickXCenter;
		end;
		Inc(i);
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyXMax';
			IntPointer := @JoystickXMax;
		end;
		Inc(i);
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyYMin';
			IntPointer := @JoystickYMin;
		end;
		Inc(i);
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyYCtr';
			IntPointer := @JoystickYCenter;
		end;
		Inc(i);
		with ConfigHiddenEntries[i] do begin
			Key := 'FJoyYMax';
			IntPointer := @JoystickYMax;
		end;
		Inc(i);
{$ENDIF}
{$ENDIF}
	end;

function GameConfigLoad: boolean;
	var
		f: text;
		i, v, code: integer;
		s: string[128];
		k: string[12];
		foundTag: boolean;
	begin
		foundTag := false;
		AssignFSysText(f, ConfigFileName);
		Reset(f);
		while (IOResult = 0) and (not Eof(f)) do begin
			ReadLn(f, s);
			if (Length(s) > 0) and (s[1] = '[') then begin
				foundTag := true;
			end else if (Length(s) > 0) and (s[1] <> ';') then begin
				v := Pos('=', s);
				if v <= 12 then begin
					k := Copy(s, 1, v - 1);
					s := Copy(s, v + 1, Length(s) - v);
					if Length(s) > 0 then begin
						if k = 'Start' then begin
							StartupWorldFileName := s;
{$IFDEF SDL2}
						end else if k = 'FInputID' then begin
							InputSetControllerID(s);
{$ENDIF}
						end else begin
							Val(s, v, code);
							for i := 1 to ConfigEntryCount do with ConfigEntries[i] do begin
								{$IFDEF FPC} if @SetValue = nil then continue; {$ENDIF}
								{$IFNDEF FPC} if Length(Key) > 0 then {$ENDIF}
								if k = Key then
									SetValue(v);
							end;
							for i := 1 to ConfigHiddenEntryCount do with ConfigHiddenEntries[i] do begin
								if k = Key then
								IntPointer^ := v;
							end;
						end;
					end;
				end;
			end;
		end;
		Close(f);
		GameConfigLoad := foundTag;
	end;

function GameConfigSave: boolean;
	var
		f: text;
		i, v: integer;
		s: string[20];
	begin
		GameConfigSave := false;
		AssignFSysText(f, ConfigFileName);
		Rewrite(f);
		WriteLn(f, '; Generated by %NAME% %VERSION%');
		WriteLn(f, '[Config]');
		if StartupWorldFilename <> '' then begin
			WriteLn(f, 'Start=' + StartupWorldFilename);
		end;
{$IFDEF SDL2}
		WriteLn(f, 'Input=' + InputGetControllerID);
{$ENDIF} 
		for i := 1 to ConfigEntryCount do with ConfigEntries[i] do begin
			{$IFNDEF FPC} if Length(Key) > 0 then begin {$ENDIF}
			{$IFDEF FPC} if @GetValue = nil then continue; {$ENDIF}
			v := GetValue;
			Str(v, s);
			WriteLn(f, Key + '=' + s);
			{$IFNDEF FPC} end; {$ENDIF}
		end;
		for i := 1 to ConfigHiddenEntryCount do with ConfigHiddenEntries[i] do begin
			v := IntPointer^;
			Str(v, s);
			WriteLn(f, Key + '=' + s);
		end;
		Close(f);
		if IOResult = 0 then GameConfigSave := true;
	end;

procedure GameAboutScreen;
	begin
		TextWindowDisplayFile('ABOUT.HLP', 'About %NAME%...');
	end;

procedure GameOptionsScreen(playingGame: boolean);
	var
		state: TTextWindowState;
		i: integer;
		numStr: TString50;
		actionMap: array[1 .. (ConfigEntryCount + 6)] of byte;
		exitRequested: boolean;
	procedure AppendCategory(subCategory: TConfigCategory);
		var
			k: integer;
		begin
			for k := 1 to ConfigEntryCount do with ConfigEntries[k] do begin
				if (Category = subCategory) and ((not playingGame) or (not HideWhilePlaying)) then begin
					Inc(state.LineCount);
					actionMap[state.LineCount] := k;
					New(state.Lines[state.LineCount]);
					state.Lines[state.LineCount]^ := '!;' + Name + ': ' + ShowValue;
				end;
			end;
			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := '';
		end;
	begin
		state.Title := 'Options...';
		TextWindowDrawOpen(state);
		exitRequested := false;
		HardEscapeHack := false;
		state.LinePos := 1;

		for i := 1 to ConfigEntryCount do ConfigEntries[i].Changed := false;

		repeat
			for i := 1 to (ConfigEntryCount + 6) do actionMap[i] := 0;
			state.Selectable := true;

			state.LineCount := 1;
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := 'Engine';
			AppendCategory(CCEngine);

			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := 'Frontend';
			AppendCategory(CCFrontend);

{$IFDEF EDITOR}
			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := 'Editor';
			AppendCategory(CCEditor);
{$ENDIF}
{$IFDEF DEBUGWND}
			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := 'Debug mode';
			AppendCategory(CCDebugger);
{$ENDIF}

			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := '!;Help';
			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := '!;About %NAME%...';
			Inc(state.LineCount);
			New(state.Lines[state.LineCount]);
			state.Lines[state.LineCount]^ := '!;Exit';

			TextWindowSelect(state, TWS_HYPERLINK_AS_SELECT);
			if (InputKeyPressed = KEY_ENTER) and (state.LinePos <> state.LineCount) then begin
				if state.LinePos = (state.LineCount - 1) then begin
					GameAboutScreen;
				end else if state.LinePos = (state.LineCount - 2) then begin
					TextWindowDisplayFile('OPTIONS.HLP', 'Help');
				end else if actionMap[state.LinePos] <> 0 then begin
					with ConfigEntries[actionMap[state.LinePos]] do begin
						if not CustomAction then
							SetValue(GetValue + 1);
						Changed := true;
{$IFDEF MSDOS}
{$IFNDEF NEC98}
						if Key = 'FVidMono' then begin
							i := VideoCurrentMode;
							VideoUninstall;
							if VideoInstall(i, nil,
								VIDEO_CHARSET_UNCHANGED, 1) then begin end;
							HardEscapeHack := true;
						end;
{$ENDIF}
{$ENDIF}
					end;
				end;
				if HardEscapeHack then begin
					exitRequested := true;
				end;
			end else begin
				exitRequested := true;
				TextWindowDrawClose(state);
			end;

			TextWindowFreeEdit(state);
		until exitRequested;

{$IFDEF MSDOS}
{$IFNDEF NEC98}
		if ConfigEntries[ConfigEntryInputPos].Changed then begin begin
			if InputMode = IMJoystick then
				i := VideoCurrentMode;
				VideoUninstall;
				if not InputCalibrateJoystick then
					InputMode := IMKeyboard;
				if VideoInstall(i, nil,
					VIDEO_CHARSET_UNCHANGED, 1) then begin end;
			end;
		end;
{$ENDIF}
{$ENDIF}

		if not GameConfigSave then begin
			{ TODO: Warn user. }
		end;
	end;

end.
