unit FMXFormUnit;

interface

 {$define dolog}
 {$define debugbox}
// {$define savecardmodel}
//  {$define use3d}
uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, Fmx.CastleControl,
  CastleViewport, CastleUIControls, CastleScene, CastleVectors, CastleTransform,
  FMX.StdCtrls, x3dnodes, x3dload, CastleImages, CastleLog, CastleDownload,
  System.Generics.Collections, System.Generics.Defaults,
  CardBuilder, RegisteredFileHandler, FMX.Layouts
  ;

type
  { TCastleCameraHelper }
  TCastleCameraHelper = class helper for TCastleCamera
    procedure ViewFromRadius(const ARadius: Single; const ACamPos: TVector3);
    { Position Camera ARadius from Origin pointing at Origin }
  end;

  TCardPos = record
    X: Integer;
    Y: Integer;
    Index: Integer;
  end;

  { TCastleApp }
  TCastleApp = class(TCastleView)
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override; // TCastleUserInterface
    procedure Start; override; // TCastleView
    procedure Stop; override; // TCastleView
    procedure Resize; override; // TCastleUserInterface
  private
    Camera: TCastleCamera;
    Viewport: TCastleViewport;
    CardModel: TCard;
    ActiveScene: TCastleScene;
    bfw: TBestFit;
    UseTextureChange : Boolean;
    CardList: TArray<TCastleScene>;
    procedure LoadViewport;
    procedure Reflow;
    {$ifdef use3d}
    procedure SwitchView3D(const Use3D: Boolean);
    {$endif}
    function GetCardPos(const Which: Integer): TCardPos;
    procedure RandomMultiCard;
  public
    CardCount: Integer;
    FirstShow: Boolean;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  { TForm }
  TForm1 = class(TForm)
    Panel1: TPanel;
    Button2: TButton;
    Label3: TLabel;
    TrackBar2: TTrackBar;
    CheckBox1: TCheckBox;
    Panel2: TPanel;
    CastleControl1: TCastleControl;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure TrackBar2Change(Sender: TObject);
    procedure CheckBox1Change(Sender: TObject);
  private
    { Private declarations }
    CastleApp: TCastleApp;
  public
    { Public declarations }
    perf10: Integer;
  end;

var
  Form1: TForm1;
  zipfs: TPackedDataReader;
  PackSize: Integer;

implementation

{$R *.fmx}

uses Math, CastleProjection, CastleFilesUtils,
  System.Threading,
  System.Diagnostics,
{$ifdef debugbox}
  CastleDebugTransform, { for TCastleDebugTransform }
{$endif}
  CastleBoxes, { for TBox3d - Bounding Boxes }
  CastleURIUtils, { for URIFileExists }
  CastleRenderOptions, { for stFragment }
  X3DFields, {for TSF..... }
  CastleApplicationProperties { LimitFPS }
  ;

constructor TCastleApp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  CardModel := TCard.Create(AOwner);
  CardModel.MaskFile := 'castle-data:/frameAlpha.png';
  CardModel.BackFile := 'castle-data:/back.jpg';
  CardModel.Width  := 672; // 1.0; // 0.71634615384;
  CardModel.Height := 936; // 1.39285714286; // 1.0;
end;

destructor TCastleApp.Destroy;
begin
  inherited;
end;

procedure TCastleApp.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  offx, offy: Single;
  bb: TBox3D;
begin
  if Assigned(ActiveScene) and not (ActiveScene.BoundingBox.IsEmptyOrZero) then
    begin
      if FirstShow then
        begin
          FirstShow := False;
          Resize;
          bb := ActiveScene.BoundingBox;
          WriteLnLog('ActiveScene : min = ' + bb.Min.ToString + ' max = '  + bb.Min.ToString + ' size = ' + FormatFloat('###0.00', bb.SizeX) + ', ' + FormatFloat('###0.00', bb.SizeY) + ', ' + FormatFloat('###0.00', bb.SizeZ));
        end;
      offx := (Camera.Orthographic.EffectiveRect.Width - ActiveScene.BoundingBox.SizeX) / 2;
      offy := (Camera.Orthographic.EffectiveRect.Height - ActiveScene.BoundingBox.SizeY) / 2;

      ActiveScene.Translation := Vector3(offx, offy, 0);
{
      Form1.Caption := 'Cards : ' +
        IntToStr(PackSize) +
        ' / ' +
        IntToStr(bfw.Quantity) +
        ' - Grid : ' +
        IntToStr(bfw.Columns) +
        'x' +
        IntToStr(bfw.Rows) +
        ' - Contain : ' +
        FormatFloat('##0.00', bfw.Rect.Width) +
        'x' +
        FormatFloat('##0.00', bfw.Rect.Height) +
        ' - Offset : ' +
        FormatFloat('##0.00', offx) +
        'x' +
        FormatFloat('##0.00', offy)
        ;
}
    end;

  inherited;
end;

procedure TCastleApp.Resize;
begin
  Reflow;
  Viewport.Width := Container.Width;
  Viewport.Height := Container.Height;
  if Camera.ProjectionType = ptOrthographic then
    begin
      Camera.Orthographic.Width := bfw.Rect.Width;
    end;
end;

function TCastleApp.GetCardPos(const Which: Integer): TCardPos;
var
  WrapWhich: Integer;
begin
  WrapWhich := Which mod bfw.Quantity;
  Result := default(TCardPos);
  Result.X := WrapWhich mod bfw.Columns;
  Result.Y := WrapWhich div bfw.Columns;
  Result.Index := ((Result.Y * bfw.Columns) + Result.X) mod bfw.Quantity;
end;

procedure TCastleApp.Start;
begin
  inherited;
  LoadViewport;
end;

procedure TCastleApp.Stop;
begin
  inherited;
end;

procedure TCastleApp.LoadViewport;
{$ifdef debugbox}
var
  dbg: TDebugTransformBox;
{$endif}
begin
  Viewport := TCastleViewport.Create(Self);
  Viewport.FullSize := False;
  Viewport.Width := Container.Width;
  Viewport.Height := Container.Height;
  Viewport.Transparent := True;

  Camera := TCastleCamera.Create(Viewport);

  Viewport.Setup2D;
  Camera.ProjectionType := ptOrthographic;
  Camera.Orthographic.Width := 1;
  Camera.Orthographic.Origin := Vector2(0, 0);

  Viewport.Items.Add(Camera);
  Viewport.Camera := Camera;

  InsertFront(Viewport);

  ActiveScene := TCastleScene.Create(Self);
  Viewport.Items.Add(ActiveScene);
{$ifdef debugbox}
  dbg := TDebugTransformBox.Create(Self);
  dbg.Parent := ActiveScene;
  dbg.Exists := True;
{$endif}
end;
{$ifdef use3d}
procedure TCastleApp.SwitchView3D(const Use3D: Boolean);
begin
  if Use3D then
    begin
      Camera.ProjectionType := ptPerspective;
      Camera.ViewFromRadius(bfw.Rect.Width, Vector3(1, 1, 1));
    end
  else
    begin
      Viewport.Setup2D;
      Camera.ProjectionType := ptOrthographic;
      Camera.Orthographic.Width := 1;
      Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    end;
  Resize;
end;
{$endif}

procedure TCastleCameraHelper.ViewFromRadius(const ARadius: Single; const ACamPos: TVector3);
var
  Spherical: TVector3;
begin
  Spherical := ACamPos.Normalize;
  Spherical := Spherical * ARadius;
  Up := Vector3(0, 1, 0);
  Direction := -ACamPos;
  Translation  := Spherical;
end;

procedure TCastleApp.Reflow;
var
  pos: TCardPos;
  I: Integer;
  C: Integer;
  TrialBestFit: TBestFit;
begin
  if bfw.Quantity > 0 then
    begin
      TrialBestFit := CardModel.MakeBestFit(PackSize, Container);
      if (TrialBestFit.Rows <> bfw.Rows) or (TrialBestFit.Columns <> bfw.Columns) then
        begin
          bfw := TrialBestFit;
          C := 0;
          for I := 0 to Length(CardList) - 1 do
            begin
              if Assigned(CardList[I]) then
                begin
                  pos := GetCardPos(C);
                  CardList[pos.Index].Translation := vector3((pos.X * CardModel.NormalWidth) + (CardModel.NormalWidth / 2), ((bfw.Rows - 1) * CardModel.NormalHeight) - (pos.Y * CardModel.NormalHeight) + (CardModel.NormalHeight / 2), 0);
                  Inc(C);
                end;
            end;
        end
      else
        bfw := CardModel.ResizeBestFit(bfw, Container);
    end;
end;

procedure TCastleApp.RandomMultiCard;
var
  pos: TCardPos;
  fn: String;
begin
  if bfw.Quantity > 0 then
    begin
//      fn := zipfs.FileIndex(CardCount mod zipfs.Count);
      fn := zipfs.RandomFile;
      if(Length(CardList) < bfw.Quantity) then
        begin
          SetLength(CardList, bfw.Quantity);
        end;
      pos := GetCardPos(CardCount);
      if UseTextureChange then
        begin
          if Assigned(CardList[pos.Index]) then
            CardModel.ChangeTexture(fn, CardList[pos.Index])
          else
            CardList[pos.Index] := CardModel.BuildCard(fn);
        end
      else
        begin
          if Assigned(CardList[pos.Index]) then
            begin
              ActiveScene.Remove(CardList[pos.Index]);
              CardList[pos.Index].Free;
              CardList[pos.Index] := Nil;
            end;
          CardList[pos.Index] := CardModel.BuildCard(fn);
        end;
      CardList[pos.Index].Translation := vector3((pos.X * CardModel.NormalWidth) + (CardModel.NormalWidth / 2), ((bfw.Rows - 1) * CardModel.NormalHeight) - (pos.Y * CardModel.NormalHeight) + (CardModel.NormalHeight / 2), 0);
      ActiveScene.Add(CardList[pos.Index]);
      {$ifdef savecardmodel}
      if not URIFileExists('card.x3d') then
        SaveNode(CardList[pos.Index].RootNode, 'card.x3d');
      {$endif}

      Inc(CardCount);
    end;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  sw: TStopWatch;
begin
  if Assigned(CastleApp) then
    begin
      CastleApp.CardCount := 0;

      CastleApp.FirstShow := False;
      CastleApp.bfw := CastleApp.CardModel.MakeBestFit(PackSize, CastleApp.Container);
      sw := TStopWatch.Create;
      sw.Reset;
      sw.Start;
    //  for var i := 0 to CastleApp.bfw.Quantity - 1 do
      for var i := 0 to PackSize - 1 do
        begin
        CastleApp.RandomMultiCard;
        end;
      sw.Stop;
      WriteLnLog('Time = ' + FloatToStr(sw.ElapsedMilliseconds / 1000));
      WriteLnLog('Speed = ' + FloatToStr(1 / ((sw.ElapsedMilliseconds / 1000) / CastleApp.bfw.Quantity)));

      Form1.Caption := 'Cards : ' +
        IntToStr(PackSize) +
        ' / ' +
        IntToStr(CastleApp.bfw.Quantity) +
        ' - Time : ' +
        FloatToStr(sw.ElapsedMilliseconds / 1000) +
        ' - Speed : ' +
        FloatToStr(1 / ((sw.ElapsedMilliseconds / 1000) / PackSize)) +
        '/s' +
        ' - Grid : ' +
        IntToStr(CastleApp.bfw.Columns) +
        'x' +
        IntToStr(CastleApp.bfw.Rows)
        ;
        Resize;
      CastleApp.FirstShow := True;
    end;
end;

procedure TForm1.CheckBox1Change(Sender: TObject);
begin
//  CastleApp.SwitchView3D(CheckBox1.IsChecked);
  CastleApp.UseTextureChange := not CastleApp.UseTextureChange;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  {$ifdef dolog}
  LogFileName := 'progam.log';
  InitializeLog;
  LogAllLoading := True;
  {$endif}
  ApplicationProperties.LimitFPS := 0;

  PackSize := 320;

  Trackbar2.Value := PackSize;
  Label3.Text := 'Cards : ' + IntToStr(PackSize);

  zipfs := MountZipFile('woe', 'castle-data:/woe.zip');

  CastleControl1.Align := TAlignLayout.Client;
  CastleControl1.Parent := Panel2;
  CastleApp := TCastleApp.Create(CastleControl1);
  CastleControl1.Container.View := CastleApp;
  CheckBox1.IsChecked := CastleApp.UseTextureChange;
  CastleApp.CardCount := 0;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  zipfs.Free;
end;

procedure TForm1.TrackBar2Change(Sender: TObject);
begin
  if Assigned(CastleApp) then
    begin
      PackSize := floor(Trackbar2.Value);
      CastleApp.Resize;
      Label3.Text := 'Cards : ' + IntToStr(PackSize);
    end;
end;

end.

