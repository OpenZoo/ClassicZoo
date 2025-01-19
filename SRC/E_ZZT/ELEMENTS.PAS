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

{$F+}
{$I-}
{$V-}
unit Elements;

interface
	uses GameVars;
	procedure ElementMonitorTick(statId: integer);
	procedure ElementMove(oldX, oldY, newX, newY: integer);
	procedure ElementPushablePush(x, y: integer; deltaX, deltaY: integer);
	procedure DrawPlayerSurroundings(x, y: integer; bombPhase: integer);
	procedure GamePromptEndPlay;
	procedure ResetMessageNotShownFlags;
	procedure InitElementsEditor;
	procedure InitElementsGame;
	procedure InitEditorStatSettings;

implementation
uses
{$IFDEF DEBUGWND} DebugWnd, {$ENDIF}
{$IFDEF UISCBACK} UiScBack, {$ENDIF}
{$IFDEF MSDOS}
{$IFDEF NEC98} Pc98, {$ELSE} Crt, {$ENDIF}
{$ENDIF} {$IFDEF SDL2} AudioSim, {$ENDIF}
ZVideo, Sounds, ZInput, TxtWind, Editor, Oop, GameConf, Sidebar, Cheats, GameSh, Game;

const
{$IFDEF RAWMEM}
	TransporterNSChars: string = '^~^-v_v-';
	TransporterEWChars: string = '(<('#179')>)'#179;
	StarAnimChars: string = #179'/'#196'\';
{$ELSE}
{$IFDEF MEMBOUND}
	TransporterNSChars: string[8] = '^~^-v_v-';
	TransporterEWChars: string[8] = '(<('#179')>)'#179;
{$ELSE}
	TransporterNSChars: string = '^~^-v_v-';
	TransporterEWChars: string = '(<('#179')>)'#179;
{$ENDIF}
	StarAnimChars: string[4] = #179'/'#196'\';
{$ENDIF}

procedure ElementDefaultTick(statId: integer);
	begin
	end;

procedure ElementDefaultTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
	end;

procedure ElementDefaultDraw(x, y: integer; var ch: byte);
	begin
		ch := Ord('?');
	end;

procedure ElementMessageTimerTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			case X of
				0: begin
{$IFDEF WIDECHAR}
					VideoWriteTextWide((60 - Length(Board.Info.Message)) div 2, 24, 9 + (P2 mod 7), ' '+Board.Info.Message+' ');
{$ELSE}
					VideoWriteText((60 - Length(Board.Info.Message)) div 2, 24, 9 + (P2 mod 7), ' '+Board.Info.Message+' ');
{$ENDIF}
					Dec(P2);
					if P2 <= 0 then begin
						RemoveStat(statId);
						Dec(CurrentStatTicked);
						BoardDrawBorder;
						Board.Info.Message := '';
					end;
				end;
			end;
		end;
	end;

procedure ElementDamagingTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		BoardAttack(sourceStatId, x, y);
	end;

procedure ElementLionTick(statId: integer);
	var
		deltaX, deltaY: integer;
	begin
		with Board.Stats[statId] do begin
			if P1 < ZRandom(10) then
				CalcDirectionRnd(deltaX, deltaY)
			else
				CalcDirectionSeek(X, Y, deltaX, deltaY);

			with Board.Tiles[X + deltaX][Y + deltaY] do begin
				if ElementDefs[Element].Walkable then begin
					MoveStat(statId, X + deltaX, Y + deltaY);
				end else if Element = E_PLAYER then begin
					BoardAttack(statId, X + deltaX, Y + deltaY)
				end;
			end;
		end;
	end;

procedure ElementTigerTick(statId: integer);
	var
		shot: boolean;
		element: byte;
	begin
		with Board.Stats[statId] do begin
			element := E_BULLET;
			if P2 >= $80 then
				element := E_STAR;

			if (ZRandom(10) * 3) <= (P2 and $7F) then begin
				if Difference(X, Board.Stats[0].X) <= 2 then begin
					shot := BoardShoot(element, X, Y, 0, Signum(Board.Stats[0].Y - Y), SHOT_SOURCE_ENEMY);
				end else begin
					shot := false;
				end;

				if not shot then begin
					if Difference(Y, Board.Stats[0].Y) <= 2 then begin
						shot := BoardShoot(element, X, Y, Signum(Board.Stats[0].X - X), 0, SHOT_SOURCE_ENEMY);
					end;
				end;
			end;

			ElementLionTick(statId);
		end;
	end;

procedure ElementRuffianTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			if (StepX = 0) and (StepY = 0) then begin
				if (P2 + 8) <= ZRandom(17) then begin
					if P1 >= ZRandom(9) then
						CalcDirectionSeek(X, Y, StepX, StepY)
					else
						CalcDirectionRnd(StepX, StepY);
				end;
			end else begin
				if ((Y = Board.Stats[0].Y) or (X = Board.Stats[0].X)) and (ZRandom(9) <= P1) then begin
					CalcDirectionSeek(X, Y, StepX, StepY);
				end;

				with Board.Tiles[X + StepX][Y + StepY] do begin
					if Element = E_PLAYER then begin
						BoardAttack(statId, X + StepX, Y + StepY)
					end else if ElementDefs[Element].Walkable then begin
						MoveStat(statId, X + StepX, Y + StepY);
						if (P2 + 8) <= ZRandom(17) then begin
							StepX := 0;
							StepY := 0;
						end;
					end else begin
						StepX := 0;
						StepY := 0;
					end;
				end;

			end;
		end;
	end;

procedure ElementBearTick(statId: integer);
	var
		deltaX, deltaY: integer;
	label Movement;
	begin
		with Board.Stats[statId] do begin
			if X <> Board.Stats[0].X then
				if Difference(Y, Board.Stats[0].Y) <= (8 - P1) then begin
					deltaX := Signum(Board.Stats[0].X - X);
					deltaY := 0;
					goto Movement;
				end;

			if Difference(X, Board.Stats[0].X) <= (8 - P1) then begin
				deltaY := Signum(Board.Stats[0].Y - Y);
				deltaX := 0;
			end else begin
				deltaX := 0;
				deltaY := 0;
			end;

		Movement:
			with Board.Tiles[X + deltaX][Y + deltaY] do begin
				if ElementDefs[Element].Walkable then begin
					MoveStat(statId, X + deltaX, Y + deltaY);
				end else if (Element = E_PLAYER) or (Element = E_BREAKABLE) then begin
					BoardAttack(statId, X + deltaX, Y + deltaY)
				end;
			end;

		end;
	end;

procedure ElementCentipedeHeadTick(statId: integer);
	var
		ix, iy: integer;
		tx, ty: integer;
		tmp: integer;
	begin
		with Board.Stats[statId] do begin
			if (X = Board.Stats[0].X) and (ZRandom(10) < P1) then begin
				StepY := Signum(Board.Stats[0].Y - Y);
				StepX := 0;
			end else if (Y = Board.Stats[0].Y) and (ZRandom(10) < P1) then begin
				StepX := Signum(Board.Stats[0].X - X);
				StepY := 0;
			end else if ((ZRandom(10) * 4) < P2) or ((StepX = 0) and (StepY = 0)) then begin
				CalcDirectionRnd(StepX, StepY);
			end;

			with Board.Tiles[X + StepX][Y + StepY] do
			if not ElementDefs[Element].Walkable
				and (Element <> E_PLAYER) then
			begin
				ix := StepX;
				iy := StepY;
				tmp := ((ZRandom(2) * 2) - 1) * iy;
				StepY := ((ZRandom(2) * 2) - 1) * ix;
				StepX := tmp;
				with Board.Tiles[X + StepX][Y + StepY] do
				if not ElementDefs[Element].Walkable
					and (Element <> E_PLAYER) then
				begin
					StepX := -StepX;
					StepY := -StepY;
					with Board.Tiles[X + StepX][Y + StepY] do
					if not ElementDefs[Element].Walkable
						and (Element <> E_PLAYER) then
					begin
						with Board.Tiles[X - ix][Y - iy] do
						if ElementDefs[Element].Walkable
							or (Element = E_PLAYER) then
						begin
							StepX := -ix;
							StepY := -iy;
						end else begin
							StepX := 0;
							StepY := 0;
						end;
					end;
				end;
			end;

			if (StepX = 0) and (StepY = 0) then begin
				Board.Tiles[X][Y].Element := E_CENTIPEDE_SEGMENT;
				Leader := -1;
				while Board.Stats[statId].Follower > 0 do begin
					with Board.Stats[statId] do begin
						tmp := Follower;
						Follower := Leader;
						Leader := tmp;
					end;
					statId := tmp;
				end;
				with Board.Stats[statId] do begin
					Follower := Leader;
					Leader := -1;
					Board.Tiles[X][Y].Element := E_CENTIPEDE_HEAD;
				end;
			end else if Board.Tiles[X + StepX][Y + StepY].Element = E_PLAYER then begin
				if Follower > 0 then begin
					Board.Stats[Follower].StepX := StepX;
					Board.Stats[Follower].StepY := StepY;
					with Board.Stats[Follower] do begin
						Board.Tiles[X][Y].Element := E_CENTIPEDE_HEAD;
						BoardDrawTile(X, Y);
					end;
				end;
				BoardAttack(statId, X + StepX, Y + StepY);
			end else begin
				MoveStat(statId, X + StepX, Y + StepY);

				repeat
					with Board.Stats[statId] do begin
						tx := X - StepX;
						ty := Y - StepY;
						ix := StepX;
						iy := StepY;
						if Follower < 0 then begin
							if (Board.Tiles[tx - ix][ty - iy].Element = E_CENTIPEDE_SEGMENT)
								and (Board.Stats[GetStatIdAt(tx - ix, ty - iy)].Leader < 0) then
							begin
								Follower := GetStatIdAt(tx - ix, ty - iy)
							end else if (Board.Tiles[tx - iy][ty - ix].Element = E_CENTIPEDE_SEGMENT)
								and (Board.Stats[GetStatIdAt(tx - iy, ty - ix)].Leader < 0) then
							begin
								Follower := GetStatIdAt(tx - iy, ty - ix);
							end else if (Board.Tiles[tx + iy][ty + ix].Element = E_CENTIPEDE_SEGMENT)
								and (Board.Stats[GetStatIdAt(tx + iy, ty + ix)].Leader < 0) then
							begin
								Follower := GetStatIdAt(tx + iy, ty + ix);
							end;
						end;

						if Follower > 0 then begin
							Board.Stats[Follower].P1 := P1;
							Board.Stats[Follower].P2 := P2;
							with Board.Stats[Follower] do begin
								Leader := statId;
								StepX := tx - X;
								StepY := ty - Y;
							end;
							MoveStat(Follower, tx, ty);
						end;
						statId := Follower;
					end;
				until statId < 0;
			end;
		end;
	end;

procedure ElementCentipedeSegmentTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			if Leader < 0 then begin
				if Leader < -1 then
					Board.Tiles[X][Y].Element := E_CENTIPEDE_HEAD
				else
					Dec(Leader);
			end;
		end;
	end;

procedure ElementBulletTick(statId: integer);
	var
		ix, iy: integer;
		iStat: integer;
		iElem: byte;
		firstTry: boolean;
	label TryMove;
	begin
		with Board.Stats[statId] do begin
			firstTry := true;

		TryMove:
			ix := X + StepX;
			iy := Y + StepY;
			iElem := Board.Tiles[ix][iy].Element;

			if ElementDefs[iElem].Walkable or (iElem = E_WATER) then begin
				MoveStat(statId, ix, iy);
				exit;
			end;

			if (iElem = E_RICOCHET) and firstTry then begin
				StepX := -StepX;
				StepY := -StepY;
				SoundQueue(1, #249#1);
				firstTry := false;
				goto TryMove;
				exit;
			end;

			if (iElem = E_BREAKABLE)
				or (ElementDefs[iElem].Destructible and ((iElem = E_PLAYER) or (P1 = 0))) then
			begin
				if ElementDefs[iElem].ScoreValue <> 0 then begin
					Inc(World.Info.Score, ElementDefs[iElem].ScoreValue);
					GameUpdateSidebar;
				end;
				BoardAttack(statId, ix, iy);
				exit;
			end;

			if (Board.Tiles[X + StepY][Y + StepX].Element = E_RICOCHET) and firstTry then begin
				ix := StepX;
				StepX := -StepY;
				StepY := -ix;
				SoundQueue(1, #249#1);
				firstTry := false;
				goto TryMove;
			end;

			if (Board.Tiles[X - StepY][Y - StepX].Element = E_RICOCHET) and firstTry then begin
				ix := StepX;
				StepX := StepY;
				StepY := ix;
				SoundQueue(1, #249#1);
				firstTry := false;
				goto TryMove;
			end;

			RemoveStat(statId);
			Dec(CurrentStatTicked);
			if (iElem = E_OBJECT) or (iElem = E_SCROLL) then begin
				iStat := GetStatIdAt(ix, iy);
				if OopSend(-iStat, 'SHOT', false) then begin end;
			end;
		end;
	end;

procedure ElementSpinningGunDraw(x, y: integer; var ch: byte);
	begin
		case CurrentTick and 7 of
			0, 1: ch := 24;
			2, 3: ch := 26;
			4, 5: ch := 25;
		else ch := 27 end;
	end;

procedure ElementLineDraw(x, y: integer; var ch: byte);
	var
		i, v, shift: integer;
	begin
		v := 1;
		shift := 1;
		for i := 0 to 3 do begin
			case Board.Tiles[x + NeighborDeltaX[i]][y + NeighborDeltaY[i]].Element of
				E_LINE, E_BOARD_EDGE: Inc(v, shift);
			end;
			shift := shift shl 1;
		end;
		ch := Ord(LineChars[v]);
	end;

procedure ElementSpinningGunTick(statId: integer);
	var
		shot: boolean;
		deltaX, deltaY: integer;
		element: byte;
	begin
		with Board.Stats[statId] do begin
			BoardDrawTile(X, Y);

			element := E_BULLET;
			if P2 >= $80 then
				element := E_STAR;

			if ZRandom(9) < (P2 and $7F) then begin
				if ZRandom(9) <= P1 then begin
					if Difference(X, Board.Stats[0].X) <= 2 then begin
						shot := BoardShoot(element, X, Y, 0, Signum(Board.Stats[0].Y - Y), SHOT_SOURCE_ENEMY);
					end else begin
						shot := false;
					end;

					if not shot then begin
						if Difference(Y, Board.Stats[0].Y) <= 2 then begin
							shot := BoardShoot(element, X, Y, Signum(Board.Stats[0].X - X), 0, SHOT_SOURCE_ENEMY);
						end;
					end;
				end else begin
					CalcDirectionRnd(deltaX, deltaY);
					shot := BoardShoot(element, X, Y, deltaX, deltaY, SHOT_SOURCE_ENEMY);
				end;
			end;
		end;
	end;

procedure ElementConveyorTick(x, y: integer; direction: integer);
	var
		i: integer;
		iStat: integer;
		ix, iy: integer;
		canMove: boolean;
		tiles: array[0..7] of TTile;
		statIds: array[0..7] of integer;
		iMin, iMax: integer;
		tmpTile: TTile;
		tx, ty: integer;
	begin
		if direction = 1 then begin
			iMin := 0;
			iMax := 8;
		end else begin
			iMin := 7;
			iMax := -1;
		end;

		{ Moved from CWTick/CCWTick }
		BoardDrawTile(X, Y);

		canMove := true;
		i := iMin;
		repeat
			tx := x + DiagonalDeltaX[i];
			ty := y + DiagonalDeltaY[i];
			tiles[i] := Board.Tiles[tx][ty];
			with tiles[i] do begin
				if Element = E_EMPTY then
					canMove := true
				else if not ElementDefs[Element].Pushable then
					canMove := false;
				{ FIX: In some cases, a movement could cause two stats to briefly overlap each other. }
				{ Pre-find stat IDs to prevent such a scenario from occuring. }
				if ElementDefs[Element].Cycle > -1 then
					statIds[i] := GetStatIdAt(tx, ty);
			end;
			Inc(i, direction);
		until i = iMax;

		i := iMin;
		repeat
			with tiles[i] do begin
				if canMove then begin
					if ElementDefs[Element].Pushable then begin
						ix := x + DiagonalDeltaX[(i - direction) and 7];
						iy := y + DiagonalDeltaY[(i - direction) and 7];
						tx := x + DiagonalDeltaX[i];
						ty := y + DiagonalDeltaY[i];

						if ElementDefs[Element].Cycle > -1 then begin
							if HighCompat then
								statIds[i] := GetStatIdAt(tx, ty);

							tmpTile := Board.Tiles[tx][ty];
							Board.Tiles[tx][ty] := tiles[i];
							Board.Tiles[ix][iy].Element := E_EMPTY;
							MoveStat(statIds[i], ix, iy);

							Board.Tiles[tx][ty] := tmpTile;
							{ FIX: Add missing BoardDrawTile. }
							BoardDrawTile(tx, ty);
						end else begin
							Board.Tiles[ix][iy] := tiles[i];
							BoardDrawTile(ix, iy);
						end;
						if not ElementDefs[tiles[(i + direction) and 7].Element].Pushable then begin
							Board.Tiles[tx][ty].Element := E_EMPTY;
							BoardDrawTile(tx, ty);
						end;
					end else begin
						canMove := false;
					end;
				end else if Element = E_EMPTY then
					canMove := true
				else if not ElementDefs[Element].Pushable then
					canMove := false;
			end;
			Inc(i, direction);
		until i = iMax;
	end;

procedure ElementConveyorCWDraw(x, y: integer; var ch: byte);
	begin
		case (CurrentTick div ElementDefs[E_CONVEYOR_CW].Cycle) and 3 of
			0: ch := 179;
			1: ch := 47;
			2: ch := 196;
		else ch := 92 end;
	end;

procedure ElementConveyorCWTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			ElementConveyorTick(X, Y, 1);
		end;
	end;

procedure ElementConveyorCCWDraw(x, y: integer; var ch: byte);
	begin
		case (CurrentTick div ElementDefs[E_CONVEYOR_CCW].Cycle) and 3 of
			3: ch := 179;
			2: ch := 47;
			1: ch := 196;
		else ch := 92 end;
	end;

procedure ElementConveyorCCWTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			ElementConveyorTick(X, Y, -1);
		end;
	end;

procedure ElementBombDraw(x, y: integer; var ch: byte);
	begin
		with Board.Stats[GetStatIdAt(x, y)] do
			if P1 <= 1 then
				ch := 11
			else
				ch := 48 + P1;
	end;

procedure ElementBombTick(statId: integer);
	var
		oldX, oldY: integer;
	begin
		with Board.Stats[statId] do begin
			if P1 > 0 then begin
				Dec(P1);
				BoardDrawTile(X, Y);

				if P1 = 1 then begin
					SoundQueue(1, #96#1#80#1#64#1#48#1#32#1#16#1);
					DrawPlayerSurroundings(X, Y, 1);
				end else if P1 = 0 then begin
					oldX := X;
					oldY := Y;
					RemoveStat(statId);
					DrawPlayerSurroundings(oldX, oldY, 2);
				end else begin
					if (P1 and 1) = 0 then
						SoundQueue(1, #248#1)
					else
						SoundQueue(1, #245#1);
				end;
			end;
		end;
	end;

procedure ElementBombTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		with Board.Stats[GetStatIdAt(x, y)] do begin
			if P1 = 0 then begin
				P1 := 9;
				BoardDrawTile(X, Y);
				DisplayMessage(200, 'Bomb activated!');
				SoundQueue(4, #48#1#53#1#64#1#69#1#80#1);
			end else begin
				ElementPushablePush(X, Y, deltaX, deltaY);
			end;
		end;
	end;

procedure ElementTransporterMove(x, y, deltaX, deltaY: integer);
	var
		ix, iy: integer;
		iStat: integer;
		isValidDest: boolean;
	label ETLoop;
	begin
		with Board.Stats[GetStatIdAt(x + deltaX, y + deltaY)] do begin
			if (deltaX = StepX) and (deltaY = StepY) then begin
				if (deltaX = 0) and (deltaY = 0) then begin
	{$IFDEF DEBUGWND}
					if DebugCompatEnabled then
						DebugShowElementMessage('Illegal transporter movement', x, y);
	{$ENDIF}
					exit;
				end;

				ix := X;
				iy := Y;
				isValidDest := true;
ETLoop:
				Inc(ix, deltaX);
				Inc(iy, deltaY);
				with Board.Tiles[ix][iy] do begin
					if Element = E_BOARD_EDGE then
						exit
					else if isValidDest then begin
						isValidDest := false;

						if not ElementDefs[Element].Walkable then
							ElementPushablePush(ix, iy, deltaX, deltaY);

						if ElementDefs[Element].Walkable then begin
							ElementMove(X - deltaX, Y - deltaY, ix, iy);
							SoundQueue(3, #48#1#66#1#52#1#70#1#56#1#74#1#64#1#82#1);
							exit;
						end;
					end;
					if Element = E_TRANSPORTER then begin
						iStat := GetStatIdAt(ix, iy);
						with Board.Stats[iStat] do
							if (StepX = -deltaX) and (StepY = -deltaY) then
								isValidDest := true;
					end;
				end;
				goto ETLoop;
			end;
		end;
	end;

procedure ElementTransporterTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		ElementTransporterMove(x - deltaX, y - deltaY, deltaX, deltaY);
		deltaX := 0;
		deltaY := 0;
	end;

procedure ElementTransporterTick(statId: integer);
	begin
		with Board.Stats[statId] do
			BoardDrawTile(X, Y);
	end;

procedure ElementTransporterDraw(x, y: integer; var ch: byte);
	var
		i: integer;
	begin
		with Board.Stats[GetStatIdAt(x, y)] do begin
			if Cycle = 0 then
				i := 0
			else
				i := (CurrentTick div Cycle) and 3;
{$IFDEF MEMBOUND}
			ch := 0;
			if StepX = 0 then begin
				i := StepY * 2 + 3 + i;
				if (i >= 1) and (i <= 8) then
					ch := Ord(TransporterNSChars[i]);
			end else begin
				i := StepX * 2 + 3 + i;
				if (i >= 1) and (i <= 8) then
					ch := Ord(TransporterEWChars[i]);
			end;
{$ELSE}
			if StepX = 0 then
				ch := Ord(TransporterNSChars[StepY * 2 + 3 + i])
			else
				ch := Ord(TransporterEWChars[StepX * 2 + 3 + i]);
{$ENDIF}
		end;
	end;

procedure ElementStarDraw(x, y: integer; var ch: byte);
	begin
		ch := Ord(StarAnimChars[(CurrentTick and 3) + 1]);
		with Board.Tiles[x][y] do begin
			if Color >= 15 then
				Color := 9
			else
				Inc(Color);
		end;
	end;

procedure ElementStarTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			Dec(P2);
			if P2 <= 0 then begin
				RemoveStat(statId);
			end else if (P2 and 1) = 0 then begin
				CalcDirectionSeek(X, Y, StepX, StepY);
				with Board.Tiles[X + StepX][Y + StepY] do begin
					if (Element = E_PLAYER) or (Element = E_BREAKABLE) then begin
						BoardAttack(statId, X + StepX, Y + StepY);
					end else begin
						if not ElementDefs[Element].Walkable then
							ElementPushablePush(X + StepX, Y + StepY, StepX, StepY);

						if ElementDefs[Element].Walkable or (Element = E_WATER) then
							MoveStat(statId, X + StepX, Y + StepY);
					end;
				end;
			end else begin
				BoardDrawTile(X, Y);
			end;
		end;
	end;

procedure ElementEnergizerTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		SoundQueue(9, #32#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3
			+ #48#3#35#3#36#3#37#3#53#3#37#3#35#3#32#3);

		Board.Tiles[x][y].Element := E_EMPTY;
		BoardDrawTile(x, y);

		World.Info.EnergizerTicks := 75;
		GameUpdateSidebar;

		if MessageEnergizerNotShown then begin
			DisplayMessage(200, 'Energizer - You are invincible');
			MessageEnergizerNotShown := false;
		end;

		if OopSend(0, 'ALL:ENERGIZE', false) then begin end;
	end;

procedure ElementSlimeTick(statId: integer);
	var
		dir, colorCopy, changedTiles: integer;
		startX, startY: integer;
		tx, ty: integer;
	begin
		with Board.Stats[statId] do begin
			if P1 < P2 then
				Inc(P1)
			else begin
				P1 := 0;
				startX := X;
				startY := Y;
				colorCopy := Board.Tiles[startX][startY].Color;
				changedTiles := 0;

				for dir := 0 to 3 do begin
					tx := startX + NeighborDeltaX[dir];
					ty := startY + NeighborDeltaY[dir];

					if ElementDefs[Board.Tiles[tx][ty].Element].Walkable then begin
						if changedTiles = 0 then begin
							MoveStat(statId, tx, ty);
							with Board.Tiles[startX][startY] do begin
								Element := E_BREAKABLE;
								color := colorCopy;
							end;
							BoardDrawTile(startX, startY);
						end else begin
							AddStat(tx, ty, E_SLIME, colorCopy,
								ElementDefs[E_SLIME].Cycle, StatTemplateDefault);
							Board.Stats[Board.StatCount].P2 := P2;
						end;

						Inc(changedTiles);
					end;
				end;

				if changedTiles = 0 then begin
					RemoveStat(statId);
					with Board.Tiles[startX][startY] do begin
						Element := E_BREAKABLE;
						color := colorCopy;
					end;
					BoardDrawTile(startX, startY);
				end;
			end;
		end;
	end;

procedure ElementSlimeTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		colorCopy: integer;
	begin
		with Board.Tiles[x][y] do begin
			colorCopy := Color;
			DamageStat(GetStatIdAt(x, y));
			Element := E_BREAKABLE;
			Color := colorCopy;
		end;

		BoardDrawTile(x, y);
		SoundQueue(2, #32#1#35#1);
	end;

procedure ElementSharkTick(statId: integer);
	var
		deltaX, deltaY: integer;
	begin
		with Board.Stats[statId] do begin
			if P1 < ZRandom(10) then
				CalcDirectionRnd(deltaX, deltaY)
			else
				CalcDirectionSeek(X, Y, deltaX, deltaY);

			case Board.Tiles[X + deltaX][Y + deltaY].Element of
				E_WATER: MoveStat(statId, X + deltaX, Y + deltaY);
				E_PLAYER: BoardAttack(statId, X + deltaX, Y + deltaY);
			end;
		end;
	end;

procedure ElementBlinkWallDraw(x, y: integer; var ch: byte);
	begin
		ch := 206;
	end;

procedure ElementBlinkWallTick(statId: integer);
	var
		ix, iy: integer;
		hitBoundary: boolean;
		playerStatId: integer;
		el: integer;
	begin
		with Board.Stats[statId] do begin
			if P3 = 0 then
				P3 := P1 + 1;
			if P3 = 1 then begin
				ix := X + StepX;
				iy := Y + StepY;

				if StepX <> 0 then
					el := E_BLINK_RAY_EW
				else
					el := E_BLINK_RAY_NS;

				while (Board.Tiles[ix][iy].Element = el)
					and (Board.Tiles[ix][iy].Color = Board.Tiles[X][Y].Color) do
				begin
					Board.Tiles[ix][iy].Element := E_EMPTY;
					BoardDrawTile(ix, iy);
					Inc(ix, StepX);
					Inc(iy, StepY);
				end;

				if ((X + StepX) = ix) and ((Y + StepY) = iy) then begin
					hitBoundary := false;
					repeat
						with Board.Tiles[ix][iy] do begin
							if (Element <> E_EMPTY) and (ElementDefs[Element].Destructible) then
								BoardDamageTile(ix, iy);

							if Element = E_PLAYER then begin
								playerStatId := GetStatIdAt(ix, iy);

								if playerStatId >= 0 then begin
									if StepX <> 0 then begin
										if Board.Tiles[ix][iy - 1].Element = E_EMPTY then
											MoveStat(playerStatId, ix, iy - 1)
										else if Board.Tiles[ix][iy + 1].Element = E_EMPTY then
											MoveStat(playerStatId, ix, iy + 1);
									end else begin
										if Board.Tiles[ix + 1][iy].Element = E_EMPTY then
											MoveStat(playerStatId, ix + 1, iy)
										else if Board.Tiles[ix - 1][iy].Element = E_EMPTY then
											MoveStat(playerStatId, ix + 1, iy);
									end;

									if Element = E_PLAYER then begin
										while World.Info.Health > 0 do begin
											DamageStat(playerStatId);
											if playerStatId > 0 then begin
{$IFDEF DEBUGWND}
												if DebugCompatEnabled then
													DebugShowElementMessage('Illegal statless player damage', x, y);
{$ENDIF}
												exit;
											end;
										end;
										hitBoundary := true;
									end;
{$IFDEF DEBUGWND}
								end else begin
									{ TODO: Should destroying a statless player have any special behaviour? }
									if DebugCompatEnabled then
										DebugShowElementMessage('Illegal statless player damage', x, y);
{$ENDIF}
								end;
							end;

							if Element = E_EMPTY then begin
								Element := el;
								Color := Board.Tiles[X][Y].Color;
								BoardDrawTile(ix, iy);
							end else begin
								hitBoundary := true;
							end;
						end;

						Inc(ix, StepX);
						Inc(iy, StepY);
					until hitBoundary;
				end;

				P3 := (P2 * 2) + 1;
			end else begin
				Dec(P3);
			end;
		end;
	end;

procedure ElementMove(oldX, oldY, newX, newY: integer);
	var
		statId: integer;
	begin
		statId := GetStatIdAt(oldX, oldY);

		if statId >= 0 then begin
			MoveStat(statId, newX, newY);
		end else begin
			Board.Tiles[newX][newY] := Board.Tiles[oldX][oldY];
			BoardDrawTile(newX, newY);
			Board.Tiles[oldX][oldY].Element := E_EMPTY;
			BoardDrawTile(oldX, oldY);
		end;
	end;

procedure ElementPushablePush(x, y: integer; deltaX, deltaY: integer);
	var
		unk1: integer;
	begin
		with Board.Tiles[x][y] do begin
			if ((Element = E_SLIDER_NS) and (deltaX = 0)) or ((Element = E_SLIDER_EW) and (deltaY = 0))
				or ElementDefs[Element].Pushable then
			begin
				if Board.Tiles[x + deltaX][y + deltaY].Element = E_TRANSPORTER then begin
					ElementTransporterMove(x, y, deltaX, deltaY);
				end else if Board.Tiles[x + deltaX][y + deltaY].Element <> E_EMPTY then begin
					if (deltaX <> 0) or (deltaY <> 0) then begin
						ElementPushablePush(x + deltaX, y + deltaY, deltaX, deltaY);
{$IFDEF DEBUGWND}
					end else begin
						if DebugCompatEnabled then
							DebugShowElementMessage('Illegal pushable movement', x, y);
{$ENDIF}
					end;
				end;

				if not ElementDefs[Board.Tiles[x + deltaX][y + deltaY].Element].Walkable
					and ElementDefs[Board.Tiles[x + deltaX][y + deltaY].Element].Destructible
					and (Board.Tiles[x + deltaX][y + deltaY].Element <> E_PLAYER) then
				begin
					BoardDamageTile(x + deltaX, y + deltaY);
				end;

				if ElementDefs[Board.Tiles[x + deltaX][y + deltaY].Element].Walkable then
					ElementMove(x, y, x + deltaX, y + deltaY);
			end;
		end;
	end;

procedure ElementDuplicatorDraw(x, y: integer; var ch: byte);
	begin
		with Board.Stats[GetStatIdAt(x, y)] do
			case P1 of
				1: ch := 250;
				2: ch := 249;
				3: ch := 248;
				4: ch := 111;
				5: ch := 79;
			else ch := 250 end;
	end;

procedure ElementObjectTick(statId: integer);
	var
		retVal: boolean;
	begin
		with Board.Stats[statId] do begin
			if DataPos >= 0 then
				OopExecute(statId, DataPos, 'Interaction');

			if (StepX <> 0) or (StepY <> 0) then begin
				if ElementDefs[Board.Tiles[X + StepX][Y + StepY].Element].Walkable then
					MoveStat(statId, X + StepX, Y + StepY)
				else
					retVal := OopSend(-statId, 'THUD', false);
			end;
		end;
	end;

procedure ElementObjectDraw(x, y: integer; var ch: byte);
	begin
		ch := Board.Stats[GetStatIdAt(x, y)].P1;
	end;

procedure ElementObjectTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		statId: integer;
		retVal: boolean;
	begin
		statId := GetStatIdAt(x, y);
		retVal := OopSend(-statId, 'TOUCH', false);
	end;

procedure ElementDuplicatorTick(statId: integer);
	var
		sourceStatId: integer;
	begin
		with Board.Stats[statId] do begin
			if P1 <= 4 then begin
				Inc(P1);
			end else begin
				P1 := 0;
				with Board.Tiles[X - StepX][Y - StepY] do begin
					if Element = E_PLAYER then begin
						ElementDefs[Board.Tiles[X + StepX][Y + StepY].Element]
							.TouchProc(X + StepX, Y + StepY, 0, InputDeltaX, InputDeltaY);
					end else begin
						if Element <> E_EMPTY then
							ElementPushablePush(X - StepX, Y - StepY, -StepX, -StepY);

						if Element = E_EMPTY then begin
							sourceStatId := GetStatIdAt(X + StepX, Y + StepY);
							if sourceStatId > 0 then begin
								{ Below is always true }
								{ if Board.StatCount < (MAX_STAT + 24) then begin }
								with Board.Tiles[X + StepX][Y + StepY] do begin
									AddStat(X - StepX, Y - StepY,
										Element, Color,
										Board.Stats[sourceStatId].Cycle, Board.Stats[sourceStatId]);
									BoardDrawTile(X - StepX, Y - StepY);
								end;
							end else if sourceStatId <> 0 then begin
								Board.Tiles[X - StepX][Y - StepY]
									:= Board.Tiles[X + StepX][Y + StepY];
								BoardDrawTile(X - StepX, Y - StepY);
							end;

							SoundQueue(3, #48#2#50#2#52#2#53#2#55#2);
						end else begin
							SoundQueue(3, #24#1#22#1);
						end;
					end;
				end;

				P1 := 0;
			end;
			BoardDrawTile(X, Y);

			Cycle := (9 - P2) * 3;
		end;
	end;

procedure ElementScrollTick(statId: integer);
	begin
		with Board.Stats[statId] do begin
			with Board.Tiles[X][Y] do begin
				if Color >= 15 then
					Color := 9
				else
					Inc(Color);
			end;

			BoardDrawTile(X, Y);
		end;
	end;

procedure ElementScrollTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		textWindow: TTextWindowState;
		statId: integer;
		unk1: integer;
	begin
		statId := GetStatIdAt(x, y);
		if statId < 0 then begin
{$IFDEF DEBUGWND}
			if DebugCompatEnabled then
				DebugShowElementMessage('Illegal scroll touch', x, y);
{$ENDIF}
			exit;
		end;

		with Board.Stats[statId] do begin
			textWindow.Selectable := false;
			textWindow.LinePos := 1;

			SoundQueue(2, SoundParse('c-c+d-d+e-e+f-f+g-g'));

			DataPos := 0;
			OopExecute(statId, DataPos, 'Scroll');
		end;

		statId := GetStatIdAt(x, y);
		if statId <> -1 then begin
			RemoveStat(statId);
{$IFDEF DEBUGWND}
		end else begin
			if DebugCompatEnabled then
				DebugShowElementMessage('Illegal scroll deletion', x, y);
{$ENDIF}
		end;
	end;

procedure ElementKeyTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		key: integer;
	begin
		with Board.Tiles[x][y] do begin
			key := Color and 7;

			if World.Info.Keys[key] then begin
				DisplayMessage(200, 'You already have a '+ColorNames[key]+' key!');
				SoundQueue(2, #48#2#32#2);
			end else begin
				World.Info.Keys[key] := true;
				Element := E_EMPTY;
				GameUpdateSidebar;
				DisplayMessage(200, 'You now have the '+ColorNames[key]+' key.');
				SoundQueue(2, #64#1#68#1#71#1#64#1#68#1#71#1#64#1#68#1#71#1#80#2);
			end;
		end;
	end;

procedure ElementAmmoTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		Inc(World.Info.Ammo, 5);

		Board.Tiles[x][y].Element := E_EMPTY;
		GameUpdateSidebar;
		SoundQueue(2, #48#1#49#1#50#1);

		if MessageAmmoNotShown then begin
			MessageAmmoNotShown := false;
			DisplayMessage(200, 'Ammunition - 5 shots per container.');
		end;
	end;

procedure ElementGemTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		Inc(World.Info.Gems);
		Inc(World.Info.Health);
		Inc(World.Info.Score, 10);

		Board.Tiles[x][y].Element := E_EMPTY;
		GameUpdateSidebar;
		SoundQueue(2, #64#1#55#1#52#1#48#1);

		if MessageGemNotShown then begin
			MessageGemNotShown := false;
			DisplayMessage(200, 'Gems give you Health!');
		end;
	end;

procedure ElementPassageTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		BoardPassageTeleport(x, y);
		deltaX := 0;
		deltaY := 0;
	end;

procedure ElementDoorTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		key: integer;
	begin
		with Board.Tiles[x][y] do begin
			key := (Color shr 4) and 7;

			if World.Info.Keys[key] then begin
				Element := E_EMPTY;
				BoardDrawTile(x, y);

				World.Info.Keys[key] := false;
				GameUpdateSidebar;

				DisplayMessage(200, 'The '+ColorNames[key]+' door is now open.');
				SoundQueue(3, #48#1#55#1#59#1#48#1#55#1#59#1#64#4);
			end else begin
				DisplayMessage(200, 'The '+ColorNames[key]+' door is locked!');
				SoundQueue(3, #23#1#16#1);
			end;
		end;
	end;

procedure ElementPushableTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		ElementPushablePush(x, y, deltaX, deltaY);
		SoundQueue(2, #21#1);
	end;

procedure ElementPusherDraw(x, y: integer; var ch: byte);
	begin
		with Board.Stats[GetStatIdAt(x, y)] do begin
			if StepX = 1 then
				ch := 16
			else if StepX = -1 then
				ch := 17
			else if StepY = -1 then
				ch := 30
			else
				ch := 31;
		end;
	end;

procedure ElementPusherTick(statId: integer);
	var
		i, startX, startY: integer;
	begin
		with Board.Stats[statId] do begin
			startX := X;
			startY := Y;

			{ Microoptimization: X + StepX, but startX currently == X, etc. }
			if not ElementDefs[Board.Tiles[startX + StepX][startY + StepY].Element].Walkable then begin
				ElementPushablePush(startX + StepX, startY + StepY, StepX, StepY);
			end;
		end;

		statId := GetStatIdAt(startX, startY);
		with Board.Stats[statId] do begin
			if ElementDefs[Board.Tiles[X + StepX][Y + StepY].Element].Walkable then begin
				MoveStat(statId, X + StepX, Y + StepY);
				SoundQueue(2, #21#1);

				if Board.Tiles[X - (StepX * 2)][Y - (StepY * 2)].Element = E_PUSHER then begin
					i := GetStatIdAt(X - (StepX * 2), Y - (StepY * 2));
					if (Board.Stats[i].StepX = StepX) and (Board.Stats[i].StepY = StepY) then
						ElementPusherTick(i);
				end;
			end;
		end;
	end;

procedure ElementTorchTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		Inc(World.Info.Torches);
		Board.Tiles[x][y].Element := E_EMPTY;

		BoardDrawTile(x, y);
		GameUpdateSidebar;

		if MessageTorchNotShown then begin
			DisplayMessage(200, 'Torch - used for lighting in the underground.');
		end;
		MessageTorchNotShown := false;

		SoundQueue(3, #48#1#57#1#52#2);
	end;

procedure ElementInvisibleTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		with Board.Tiles[x][y] do begin
			Element := E_NORMAL;
			BoardDrawTile(x, y);

			SoundQueue(3, #18#1#16#1);
			DisplayMessage(100, 'You are blocked by an invisible wall.');
		end;
	end;

procedure ElementForestTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		Board.Tiles[x][y].Element := E_EMPTY;
		BoardDrawTile(x, y);

		SoundQueue(3, #57#1);

		if CleenMode then exit;
		if MessageForestNotShown then begin
			DisplayMessage(200, 'A path is cleared through the forest.');
		end;
		MessageForestNotShown := false;
	end;

procedure ElementFakeTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		if CleenMode then exit;
		if MessageFakeNotShown then begin
			DisplayMessage(150, 'A fake wall - secret passage!');
		end;
		MessageFakeNotShown := false;
	end;

procedure ElementBoardEdgeTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	var
		neighborId: integer;
		boardId: integer;
		entryX, entryY: integer;
	begin
		entryX := Board.Stats[0].X;
		entryY := Board.Stats[0].Y;
		if deltaY = -1 then begin
			neighborId := 0;
			entryY := BOARD_HEIGHT;
		end else if deltaY = 1 then begin
			neighborId := 1;
			entryY := 1;
		end else if deltaX = -1 then begin
			neighborId := 2;
			entryX := BOARD_WIDTH;
		end else begin
			neighborId := 3;
			entryX := 1;
		end;

		if Board.Info.NeighborBoards[neighborId] <> 0 then begin
			boardId := World.Info.CurrentBoard;
			BoardChange(Board.Info.NeighborBoards[neighborId]);
			with Board.Tiles[entryX][entryY] do begin
				if Element <> E_PLAYER then begin
					ElementDefs[Element].TouchProc(entryX, entryY, sourceStatId, InputDeltaX, InputDeltaY);
				end;

				if ElementDefs[Element].Walkable or (Element = E_PLAYER)
{$IFDEF EXTCHEAT}
				or (CheatNoClip and (Element <> E_BOARD_EDGE))
{$ENDIF}
				then begin
					if Element <> E_PLAYER then
						MoveStat(0, entryX, entryY);

					TransitionDrawBoardChange;
					deltaX := 0;
					deltaY := 0;
					BoardEnter;
				end else begin
					BoardChange(boardId);
				end;
			end;
		end;
	end;

procedure ElementWaterTouch(x, y: integer; sourceStatId: integer; var deltaX, deltaY: integer);
	begin
		if CleenMode then exit;
		SoundQueue(3, #64#1#80#1);
		DisplayMessage(100, 'Your way is blocked by water.');
	end;

procedure DrawPlayerSurroundings(x, y: integer; bombPhase: integer);
	var
		ix, iy: integer;
		istat: integer;
		result: boolean;
	begin
		for ix := ((x - TORCH_DX) - 1) to ((x + TORCH_DX) + 1) do
			if (ix >= 1) and (ix <= BOARD_WIDTH) then
				for iy := ((y - TORCH_DY) - 1) to ((y + TORCH_DY) + 1) do
					if (iy >= 1) and (iy <= BOARD_HEIGHT) then
						with Board.Tiles[ix][iy] do begin
							if (bombPhase > 0) and ((Sqr(ix-x) + Sqr(iy-y)*2) < TORCH_DIST_SQR) then begin
								if bombPhase = 1 then begin
									if Length(ElementDefs[Element].ParamTextName) <> 0 then begin
										istat := GetStatIdAt(ix, iy);
										if istat > 0 then
											result := OopSend(-istat, 'BOMBED', false);
									end;

									if ElementDefs[Element].Destructible or (Element = E_STAR) then
										BoardDamageTile(ix, iy);

									if (Element = E_EMPTY) or (Element = E_BREAKABLE) then begin
										Element := E_BREAKABLE;
										Color := $09 + ZRandom(7);
										{ BoardDrawTile(ix, iy); (duplicate) }
									end;
								end else begin
									if Element = E_BREAKABLE then
										Element := E_EMPTY;
								end;
							end;
							BoardDrawTile(ix, iy);
						end;
	end;

procedure GamePromptEndPlay;
	begin
		if World.Info.Health <= 0 then begin
			GamePlayExitRequested := true;
			BoardDrawBorder;
		end else begin
			GamePlayExitRequested := SidebarPromptYesNo('End this game? ', true);
			if InputKeyPressed = #27 then
				GamePlayExitRequested := false;
		end;
		InputKeyPressed := #0;
	end;

procedure ElementPlayerTick(statId: integer);
	var
		unk1, unk2, unk3: integer;
		i: integer;
		bulletCount: integer;
	begin
		GameControllerHasTicked := true;

		with Board.Stats[statId] do begin
			with Board.Tiles[X][Y] do begin
				if World.Info.EnergizerTicks > 0 then begin
					if ElementDefs[E_PLAYER].Character = #2 then
						ElementDefs[E_PLAYER].Character := #1
					else
						ElementDefs[E_PLAYER].Character := #2;

					if (CurrentTick and 1) <> 0 then
						Color := $0F
					else
						Color := ((CurrentTick mod 7) shl 4) + $1F;

					BoardDrawTile(X, Y);
				end else if (Color <> $1F) or (ElementDefs[E_PLAYER].Character <> #2) then begin
					Color := $1F;
					ElementDefs[E_PLAYER].Character := #2;
					BoardDrawTile(X, Y);
				end;
			end;

			if World.Info.Health <= 0 then begin
				InputDeltaX := 0;
				InputDeltaY := 0;
				InputShiftPressed := false;

				if GetStatIdAt(0,0) = -1 then
					DisplayMessage(32000, ' Game over  -  Press ESCAPE');

				TickTimeDuration := 0;
				SoundBlockQueueing := true;
			end;
			if InputShiftPressed or (InputKeyPressed = ' ') then begin
				if InputShiftPressed and ((InputDeltaX <> 0) or (InputDeltaY <> 0)) then begin
					PlayerDirX := InputDeltaX;
					PlayerDirY := InputDeltaY;
				end;

				if (PlayerDirX <> 0) or (PlayerDirY <> 0) then begin
					if Board.Info.MaxShots = 0 then begin
						if MessageNoShootingNotShown then
							DisplayMessage(200, 'Can'#39't shoot in this place!');
						MessageNoShootingNotShown := false;
					end else if World.Info.Ammo = 0 then begin
						if MessageOutOfAmmoNotShown then
							DisplayMessage(200, 'You don'#39't have any ammo!');
						MessageOutOfAmmoNotShown := false;
					end else begin
						bulletCount := 0;
						for i := 0 to Board.StatCount do
							with Board.Stats[i] do
								if (Board.Tiles[X][Y].Element = E_BULLET)
									and (P1 = SHOT_SOURCE_PLAYER)
								then
									Inc(bulletCount);

						if bulletCount < Board.Info.MaxShots then begin
							if BoardShoot(E_BULLET, X, Y, PlayerDirX, PlayerDirY, SHOT_SOURCE_PLAYER) then begin
								Dec(World.Info.Ammo);
								GameUpdateSidebar;

								SoundQueue(2, #64#1#48#1#32#1);

								InputDeltaX := 0;
								InputDeltaY := 0;
							end;
						end;
					end;
				end;
			end else if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
				PlayerDirX := InputDeltaX;
				PlayerDirY := InputDeltaY;

				ElementDefs[Board.Tiles[X + InputDeltaX][Y + InputDeltaY].Element].TouchProc(
					X + InputDeltaX, Y + InputDeltaY, 0, InputDeltaX, InputDeltaY);
				if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
{$IFDEF PLAYSTEP}
					if PlayerStepEnabled then
						if SoundEnabled and not SoundIsPlaying then
{$IFDEF SDL2}
							AudioSimPlayerStep := true;
{$ELSE}
							Sound(110);
{$ENDIF}
{$ENDIF}
					if (ElementDefs[Board.Tiles[X + InputDeltaX][Y + InputDeltaY].Element].Walkable)
{$IFDEF EXTCHEAT}
					or (CheatNoClip and (Board.Tiles[X + InputDeltaX][Y + InputDeltaY].Element <> E_BOARD_EDGE))
{$ENDIF}
					then begin
{$IFDEF PLAYSTEP}
{$IFNDEF SDL2}
						if PlayerStepEnabled then
							if SoundEnabled and not SoundIsPlaying then
								NoSound;
{$ENDIF}
{$ENDIF}

						MoveStat(0, X + InputDeltaX, Y + InputDeltaY);
{$IFDEF PLAYSTEP}
{$IFNDEF SDL2}
					end else if PlayerStepEnabled and SoundEnabled and not SoundIsPlaying then begin
						NoSound;
{$ENDIF}
{$ENDIF}
					end;
				end;
			end;

			case UpCase(InputKeyPressed) of
				'T': begin
					if World.Info.TorchTicks <= 0 then begin
						if World.Info.Torches > 0 then begin
							if Board.Info.IsDark then begin
								Dec(World.Info.Torches);
								World.Info.TorchTicks := TORCH_DURATION;

								DrawPlayerSurroundings(X, Y, 0);
								GameUpdateSidebar;
							end else begin
								if MessageRoomNotDarkNotShown then begin
									DisplayMessage(200, 'Don'#39't need torch - room is not dark!');
									MessageRoomNotDarkNotShown := false;
								end;
							end;
						end else begin
							if MessageOutOfTorchesNotShown then begin
								DisplayMessage(200, 'You don'#39't have any torches!');
								MessageOutOfTorchesNotShown := false;
							end;
						end;
					end;
				end;
				#27, 'Q': begin
					GamePromptEndPlay;
				end;
				'S': begin
					GameWorldSave('Save game:', SavedGameFileName, '.SAV');
				end;
				'P': begin
					if not NeuromotorAssist then begin
						if World.Info.Health > 0 then begin
							GamePaused := true;
						end;
					end;
				end;
				'B': begin
					SoundEnabled := not SoundEnabled;
					SoundClearQueue;
					GameUpdateSidebar;
					InputKeyPressed := ' ';
				end;
				'H': begin
					TextWindowDisplayFile('GAME.HLP', 'Playing ZZT');
				end;
{$IFDEF UISCBACK}
				'M': begin
					ScrollbackDisplay;
				end;
{$ENDIF}
				'?': begin
					GameDebugPrompt;
					InputKeyPressed := #0;
				end;
				'A': begin
					GameOptionsScreen(true);
					TransitionDrawToBoard;
				end;
			end;

			if World.Info.TorchTicks > 0 then begin
				Dec(World.Info.TorchTicks);
				if World.Info.TorchTicks <= 0 then begin
					DrawPlayerSurroundings(X, Y, 0);
					SoundQueue(3, #48#1#32#1#16#1);
				end;

				if (World.Info.TorchTicks mod 40) = 0 then
					GameUpdateSidebar;
			end;

			if World.Info.EnergizerTicks > 0 then begin
				Dec(World.Info.EnergizerTicks);

				if World.Info.EnergizerTicks = 10 then
					SoundQueue(9, #32#3#26#3#23#3#22#3#21#3#19#3#16#3)
				else if World.Info.EnergizerTicks <= 0 then begin
					Board.Tiles[X][Y].Color := ElementDefs[E_PLAYER].Color;
					BoardDrawTile(X, Y);
				end;
			end;

			if (Board.Info.TimeLimitSec > 0) and (World.Info.Health > 0) then
				if SoundHasTimeElapsed(World.Info.BoardTimeHsec, 100) then begin
					Inc(World.Info.BoardTimeSec);

					if (Board.Info.TimeLimitSec - 10) = World.Info.BoardTimeSec then begin
						DisplayMessage(200, 'Running out of time!');
						SoundQueue(3, #64#6#69#6#64#6#53#6#64#6#69#6#64#10);
					end else if World.Info.BoardTimeSec > Board.Info.TimeLimitSec then begin
						DamageStat(0);
					end;

					GameUpdateSidebar;
				end;
		end;
	end;

procedure ElementMonitorTick(statId: integer);
	begin
		GameControllerHasTicked := true;

		if UpCase(InputKeyPressed) in [#27, 'A', 'E', 'H', 'N', 'P', 'Q', 'R', 'S', 'W', '|'] then
			GamePlayExitRequested := true;
	end;

procedure ResetMessageNotShownFlags;
	begin
		MessageAmmoNotShown := true;
		MessageOutOfAmmoNotShown := true;
		MessageNoShootingNotShown := true;
		MessageTorchNotShown := true;
		MessageOutOfTorchesNotShown := true;
		MessageRoomNotDarkNotShown := true;
		MessageHintTorchNotShown := true;
		MessageForestNotShown := true;
		MessageFakeNotShown := true;
		MessageGemNotShown := true;
		MessageEnergizerNotShown := true;
	end;

procedure InitElementDefs;
	var
		i: integer;
	begin
		with ElementDefs[0] do begin
			Character := ' ';
			Color := COLOR_CHOICE_ON_BLACK;
			Destructible := false;
			Pushable := false;
			VisibleInDark := false;
			PlaceableOnTop := false;
			Walkable := false;
			HasDrawProc := false;
			Cycle := -1;
			TickProc := ElementDefaultTick;
			DrawProc := ElementDefaultDraw;
			TouchProc := ElementDefaultTouch;
			EditorCategory := 0;
			EditorShortcut := #0;
			Name := '';
			CategoryName := '';
			Param1Name := '';
			Param2Name := '';
			ParamBulletTypeName := '';
			ParamBoardName := '';
			ParamDirName := '';
			ParamTextName := '';
			ScoreValue := 0;
		end;
		for i := 1 to MAX_ELEMENT do
			ElementDefs[i] := ElementDefs[0];

		{ ElementDefs[0].Character := ' '; -- default }
		ElementDefs[0].Color := $70;
		ElementDefs[0].Pushable := true;
		ElementDefs[0].Walkable := true;
		ElementDefs[0].Name := 'Empty';

		{ ElementDefs[3].Character := ' '; -- default }
		ElementDefs[3].Color := $07;
		ElementDefs[3].Cycle := 1;
		ElementDefs[3].TickProc := ElementMonitorTick;
		ElementDefs[3].Name := 'Monitor';

		ElementDefs[19].Character := #176;
		ElementDefs[19].Color := $F9;
		ElementDefs[19].PlaceableOnTop := true;
		ElementDefs[19].TouchProc := ElementWaterTouch;
		ElementDefs[19].Name := 'Water';
		ElementDefs[19].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[19].EditorShortcut := 'W';
		ElementDefs[19].CategoryName := 'Terrains:';

		ElementDefs[20].Character := #176;
		ElementDefs[20].Color := $20;
		{ ElementDefs[20].Walkable := false; -- default }
		ElementDefs[20].TouchProc := ElementForestTouch;
		ElementDefs[20].Name := 'Forest';
		ElementDefs[20].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[20].EditorShortcut := 'F';

		ElementDefs[4].Character := #2;
		ElementDefs[4].Color := $1F;
		ElementDefs[4].Destructible := true;
		ElementDefs[4].Pushable := true;
		ElementDefs[4].VisibleInDark := true;
		ElementDefs[4].Cycle := 1;
		ElementDefs[4].TickProc := ElementPlayerTick;
		ElementDefs[4].Name := 'Player';
		ElementDefs[4].EditorCategory := CATEGORY_ITEM;
		ElementDefs[4].EditorShortcut := 'Z';
		ElementDefs[4].CategoryName := 'Items:';

		ElementDefs[41].Character := #234;
		ElementDefs[41].Color := $0C;
		ElementDefs[41].Destructible := true;
		ElementDefs[41].Pushable := true;
		ElementDefs[41].Cycle := 2;
		ElementDefs[41].TickProc := ElementLionTick;
		ElementDefs[41].TouchProc := ElementDamagingTouch;
		ElementDefs[41].Name := 'Lion';
		ElementDefs[41].ScoreValue := 1;
		ElementDefs[41].CategoryName := 'Beasts:';
		ElementDefs[41].Param1Name := 'Intelligence?';
		ElementDefs[41].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[41].EditorShortcut := 'L';

		ElementDefs[42].Character := #227;
		ElementDefs[42].Color := $0B;
		ElementDefs[42].Destructible := true;
		ElementDefs[42].Pushable := true;
		ElementDefs[42].Cycle := 2;
		ElementDefs[42].TickProc := ElementTigerTick;
		ElementDefs[42].TouchProc := ElementDamagingTouch;
		ElementDefs[42].Name := 'Tiger';
		ElementDefs[42].ScoreValue := 2;
		ElementDefs[42].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[42].EditorShortcut := 'T';
		ElementDefs[42].Param1Name := 'Intelligence?';
		ElementDefs[42].Param2Name := 'Firing rate?';
		ElementDefs[42].ParamBulletTypeName := 'Firing type?';

		ElementDefs[44].Character := #233;
		ElementDefs[44].Destructible := true;
		ElementDefs[44].Cycle := 2;
		ElementDefs[44].TickProc := ElementCentipedeHeadTick;
		ElementDefs[44].TouchProc := ElementDamagingTouch;
		ElementDefs[44].Name := 'Head';
		ElementDefs[44].ScoreValue := 1;
		ElementDefs[44].CategoryName := 'Centipedes';
		ElementDefs[44].Param1Name := 'Intelligence?';
		ElementDefs[44].Param2Name := 'Deviance?';
		ElementDefs[44].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[44].EditorShortcut := 'H';

		ElementDefs[45].Character := 'O';
		ElementDefs[45].Destructible := true;
		ElementDefs[45].Cycle := 2;
		ElementDefs[45].TickProc := ElementCentipedeSegmentTick;
		ElementDefs[45].TouchProc := ElementDamagingTouch;
		ElementDefs[45].Name := 'Segment';
		ElementDefs[45].ScoreValue := 3;
		ElementDefs[45].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[45].EditorShortcut := 'S';

		ElementDefs[18].Character := #248;
		ElementDefs[18].Color := $0F;
		ElementDefs[18].Destructible := true;
		ElementDefs[18].Cycle := 1;
		ElementDefs[18].TickProc := ElementBulletTick;
		ElementDefs[18].TouchProc := ElementDamagingTouch;
		ElementDefs[18].Name := 'Bullet';

		ElementDefs[15].Character := 'S';
		ElementDefs[15].Color := $0F;
		{ ElementDefs[15].Destructible := false; -- default }
		ElementDefs[15].Cycle := 1;
		ElementDefs[15].TickProc := ElementStarTick;
		ElementDefs[15].TouchProc := ElementDamagingTouch;
		ElementDefs[15].HasDrawProc := true;
		ElementDefs[15].DrawProc := ElementStarDraw;
		ElementDefs[15].Name := 'Star';

		ElementDefs[8].Character := #12;
		ElementDefs[8].Pushable := true;
		ElementDefs[8].TouchProc := ElementKeyTouch;
		ElementDefs[8].Name := 'Key';
		ElementDefs[8].EditorCategory := CATEGORY_ITEM;
		ElementDefs[8].EditorShortcut := 'K';

		ElementDefs[5].Character := #132;
		ElementDefs[5].Color := $03;
		ElementDefs[5].Pushable := true;
		ElementDefs[5].TouchProc := ElementAmmoTouch;
		ElementDefs[5].Name := 'Ammo';
		ElementDefs[5].EditorCategory := CATEGORY_ITEM;
		ElementDefs[5].EditorShortcut := 'A';

		ElementDefs[7].Character := #4;
		ElementDefs[7].Pushable := true;
		ElementDefs[7].TouchProc := ElementGemTouch;
		ElementDefs[7].Destructible := true;
		ElementDefs[7].Name := 'Gem';
		ElementDefs[7].EditorCategory := CATEGORY_ITEM;
		ElementDefs[7].EditorShortcut := 'G';

		ElementDefs[11].Character := #240;
		ElementDefs[11].Color := COLOR_WHITE_ON_CHOICE;
		ElementDefs[11].Cycle := 0;
		ElementDefs[11].VisibleInDark := true;
		ElementDefs[11].TouchProc := ElementPassageTouch;
		ElementDefs[11].Name := 'Passage';
		ElementDefs[11].ParamBoardName := 'Room thru passage?';
		ElementDefs[11].EditorCategory := CATEGORY_ITEM;
		ElementDefs[11].EditorShortcut := 'P';

		ElementDefs[9].Character := #10;
		ElementDefs[9].Color := COLOR_WHITE_ON_CHOICE;
		ElementDefs[9].TouchProc := ElementDoorTouch;
		ElementDefs[9].Name := 'Door';
		ElementDefs[9].EditorCategory := CATEGORY_ITEM;
		ElementDefs[9].EditorShortcut := 'D';

		ElementDefs[10].Character := #232;
		ElementDefs[10].Color := $0F;
		ElementDefs[10].TouchProc := ElementScrollTouch;
		ElementDefs[10].TickProc := ElementScrollTick;
		ElementDefs[10].Pushable := true;
		ElementDefs[10].Cycle := 1;
		ElementDefs[10].Name := 'Scroll';
		ElementDefs[10].EditorCategory := CATEGORY_ITEM;
		ElementDefs[10].EditorShortcut := 'S';
		ElementDefs[10].ParamTextName := 'Edit text of scroll';

		ElementDefs[12].Character := #250;
		ElementDefs[12].Color := $0F;
		ElementDefs[12].Cycle := 2;
		ElementDefs[12].TickProc := ElementDuplicatorTick;
		ElementDefs[12].HasDrawProc := true;
		ElementDefs[12].DrawProc := ElementDuplicatorDraw;
		ElementDefs[12].Name := 'Duplicator';
		ElementDefs[12].EditorCategory := CATEGORY_ITEM;
		ElementDefs[12].EditorShortcut := 'U';
		ElementDefs[12].ParamDirName := 'Source direction?';
		ElementDefs[12].Param2Name := 'Duplication rate?;SF';

		ElementDefs[6].Character := #157;
		ElementDefs[6].Color := $06;
		ElementDefs[6].VisibleInDark := true;
		ElementDefs[6].TouchProc := ElementTorchTouch;
		ElementDefs[6].Name := 'Torch';
		ElementDefs[6].EditorCategory := CATEGORY_ITEM;
		ElementDefs[6].EditorShortcut := 'T';

		ElementDefs[39].Character := #24;
		ElementDefs[39].Cycle := 2;
		ElementDefs[39].TickProc := ElementSpinningGunTick;
		ElementDefs[39].HasDrawProc := true;
		ElementDefs[39].DrawProc := ElementSpinningGunDraw;
		ElementDefs[39].Name := 'Spinning gun';
		ElementDefs[39].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[39].EditorShortcut := 'G';
		ElementDefs[39].Param1Name := 'Intelligence?';
		ElementDefs[39].Param2Name := 'Firing rate?';
		ElementDefs[39].ParamBulletTypeName := 'Firing type?';

		ElementDefs[35].Character := #5;
		ElementDefs[35].Color := $0D;
		ElementDefs[35].Destructible := true;
		ElementDefs[35].Pushable := true;
		ElementDefs[35].Cycle := 1;
		ElementDefs[35].TickProc := ElementRuffianTick;
		ElementDefs[35].TouchProc := ElementDamagingTouch;
		ElementDefs[35].Name := 'Ruffian';
		ElementDefs[35].ScoreValue := 2;
		ElementDefs[35].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[35].EditorShortcut := 'R';
		ElementDefs[35].Param1Name := 'Intelligence?';
		ElementDefs[35].Param2Name := 'Resting time?';

		ElementDefs[34].Character := #153;
		ElementDefs[34].Color := $06;
		ElementDefs[34].Destructible := true;
		ElementDefs[34].Pushable := true;
		ElementDefs[34].Cycle := 3;
		ElementDefs[34].TickProc := ElementBearTick;
		ElementDefs[34].TouchProc := ElementDamagingTouch;
		ElementDefs[34].Name := 'Bear';
		ElementDefs[34].ScoreValue := 1;
		ElementDefs[34].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[34].EditorShortcut := 'B';
		ElementDefs[34].CategoryName := 'Creatures:';
		ElementDefs[34].Param1Name := 'Sensitivity?';

		ElementDefs[37].Character := '*';
		{ ElementDefs[37].Color := COLOR_CHOICE_ON_BLACK; -- default }
		{ ElementDefs[37].Destructible := false; -- default }
		ElementDefs[37].Cycle := 3;
		ElementDefs[37].TickProc := ElementSlimeTick;
		ElementDefs[37].TouchProc := ElementSlimeTouch;
		ElementDefs[37].Name := 'Slime';
		ElementDefs[37].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[37].EditorShortcut := 'V';
		ElementDefs[37].Param2Name := 'Movement speed?;FS';

		ElementDefs[38].Character := '^';
		ElementDefs[38].Color := $07;
		{ ElementDefs[38].Destructible := false; -- default }
		ElementDefs[38].Cycle := 3;
		ElementDefs[38].TickProc := ElementSharkTick;
		ElementDefs[38].Name := 'Shark';
		ElementDefs[38].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[38].EditorShortcut := 'Y';
		ElementDefs[38].Param1Name := 'Intelligence?';

		ElementDefs[16].Character := '/';
		ElementDefs[16].Cycle := 3;
		ElementDefs[16].HasDrawProc := true;
		ElementDefs[16].TickProc := ElementConveyorCWTick;
		ElementDefs[16].DrawProc := ElementConveyorCWDraw;
		ElementDefs[16].Name := 'Clockwise';
		ElementDefs[16].EditorCategory := CATEGORY_ITEM;
		ElementDefs[16].EditorShortcut := '1';
		ElementDefs[16].CategoryName := 'Conveyors:';

		ElementDefs[17].Character := '\';
		ElementDefs[17].Cycle := 2;
		ElementDefs[17].HasDrawProc := true;
		ElementDefs[17].DrawProc := ElementConveyorCCWDraw;
		ElementDefs[17].TickProc := ElementConveyorCCWTick;
		ElementDefs[17].Name := 'Counter';
		ElementDefs[17].EditorCategory := CATEGORY_ITEM;
		ElementDefs[17].EditorShortcut := '2';

		ElementDefs[21].Character := #219;
		ElementDefs[21].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[21].CategoryName := 'Walls:';
		ElementDefs[21].EditorShortcut := 'S';
		ElementDefs[21].Name := 'Solid';

		ElementDefs[22].Character := #178;
		ElementDefs[22].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[22].EditorShortcut := 'N';
		ElementDefs[22].Name := 'Normal';

		ElementDefs[31].Character := #206;
		ElementDefs[31].HasDrawProc := true;
		ElementDefs[31].DrawProc := ElementLineDraw;
		ElementDefs[31].Name := 'Line';

		ElementDefs[43].Character := #186;

		ElementDefs[33].Character := #205;

		ElementDefs[32].Character := '*';
		ElementDefs[32].Color := $0A;
		ElementDefs[32].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[32].EditorShortcut := 'R';
		ElementDefs[32].Name := 'Ricochet';

		ElementDefs[23].Character := #177;
		{ ElementDefs[23].Destructible := false; -- default }
		ElementDefs[23].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[23].EditorShortcut := 'B';
		ElementDefs[23].Name := 'Breakable';

		ElementDefs[24].Character := #254;
		ElementDefs[24].Pushable := true;
		ElementDefs[24].TouchProc := ElementPushableTouch;
		ElementDefs[24].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[24].EditorShortcut := 'O';
		ElementDefs[24].Name := 'Boulder';

		ElementDefs[25].Character := #18;
		ElementDefs[25].TouchProc := ElementPushableTouch;
		ElementDefs[25].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[25].EditorShortcut := '1';
		ElementDefs[25].Name := 'Slider (NS)';

		ElementDefs[26].Character := #29;
		ElementDefs[26].TouchProc := ElementPushableTouch;
		ElementDefs[26].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[26].EditorShortcut := '2';
		ElementDefs[26].Name := 'Slider (EW)';

		ElementDefs[30].Character := #197;
		ElementDefs[30].TouchProc := ElementTransporterTouch;
		ElementDefs[30].HasDrawProc := true;
		ElementDefs[30].DrawProc := ElementTransporterDraw;
		ElementDefs[30].Cycle := 2;
		ElementDefs[30].TickProc := ElementTransporterTick;
		ElementDefs[30].Name := 'Transporter';
		ElementDefs[30].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[30].EditorShortcut := 'T';
		ElementDefs[30].ParamDirName := 'Direction?';

		ElementDefs[40].Character := #16;
		{ ElementDefs[40].Color := COLOR_CHOICE_ON_BLACK; -- default }
		ElementDefs[40].HasDrawProc := true;
		ElementDefs[40].DrawProc := ElementPusherDraw;
		ElementDefs[40].Cycle := 4;
		ElementDefs[40].TickProc := ElementPusherTick;
		ElementDefs[40].Name := 'Pusher';
		ElementDefs[40].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[40].EditorShortcut := 'P';
		ElementDefs[40].ParamDirName := 'Push direction?';

		ElementDefs[13].Character := #11;
		ElementDefs[13].HasDrawProc := true;
		ElementDefs[13].DrawProc := ElementBombDraw;
		ElementDefs[13].Pushable := true;
		ElementDefs[13].Cycle := 6;
		ElementDefs[13].TickProc := ElementBombTick;
		ElementDefs[13].TouchProc := ElementBombTouch;
		ElementDefs[13].EditorCategory := CATEGORY_ITEM;
		ElementDefs[13].EditorShortcut := 'B';
		ElementDefs[13].Name := 'Bomb';

		ElementDefs[14].Character := #127;
		ElementDefs[14].Color := $05;
		ElementDefs[14].TouchProc := ElementEnergizerTouch;
		ElementDefs[14].EditorCategory := CATEGORY_ITEM;
		ElementDefs[14].EditorShortcut := 'E';
		ElementDefs[14].Name := 'Energizer';

		ElementDefs[29].Character := #206;
		ElementDefs[29].Cycle := 1;
		ElementDefs[29].TickProc := ElementBlinkWallTick;
		ElementDefs[29].HasDrawProc := true;
		ElementDefs[29].DrawProc := ElementBlinkWallDraw;
		ElementDefs[29].Name := 'Blink wall';
		ElementDefs[29].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[29].EditorShortcut := 'L';
		ElementDefs[29].Param1Name := 'Starting time';
		ElementDefs[29].Param2Name := 'Period';
		ElementDefs[29].ParamDirName := 'Wall direction';

		ElementDefs[27].Character := #178;
		ElementDefs[27].PlaceableOnTop := true;
		ElementDefs[27].Walkable := true;
		ElementDefs[27].TouchProc := ElementFakeTouch;
		ElementDefs[27].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[27].EditorShortcut := 'A';
		ElementDefs[27].Name := 'Fake';

		{ ElementDefs[28].Character := ' '; -- default }
		ElementDefs[28].EditorCategory := CATEGORY_TERRAIN;
		ElementDefs[28].EditorShortcut := 'I';
		ElementDefs[28].TouchProc := ElementInvisibleTouch;
		ElementDefs[28].Name := 'Invisible';

		ElementDefs[36].Character := #2;
		ElementDefs[36].Cycle := 3;
		ElementDefs[36].HasDrawProc := true;
		ElementDefs[36].DrawProc := ElementObjectDraw;
		ElementDefs[36].TickProc := ElementObjectTick;
		ElementDefs[36].TouchProc := ElementObjectTouch;
		ElementDefs[36].Name := 'Object';
		ElementDefs[36].EditorCategory := CATEGORY_CREATURE;
		ElementDefs[36].EditorShortcut := 'O';
		ElementDefs[36].Param1Name := 'Character?';
		ElementDefs[36].ParamTextName := 'Edit Program';

		ElementDefs[2].TickProc := ElementMessageTimerTick;

		ElementDefs[1].TouchProc := ElementBoardEdgeTouch;

{$IFDEF EDITOR}
		EditorPatterns[1] := E_SOLID;
		EditorPatterns[2] := E_NORMAL;
		EditorPatterns[3] := E_BREAKABLE;
		EditorPatterns[4] := E_WATER;
		EditorPatterns[5] := E_EMPTY;
		EditorPatterns[6] := E_LINE;
{$ENDIF}

{$IFDEF EXTCHEAT}
		for i := 0 to MAX_ELEMENT do begin
			CheatColorModifiers[i] := 0;
			CheatCharModifiers[i] := ElementDefs[i].Character;
		end;
		CheatCharModifiers[E_BOARD_EDGE] := 'E';
		CheatCharModifiers[E_INVISIBLE] := #176;
		CheatCharModifiers[E_FAKE] := #178;
{$ENDIF}
	end;

procedure InitElementsEditor;
	begin
		InitElementDefs;

		ElementDefs[28].Character := #176;
		ElementDefs[28].Color := COLOR_CHOICE_ON_BLACK;

		ElementDefs[1].Character := 'E';
		ElementDefs[1].Color := COLOR_CHOICE_ON_BLACK;

		ElementDefs[E_BULLET].ParamDirName := 'Direction?';
		ElementDefs[44].CategoryName := 'Centipedes:';

		ForceDarknessOff := true;
	end;

procedure InitElementsGame;
	begin
		InitElementDefs;
		ForceDarknessOff := false;
	end;

procedure InitEditorStatSettings;
	var
		i: integer;
	begin
		PlayerDirX := 0;
		PlayerDirY := 0;

		for i := 0 to MAX_ELEMENT do
			with World.EditorStatSettings[i] do begin
				P1 := 4;
				P2 := 4;
				P3 := 0;
				StepX := 0;
				StepY := -1;
			end;

		World.EditorStatSettings[E_OBJECT].P1 := 1;
		World.EditorStatSettings[E_BEAR].P1 := 8;
	end;

end.
