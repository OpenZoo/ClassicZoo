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

unit ZInput;

interface
	const
		KEY_BACKSPACE = #8;
		KEY_TAB = #9;
		KEY_ENTER = #13;
		KEY_ESCAPE = #27;
		KEY_F1 = #187;
		KEY_F2 = #188;
		KEY_F3 = #189;
		KEY_F4 = #190;
		KEY_F5 = #191;
		KEY_F6 = #192;
		KEY_F7 = #193;
		KEY_F8 = #194;
		KEY_F9 = #195;
		KEY_F10 = #196;
		KEY_UP = #200;
		KEY_PAGE_UP = #201;
		KEY_LEFT = #203;
		KEY_RIGHT = #205;
		KEY_DOWN = #208;
		KEY_PAGE_DOWN = #209;
		KEY_INSERT = #210;
		KEY_DELETE = #211;
		KEY_HOME = #199;
		KEY_END = #207;
		{ Maximum emulated scancode: 128 + 83 = 211 }
		KEY_CTRL_C = #212;
		KEY_CTRL_O = #213;
		KEY_CTRL_S = #214;
		KEY_CTRL_T = #215;
		KEY_CTRL_V = #216;
		KEY_CTRL_X = #217;
		KEY_CTRL_Y = #218;
		KEY_ALT_P = #219;
{$IFDEF WIDECHAR}
		KEY_WIDESTRING = #220;
{$ENDIF}
	var
		InputDeltaX, InputDeltaY: integer;
		InputShiftPressed: boolean;
		InputShiftAccepted: boolean;
		InputJoystickEnabled: boolean;
		InputMouseEnabled: boolean;
		InputKeyPressed: char;
{$IFDEF WIDECHAR}
		InputKeyPressedWide: string[4];
{$ENDIF}
		InputMouseX, InputMouseY: integer;
		InputMouseActivationX, InputMouseActivationY: integer;
		InputMouseButtonX, InputMouseButtonY: integer;
		InputJoystickMoved: boolean;
		InputLastDeltaX, InputLastDeltaY: integer;
		InputKeyBuffering: boolean;
	procedure InputUpdate;
	procedure InputInitDevices;
	procedure InputReadWaitKey;
	function InputGetControllerID: string;
	function InputGetControllerName: string;
	procedure InputSetControllerID(value: string);
	procedure InputSwitchToNextController;

{DEFINE DEBUG_INPUT_FLAGS}

implementation
uses
{$IFDEF WIDECHAR} ZWideChr, {$ENDIF}
Classes, SysUtils, Keys, Sounds, TimerSys, ZVideo, SDL2;

type
	TKeyPressSource = (KPSKeyboard, KPSGamepad);
	TKeyPress = record
		Hsecs: word;
		Value: Uint32;
		Flags: byte;
		Source: TKeyPressSource;
	end;
{$IFDEF SHIFTJIS}
	TJISString = type AnsiString(932);
{$ENDIF}

const
{$IFDEF SHIFTJIS}
	KV_JIS = $80000000;
{$ENDIF}
	MAX_KEYS_PRESSED = 64;
	KP_PRESSED = $01;
	KP_HELD = $02;
	KP_REPEATED = $04;
	JOY_REPEAT_HSECS_DELAY = 25;
	JOY_REPEAT_HSECS_DELAY_NEXT = 4;
	PCScancodeMap: array[0 .. 83] of Byte = (
{  0 } 0,
{  1 } 0, 0, 0,
{  4 } $1E, $30, $2E, $20, $12, $21, $22, $23, $17, { A-I }
{ 13 } $24, $25, $26, $32, $31, $18, $19, $10, $13, { J-R }
{ 22 } $1F, $14, $16, $2F, $11, $2D, $15, $2C,       { S-Z }
{ 30 } 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, { 1-0  }
{ 40 } $1C, $01, $0E, $0F, $39,
{ 45 } $0C, $0D, $1A, $1B, $2B,
{ 50 } $2B, $27, $28, $29,
{ 54 } $33, $34, $35, $3A,
        $3B, $3C, $3D, $3E, $3F, $40, $41, $42, $43, $44, $57, $58,
        $37, $46, 0, $52, $47, $49, $53, $4F, $51,
        $4D, $4B, $50, $48, $45
	);

var
	KeysPressed: array[1 .. MAX_KEYS_PRESSED] of TKeyPress;
	KeysPressedPos: integer;
	InputControllerIndex: LongInt;
	InputGameController: PSDL_GameController;
	InputJoystick: PSDL_Joystick;

procedure InputCloseController;
	begin
		if InputGameController <> nil then begin
			SDL_GameControllerClose(InputGameController);
			InputGameController := nil;
			InputJoystick := nil; { belongs to GameController }
			InputControllerIndex := -1;
		end;
	end;

procedure InputOpenController(id: LongInt);
	begin
		InputCloseController;

		InputGameController := SDL_GameControllerOpen(id);
		if InputGameController <> nil then begin
			InputJoystick := SDL_GameControllerGetJoystick(InputGameController);
			InputControllerIndex := id;
		end;
	end;

const
	NIBBLE_TO_HEX: array[0 .. 15] of char = ('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f');

function InputGUIDToString(guid: TSDL_JoystickGUID): string;
	var
		i: integer;
		s: string;
	begin
		s := '';
		for i := 0 to 15 do begin
			s := s + NIBBLE_TO_HEX[guid.data[i] shr 4] + NIBBLE_TO_HEX[guid.data[i] and 15];
		end;
		InputGUIDToString := s;
	end;

function InputGetControllerID: string;
	begin
		if InputJoystick <> nil then begin
			InputGetControllerID := 'j' + InputGUIDToString(SDL_JoystickGetGUID(InputJoystick)); 
		end else begin
			InputGetControllerID := 'k';
		end;
	end;

function InputGetControllerName: string;
	begin
		if InputGameController <> nil then begin
			InputGetControllerName := StrPas(SDL_GameControllerName(InputGameController));
		end else begin
			InputGetControllerName := 'Keyboard';
		end;
	end;

procedure InputSetControllerID(value: string);
	var
		i: integer;
		jid: string;
	begin
		InputCloseController;

		if (Length(value) >= 1) and (value[1] = 'j') then begin
			for i := 0 to (SDL_NumJoysticks() - 1) do begin
				if SDL_IsGameController(i) = SDL_TRUE then begin
					jid := 'j' + InputGUIDToString(SDL_JoystickGetDeviceGUID(i));
					if jid = value then begin
						InputOpenController(i);
						exit;
					end;
				end;
			end;
		end;
	end;

procedure InputSwitchToNextController;
	var
		ids: TStringList;
		currId, newId: string;
		i: integer;
	begin
		ids := TStringList.Create;
		ids.Add('k');
		for i := 0 to (SDL_NumJoysticks() - 1) do begin
			if SDL_IsGameController(i) = SDL_TRUE then begin
				ids.Add('j' + InputGUIDToString(SDL_JoystickGetDeviceGUID(i)));
			end;
		end;
		currId := InputGetControllerID;
		newId := ids[0];
		for i := 0 to (ids.Count - 2) do begin
			if ids[i] = currId then
				newId := ids[i + 1];
		end;
		InputSetControllerID(newId);
		ids.Free;
	end;

function InputSetKeyPressed(kpSource: TKeyPressSource; key: Uint32; oneTime: boolean; isRepeat: boolean): boolean;
	var
		i, kid, kid2: integer;
		anyPressed: boolean;
		newHsecs: word;
	begin
		{ if isPressed and (key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]) then begin
			InputSetKeyPressed(KEY_UP, false, false, false);
			InputSetKeyPressed(KEY_DOWN, false, false, false);
			InputSetKeyPressed(KEY_LEFT, false, false, false);
			InputSetKeyPressed(KEY_RIGHT, false, false, false);
		end; }

		anyPressed := false;
		InputSetKeyPressed := true;

		kid := 0;
		for i := 1 to MAX_KEYS_PRESSED do with KeysPressed[i] do begin
			anyPressed := anyPressed or ((Flags and (KP_PRESSED or KP_HELD)) <> 0);
			if (Source = kpSource) and (Value = key) and ((Flags and (KP_PRESSED or KP_HELD)) <> 0) then begin
				if (isRepeat or ((Flags and KP_HELD) <> 0)) then begin
					kid := i;
					break;
				end;
			end;
		end;

		if not anyPressed then begin
			KeysPressedPos := 0;
		end;

		if (kid = 0) then begin
			for i := (KeysPressedPos + 1) to MAX_KEYS_PRESSED do with KeysPressed[i] do begin
				if ((Flags and (KP_PRESSED or KP_HELD)) = 0) then begin
					kid := i;
					break;
				end;
			end;
		end;

		if kid > 0 then begin
			with KeysPressed[kid] do begin
				if isRepeat and ((Flags and KP_HELD) <> 0) then exit;
				Source := kpSource;
				Value := key;
				Hsecs := TimerSysGetHsecs + JOY_REPEAT_HSECS_DELAY;
				Flags := KP_PRESSED;
				if not oneTime then Flags := Flags or KP_HELD;
{$IFDEF DEBUG_INPUT_FLAGS}
				WriteLn('flag changed by press');
				WriteLn(Flags);
{$ENDIF}
				{ Anti-skating }
				if (key < $100) and (Char(key and $FF) in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]) then begin
					newHsecs := TimerSysGetHsecs + JOY_REPEAT_HSECS_DELAY_NEXT;
					for kid2 := 1 to MAX_KEYS_PRESSED do with KeysPressed[kid2] do begin
						if (Value < $100) and (Char(Value and $FF) in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]) then
							if Hsecs < newHsecs then
								Hsecs := newHsecs;
					end;
				end;
			end;
		end else InputSetKeyPressed := false; { Slot not found }
	end;

procedure InputClearKeyPressed(kpSource: TKeyPressSource; key: Uint32; forceClear: boolean);
	var
		i: integer;
	begin
		for i := 1 to MAX_KEYS_PRESSED do begin
			with KeysPressed[i] do begin
				if (Source = kpSource) and (Value = key) then begin
					Flags := Flags and (not KP_HELD);
					if forceClear or ((Flags and KP_REPEATED) <> 0) then begin
						Flags := Flags and (not KP_PRESSED) and (not KP_REPEATED);
					end;
{$IFDEF DEBUG_INPUT_FLAGS}
					WriteLn('flag changed by clear');
					WriteLn(Flags);
{$ENDIF}
				end;
			end;
		end;
	end;

procedure InputUpdateKeymod(kmod: Uint16);
	begin
		KeysLeftShiftHeld := (kmod and KMOD_LSHIFT) <> 0;
		KeysRightShiftHeld := (kmod and KMOD_RSHIFT) <> 0;
		KeysShiftHeld := (kmod and KMOD_SHIFT) <> 0;
		KeysCtrlHeld := (kmod and KMOD_CTRL) <> 0;
		KeysAltHeld := (kmod and KMOD_ALT) <> 0;
		KeysNumLockHeld := (kmod and KMOD_NUM) <> 0;
	end;

procedure InputUpdate;
	var
		event: TSDL_Event;
		scode, kcode: Uint32;
		k: char;
		kv: Uint32;
		i: integer;
		localHsecs, hsecsDiff: word;
		sizeChanged: boolean;
{$IFDEF SHIFTJIS}
		tmpString: string[SDL_TEXTINPUTEVENT_TEXT_SIZE];
		jisString: TJISString;
{$ENDIF}
	begin
		InputDeltaX := 0;
		InputDeltaY := 0;
		InputShiftPressed := false;
		InputJoystickMoved := false;
		localHsecs := TimerSysGetHsecs;
		sizeChanged := false;

		SDL_LockMutex(eventMutex);
		while SDL_PollEvent(@event) <> 0 do begin
			case event.type_ of
				SDL_WINDOWEVENT: begin
					if event.window.event = SDL_WINDOWEVENT_SIZE_CHANGED then begin
						sizeChanged := true;
					end;
				end;
				SDL_TEXTINPUT: begin
{$IFDEF SHIFTJIS}
					i := 0;
					while (i < SDL_TEXTINPUTEVENT_TEXT_SIZE) and (Byte(event.text.text[i]) <> 0) do begin
						tmpString[i + 1] := event.text.text[i];
						Inc(i);
					end;
					tmpString[0] := Char(i);
					jisString := UTF8Decode(tmpString);
					i := 1;
					while (i <= Length(jisString)) do begin
						k := jisString[i];
						kv := Byte(k);
						if WideIsFirstByte(kv) then begin
							Inc(i);
							k := jisString[i];
							kv := (kv shl 8) or Byte(k);
						end;
						if (kv >= 32) then begin
							if (kv >= 128) then kv := kv or KV_JIS;
							{ TODO: Handle failure. }
							if InputSetKeyPressed(KPSKeyboard, kv, true, false) then begin end;							
						end;
						Inc(i);
					end;
{$ELSE}
					i := 0;
					while (i < SDL_TEXTINPUTEVENT_TEXT_SIZE) and (Byte(event.text.text[i]) <> 0) do begin
						k := event.text.text[i];
						if (Byte(k) >= 32) and (Byte(k) < 127) then
							{ TODO: Handle failure. }
							if InputSetKeyPressed(KPSKeyboard, Byte(k), true, false) then begin end;
						Inc(i);
					end;
{$ENDIF}
				end;
				SDL_KEYDOWN, SDL_KEYUP: begin
					InputUpdateKeymod(event.key.keysym.mod_);
					scode := Uint32(event.key.keysym.scancode);
					kcode := Uint32(event.key.keysym.sym);
					if KeysAltHeld and (Char(kcode) = 'p') then begin
						k := KEY_ALT_P;
					end else if KeysCtrlHeld and (Char(kcode) = 'c') then begin
						k := KEY_CTRL_C;
					end else if KeysCtrlHeld and (Char(kcode) = 'o') then begin
						k := KEY_CTRL_O;
					end else if KeysCtrlHeld and (Char(kcode) = 's') then begin
						k := KEY_CTRL_S;
					end else if KeysCtrlHeld and (Char(kcode) = 't') then begin
						k := KEY_CTRL_T;
					end else if KeysCtrlHeld and (Char(kcode) = 'v') then begin
						k := KEY_CTRL_V;
					end else if KeysCtrlHeld and (Char(kcode) = 'x') then begin
						k := KEY_CTRL_X;
					end else if KeysCtrlHeld and (Char(kcode) = 'y') then begin
						k := KEY_CTRL_Y;
					end else if (kcode > 0) and (kcode < 127) then begin
						k := Char(kcode);
					end else if scode <= 83 then begin
						k := Char(Integer(PCScancodeMap[scode]) + 128);
					end else k := #0;
					if Byte(k) >= 212 then begin
						{ Modifier keys are bound by regular autorepeat to prevent stickiness. }
						{ TODO: Handle failure. }
						if InputSetKeyPressed(KPSKeyboard, Byte(k), true, false) then begin end;
					end else if ((Byte(k) and $7F) <> 0) and not ((Byte(k) >= 32) and (Byte(k) < 127)) then begin
 						if event.type_ = SDL_KEYDOWN then begin
							{ TODO: Handle failure. }
							if InputSetKeyPressed(KPSKeyboard, Byte(k), false, event.key.repeat_ <> 0) then begin end;
						end else begin
							InputClearKeyPressed(KPSKeyboard, Byte(k), false);
						end;
					end;
				end;
				SDL_CONTROLLERDEVICEREMOVED: begin
					if event.cdevice.which = InputControllerIndex then
						InputCloseController;
				end;
				SDL_CONTROLLERBUTTONDOWN, SDL_CONTROLLERBUTTONUP: begin
					if event.cbutton.which = InputControllerIndex then begin
						case event.cbutton.button of
						SDL_CONTROLLER_BUTTON_DPAD_UP: k := KEY_UP;
						SDL_CONTROLLER_BUTTON_DPAD_LEFT: k := KEY_LEFT;
						SDL_CONTROLLER_BUTTON_DPAD_RIGHT: k := KEY_RIGHT;
						SDL_CONTROLLER_BUTTON_DPAD_DOWN: k := KEY_DOWN;
						SDL_CONTROLLER_BUTTON_X: k := ' ';
						SDL_CONTROLLER_BUTTON_Y: k := 'T';
						SDL_CONTROLLER_BUTTON_LEFTSHOULDER: k := KEY_PAGE_UP;
						SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: k := KEY_PAGE_DOWN;
						SDL_CONTROLLER_BUTTON_START: k := 'P';
						else k := #0 end;
						if (k <> #0) then begin
							if event.cbutton.state = SDL_PRESSED then
								InputSetKeyPressed(KPSGamepad, Byte(k), false, false)
							else
								InputClearKeyPressed(KPSGamepad, Byte(k), false);
						end;
					end;
				end;
			end;
		end;
		SDL_UnlockMutex(eventMutex);

		if sizeChanged then begin
			VideoOnSizeChanged;
		end;

		InputKeyPressed := #0;
		for i := 1 to MAX_KEYS_PRESSED do begin
			with KeysPressed[KeysPressedPos + 1] do begin
				if ((Flags and (KP_PRESSED or KP_HELD)) = KP_HELD) then begin
					hsecsDiff := Hsecs - localHsecs;
					if hsecsDiff >= 32768 then begin
						Hsecs := localHsecs + JOY_REPEAT_HSECS_DELAY_NEXT;
						Flags := (Flags or KP_PRESSED) or KP_REPEATED;
{$IFDEF DEBUG_INPUT_FLAGS}
						WriteLn('flag changed by hsecs diff');
						WriteLn(Flags);
{$ENDIF}
					end;
				end;
				if ((Flags and KP_PRESSED) = KP_PRESSED) then begin
					Flags := Flags and (not KP_PRESSED);
{$IFDEF DEBUG_INPUT_FLAGS}
					WriteLn('flag changed by unpress');
					WriteLn(Flags);
{$ENDIF}
{$IFDEF SHIFTJIS}
					if (Value and KV_JIS) <> 0 then begin
						InputKeyPressed := KEY_WIDESTRING;
						if (Value and $FFFF) >= $100 then begin
							InputKeyPressedWide[0] := Chr(2);
							InputKeyPressedWide[1] := Chr((Value shr 8) and $FF);
							InputKeyPressedWide[2] := Chr(Value and $FF);
						end else begin
							InputKeyPressedWide[0] := Chr(1);
							InputKeyPressedWide[1] := Chr(Value and $FF);
						end;
					end else
{$ENDIF}
					InputKeyPressed := Char(Value and $FF);
					KeysPressedPos := (KeysPressedPos + 1) mod MAX_KEYS_PRESSED;
					break;
				end;
			end;

			KeysPressedPos := (KeysPressedPos + 1) mod MAX_KEYS_PRESSED;
		end;

		case InputKeyPressed of
			KEY_UP, '8': begin
				InputDeltaX := 0;
				InputDeltaY := -1;
			end;
			KEY_LEFT, '4': begin
				InputDeltaX := -1;
				InputDeltaY := 0;
			end;
			KEY_RIGHT, '6': begin
				InputDeltaX := 1;
				InputDeltaY := 0;
			end;
			KEY_DOWN, '2': begin
				InputDeltaX := 0;
				InputDeltaY := 1;
			end;
		end;

		if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
			if InputControllerIndex >= 0 then begin
				InputShiftPressed := InputShiftPressed or
					(SDL_GameControllerGetButton(InputGameController, SDL_CONTROLLER_BUTTON_A) <> 0)
					or (SDL_GameControllerGetButton(InputGameController, SDL_CONTROLLER_BUTTON_B) <> 0);
			end;
			{ keyboard movement }
			InputShiftPressed := InputShiftPressed or KeysShiftHeld;
		end;
	end;

procedure InputInitDevices;
	begin
		InputJoystickEnabled := false; 
		InputMouseEnabled := false;
	end;

procedure InputReadWaitKey;
	begin
		repeat
			SoundIdle(IMUntilFrame);
			InputUpdate;
		until InputKeyPressed <> #0;
	end;

begin
	InputLastDeltaX := 0;
	InputLastDeltaY := 0;
	InputDeltaX := 0;
	InputDeltaY := 0;
	InputShiftPressed := false;
	InputShiftAccepted := false;
	InputMouseX := 0;
	InputMouseY := 0;
	InputMouseActivationX := 60;
	InputMouseActivationY := 60;
	InputMouseButtonX := 0;
	InputMouseButtonY := 0;

	InputGameController := nil;
	InputJoystick := nil;
	InputControllerIndex := -1;

	KeysPressedPos := 0;
end.
