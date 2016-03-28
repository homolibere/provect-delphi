unit Provect.ModalController;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Threading,
  FMX.Controls, FMX.TabControl, FMX.Forms, FMX.Types, FMX.Objects;

type
  TFrameClass = class of TFrame;

  TModalController = class(TTabControl)
  private
    FWaitTask: ITask;
    FWaitTaskFuture: IFuture<Boolean>;
    FModalResult: TModalResult;
    function InternalCheckCurrent(const AClassName: string): Boolean;
    procedure InternalModal(const ATab: TTabItem; const AProc: TProc; const AFunc: TFunc<Boolean>);
  protected
    function IsInitialized: Boolean;
    function IsModal: Boolean;
    function IsWaitingTask: Boolean;
    procedure CallOnShow;
    property ModalResult: TModalResult read FModalResult write FModalResult;
  public
    class procedure CloseHide;
    class function CheckCurrent(const AFrame: TFrame): Boolean; overload;
    class function CheckCurrent(const AFrame: TFrameClass): Boolean; overload;
    class procedure EscapeHide;
    class procedure Hide(ANumber: Integer); reintroduce; overload;
    class procedure Hide(const AControl: TFrame); reintroduce; overload;
    class procedure HideModal(ANumber: Integer; AModalResult: TModalResult); reintroduce; overload;
    class procedure HideModal(const AControl: TFrame; AModalResult: TModalResult); reintroduce; overload;
    class procedure SetStyle(const AStyleName: string);
    class function Show(const AControl: TFrame): Integer; reintroduce; overload;
    class function Show(const AFrame: TFrameClass): Integer; reintroduce; overload;
    class function ShowModal(const AControl: TFrame; const AProc: TProc): TModalResult; overload;
    class function ShowModal(const AFrame: TFrameClass; const AProc: TProc): TModalResult; overload;
    class function ShowModal(const AFrame: TFrameClass; const AFunc: TFunc<Boolean>): TModalResult; overload;
  end;

implementation

uses
  System.Rtti,
  FMX.ActnList, FMX.Ani;

var
  _ModalController: TModalController;

function CheckModalController: Boolean;
begin
  if not Assigned(_ModalController) then
    _ModalController := TModalController.Create(nil);
  Result := Assigned(_ModalController);
end;

{ TModalController }

class procedure TModalController.Hide(ANumber: Integer);
begin
  if CheckModalController and _ModalController.IsInitialized and (_ModalController.TabCount > ANumber) and
     not _ModalController.IsWaitingTask and (_ModalController.ActiveTab.Index = ANumber) and
     not _ModalController.IsModal then
  begin
    if _ModalController.TabCount = 1 then
    begin
      TAnimator.AnimateFloat(_ModalController, 'Opacity', 0);
      _ModalController.Visible := False
    end
    else
      _ModalController.Previous(TTabTransition.Slide, TTabTransitionDirection.Reversed);
    _ModalController.Tabs[ANumber].Enabled := False;
  end;
end;

class procedure TModalController.Hide(const AControl: TFrame);
var
  Item: TTabItem;
  I: Integer;
begin
  if CheckModalController and Assigned(AControl) and _ModalController.IsInitialized and not _ModalController.IsWaitingTask then
  begin
    for I := 0 to Pred(_ModalController.TabCount) do
    begin
      Item := _ModalController.Tabs[I];
      if Item.StylesData['object-link'].AsType<TFrame> = AControl then
      begin
        TModalController.Hide(Item.Index);
        Break;
      end;
    end;
  end;
end;

class procedure TModalController.HideModal(ANumber: Integer; AModalResult: TModalResult);
begin
  if CheckModalController then
  begin
    _ModalController.ModalResult := AModalResult;
    _ModalController.Hide(ANumber);
  end;
end;

class procedure TModalController.HideModal(const AControl: TFrame; AModalResult: TModalResult);
begin
  if CheckModalController then
  begin
    _ModalController.ModalResult := AModalResult;
    _ModalController.Hide(AControl);
  end;
end;

procedure TModalController.CallOnShow;
var
  Rtti: TRttiMethod;
  RttiClass: TObject;
begin
  RttiClass := _ModalController.ActiveTab.StylesData['object-link'].AsObject;
  for Rtti in TRttiContext.Create.GetType(RttiClass.ClassInfo).GetDeclaredMethods do
  begin
    if CompareText(Rtti.Name, 'FrameShow') = 0 then
      Rtti.Invoke(RttiClass, []);
  end;
end;

class function TModalController.CheckCurrent(const AFrame: TFrameClass): Boolean;
begin
  Result := _ModalController.InternalCheckCurrent(AFrame.ClassName);
end;

class function TModalController.CheckCurrent(const AFrame: TFrame): Boolean;
begin
  Result := _ModalController.InternalCheckCurrent(AFrame.ClassName);
end;

class procedure TModalController.CloseHide;
begin
  if CheckModalController and _ModalController.IsInitialized and _ModalController.Visible and
     not _ModalController.IsWaitingTask then
  begin
    while Assigned(_ModalController.ActiveTab) do
    begin
      _ModalController.ModalResult := mrAbort;
      _ModalController.Hide(_ModalController.ActiveTab.Index);
    end;
  end;
end;

class procedure TModalController.EscapeHide;
begin
  if CheckModalController and _ModalController.IsInitialized and _ModalController.Visible and
     not _ModalController.IsWaitingTask then
  begin
    _ModalController.ModalResult := mrAbort;
    _ModalController.Hide(_ModalController.ActiveTab.Index);
  end;
end;

function TModalController.InternalCheckCurrent(const AClassName: string): Boolean;
begin
  Result := False;
  if CheckModalController and _ModalController.IsInitialized and _ModalController.Visible then
    Result := _ModalController.ActiveTab.StylesData['object-link'].AsType<TFrame>.ClassName = AClassName;
end;

procedure TModalController.InternalModal(const ATab: TTabItem; const AProc: TProc; const AFunc: TFunc<Boolean>);
begin
  ATab.StylesData['IsModal'] := True;
  try
    if Assigned(AProc) then
    begin
      FWaitTask := TTask.Create(AProc);
      FWaitTask.Start;
      while IsWaitingTask do
      begin
        Application.ProcessMessages;
        Sleep(100);
      end;
      HideModal(ATab.Index, mrOk);
      FWaitTask := nil;
    end
    else
    if Assigned(AFunc) then
    begin
      FWaitTaskFuture := TFuture<Boolean>.Create(TObject(nil), TFunctionEvent<Boolean>(nil), AFunc, TThreadPool.Default);
      FWaitTaskFuture.Start;
      while IsWaitingTask do
      begin
        Application.ProcessMessages;
        Sleep(1);
      end;
      if FWaitTaskFuture.Value then
        HideModal(ATab.Index, mrOk)
      else
        HideModal(ATab.Index, mrCancel);
      FWaitTaskFuture := nil;
    end
    else
    begin
      while ATab.Enabled do
      begin
        Application.ProcessMessages;
        Sleep(100);
      end;
    end;
  finally
    ATab.StylesData['IsModal'] := False;
  end;
end;

function TModalController.IsInitialized: Boolean;
var
  I: Integer;
  TabsDisabled: Boolean;
begin
  Result := Assigned(Parent);
  if not Result then
  begin
    if Assigned(Application) and Assigned(Application.MainForm) then
    begin
      Application.MainForm.AddObject(_ModalController);
      _ModalController.Align := TAlignLayout.Contents;
      _ModalController.TabPosition := TTabPosition.None;
      _ModalController.Visible := False;
      _ModalController.Opacity := 0;
    end;
    Result := Assigned(Parent);
  end
  else
  begin
    TabsDisabled := True;
    while TabsDisabled and (TabCount > 0) do
    begin
      for I := 0 to Pred(TabCount) do
      begin
        TabsDisabled := False;
        if not Tabs[I].Enabled then
        begin
          Delete(I);
          TabsDisabled := True;
          Break;
        end;
      end;
    end;
  end;
end;

function TModalController.IsModal: Boolean;
begin
  Result := ActiveTab.StylesData['IsModal'].AsBoolean and (ModalResult = mrNone);
end;

function TModalController.IsWaitingTask: Boolean;
begin
  Result := (Assigned(FWaitTask) and not FWaitTask.Wait(10)) or
    (Assigned(FWaitTaskFuture) and not FWaitTaskFuture.Wait(10));
end;

class function TModalController.Show(const AControl: TFrame): Integer;
var
  Item: TTabItem;
begin
  Result := -1;
  if CheckModalController and Assigned(AControl) and _ModalController.IsInitialized and
     not _ModalController.IsWaitingTask then
  begin
    _ModalController.ModalResult := mrNone;
    _ModalController.BeginUpdate;
    try
      Item := _ModalController.Add;
      Item.AddObject(AControl);
      AControl.Align := TAlignLayout.Center;
      Item.StylesData['object-link'] := AControl;
      Result := Item.Index;
    finally
      _ModalController.EndUpdate;
    end;
    _ModalController.BringToFront;
    _ModalController.Visible := True;
    if _ModalController.TabCount = 1 then
    begin
      _ModalController.ActiveTab := Item;
      TAnimator.AnimateFloat(_ModalController, 'Opacity', 1);
    end
    else
      _ModalController.Next(TTabTransition.Slide, TTabTransitionDirection.Reversed);
    _ModalController.CallOnShow;
  end;
end;

class procedure TModalController.SetStyle(const AStyleName: string);
begin
  if CheckModalController then
    _ModalController.StyleLookup := AStyleName;
end;

class function TModalController.Show(const AFrame: TFrameClass): Integer;
var
  TempFrame: TFrame;
begin
  Result := -1;
  if CheckModalController and _ModalController.IsInitialized and not _ModalController.IsWaitingTask then
  begin
    TempFrame := AFrame.Create(nil);
    Result := TModalController.Show(TempFrame);
  end;
end;

class function TModalController.ShowModal(const AFrame: TFrameClass; const AFunc: TFunc<Boolean>): TModalResult;
var
  Tab: TTabItem;
begin
  Result := -1;
  if CheckModalController and _ModalController.IsInitialized and not _ModalController.IsWaitingTask then
  begin
    Tab := _ModalController.Tabs[Show(AFrame)];
    _ModalController.InternalModal(Tab, nil, AFunc);
    Result := _ModalController.ModalResult;
  end;
end;

class function TModalController.ShowModal(const AFrame: TFrameClass; const AProc: TProc): TModalResult;
var
  Tab: TTabItem;
begin
  Result := -1;
  if Assigned(AProc) and CheckModalController and _ModalController.IsInitialized and
     not _ModalController.IsWaitingTask then
  begin
    Tab := _ModalController.Tabs[Show(AFrame)];
    _ModalController.InternalModal(Tab, AProc, nil);
    Result := _ModalController.ModalResult;
  end;
end;

class function TModalController.ShowModal(const AControl: TFrame; const AProc: TProc): TModalResult;
var
  Tab: TTabItem;
begin
  Result := -1;
  if Assigned(AProc) and CheckModalController and _ModalController.IsInitialized and
     not _ModalController.IsWaitingTask then
  begin
    Tab := _ModalController.Tabs[Show(AControl)];
    _ModalController.InternalModal(Tab, AProc, nil);
    Result := _ModalController.ModalResult;
  end;
end;

end.
