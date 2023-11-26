unit RegisteredFileHandler;

// {$define zdebug}
// {$define copystream}

interface

uses SysUtils, Classes, System.Zip, System.Generics.Collections, System.Generics.Defaults, CastleImages;

type
  TZipDirEntry = class
    name: String;
    size: Cardinal;
    date: TDateTime;
    crc32: UInt32;
    isDirectory: Boolean;
  end;

  TZipDir = TObjectDictionary<String, TZipDirEntry>;

  TPackedDataReader = class
  private
    fZipDir: TZipDir;
    fZipList: TArray<String>;
    fZipFileName: String;
    fZipFile: TZipFile;
    fProtocol: String;
    function WriteFile(const FileInZip: String; AStream: TStream): Boolean; overload;
    procedure SetZipFileName(const AValue: String);
    function ReadFile(const FileInZip: String): TStream;
  public
    function ReadUrl(const Url: string; out MimeType: string): TStream;
    function FileExists(const Url: string): Boolean;
    function DirectoryExists(const Url: string): Boolean;
    function RandomFile: String;
    function FileIndex(const I: Integer): String;
    function Count: Integer;
    function WriteFile(const FileInZip: String; AImage: TCastleImage): Boolean; overload;
    constructor Create;
    destructor Destroy; override;
    property ZipFileName: String read fZipFileName write SetZipFileName;
    property Protocol: String read fProtocol write fProtocol;
  end;

var
    PackedDataReader: TPackedDataReader;


function MountZipFile(const Identifier: String; const ZipFile: String): TPackedDataReader;

implementation

uses CastleLog, CastleURIUtils, CastleDownload, CastleFilesUtils, URIParser,
  System.ZLib, CastleStringUtils, CastleInternalDirectoryInformation;

function TBytesToString(const Bytes: TBytes): String;
begin
  SetString(Result, PAnsiChar(Bytes), Length(Bytes));
end;

constructor TPackedDataReader.Create;
begin
  fZipFile := TZipFile.Create;
  fZipDir := TZipDir.Create([doOwnsValues]);
end;

procedure TPackedDataReader.SetZipFileName(const AValue: String);
var
  I: Integer;
  zde: TZipDirEntry;
begin
  if AValue <> '' then
    begin
      fZipFileName := AValue;

      if not URIFileExists(fZipFileName) then
        begin
          fZipFile.Open(fZipFileName, TZipMode.zmWrite);
          fZipFile.Close;
        end;

      fZipFile.Open(fZipFileName, TZipMode.zmReadWrite);
      fZipDir.Clear;
      for I := 0 to FZipFile.FileCount - 1 do
        begin
          zde := TZipDirEntry.Create;
          zde.name := TBytesToString(fZipFile.FileInfo[I].FileName);
          zde.size := fZipFile.FileInfo[I].UncompressedSize;
          zde.date := FileDateToDateTime(fZipFile.FileInfo[I].ModifiedDateTime);
          zde.crc32 := fZipFile.FileInfo[I].CRC32;
          if (zde.name.EndsWith('/')) then
            zde.isDirectory := True
          else
            zde.isDirectory := False;

          if {$ifndef zdebug}not {$endif}fZipDir.TryAdd(zde.name, zde) then
          {$ifdef zdebug}
            WritelnLog(Format('Added %s, %d, %s, %s to fZipDir', [
              zde.name,
              zde.size,
              DateTimeToStr(zde.date),
              BoolToStr(zde.isDirectory, True)
              ]))
          else
          {$endif}
            begin
            zde.Free;
            raise Exception.Create('Couldn''t add file to dict');
            end;
        end;
    end;
end;

function TPackedDataReader.FileExists(const Url: string): Boolean;
var
  zde: TZipDirEntry;
  convertedURL: String;
begin
  Result := False;

  convertedURL := Url;
  convertedURL := convertedURL.Replace('\', '/', [rfReplaceAll]);

  if fZipDir.TryGetValue(Url, zde) then
    begin
      if zde.isDirectory = False then
        Result := True;
    end;
end;

function TPackedDataReader.DirectoryExists(const Url: string): Boolean;
var
  zde: TZipDirEntry;
  convertedURL: String;
begin
  Result := False;

  convertedURL := Url;
  convertedURL := convertedURL.Replace('\', '/', [rfReplaceAll]);
  if not convertedURL.EndsWith('/') then
    convertedURL := convertedURL + '/';

  if fZipDir.TryGetValue(convertedUrl, zde) then
    begin
      if zde.isDirectory = True then
        Result := True;
    end;
end;

function TPackedDataReader.WriteFile(const FileInZip: String; AImage: TCastleImage): Boolean;
var
  MimeType: String;
  TempStream: TMemoryStream;
begin
  MimeType := URIMimeType(FileInZip);
  TempStream := TMemoryStream.Create;
  SaveImage(AImage, MimeType, TempStream);
  Result := WriteFile(FileInZip, TempStream);
  TempStream.Free;
end;

function TPackedDataReader.WriteFile(const FileInZip: String; AStream: TStream): Boolean;
var
  zde: TZipDirEntry;
  crcCheck: UInt32;
  dupe: Boolean;
begin
  Result := False; // Default to not writing to Zip

  dupe := False;

  if AStream is TMemoryStream then
    crcCheck := crc32(0, TMemoryStream(AStream).Memory, AStream.Size)
  else
    raise Exception.Create('AStream in not MemoryStream');

  if fZipDir.TryGetValue(FileInZip, zde) then
    begin
      if zde.crc32 = crcCheck then
        dupe := True // Have a file of same name with same CRC32 - skip it
      else
        begin // There's an updated file so remove old one and it's directory entry (about to add it back anyway)
          fZipFile.Delete(FileInZip);
          fZipDir.Remove(FileInZip);
        end;
    end;
  if not dupe then
    begin
      AStream.Position := 0;
      fZipFile.Add(AStream, FileInZip);
      zde := TZipDirEntry.Create;
      zde.name := FileInZip;
      zde.size := AStream.Size;
      zde.date := Now;
      zde.crc32 := crcCheck;
      if (zde.name.EndsWith('/')) then
        zde.isDirectory := True
      else
        zde.isDirectory := False;
      Result := True;
      if not fZipDir.TryAdd(FileInZip, zde) then
        begin // Shouldn't ever get here
          zde.Free;
          raise Exception.Create('Couldn''t add file to dict');
        end;
    end;
end;

function TPackedDataReader.ReadFile(const FileInZip: String): TStream;
var
  LocalHeader: TZipHeader;
  TempStream: TStream;
begin
    fZipFile.Read(FileInZip, TempStream, LocalHeader);
    WritelnLog('UnZipFile read from zip ' + FileInZip);
    {$ifdef copystream}
    Result := TMemoryStream.Create;
    Result.CopyFrom(TempStream, 0);
    TempStream.Free;
    {$else}
    Result := TempStream;
    {$endif}
    Result.Position := 0; // rewind, CGE reading routines expect this
end;

function TPackedDataReader.ReadUrl(const Url: string; out MimeType: string): TStream;
var
  U: TURI;
  FileInZip: String;
begin
  U := ParseURI(Url);
  FileInZip := PrefixRemove('/', U.Path + U.Document, false);
  Result := ReadFile(FileInZip);

  { Determine mime type from Url, which practically means:
    determine content type from filename extension. }
  MimeType := URIMimeType(Url);
end;

function TPackedDataReader.RandomFile: String;
var
  s: String;
  e: TZipDirEntry;
begin
  if not Assigned(fZipList) then
    begin
      fZipList := fZipDir.Keys.ToArray;
    end;

  repeat
    begin
      s := fZipList[Random(Length(fZipList) - 1)];
      if not fZipDir.TryGetValue(s, e) then
        raise Exception.Create('Key not found in Dict (impossible)');
    end;
  until not e.isDirectory;


  Result := fProtocol + ':/' + s;
end;

function TPackedDataReader.Count: Integer;
begin
  Result := fZipDir.Count;
end;

function TPackedDataReader.FileIndex(const I: Integer): String;
var
  s: String;
begin
  if not Assigned(fZipList) then
    begin
      fZipList := fZipDir.Keys.ToArray;
    end;

  s := fZipList[I];
  Result := fProtocol + ':/' + s;
end;

destructor TPackedDataReader.Destroy;
begin
  if RegisteredUrlProtocol(fProtocol) then
    UnregisterUrlProtocol(fProtocol);
  fZipDir.Free;
  fZipDir := Nil;
  FreeAndNil(fZipFile);
  inherited;
end;

function MountZipFile(const Identifier: String; const ZipFile: String): TPackedDataReader;
begin
  PackedDataReader := TPackedDataReader.Create;
  PackedDataReader.ZipFileName := URIToFilenameSafe(ZipFile);
  PackedDataReader.Protocol := 'zip-' + LowerCase(Identifier);
  RegisterUrlProtocol(PackedDataReader.Protocol, PackedDataReader.ReadUrl, nil);
  Result := PackedDataReader;
end;

end.
