unit Provect.EurekaStackTrace;

interface

uses
  ECallStack, EDebugInfo,
  System.Classes, System.SysUtils;

function EuExceptionStackInfoProc(AExceptionRecord: PExceptionRecord): Pointer;
function EuStackInfoStringProc(AInfo: Pointer): string;
procedure EuCleanUpStackInfoProc(AInfo: Pointer);

implementation

function EuExceptionStackInfoProc(AExceptionRecord: PExceptionRecord): Pointer;
var
  Trace: String;
  TraceSize: Integer;
  EuBaseStackList : TEurekaStackListV7;
begin
  EuBaseStackList := nil;
  try
    EuBaseStackList := TEurekaStackListV7.Create(AExceptionRecord.ExceptionAddress);
    Trace := EuBaseStackList.ToString;
  finally
    EuBaseStackList.Free;
  end;
  if not Trace.IsEmpty then
  begin
    TraceSize := (Length(Trace) + 1) * SizeOf(Char);
    GetMem(Result, TraceSize);
    Move(Pointer(Trace)^, Result^, TraceSize);
  end
  else
    Result := nil;
end;

function EuStackInfoStringProc(AInfo: Pointer): string;
begin
  Result := PChar(AInfo);
end;

procedure EuCleanUpStackInfoProc(AInfo: Pointer);
begin
  FreeMem(AInfo);
end;

initialization
  Exception.GetExceptionStackInfoProc := EuExceptionStackInfoProc;
  Exception.GetStackInfoStringProc := EuStackInfoStringProc;
  Exception.CleanUpStackInfoProc := EuCleanUpStackInfoProc;

end.
