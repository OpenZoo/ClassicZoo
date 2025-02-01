{
	Copyright (c) 2024 Kristofer Munsterhjelm

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
	Fileops contains a number of file operations used for handling ZZT demo
	files.
}

{$I-}
{$V-}
unit FileOps;

interface
	{ Copy an already open file. }
	procedure CopyOpenFile(var fromFile: file; toFilename, toExt: string);
	{ Copy a file that isn't open. }
	procedure CopyFile(fromFilename, fromExt, toFilename, toExt: string);

	function FileExists(fullFileName: string): boolean;
	function GetNumberedFilename(origFilename, origExtension: string;
		maxNumber: integer): string;

implementation
uses Dos;

const COPY_BUFFER_SIZE = 1024;
var CopyBuffer: array[1 .. COPY_BUFFER_SIZE] of byte;

{ Copies the whole fromFile to a new to file. }
procedure CopyOpenFile(var fromFile: file; toFilename: string; toExt: string);
	var
		toFile: file;
		bytesRead, bytesWritten: integer;
		OK: boolean;
		currentPos: longint;
		byteArray : array[1..8] of byte;
	begin
		Assign(toFile, toFilename + toExt);
		Rewrite(toFile, 1);

		OK := (IOResult = 0);
		if not OK then Exit;	{ Couldn't open destination file. }

		{ Get current position (which is usually the end of the file). 
		  Does TP support files > 65K? I don't know. }
		currentPos := FilePos(fromFile);
		Seek(fromFile, 0);

		while OK and not Eof(fromFile) do
		begin
			BlockRead(fromFile, CopyBuffer, COPY_BUFFER_SIZE, bytesRead);
			BlockWrite(toFile, CopyBuffer, bytesRead, bytesWritten);
			OK := (IOResult = 0);
		end;
		Close(toFile);

		Seek(fromFile, currentPos);
	end;

procedure CopyFile(fromFilename, fromExt, toFilename, toExt: string);
	var
		fromFile: file;
	begin
		Assign(fromFile, fromFilename + fromExt);
		Reset(fromFile, 1);

		if IOResult = 0 then
			CopyOpenFile(fromFile, toFilename, toExt);

		Close(fromFile);
	end;

{ Boolean function that returns True if the file exists;
 	otherwise, it returns False. Closes the file if it exists.
 	From the TP 5.5 reference manual. }
function FileExists(fullFileName: string): boolean;
	var
		f: file;
	begin
	{SI-}
		Assign(f, fullFileName);
		Reset (f);
		Close (f);
	{SI+}
		FileExists := (IOResult = 0) and (fullFileName <> '');
	end; {FileExists}

{ Given an original file like FOOBAR.BAZ, repeatedly adds a number to it,
  producing FOOBAR1, FOOBAR2, etc. until it finds a file that doesn't exist.
  If the filename ends in a number, this number is stripped first, and the
  name is also truncated so it and the number will fit in eight letters (due
  to DOS' 8.3 filename limit).
  This is used for creating consecutive demo names when resuming a demo
  recording after restoring a savegame.
  Note that this function only returns the actual filename, not the
  extension. The input extension is only used as part of the file
  extension checking.
  It returns an empty string if no suitable file was found.
}
function GetNumberedFilename(origFilename, origExtension: string;
	maxNumber: integer): string;
	var
		i: integer;
		numStr: string[6];
		proposed: string;
	begin
		{ First check whether the original file exists. If not,
		  return it. }
		if not FileExists(origFilename + origExtension) then begin
			GetNumberedFilename := origFilename;
			Exit;
		end;

		for i := 1 to maxNumber do begin
			Str(i, numStr);
			proposed := copy(origFilename, 1,
				8-Length(numStr)) + numStr;
			if not FileExists(proposed + origExtension) then begin
				GetNumberedFilename := proposed;
				Exit;
			end;
		end;

		GetNumberedFilename := '';
	end;
end.