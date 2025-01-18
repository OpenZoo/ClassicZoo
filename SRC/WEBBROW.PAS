{
	Copyright (c) 2022 Adrian Siekierka

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
{$MODE OBJFPC}
unit WebBrow{ser};

interface
	uses GameVars;
	procedure WebBrowserLoop;

implementation
uses
StrUtils, SysUtils, Classes,
FPHttpClient, OpenSSLSockets,
FPJson, JsonParser, Zipper,
TxtWind, Game, ZVideo, Sidebar;

type
	TMuseumSearchQuery = record
		Title: string;
		Author: string;
		Company: string;
		Genre: string;
		Year: integer;
		Offset: integer;
		Sort: string;
	end;
	TWebUnzipper = class(TUnzipper)
	private
		WebPath: string;
		WebClient: TFPHttpClient;
		WebStream: TMemoryStream;
		procedure WebOpenStream(Sender: TObject; var AStream: TStream);
		procedure WebCloseStream(Sender: TObject; var AStream: TStream);
	public
		constructor Create(path: string);
		destructor Destroy;
	end;
const
	SEARCH_RESULT_SIZE = 25;
{$IFDEF E_ZZT}
	ENGINE_DETAIL_CODE = 15;
	ENGINE_EXTENSION = '.ZZT';
{$ENDIF}
{$IFDEF E_SUPERZ}
	ENGINE_DETAIL_CODE = 13;
	ENGINE_EXTENSION = '.SZT';
{$ENDIF}
var
	startingPath: string;

constructor TWebUnzipper.Create(path: string);
begin
	Inherited Create;

	WebPath := path;
	OnOpenInputStream := @WebOpenStream;
	OnCloseInputStream := @WebCloseStream;

	WebClient := TFPHttpClient.Create(nil);
	WebStream := TMemoryStream.Create;
	try
		WebClient.AllowRedirect := true;
		WebClient.Get(WebPath, WebStream);
	finally
		WebClient.Free;
	end;
end;

destructor TWebUnzipper.Destroy;
begin
	FreeAndNil(WebStream);
	Inherited;
end;

procedure TWebUnzipper.WebOpenStream(Sender: TObject; var AStream: TStream);
begin
	WebStream.Seek(0, soBeginning);
	AStream := WebStream;
end;

procedure TWebUnzipper.WebCloseStream(Sender: TObject; var ASTream: TStream);
begin
	AStream := Nil;
end;

procedure ShowStatusMessage(msg: string);
begin
	SidebarClearLine(4);
	if Length(msg) > 0 then
		VideoWriteText(VideoSidebarX + 2, 4, $1E, msg);
end;

function QueryEncode(s: string): string;
var
	i: integer;
begin
	result := '';
	for i := 1 to Length(s) do begin
		if not (s[i] in ['A'..'Z', 'a'..'z', '0'..'9']) then
			result := result + '%' + IntToHex(Ord(s[i]), 2)
		else
			result := result + s[i];
	end;
end;

function DownloadZipFile(path: string; var unz: TUnzipper): boolean;
begin
	DownloadZIpFile := false;
	ShowStatusMessage('Downloading...');

	unz := TWebUnzipper.Create(path);
	try
		unz.Examine;
	finally
	end;

	ShowStatusMessage('');
	DownloadZipFile := true;
end;

function DownloadMuseumZipFile(letter, filename: string; var unz: TUnzipper): boolean;
begin
	DownloadMuseumZipFile := DownloadZipFile('https://museumofzzt.com/zgames/' + letter + '/' + filename, unz);
end;

function CallMuseumApi(path: string; var jsonData: TJSONObject): boolean;
var
	data: UTF8String;
begin
	CallMuseumApi := false;
	ShowStatusMessage('Connecting...');

	with TFPHttpClient.Create(Nil) do
		try
			AllowRedirect := true;
			data := Get('https://museumofzzt.com/' + path);
			jsonData := GetJSON(data) as TJSONObject;
			CallMuseumApi := jsonData.Get('status') = 'SUCCESS';
		finally
			Free;
		end;

	ShowStatusMessage('');
end;

function CallMuseumSearch(var query: TMuseumSearchQuery; var jsonData: TJSONObject): boolean;
var
	path: string;
	queryChar: char;
procedure AppendQuery(key, value: string);
	begin
		path := path + queryChar + key + '=' + QueryEncode(value);
		queryChar := '&';
	end;
begin
	path := 'api/v1/search/files/';
	queryChar := '?';

	if Length(query.Title) > 0 then AppendQuery('title', query.Title);
	if Length(query.Author) > 0 then AppendQuery('author', query.Author);
	if Length(query.Company) > 0 then AppendQuery('company', query.Company);
	if Length(query.Genre) > 0 then AppendQuery('genre', query.Genre);
	if query.Year > 1990 then AppendQuery('year', IntToStr(query.Year));
	if query.Offset > 0 then AppendQuery('offset', IntToStr(query.Offset));
	if Length(query.Sort) > 0 then AppendQuery('sort', query.Sort);

	CallMuseumSearch := CallMuseumAPI(path, jsonData);
end;

function WebBrowserLoadZipFile(letter, museumFilename: string): boolean;
var
	i: Int32;
	unz: TUnzipper;
{	textWindow: TTextWindowState;
	filename: string;
	filenameShort: string; }
	choiceResult: byte;
	zztEntryCount: integer;
	zztEntryFilename: string;
begin
	WebBrowserLoadZipFile := false;
	try
		if not DownloadMuseumZipFile(letter, museumFilename, unz) then exit;
	except
		exit
	end;

	zztEntryCount := 0;
	for i := 0 to (unz.Entries.Count - 1) do with unz.Entries.Entries[i] do begin
		if EndsText(ENGINE_EXTENSION, ArchiveFilename) then begin
			Inc(zztEntryCount);
			zztEntryFilename := ArchiveFilename;
		end;
	end;

	if zztEntryCount <= 0 then begin
		ShowStatusMessage('No file found!');
		exit;
	end;

	ShowStatusMessage('Unpacking...');

	if unz.Entries.Count > 1 then begin
		CreateDir(ChangeFileExt(museumFilename, ''));
		ChDir(ChangeFileExt(museumFilename, ''));
	end;

	choiceResult := 1;
	for i := 0 to (unz.Entries.Count - 1) do with unz.Entries.Entries[i] do begin
		if FileExists(ArchiveFilename) and (choiceResult = 1) then begin
			SidebarPromptChoice(true, 3, 'Overwrite?', 'Yes No', choiceResult);
			SidebarClearLine(3);
			SidebarClearLine(4);
			SidebarClearLine(5);
			if choiceResult = 1 then begin
				ChDir('..');
				exit;
			end;
		end;
		unz.UnZipFile(ArchiveFilename, ArchiveFilename);
	end;

	ShowStatusMessage('');

	if zztEntryCount {$IFDEF E_SUPERZ}>={$ELSE}>{$ENDIF} 1 then begin
		if GameWorldLoad(ENGINE_EXTENSION) then begin
			ReturnBoardId := World.Info.CurrentBoard;
			BoardChange(0);
			WebBrowserLoadZipFile := true;
		end;
	end else begin
		if WorldLoad(zztEntryFilename, '', false) then begin
			ReturnBoardId := World.Info.CurrentBoard;
			BoardChange(0);
			WebBrowserLoadZipFile := true;
		end else begin
			WorldCreate;
			ShowStatusMessage('World load error!');
			PauseOnError;
		end;
	end;

{	TextWindowInitState(textWindow);
	textWindow.Title := 'Select file';
	textWindow.LinePos := 1;

	for i := 0 to (unz.Entries.Count - 1) do with unz.Entries.Entries[i] do begin
		if not EndsText(ENGINE_EXTENSION, ArchiveFilename) then continue;
		TextWindowAppend(textWindow, ArchiveFileName);
	end;

	if textWindow.LineCount = 0 then begin
		ShowStatusMessage('No file found!');
		exit;
	end else if textWindow.LineCount > 1 then begin
		TextWindowSort(textWindow, 0, textWindow.LineCount);
		TextWindowSelect(textWindow, TWS_IGNORE_HYPERLINKS);
		if TextWindowRejected then exit;
	end;

	filename := textWindow.Lines[textWindow.LinePos]^;
	filenameShort := ExtractFileName(filename);

	TextWindowFree(textWindow);

	if FileExists(filenameShort) then begin
		choiceResult := 1;
		SidebarPromptChoice(true, 3, 'Overwrite?', 'Yes No', choiceResult);
		SidebarClearLine(3);
		SidebarClearLine(4);
		SidebarClearLine(5);
		if choiceResult = 1 then exit;
	end;

	ShowStatusMessage('Unpacking...');
	unz.UnZipFile(filename, filenameShort);
	ShowStatusMessage('Loading...');
	if WorldLoad(filenameShort, '', false) then begin
		ReturnBoardId := World.Info.CurrentBoard;
		BoardChange(0);
		WebBrowserLoadZipFile := true;
		ShowStatusMessage('');
	end else begin
		WorldCreate;
		ShowStatusMessage('World load error!');
	end; }
end;

function WebBrowserTextFiles(title, url, urlFilename: string): boolean;
var
	i: Int32;
	textWindow: TTextWindowState;
	urlRequested: boolean;
	running: boolean;
	data: AnsiString;
	dataLine: string;
begin
	WebBrowserTextFiles := false;
	urlRequested := true;
	running := true;

	while running do begin
		ShowStatusMessage('Connecting...');

		with TFPHttpClient.Create(Nil) do
			try
				AllowRedirect := true;
				data := Get(url + '/' + urlFilename + '.TXT');
				urlRequested := false;
			finally
				Free;
			end;

		ShowStatusMessage('');

		TextWindowInitState(textWindow);
		textWindow.Title := title;
		if urlRequested then begin
			TextWindowAppend(textWindow, 'Error downloading file!');
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, '!$return;Return');
		end else begin
			dataLine := '';
			for i := 1 to Length(data) do begin
				if data[i] = #10 then begin
					TextWindowAppend(textWindow, dataLine);
					dataLine := '';
				end else begin
					dataLine := dataLine + data[i];
				end;
			end;
			if Length(dataLine) > 0 then begin
				TextWindowAppend(textWindow, dataLine);
			end;
		end;

		TextWindowSelect(textWindow, TWS_HYPERLINK_AS_SELECT or TWS_LONG_HYPERLINKS);

		if (TextWindowRejected) or (textWindow.Hyperlink = '$return') then begin
			running := false;
		end else if (Length(textWindow.Hyperlink) >= 1) and (textWindow.Hyperlink[1] = '$') then begin
			{ }
		end else if (Length(textWindow.Hyperlink) >= 1) and (textWindow.Hyperlink[1] = '@') then begin
			urlFilename := Copy(textWindow.Hyperlink, 2, Length(textWindow.Hyperlink) - 1);
			urlRequested := true;
		end else if (Length(textWindow.Hyperlink) >= 2) then begin
			if WebBrowserLoadZipFile(
				Copy(textWindow.Hyperlink, 1, 1),
				Copy(textWindow.Hyperlink, 2, Length(textWindow.Hyperlink) - 1)
			) then begin
				WebBrowserTextFiles := true;
				running := false;
			end;
		end;

		TextWindowFree(textWindow);
	end;
end;

procedure WebBrowserLoop;
var
	preLoopPath: string;
	textWindow: TTextWindowState;
	function EntryContainsDetail(entry: TJSONObject; detailId: Int32): boolean;
	var
		jsonDetail: TJSONObject;
		jsonDetailEnum: TJSONEnum;
		jsonDetailMatches: boolean;
	begin
		for jsonDetailEnum in (entry.GetPath('details') as TJSONArray) do begin
			jsonDetail := jsonDetailEnum.Value as TJSONObject;
			if jsonDetail.Get('id', -1) = detailId then begin
				EntryContainsDetail := true;
				exit;
			end;
		end;

		EntryContainsDetail := false;
	end;
	function WebBrowserSearch: boolean;
	var
		jsonData: TJSONObject;
		jsonResults: TJSONArray;
		jsonResult: TJSONObject;
		jsonResultEnum: TJSONEnum;
		searchQuery: TMuseumSearchQuery;
		searchCount: Int32;
		searchActive: boolean;
		searchRequested: boolean;
		detailActive: boolean;
		running: boolean;
		titleString: string;
		authorArray: TJSONArray;
		authorResultEnum: TJSONEnum;
		authorIndex: Int32;
		addSpace: boolean;
		procedure NewSearchQuery;
		begin
			FillChar(searchQuery, SizeOf(searchQuery), 0);
		end;
	begin
		searchActive := false;
		searchRequested := false;
		detailActive := false;

		WebBrowserSearch := false;
		NewSearchQuery;

		running := true;
		while running do begin
			TextWindowInitState(textWindow);
			{ if detailActive then try
				
			end else }if searchActive then try
				if (not searchRequested) or CallMuseumSearch(searchQuery, jsonData) then begin
					if Length(searchQuery.Title) <> 0 then
						titleString := 'Title: ' + searchQuery.Title
					else if Length(searchQuery.Author) <> 0 then
						titleString := 'Author: ' + searchQuery.Author
					else if Length(searchQuery.Company) <> 0 then
						titleString := 'Company: ' + searchQuery.Company
					else
						titleString := 'Search Results';
					if Length(titleString) > 40 then
						titleString := Copy(titleString, 1, 37) + '...';
					textWindow.Title := titleString;
			
					jsonResults := jsonData.GetPath('data.results') as TJSONArray;
					for jsonResultEnum in jsonResults do begin
						jsonResult := jsonResultEnum.Value as TJSONObject;
						if not EntryContainsDetail(jsonResult, ENGINE_DETAIL_CODE) then continue;
						if jsonResult.Get('explicit', 0) <> 0 then continue;

						titleString := jsonResult.Get('title') + ' by ';
						if jsonResult.GetPath('author').JSONType = jtArray then begin
							authorIndex := 0;
							authorArray := jsonResult.GetPath('author') as TJSONArray;
							for authorResultEnum in authorArray do begin
								if authorIndex > 0 then titleString := titleString + ', ';
								titleString := titleString + authorResultEnum.Value.AsString;
								Inc(authorIndex);
							end;
						end else titleString := titleString + jsonResult.Get('author');

						if Length(titleString) > 34 then
							titleString := Copy(titleString, 1, 31) + '...';
						TextWindowAppend(textWindow, '!'
							+ IntToStr(jsonResultEnum.KeyNum)
							+ ';' + titleString);
					end;
					searchCount := jsonData.Get('count', 0);

					if textWindow.LineCount = 0 then
						TextWindowAppend(textWindow, 'No results found.');
					TextWindowAppend(textWindow, '');
					addSpace := false;
					if searchQuery.Sort <> 'roulette' then begin
						if searchCount = SEARCH_RESULT_SIZE then begin
							TextWindowAppend(textWindow, '!$next;Next page');
							addSpace := true;
						end;
						if searchQuery.Offset > 0 then begin
							TextWindowAppend(textWindow, '!$prev;Previous page');
							addSpace := true;
						end;
					end;
					if addSpace then
						TextWindowAppend(textWindow, '');
				end else if (searchRequested) then begin
					{ TODO: Error handling }
					running := false;
				end;

				searchRequested := false;
			except
				begin
					ShowStatusMessage('Search error!');
					PauseOnError;
					searchActive := false;
				end;
			end else begin
				textWindow.Title := 'Museum of ZZT';
			end;
			TextWindowAppend(textWindow, '!$title;Search by title');
			TextWindowAppend(textWindow, '!$author;Search by author');
			TextWindowAppend(textWindow, '!$company;Search by company');
			TextWindowAppend(textWindow, '!$genre;Search by genre');
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, '!@REC_%ENGINE%;Recommended worlds');
			TextWindowAppend(textWindow, '!$new;New releases');
			TextWindowAppend(textWindow, '!$newpub;New additions');
			TextWindowAppend(textWindow, '!$all;Browse all files');
			TextWindowAppend(textWindow, '');
			TextWindowAppend(textWindow, '       Visit the Museum of ZZT at:');
			TextWindowAppend(textWindow, '         https://museumofzzt.com');
			TextWindowAppend(textWindow, '');

			TextWindowSelect(textWindow, TWS_HYPERLINK_AS_SELECT or TWS_CONSTANT_TITLE
				or TWS_LONG_HYPERLINKS);
			try
				if TextWindowRejected then begin
					running := false;
				end else if textWindow.Hyperlink = '$all' then begin
					NewSearchQuery;
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$newpub' then begin
					NewSearchQuery;
					searchQuery.Sort := 'published';
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$new' then begin
					NewSearchQuery;
					searchQuery.Sort := '-release';
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$title' then begin
					NewSearchQuery;
					PopupPromptString('Title?', searchQuery.Title, 50);
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$author' then begin
					NewSearchQuery;
					PopupPromptString('Author?', searchQuery.Author, 50);
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$company' then begin
					NewSearchQuery;
					PopupPromptString('Company?', searchQuery.Company, 50);
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$genre' then begin
					NewSearchQuery;
					PopupPromptString('Genre?', searchQuery.Genre, 50);
					searchActive := true;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$next' then begin
					searchQuery.Offset := jsonData.Get('next_offset', searchQuery.Offset + SEARCH_RESULT_SIZE);
					searchRequested := true;
				end else if textWindow.Hyperlink = '$prev' then begin
					searchQuery.Offset := searchQuery.Offset - SEARCH_RESULT_SIZE;
					if searchQuery.Offset < 0 then
						searchQuery.Offset := 0;
					searchRequested := true;
				end else if textWindow.Hyperlink = '$download' then begin
					if WebBrowserLoadZipFile(
						jsonResult.Get('letter'), jsonResult.Get('filename')
					) then begin
						WebBrowserSearch := true;
						running := false;
					end;
				end else if (Length(textWindow.Hyperlink) >= 1) and (textWindow.Hyperlink[1] = '@') then begin
					if WebBrowserTextFiles('Viewing file', 'https://zeta.asie.pl/museum_client',
						Copy(textWindow.Hyperlink, 2, Length(textWindow.Hyperlink) - 1)
					) then begin
						WebBrowserSearch := true;
						running := false;
					end;
				end else if (Length(textWindow.Hyperlink) >= 1) and (textWindow.Hyperlink[1] <> '$') then begin
					jsonResult := jsonResults.Extract(StrToInt(textWindow.Hyperlink)) as TJSONObject;
					if WebBrowserLoadZipFile(
						jsonResult.Get('letter'), jsonResult.Get('filename')
					) then begin
						WebBrowserSearch := true;
						running := false;
					end;
					{ detailActive := true; }
				end;
			except
				begin
					ShowStatusMessage('Error!');
					PauseOnError;
				end;
			end;
			TextWindowFree(textWindow);
		end;
	end;
begin
	GetDir(0, preLoopPath);
	ChDir(startingPath);

	VideoClear(1);
	GameDisplayResourceImage('MUSEUMBG', 0, 0, 60, 25);
	VideoWriteText(VideoSidebarX + 1, 0, $1F, '     - - - -       ');
	VideoWriteText(VideoSidebarX + 1, 1, $70, '  Museum of ZZT  ');
	VideoWriteText(VideoSidebarX + 1, 2, $1F, '     - - - -       ');

	TextWindowInitState(textWindow);
	textWindow.Title := '';
	TextWindowDrawOpen(textWindow);
	TextWindowFree(textWindow);

	if WebBrowserSearch then begin
		{ Exit to new path. }
	end else begin
		{ Return to old path. }
		ChDir(preLoopPath);
	end;

	TextWindowInitState(textWindow);
	TextWindowDrawClose(textWindow);
	TextWindowFree(textWindow);
end;

begin
	GetDir(0, startingPath);
end.
