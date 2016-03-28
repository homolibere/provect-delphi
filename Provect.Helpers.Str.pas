unit Provect.Helpers.Str;

interface

type
  TStringHelper = record helper for string
    function Contains(const Value: string): Boolean;
    function IsEmpty: Boolean;
    function ToCurrency: Currency;
    function ToInteger: Integer;
    class function Join(const Separator: string; const values: array of const): string; overload; static;
    class function Join(const Separator: string; const Values: array of string): string; overload; static;
    class function Join(const Separator: string; const Values: IEnumerator<string>): string; overload; static;
    class function Join(const Separator: string; const Values: IEnumerable<string>): string; overload; static;
    class function Join(const Separator: string; const value: array of string; StartIndex: Integer; Count: Integer): string; overload; static;
  end;

implementation

uses
  System.SysUtils, System.SysConst;

{ TStringHelper }

class function TStringHelper.Join(const Separator: string; const Values: array of string): string;
begin
  Result := Join(Separator, Values, 0, System.Length(Values));
end;

class function TStringHelper.Join(const Separator: string; const Values: IEnumerable<string>): string;
var
  eValues: IEnumerator<string>;
begin
  if Assigned(Values) then
  begin
    eValues := Values.GetEnumerator;
    Result := eValues.Current;
    while eValues.MoveNext do
      Result := Result +  Separator + eValues.Current;
  end
  else Result := '';
end;

class function TStringHelper.Join(const Separator: string; const Values: IEnumerator<string>): string;
begin
  if Assigned(Values) then
  begin
    Result := Values.Current;
    while Values.MoveNext do
      Result := Result + Separator + Values.Current;
  end
  else Result := '';
end;

function TStringHelper.Contains(const Value: string): Boolean;
begin
  Result := System.Pos(Value, Self) > 0;
end;

function TStringHelper.IsEmpty: Boolean;
begin
  Result := Self = EmptyStr;
end;

class function TStringHelper.Join(const Separator: string; const Value: array of string; StartIndex,
  Count: Integer): string;
var
  I: Integer;
  Max: Integer;
begin
  if StartIndex >= System.Length(Value) then
    raise ERangeError.Create(SRangeError);
  if (StartIndex + Count) > System.Length(Value) then
    Max := System.Length(Value)
  else
    Max := StartIndex + Count;
  Result := Value[StartIndex];
  for I:= StartIndex + 1 to Max - 1 do
    Result := Result + Separator + Value[I];
end;

function TStringHelper.ToCurrency: Currency;
var
  TempStr: string;
begin
  TempStr := StringReplace(Self, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  TempStr := StringReplace(TempStr, ',', FormatSettings.DecimalSeparator, [rfReplaceAll]);
  TempStr := StringReplace(TempStr, FormatSettings.ThousandSeparator, EmptyStr, [rfReplaceAll]);
  Result := StrToCurrDef(TempStr, 0);
end;

function TStringHelper.ToInteger: Integer;
begin
  Result := StrToIntDef(Self, 0);
end;

class function TStringHelper.Join(const Separator: string; const values: array of const): string;
var
  I: Integer;
  len: Integer;
  function ValueToString(const val: TVarRec):string;
  begin
    case val.VType of
      vtInteger: Result := IntToStr(val.VInteger);
{$IFNDEF NEXTGEN}
      vtChar: Result := Char(val.VChar);
      vtPChar: Result := string(val.VPChar);
{$ENDIF !NEXTGEN}
      vtExtended: Result := FloatToStr(val.VExtended^);
      vtObject: Result := TObject(val.VObject).Classname;
      vtClass: Result := val.VClass.Classname;
      vtCurrency: Result := CurrToStr(val.VCurrency^);
      vtInt64: Result := IntToStr(PInt64(val.VInt64)^);
      vtUnicodeString: Result := string(val.VUnicodeString);
    else
        Result := Format('(Unknown) : %d',[val.VType]);
    end;
  end;
begin
  len := System.Length(Values);
  if len = 0 then
    Result := ''
  else begin
    Result := ValueToString(Values[0]);
    for I := 1 to len-1 do
      Result := Result + Separator + ValueToString(Values[I]);
  end;
end;


end.
