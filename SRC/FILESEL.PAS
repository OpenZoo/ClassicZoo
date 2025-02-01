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
{$V-}
unit FileSel;

interface
	uses GameVars;
	function FileReadAll(name: TFilenameString; var fdata: pointer; maxSize: word): word;
	function FileSelect(title, extension: TString50; var cachedLinePos: integer): TFilenameString;

{$IFDEF FPC}
{$IFNDEF MSDOS}
{$DEFINE ADVFILES}
{$ENDIF}
{$ENDIF}

implementation
uses
{$IFDEF ADVFILES}
StrUtils, SysUtils,
{$ELSE}
Dos,
{$ENDIF}
Game, ZInput, TxtWind, FileOps, FileSys;

const
	PATH_PREVIEW_LENGTH = 24;
	MAX_FILENAME_LENGTH = 42; { TODO: Increase. }

function FileReadAll(name: TFilenameString; var fdata: pointer; maxSize: word): word;
	var
		f: file;
		fsize: longint;
		bsize: word;
	begin
		bsize := 0;

		AssignFSys(f, name);
		Reset(f, 1);
		if IOResult = 0 then begin
			fsize := FileSize(f);
			bsize := maxSize;
			if (fsize < bsize) then bsize := fsize;
			if bsize > 0 then begin
				GetMem(fdata, bsize);
				BlockRead(f, fdata^, bsize);
			end;
			Close(f);
		end;

		FileReadAll := bsize;
	end;

function FileSelect(title, extension: TString50; var cachedLinePos: integer): TFilenameString;
	var
		textWindow: TTextWindowState;
{$IFDEF ADVFILES}
		fileSearchRec: TRawbyteSearchRec;
		multiExtension: boolean;
		extensionTemp: TString50;
{$ELSE}
		fileSearchRec: SearchRec;
{$ENDIF}
		entryName: TFilenameString;
		entryNameCropped: TFilenameString;
		searching: boolean;
		i, iSortStart: integer;
		startLinePos: integer;
{$IFNDEF NODIRS}
		lastDirLinePos: integer;
		startPath: TFilenameString;
{$ENDIF}
		curPath: TFilenameString;
		previewPath: string[PATH_PREVIEW_LENGTH + 4];
	begin
		searching := true;
{$IFDEF ADVFILES}
		multiExtension := ANSIContainsText(extension, ';');
{$ENDIF}
{$IFNDEF NODIRS}
		GetDir(0, startPath);
{$ENDIF}
		startLinePos := cachedLinePos;

		TextWindowInitState(textWindow);
		textWindow.Title := '';
		TextWindowDrawOpen(textWindow);

		while searching do begin
			TextWindowInitState(textWindow);
{$IFNDEF NODIRS}
			GetDir(0, curPath);

			i := PATH_PREVIEW_LENGTH;
			if (42 - 4 - Length(title)) < i then
				i := 42 - 4 - Length(title);
			if Length(curPath) > i then
				previewPath := '...' + Copy(curPath, Length(curPath) - i + 1, i)
			else
				previewPath := curPath;
			textWindow.Title := title + ': ' + previewPath;
{$ELSE}
			textWindow.Title := title;
{$ENDIF}
			textWindow.Selectable := true;
			textWIndow.Hyperlink := '';


{$IFDEF ADVFILES}
{$IFNDEF NODIRS}
			{ .. }
			if ExpandFileName(curPath) <> ExpandFileName(IncludeTrailingPathDelimiter(curPath) + '..') then
				TextWindowAppend(textWindow, '!..;[..]');
			iSortStart := textWindow.LineCount + 1;

			{ Directories }
			FindFirst('*', faDirectory, fileSearchRec);
			repeat
				if (fileSearchRec.Attr and faDirectory) <> 0 then begin
					entryName := fileSearchRec.Name;
					if Length(entryName) <= MAX_FILENAME_LENGTH then
						if (Length(entryName) > 0) and (entryName <> '.') and (entryName <> '..') then begin
							entryNameCropped := entryName;
							if Length(entryNameCropped) > 32 then
								entryNameCropped := Copy(entryNameCropped, 1, 29) + '...';
							TextWindowAppend(textWindow, '!' + entryName + ';[' + entryNameCropped + ']');
						end;
				end;
			until FindNext(fileSearchRec) <> 0;
			FindClose(fileSearchRec);

			lastDirLinePos := textWindow.LineCount;
{$ENDIF}

			{ Files }
			FindFirst('*', faAnyFile, fileSearchRec);
			repeat
				if ((fileSearchRec.Attr and faDirectory) = 0) then begin
					entryName := '';
					if multiExtension then begin
						i := 1;
						repeat
							extensionTemp := ExtractDelimited(i, extension, [';']);
							if extensionTemp = '' then break;
							if UpCase(Copy(fileSearchRec.Name,
								Length(fileSearchRec.name) - Length(extensionTemp) + 1,
								Length(extensionTemp))) = extensionTemp then begin
								entryName := fileSearchRec.name;
								break;
							end;
							Inc(i);
						until 1 <> 1;
					end else begin
						if UpCase(Copy(fileSearchRec.Name,
							Length(fileSearchRec.name) - Length(extension) + 1,
							Length(extension))) = extension then begin
							entryName := Copy(fileSearchRec.Name, 1, Length(fileSearchRec.name) - Length(extension));
						end;
					end;

					if (Length(entryName) > 0) and (Length(entryName) <= MAX_FILENAME_LENGTH) then
						TextWindowAppend(textWindow, entryName);
				end;
			until FindNext(fileSearchRec) <> 0;
			FindClose(fileSearchRec);
{$ELSE}
{$IFNDEF NODIRS}
			{ .. }
			if Length(curPath) > 3 then
				TextWindowAppend(textWindow, '!..;[..]');
			iSortStart := textWindow.LineCount + 1;

			{ Directories }
			FindFirst('*', Directory, fileSearchRec);
			while DosError = 0 do begin
				if (fileSearchRec.Attr and Directory) <> 0 then begin
					entryName := fileSearchRec.Name;
					if Length(entryName) <= MAX_FILENAME_LENGTH then
						if (Length(entryName) > 0) and (entryName <> '.') and (entryName <> '..') then begin
							entryNameCropped := entryName;
							if Length(entryNameCropped) > 32 then
								entryNameCropped := Copy(entryNameCropped, 1, 29) + '...';
							TextWindowAppend(textWindow, '!' + entryName + ';[' + entryNameCropped + ']');
						end;
				end;
				FindNext(fileSearchRec);
			end;

			lastDirLinePos := textWindow.LineCount;
{$ENDIF}

			{ Files }
			FindFirst('*' + extension, AnyFile, fileSearchRec);
			while DosError = 0 do begin
				if (fileSearchRec.Attr and Directory) = 0 then begin
					entryName := Copy(fileSearchRec.Name, 1, Length(fileSearchRec.name) - Length(extension));

					if Length(entryName) <= MAX_FILENAME_LENGTH then
						TextWindowAppend(textWindow, entryName);
				end;
				FindNext(fileSearchRec);
			end;
{$ENDIF}

			textWindow.LinePos := cachedLinePos;

			TextWindowSort(textWindow, iSortStart, textWindow.LineCount);
			TextWindowAppend(textWindow, 'Exit');

			TextWindowSelect(textWindow, TWS_HYPERLINK_AS_SELECT or TWS_LONG_HYPERLINKS);
			InputKeyPressed := #0;

			if (textWindow.LinePos = textWindow.LineCount) or TextWindowRejected then begin
				{ Exit }
				FileSelect := '';
				searching := false;
				cachedLinePos := startLinePos;
{$IFNDEF NODIRS}
				ChDir(startPath);
			end else if textWindow.LinePos <= lastDirLinePos then begin
				{ Directory }
				ChDir(textWindow.Hyperlink);
				cachedLinePos := 1;
{$ENDIF}
			end else begin
				{ File }
				entryName := textWindow.Lines[textWindow.LinePos]^;
				FileSelect := entryName;
				searching := false;

{$IFNDEF NODIRS}
				if startPath <> curPath then
					ResetCachedLinePos;
				cachedLinePos := textWindow.LinePos;
{$ENDIF}
			end;

			TextWindowFree(textWindow);

			{ Clear IOResult }
			if IOResult <> 0 then begin end;
		end;

		TextWindowInitState(textWindow);
		TextWindowDrawClose(textWindow);
		TextWindowFree(textWindow);
	end;

end.
