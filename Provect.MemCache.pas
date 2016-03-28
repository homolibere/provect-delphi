////////////////////////////////////////////////////////////////////////////////////
//
// This component was originally developed by Sivv LLC
// MemCache.pas - Delphi client for Memcached
// Original Project Homepage:
//    http://code.google.com/p/delphimemcache
// Distributed under New BSD License.
//
// Component was heavily redesigned and refactored. Was added new functionality.
// Current author: Nick Remeslennikov
//
////////////////////////////////////////////////////////////////////////////////////

unit Provect.MemCache;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
{$IF CompilerVersion > 27.0}
  Provect.Sockets,
{$ELSE}
  Web.Win.Sockets,
{$ENDIF}
  IdHashSHA;

type
  TObjectEvent = procedure(ASender: TObject; var AObject: TObject) of object;

  TObjectPool = class(TObject)
  private
    FCritSec: TCriticalSection;
    ObjList: TList;
    ObjInUse: TBits;
    FActive: Boolean;
    FAutoGrow: Boolean;
    FStopping: Boolean;
    FGrowToSize: Integer;
    FPoolSize: Integer;
    FOnCreateObject: TObjectEvent;
    FOnDestroyObject: TObjectEvent;
    FUsageCount: Integer;
    FRaiseExceptions: Boolean;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Start(ARaiseExceptions: Boolean = False); virtual;
    procedure Stop; virtual;
    function Acquire: TObject; virtual;
    procedure Release(AItem: TObject); virtual;
    property Active: boolean read FActive;
    property RaiseExceptions: Boolean read FRaiseExceptions write FRaiseExceptions;
    property UsageCount: Integer read FUsageCount;
    property PoolSize: Integer read FPoolSize write FPoolSize;
    property AutoGrow: boolean read FAutoGrow write FAutoGrow;
    property GrowToSize: Integer read FGrowToSize write FGrowToSize;
    property OnCreateObject: TObjectEvent read FOnCreateObject write FOnCreateObject;
    property OnDestroyObject: TObjectEvent read FOnDestroyObject write FOnDestroyObject;
  end;

  EMemCacheException = class(Exception);

  TConnectionPool = class(TObjectPool)
  public
    function Acquire: TTCPClient; reintroduce;
    procedure Release(AItem: TTCPClient); reintroduce;
  end;

  TMemCacheServer = class(TObject)
  private
    FConnections: TConnectionPool;
    FIP: string;
    FPort: Integer;
  public
    constructor Create; reintroduce; virtual;
    destructor Destroy; override;
    procedure CreateConnection(ASender: TObject; var AObject: TObject);
    procedure DestroyConnection(ASender: TObject; var AObject: TObject);
    property Connections: TConnectionPool read FConnections;
    property IP: string read FIP write FIP;
    property Port: Integer read FPort write FPort;
  end;

  TMemCacheValue = class(TObject)
  private
    FStream: TMemoryStream;
    FFlags: Word;
    FSafeToken: UInt64;
    FKey: string;
    FCommand: string;
  public
    constructor Create(ACmd: string; AData: TStream); virtual;
    destructor Destroy; override;
    function Command: string;
    function Value: string;
    function Key: string;
    function Stream: TStream;
    function Bytes: TBytes;
    function Flags: Word;
    function SafeToken: UInt64;
  end;

  TMemCache = class(TObject)
  private
    FServer: TMemCacheServer;
    FRegisterPosition: Integer;
    FFailureCheckRate: Integer;
    FPoolSize: Integer;
  protected
    function ToHash(const AStr: string): UInt64; virtual;
    function ExecuteCommand(const AKey, ACmd: string; AData: TStream = nil): string; virtual;
    procedure RegisterServer(const AConfigStr: string); virtual;
  public
    constructor Create(const ConfigData: string = ''); overload;
    destructor Destroy; override;
    procedure Store(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Store(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Store(const Key: string; Value: TBytes; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Append(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Append(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Prepend(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Prepend(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Replace(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Replace(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Insert(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure Insert(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure StoreSafely(const Key, Value: string; SafeToken: UInt64; Expires: TDateTime = 0; Flags: Word = 0); overload;
    procedure StoreSafely(const Key: string; Value: TStream; SafeToken: UInt64; Expires: TDateTime = 0;
      Flags: Word = 0); overload;
    procedure StoreSafely(const Key: string; Value: TBytes; SafeToken: UInt64; Expires: TDateTime = 0;
      Flags: Word = 0); overload;
    function Touch(const Key: string; Expires: TDateTime = 0): Boolean;
    function Lookup(const Key: string; RequestSafeToken: boolean = False): TMemCacheValue;
    function Delete(const Key: string): boolean;
    function Increment(const Key: string; ByValue: Integer = 1): UInt64;
    function Decrement(const Key: string; ByValue: Integer = 1): UInt64;
    procedure ServerStatistics(AResultList: TStrings);
    property FailureCheckRate: Integer read FFailureCheckRate write FFailureCheckRate; // in seconds
  end;

function MemcacheConfigFormat(ALoad: Integer; const AIP: string; APort: Integer = 11211): string;

implementation

uses
  System.DateUtils,
  IdGlobal, IdCoderMIME;

function Encode64Stream(AStream: TStream): string;
begin
  Result := TIdEncoderMIME.EncodeStream(AStream);
end;

function Encode64String(AStr: string): string;
begin
  Result := TIdEncoderMIME.EncodeString(AStr);
end;

procedure Decode64(const AEncodedStr: string; ADestStream: TStream);
begin
  TIdDecoderMIME.DecodeStream(AEncodedStr, ADestStream);
end;

function MemcacheConfigFormat(ALoad: Integer; const AIP: string; APort: Integer): string;
begin
  Result := Format('%d=%s:%d', [ALoad, AIP, APort]);
end;

function StrToUInt64(const AString: string): UInt64;
var
  E: Integer;
begin
  Val(AString, Result, E);
  if E <> 0 then
    raise Exception.Create('Invalid UINT64');
end;

function MemCacheTime(dt: TDateTime): string;
var
  i: Integer;
begin
  if dt <> 0 then
  begin
    i := SecondsBetween(Now, dt);
    if i >= 60 * 60 * 24 * 30 then
      Result := IntToStr(DateTimeToUnix(dt))
    else
      Result := IntToStr(i);
  end
  else
    Result := '0';
end;

function IndexOf(const AString: string; const AStrArray: array of string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Pred(Length(AStrArray)) do
  begin
    if AString = AStrArray[I] then
    begin
      Result := I;
      Break;
    end;
  end;
end;

{ TMemCache }

procedure TMemCache.Append(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'append ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Append(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'append ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(length(Value)), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

function TMemCache.Decrement(const Key: string; ByValue: Integer = 1): UInt64;
var
  S: string;
begin
  S := ExecuteCommand(Key, 'decr ' + Key + ' ' + IntToStr(ByValue));
  if S = 'NOT_FOUND' then
    raise EMemCacheException.Create('The specified key does not exist.');
  Result := StrToUInt64(S);
end;

function TMemCache.Delete(const Key: string): boolean;
var
  S: string;
begin
  S := ExecuteCommand(Key, 'delete ' + Key);
  if S = 'NOT_FOUND' then
    raise EMemCacheException.Create('The specified key does not exist.');
  Result := S = 'DELETED';
end;

destructor TMemCache.Destroy;
begin
  FreeAndNil(FServer);
  inherited Destroy;
end;

function TMemCache.ExecuteCommand(const AKey, ACmd: string; AData: TStream): string;

  procedure SendCommandToServer(ATCPConn: TTCPClient; const ACommand: string; ADataStream: TStream);
  begin
    try
      if not ATCPConn.Connected then
        ATCPConn.Connect;
      ATCPConn.Sendln(AnsiString(ACommand));
      if Assigned(ADataStream) and (ADataStream.Size > 0) then
      begin
        AData.Position := 0;
        ATCPConn.SendStream(ADataStream);
        ATCPConn.Sendln(AnsiString(EmptyStr));
      end;
    except
      on E: Exception do
      begin
        FServer.Connections.Release(ATCPConn);
        raise;
      end
      else
        raise;
    end;
  end;

  function RecieveServerResponse(ATCPConn: TTCPClient; const ACommand: string; ADataStream: TStream): string;
  var
    TempStr: string;
    DelimPos: Integer;
    Buffer: TBytes;
  begin
    try
      Result := String(ATCPConn.Receiveln);
      if Result.Contains('VALUE') then
      begin
        TempStr := Result.Split([' '])[3];
        SetLength(Buffer, StrToInt(TempStr));
        AData.Position := 0;
        DelimPos := 0;
        while DelimPos <>  StrToInt(TempStr) do
          DelimPos := DelimPos + ATCPConn.ReceiveBuf(Buffer[DelimPos], StrToInt(TempStr) - DelimPos);
        TMemoryStream(AData).Write(Buffer, Length(Buffer));
      end;
    except
      on E: Exception do
      begin
        FServer.Connections.Release(ATCPConn);
        raise;
      end;
    end;
  end;

var
  TCPConn: TTCPClient;
  ResponseString: string;
  IsIncDecCmd, RecieveDone: Boolean;
  ResultList: TArray<string>;
begin
  Result := EmptyStr;
  IsIncDecCmd := (Copy(ACmd, 1, 4) = 'incr') or (Copy(ACmd, 1, 4) = 'decr');
  TCPConn := FServer.Connections.Acquire;
  try
    SendCommandToServer(TCPConn, ACmd, AData);
    RecieveDone := False;
    while not RecieveDone do
    begin
      ResponseString := RecieveServerResponse(TCPConn, ACmd, AData);
      while not ResponseString.IsEmpty do
      begin
        ResultList := ResponseString.Split([' ']);
        if Length(ResultList) > 0 then
        begin
          if IndexOf(ResultList[0], ['VALUE', 'STAT']) <> -1 then
          begin
            if Result.IsEmpty then
              Result := ResponseString
            else
              Result := Result.Join(#13#10, [Result, ResponseString]);
            ResponseString := EmptyStr;
            Break;
          end
          else
          if IndexOf(ResultList[0], ['CLIENT_ERROR', 'SERVER_ERROR']) <> -1 then
            raise EMemCacheException.CreateFmt('Memcache Error: %s', [ResponseString])
          else
          if (IndexOf(ResultList[0], ['END', 'DELETED', 'STORED', 'EXISTS', 'NOT_STORED', 'NOT_FOUND', 'ERROR',
             'TOUCHED']) <> -1) or IsIncDecCmd then
          begin
            if Result.IsEmpty then
              Result := ResponseString
            else
              Result := Result.Join(#13#10, [Result, ResponseString]);
            ResponseString := EmptyStr;
            RecieveDone := True;
          end;
        end;
      end;
    end;
  finally
    FServer.Connections.Release(TCPConn);
  end;
end;

function TMemCache.Increment(const Key: string; ByValue: Integer = 1): UInt64;
var
  S: string;
begin
  S := ExecuteCommand(Key, 'incr ' + Key + ' ' + IntToStr(ByValue));
  if S = 'NOT_FOUND' then
    raise EMemCacheException.Create('The specified key does not exist.');
  Result := StrToUInt64(TrimRight(S));
end;

procedure TMemCache.Insert(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'add ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Insert(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'add ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(length(Value)), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

function TMemCache.Lookup(const Key: string; RequestSafeToken: boolean = False): TMemCacheValue;
var
  Data: TMemoryStream;
  ExecResult: string;
begin
  Data := TMemoryStream.Create;
  try
    if RequestSafeToken then
      ExecResult := ExecuteCommand(Key, 'gets ' + Key, Data)
    else
      ExecResult := ExecuteCommand(Key, 'get ' + Key, Data);
    Result := TMemCacheValue.Create(ExecResult, Data);
  finally
    FreeAndNil(Data);
  end;
end;

procedure TMemCache.Prepend(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'prepend ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Prepend(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'prepend ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(length(Value)), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Replace(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'replace ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(length(Value)), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.RegisterServer(const AConfigStr: string);
var
  DelimPos: Integer;
begin
  if AConfigStr <> '' then
  begin
    DelimPos := Pos(':', AConfigStr);
    if DelimPos > 0 then
    begin
      FServer.IP := Copy(AConfigStr, 1, DelimPos - 1);
      FServer.Port := StrToInt(Copy(AConfigStr, DelimPos + 1, MaxInt));
    end
    else
      FServer.IP := AConfigStr;
  end;
  FServer.Connections.PoolSize := FPoolSize;
  FServer.Connections.Start(True);
end;

procedure TMemCache.Replace(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'replace ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Store(const Key, Value: string; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'set ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(data.Size), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.ServerStatistics(AResultList: TStrings);
var
  ExecResult: string;
begin
  ExecResult := ExecuteCommand(EmptyStr, 'stats');
  AResultList.Clear;
  while True do
  begin
    if Pos(#13#10, ExecResult) <> 0 then
    begin
      AResultList.Add(Copy(ExecResult, 1, Pos(#13#10, ExecResult) - 1));
      System.Delete(ExecResult, 1, Pos(#13#10, ExecResult) + 1);
    end
    else
      Break;
  end;
end;

procedure TMemCache.Store(const Key: string; Value: TStream; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'set ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.StoreSafely(const Key, Value: string; SafeToken: UInt64; Expires: TDateTime = 0; Flags: Word = 0);
var
  S: string;
  data: TStringStream;
begin
  data := TStringStream.Create(Value);
  try
    data.Position := 0;
    S := ExecuteCommand(Key, 'cas ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(length(Value)) + ' ' + IntToStr(SafeToken), data);
  finally
    FreeAndNil(data);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.Store(const Key: string; Value: TBytes; Expires: TDateTime; Flags: Word);
var
  S: string;
  Strm: TMemoryStream;
begin
  Strm := TMemoryStream.Create;
  try
    Strm.WriteBuffer(Value[0], Length(Value));
    Strm.Position := 0;
    S := ExecuteCommand(Key, 'set ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(Strm.Size), Strm);
  finally
    FreeAndNil(Strm);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.StoreSafely(const Key: string; Value: TBytes; SafeToken: UInt64; Expires: TDateTime; Flags: Word);
var
  S: string;
  Strm: TStream;
begin
  Strm := TStream.Create;
  try
    Strm.WriteBuffer(Value[0], Length(Value));
    Strm.Position := 0;
    S := ExecuteCommand(Key, 'cas ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
      IntToStr(Strm.Size) + ' ' + UIntToStr(SafeToken), Strm);
  finally
    FreeAndNil(Strm);
  end;
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

procedure TMemCache.StoreSafely(const Key: string; Value: TStream; SafeToken: UInt64; Expires: TDateTime = 0;
  Flags: Word = 0);
var
  S: string;
begin
  S := ExecuteCommand(Key, 'cas ' + Key + ' ' + IntToStr(Flags) + ' ' + MemCacheTime(Expires) + ' ' +
    IntToStr(Value.Size) + ' ' + UIntToStr(SafeToken), Value);
  if S <> 'STORED' then
    raise EMemCacheException.Create('Error storing Value: ' + S);
end;

constructor TMemCache.Create(const ConfigData: string);
begin
  inherited Create;
  FPoolSize := 1;
  FRegisterPosition := 0;
  FFailureCheckRate := 30;
  FServer := TMemCacheServer.Create;
  RegisterServer(ConfigData);
end;

function TMemCache.ToHash(const AStr: string): UInt64;

  function HexToInt64(const AHex: string): UInt64;
  const
    HexValues = '0123456789ABCDEF';
  var
    I: Integer;
  begin
    Result := 0;
    case length(AHex) of
      0: Result := 0;
      1 .. 16:
        for I := 1 to Length(AHex) do
          Result := 16 * Result + Pos(Upcase(AHex[I]), HexValues) - 1;
    else
      for I := 1 to 16 do
        Result := 16 * Result + Pos(Upcase(AHex[I]), HexValues) - 1;
    end;
  end;

var
  Hash: TIdHashSHA1;
begin
  Hash := TIdHashSHA1.Create;
  try
    Result := HexToInt64(Copy(Hash.HashStringAsHex(AStr), 1, 8));
  finally
    FreeAndNil(Hash);
  end;
end;

function TMemCache.Touch(const Key: string; Expires: TDateTime): Boolean;
var
  S: string;
begin
  S := ExecuteCommand(Key, 'touch ' + Key + ' ' + MemCacheTime(Expires));
  Result := S = 'TOUCHED';
end;

{ TMemCacheValue }

function TMemCacheValue.Bytes: TBytes;
begin
  SetLength(Result, 0);
  if Assigned(FStream) and (FStream.Size > 0) then
  begin
    SetLength(Result, FStream.Size);
    FStream.Position := 0;
    FStream.ReadBuffer(Result[0], FStream.Size);
    FStream.Position := 0;
  end;
end;

function TMemCacheValue.Command: string;
begin
  Result := FCommand;
end;

constructor TMemCacheValue.Create(ACmd: string; AData: TStream);

  function NextField(var AStr: string): string;
  var
    I: Integer;
    IsSingleLine: Boolean;
  begin
    Result := EmptyStr;
    IsSingleLine := False;
    for I := 1 to Length(AStr) do
    begin
      case AStr[I] of
        ' ', #13:
          begin
            Result := Copy(AStr, 1, I - 1);
            if AStr[I] = #13 then
              Delete(AStr, 1, I - 1)
            else
              Delete(AStr, 1, I);
            IsSingleLine := True;
            Break;
          end;
      end;
    end;
    if not IsSingleLine and not Result.IsEmpty and not AStr.IsEmpty then
    begin
      Result := AStr;
      AStr := EmptyStr;
    end;
  end;

var
  SingleLine: string;
  DataSize: Integer;
begin
  inherited Create;
  FStream := TMemoryStream.Create;
  if ACmd = 'END' then
  begin
    FCommand := ACmd;
    FKey := EmptyStr;
    FFlags := 0;
    FSafeToken := 0;
    FStream.Size := 0;
  end
  else
  begin
    FCommand := NextField(ACmd);
    FKey := NextField(ACmd);
    FFlags := StrToIntDef(NextField(ACmd), 0);
    DataSize := StrToIntDef(NextField(ACmd), 0);
    SingleLine := NextField(ACmd);
    if not SingleLine.IsEmpty then
      FSafeToken := StrToUInt64(SingleLine)
    else
      FSafeToken := 0;
    AData.Position := 0;
    FStream.CopyFrom(AData, DataSize);
    FStream.Position := 0;
  end;
end;

destructor TMemCacheValue.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TMemCacheValue.Flags: Word;
begin
  Result := FFlags;
end;

function TMemCacheValue.Key: string;
begin
  Result := FKey;
end;

function TMemCacheValue.SafeToken: UInt64;
begin
  Result := FSafeToken;
end;

function TMemCacheValue.Stream: TStream;
begin
  Result := FStream;
end;

function TMemCacheValue.Value: string;
begin
  SetString(Result, PAnsiChar(FStream.Memory), FStream.Size);
end;

{ TMemCacheServer }

constructor TMemCacheServer.Create;
begin
  inherited Create;
  FPort := 11211;
  FIP := '127.0.0.1';
  FConnections := TConnectionPool.Create;
  FConnections.OnCreateObject := Self.CreateConnection;
  FConnections.OnDestroyObject := Self.DestroyConnection;
end;

procedure TMemCacheServer.CreateConnection(ASender: TObject; var AObject: TObject);
var
  TCPConn: TTCPClient;
begin
  TCPConn := TTCPClient.Create(nil);
  try
    TCPConn.RemoteHost := AnsiString(IP);
    TCPConn.RemotePort := AnsiString(IntToStr(Port));
    TCPConn.Connect;
  except
    FreeAndNil(TCPConn);
    raise;
  end;
  AObject := TCPConn;
end;

destructor TMemCacheServer.Destroy;
begin
  FreeAndNil(FConnections);
  inherited Destroy;
end;

procedure TMemCacheServer.DestroyConnection(ASender: TObject; var AObject: TObject);
begin
  FreeAndNil(AObject);
end;

{ TConnectionPool }

function TConnectionPool.Acquire: TTCPClient;
begin
  Result := TTCPClient(inherited Acquire);
end;

procedure TConnectionPool.Release(AItem: TTCPClient);
begin
  inherited Release(AItem);
end;

{ TObjectPool }

function TObjectPool.Acquire: TObject;
var
  ConnectionIdx: Integer;
begin
  Result := nil;
  if not FActive then
  begin
    if FRaiseExceptions then
      raise EAbort.Create('Cannot acquire an object before calling Start')
    else
      exit;
  end;
  FCritSec.Enter;
  try
    Inc(FUsageCount);
    ConnectionIdx := ObjInUse.OpenBit;
    if ConnectionIdx < FPoolSize then // idx = FPoolSize when there are no openbits
    begin
      Result := TObject(ObjList[ConnectionIdx]);
      ObjInUse[ConnectionIdx] := True;
    end
    else
    begin
      // Handle the case where the pool is completely acquired.
      if not AutoGrow or (FPoolSize > FGrowToSize) then
      begin
        if FRaiseExceptions then
          raise Exception.Create('There are no available objects in the pool')
        else
          exit;
      end;
      Inc(FPoolSize);
      ObjInUse.Size := FPoolSize;
      FOnCreateObject(Self, Result);
      ObjList.Add(Result);
      ObjInUse[FPoolSize - 1] := True;
    end;
  finally
    FCritSec.Leave;
  end;
end;

constructor TObjectPool.Create;
begin
  FCritSec := TCriticalSection.Create;
  ObjList := TList.Create;
  ObjInUse := TBits.Create;
  FActive := False;
  FAutoGrow := True;
  FGrowToSize := 1000;
  FPoolSize := 20;
  FRaiseExceptions := True;
  FOnCreateObject := nil;
  FOnDestroyObject := nil;
  FStopping := False;
end;

destructor TObjectPool.Destroy;
begin
  if FActive then
    Stop;
  FreeAndNil(FCritSec);
  ObjList.Free;
  ObjInUse.Free;
  inherited Destroy;
end;

procedure TObjectPool.Release(AItem: TObject);
var
  Idx: Integer;
begin
  if (not FStopping) and (not FActive) then
  begin
    if FRaiseExceptions then
      raise Exception.Create('Cannot release an object before calling Start')
    else
      Exit;
  end;
  if AItem = nil then
  begin
    if FRaiseExceptions then
      raise Exception.Create('Cannot release an object before calling Start')
    else
      Exit;
  end;
  FCritSec.Enter;
  try
    Idx := ObjList.IndexOf(AItem);
    if Idx < 0 then
    begin
      if FRaiseExceptions then
        raise Exception.Create('Cannot release an object that is not in the pool')
      else
        Exit;
    end;
    ObjInUse[Idx] := False;
    Dec(FUsageCount);
  finally
    FCritSec.Leave;
  end;
end;

procedure TObjectPool.Start(ARaiseExceptions: Boolean = False);
var
  I: Integer;
  TmpObject: TObject;
begin
  // Make sure events are assigned before starting the pool.
  if not Assigned(FOnCreateObject) then
    raise Exception.Create('There must be an OnCreateObject event before calling Start');
  if not Assigned(FOnDestroyObject) then
    raise Exception.Create('There must be an OnDestroyObject event before calling Start');
  // Set the TBits class to the same size as the pool.
  ObjInUse.Size := FPoolSize;
  // Call the OnCreateObject event once for each item in the pool.
  for I := 0 to FPoolSize - 1 do
  begin
    TmpObject := nil;
    FOnCreateObject(Self, TmpObject);
    ObjList.Add(TmpObject);
    ObjInUse[I] := False;
  end;
  // Set the active flag to true so that the Acquire method will return Values.
  FActive := True;
  // Automatically set RaiseExceptions to false by default.  This keeps
  // exceptions from being raised in threads.
  FRaiseExceptions := ARaiseExceptions;
end;

procedure TObjectPool.Stop;
var
  I: Integer;
  TmpObject: TObject;
begin
  // Wait until all objects have been released from the pool.  After waiting
  // 10 seconds, stop anyway.  This may cause unforseen problems, but usually
  // you only Stop a pool as the application is stopping.  40 x 250 = 10,000
  for I := 1 to 40 do
  begin
    FCritSec.Enter;
    try
      // Setting Active to false here keeps the Acquire method from continuing to
      // retrieve objects.
      FStopping := True;
      FActive := False;
      if FUsageCount = 0 then
        break;
    finally
      FCritSec.Leave;
    end;
    // Sleep here to allow give threads time to release their objects.
    Sleep(250);
  end;
  FCritSec.Enter;
  try
    // Loop through all items in the pool calling the OnDestroyObject event.
    for I := 0 to FPoolSize - 1 do
    begin
      TmpObject := TObject(ObjList[I]);
      if Assigned(FOnDestroyObject) then
        FOnDestroyObject(Self, TmpObject)
      else
        TmpObject.Free;
    end;
    // clear the memory used by the list object and TBits class.
    ObjList.Clear;
    ObjInUse.Size := 0;
    FRaiseExceptions := True;
  finally
    FCritSec.Leave;
    FStopping := False;
  end;
end;

end.
