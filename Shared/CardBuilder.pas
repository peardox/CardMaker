unit CardBuilder;

interface

uses System.SysUtils, System.Types, System.UITypes, System.Classes,
  CastleScene, CastleImages, CastleUIControls, X3DNodes;

type
  TTrialRect = record
    Rows: Integer;
    Columns: Integer;
    Spare: Integer;
  end;
  { This type is used to work out the spare slots
    for any arrangement of cols + rows in a grid.
    Spare may be negative which is makes that option
    invalid }

  TBestFit = record
    Rows: Integer;
    Columns: Integer;
    Quantity: Integer;
    AspectRatio: Single;
    Rect: TRectF;
  end;
  { This type is to hold the result of the ideal rectangle to
    hold HowMany similar objects in a grid. The ideal rectangle
    is the one that holds HowMany objects and has the
    minimum number of employ slots }

  TCard = class(TComponent)
    private
      fMask: TCastleImage;
      fBack: TCastleImage;
      fMaskFile: String;
      fBackFile: String;
      fWidth: Single;
      fHeight: Single;
      fAspect: Single;
      function CreateAlphaMaskShader: TEffectNode;
      procedure SetMaskFile(const AFilename: String);
      procedure SetBackFile(const AFilename: String);
      procedure SetWidth(const AValue: Single);
      procedure SetHeight(const AValue: Single);
      function GetNormalWidth: Single;
      function GetNormalHeight: Single;
      function MakeTrialRect(const HowMany: Integer; const TrialColumns: Integer; const TrialRows: Integer): TTrialRect;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      procedure ChangeTexture(const Filename: String; var Card: TCastleScene);
      function BuildCard(const Filename: String): TCastleScene;
      property MaskFile: String read fMaskFile write SetMaskFile;
      property BackFile: String read fBackFile write SetBackFile;
      property Width: Single read fWidth write SetWidth;
      property Height: Single read fHeight write SetHeight;
      property NormalWidth: Single read GetNormalWidth;
      property NormalHeight: Single read GetNormalHeight;
      function MakeBestFit(const HowMany: Integer; const AContainer: TCastleContainer): TBestFit; overload;
      function MakeBestFit(const HowMany: Integer; const AContainer: TRectF): TBestFit; overload;
      function ResizeBestFit(const OldFit: TBestFit; const AContainer: TCastleContainer): TBestFit; overload;
      function ResizeBestFit(const OldFit: TBestFit; const AContainer: TRectF): TBestFit; overload;
    end;
    {
    Creation Example

    CardModel := TCard.Create(AOwner);
    CardModel.MaskFile := 'castle-data:/frameAlpha.png';
    CardModel.BackFile := 'castle-data:/back.jpg';
    CardModel.Width  := 0.71634615384;
    CardModel.Height := 1.0;
    }

function BestFit(const AWidth: Single; const AHeight: Single; const NColumns: Integer; const NRows: Integer; const DesiredAspect: Single): TBestFit;

const
  AlphaShaderCode: String = 'uniform sampler2D mask_texture; void PLUG_texture_color(inout vec4 texture_color, const in sampler2D alpha_texture, const in vec4 tex_coord) {float alpha = texture2D(mask_texture, tex_coord.st).r; texture_color = vec4(texture_color.xyz, alpha);}';

implementation

uses Math,
  CastleVectors,
  CastleTransform,
  CastleURIUtils, { for URIFileExists }
  CastleRenderOptions, { for stFragment }
  X3DFields; {for TSF..... }

function BestFit(const AWidth: Single; const AHeight: Single; const NColumns: Integer; const NRows: Integer; const DesiredAspect: Single): TBestFit;
var
  Aspect: Single;
  ARect: TRectF;
  Adjust: Single;
begin
  Aspect := (NColumns * AWidth) / (NRows * AHeight);
  Adjust := DesiredAspect / Aspect;
  if DesiredAspect > Aspect then // 1.78 > 1.72
    ARect := TRectF.Create(0, 0, (NColumns * Adjust), NRows)
  else if DesiredAspect < Aspect then
    ARect := TRectF.Create(0, 0, NColumns, (NRows * Adjust))
  else
    ARect := TRectF.Create(0, 0, NColumns, NRows);

  with Result do
    begin
      Rows:= NRows;
      Columns := NColumns;
      Quantity := Columns * Rows;
      AspectRatio :=  (Columns * AWidth) / (Rows * AHeight);;
      Rect := ARect;
    end;
end;

constructor TCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fMask := Nil;
  fBack := Nil;
  fWidth := 1.0;
  fHeight := 1.0;
end;

destructor TCard.Destroy;
begin
  if Assigned(fBack) then
    begin
      fBack.Free;
      fBack := Nil;
    end;
  if Assigned(fMask) then
    begin
      fMask.Free;
      fMask := Nil;
    end;
  inherited;
end;

function TCard.GetNormalWidth: Single;
begin
  if fAspect < 1 then
    Result := 1
  else
    Result := fAspect;
end;

function TCard.GetNormalHeight: Single;
begin
  if fAspect < 1 then
    Result := 1 / fAspect
  else
    Result := 1;
end;

procedure TCard.SetWidth(const AValue: Single);
begin
  if AValue > 0 then
    begin
      fWidth := AValue;
      if (fWidth > 0) and (fHeight > 0) then
        begin
          fAspect := fWidth / fHeight;
        end;
    end
  else
    raise Exception.Create('Rect Width must be > 0');
end;

procedure TCard.SetHeight(const AValue: Single);
begin
  if AValue > 0 then
    begin
      fHeight := AValue;
      if (fWidth > 0) and (fHeight > 0) then
        begin
          fAspect := fWidth / fHeight;
        end;
    end
  else
    raise Exception.Create('Rect Height must be > 0');
end;

procedure TCard.SetMaskFile(const AFilename: String);
begin
  if (AFilename <> EmptyStr) then
    begin
      if URIFileExists(AFilename) then
        begin
          fMaskFile := AFilename;
          try
            fMask := LoadImage(fMaskFile, [TRGBImage]) as TRGBImage;
          except
            on E : Exception do
              raise Exception.Create('Error in SetMaskFile : ' + E.ClassName + ' - ' + E.Message);
          end;
        end
      else
        raise Exception.Create(AFilename + ' : Mask File Not Found');
    end;
end;

procedure TCard.SetBackFile(const AFilename: String);
begin
  if (AFilename <> EmptyStr) then
    begin
      if URIFileExists(AFilename) then
        begin
          fBackFile := AFilename;
          try
            fBack := LoadImage(fBackFile, [TRGBImage]) as TRGBImage;
          except
            on E : Exception do
              raise Exception.Create('Error in SetBackFile : ' + E.ClassName + ' - ' + E.Message);
          end;
        end
      else
        raise Exception.Create(AFilename + ' : Back File Not Found');
    end;
end;

function TCard.CreateAlphaMaskShader: TEffectNode;
var
  MaskTextureNode: TImageTextureNode;
  Shader: TEffectNode;
  FragmentPart: TEffectPartNode;
  EffectTextureField: TSFNode;
begin
  MaskTextureNode := TImageTextureNode.Create;
  MaskTextureNode.LoadFromImage(fMask, False, '');
  MaskTextureNode.X3DName := 'MaskTexture';

  Shader := TEffectNode.Create;
  Shader.Language := slGLSL;
  Shader.X3DName := 'ShaderEffect';

  EffectTextureField := TSFNode.Create(Shader, false, 'mask_texture', [TImageTextureNode], MaskTextureNode);
  Shader.AddCustomField(EffectTextureField);

  FragmentPart := TEffectPartNode.Create;
  FragmentPart.ShaderType := stFragment;
  FragmentPart.Contents := AlphaShaderCode;
  Shader.SetParts([FragmentPart]);
  Shader.Enabled := True;

  Result := Shader;
end;

procedure TCard.ChangeTexture(const Filename: String; var Card: TCastleScene);
var
  Img: TCastleImage;
  PixelTextureNode: TPixelTextureNode;
begin
    Img := LoadImage(Filename, [TRGBImage]) as TRGBImage;

    PixelTextureNode := Card.Node('CardTexture') as TPixelTextureNode;
    PixelTextureNode.FdImage.Value := Img;
    PixelTextureNode.FdImage.Changed;
end;

function TCard.BuildCard(const Filename: String): TCastleScene;
var
  X3DTree: TX3DRootNode;
  Shape: TShapeNode;
  Geometry: TIndexedFaceSetNode;
  Coordinate: TCoordinateNode;
  TextureCoordinate: TTextureCoordinateNode;
  Img: TCastleImage;
  UnlitMaterialNode: TUnlitMaterialNode;
  PixelTextureNode: TPixelTextureNode;
  MouseHook: TTouchSensorNode;
  Shader: TEffectNode;
  vWidth: Single;
  vHeight: Single;
begin
  Result := Nil;
  if fAspect < 1 then
    begin
      vWidth := 1/2;
      vHeight := 0.5/fAspect;
    end
  else
    begin
      vHeight := 1/2;
      vWidth := 0.5/fAspect;
    end;

  try
    Img := LoadImage(Filename, [TRGBImage]) as TRGBImage;

    PixelTextureNode := TPixelTextureNode.Create;
    PixelTextureNode.X3DName := 'CardTexture';
    PixelTextureNode.FdImage.Value := Img;
  //  PixelTextureNode.FdImage.Changed;

    if PixelTextureNode.IsTextureImage then
      begin
        { Define the front }
        Coordinate := TCoordinateNode.Create;

        Coordinate.SetPoint([
          Vector3(-vWidth, -vHeight, 0),
          Vector3( vWidth, -vHeight, 0),
          Vector3( vWidth,  vHeight, 0),
          Vector3(-vWidth,  vHeight, 0)
        ]);

        TextureCoordinate := TTextureCoordinateNode.Create;
        TextureCoordinate.SetPoint([
          Vector2( 0, 0),
          Vector2( 1, 0),
          Vector2( 1, 1),
          Vector2( 0, 1)
        ]);

        { Create Shape and IndexedFaceSet node (mesh with coordinates, texture coordinates) }
        Geometry := TIndexedFaceSetNode.CreateWithShape(Shape);
        Geometry.Coord := Coordinate;
        Geometry.TexCoord := TextureCoordinate;
        Geometry.Solid := true; // false; // to see it from any side
        Geometry.SetCoordIndex([0, 1, 2, 3]);

        { Create Appearance (refers to a texture, connects the Texture to Shape) }
        Shape.Appearance := TAppearanceNode.Create;
        UnlitMaterialNode := TUnlitMaterialNode.Create;
        UnlitMaterialNode.EmissiveTexture := PixelTextureNode;

        Shader := CreateAlphaMaskShader;
        PixelTextureNode.SetEffects([Shader]);

        Shape.Appearance.Material := UnlitMaterialNode;
        Shape.Appearance.Material.X3dName := 'Material_Front';
        Shape.Appearance.AlphaMode := amMask;

        MouseHook := TTouchSensorNode.Create('MouseHook');

        X3DTree := TX3DRootNode.Create;
        { Add mouse hook to tree }
        X3DTree.AddChildren(MouseHook);
        { Add front to tree }
        X3DTree.AddChildren(Shape);
        { Add back to tree }

        Img := fBack.MakeCopy;

        PixelTextureNode := TPixelTextureNode.Create;
        PixelTextureNode.X3DName := 'BackTexture';
        PixelTextureNode.FdImage.Value := Img;

        { Define the back }

        Coordinate := TCoordinateNode.Create;
        Coordinate.SetPoint([
          Vector3( vWidth, -vHeight, 0),
          Vector3(-vWidth, -vHeight, 0),
          Vector3(-vWidth,  vHeight, 0),
          Vector3( vWidth,  vHeight, 0)
        ]);

        TextureCoordinate := TTextureCoordinateNode.Create;
        TextureCoordinate.SetPoint([
          Vector2( 0, 0),
          Vector2( 1, 0),
          Vector2( 1, 1),
          Vector2( 0, 1)
        ]);

        Geometry := TIndexedFaceSetNode.CreateWithShape(Shape);
        Geometry.Coord := Coordinate;
        Geometry.TexCoord := TextureCoordinate;
        Geometry.Solid := true;
        Geometry.SetCoordIndex([0, 1, 2, 3]);

        Shape.Appearance := TAppearanceNode.Create;
        UnlitMaterialNode := TUnlitMaterialNode.Create;
        UnlitMaterialNode.EmissiveTexture := PixelTextureNode;

        Shader := CreateAlphaMaskShader;
        PixelTextureNode.SetEffects([Shader]);

        Shape.Appearance.Material := UnlitMaterialNode;
        Shape.Appearance.Material.X3dName := 'Material_Back';
        Shape.Appearance.AlphaMode := amMask;

        X3DTree.AddChildren(Shape);

        Result := TCastleScene.Create(Self);
        Result.Load(X3DTree, True);
      end;
  except
    on E : Exception do
      begin
        raise Exception.Create('Error in BuildCard : ' + E.ClassName + ' - ' + E.Message);
       end;
  end;
end;

function TCard.MakeBestFit(const HowMany: Integer; const AContainer: TCastleContainer): TBestFit;
begin
  Result := MakeBestFit(HowMany, TRectF.Create(0, 0, AContainer.Width, AContainer.Height));
end;

function TCard.MakeBestFit(const HowMany: Integer; const AContainer: TRectF): TBestFit;
var
  AdjustedContainerAspect: Single;
  DesiredAspect: Single;
  bfwidth: Single;
  bfheight: Single;
  TrialRects: Array [0..5] of TTrialRect;
  Choice: Integer;
  I: Integer;
  MinSpare: Integer;
begin
  Result := Default(TBestFit);

  if not (fAspect = 0) and not (AContainer.Height = 0) then
    begin
      AdjustedContainerAspect := AContainer.Width / (AContainer.Height * fAspect);  // 2.47619047622     (322)
      bfheight := Sqrt(HowMany / AdjustedContainerAspect);  // 11.4034407762 / sqrt(130.038461537)
      bfwidth := (bfheight * AdjustedContainerAspect);  // 28.2370914462
      DesiredAspect := AContainer.Width / AContainer.Height;

      TrialRects[0] := MakeTrialRect(HowMany, floor(bfwidth), floor(bfheight));
      TrialRects[1] := MakeTrialRect(HowMany, floor(bfwidth), ceil(bfheight));
      TrialRects[2] := MakeTrialRect(HowMany, ceil(bfwidth), floor(bfheight));
      TrialRects[3] := MakeTrialRect(HowMany, ceil(bfwidth), ceil(bfheight));
      TrialRects[4] := MakeTrialRect(HowMany, floor(bfwidth)-1, ceil(bfheight));
      TrialRects[5] := MakeTrialRect(HowMany, ceil(bfwidth), floor(bfheight)-1);

      Choice := -1; // Not Chosen
      MinSpare := ceil(bfwidth) * ceil(bfheight);

      for I := Low(TrialRects) to High(TrialRects) do
        begin
          if (MinSpare > TrialRects[I].Spare) and (TrialRects[I].Spare > 0) then
            begin
              Choice := I;
              MinSpare := TrialRects[I].Spare;
            end;
        end;
      { Locate the grid with the minimum number of spare slots }

      if Choice <> -1 then
        begin
          Result := BestFit(fWidth, fHeight, TrialRects[Choice].Columns, TrialRects[Choice].Rows, DesiredAspect);
        end
      else
        raise Exception.Create('MakeBestFit couldn''t find a fit');   {This shoouldn't be possible }
    end;
end;

function TCard.MakeTrialRect(const HowMany: Integer; const TrialColumns: Integer; const TrialRows: Integer): TTrialRect;
begin
  with Result do
    begin
      Columns := TrialColumns;
      Rows := TrialRows;
      Spare := (TrialColumns * TrialRows) - HowMany;
    end;
end;

function TCard.ResizeBestFit(const OldFit: TBestFit; const AContainer: TCastleContainer): TBestFit;
begin
  Result := ResizeBestFit(OldFit, TRectF.Create(0, 0, AContainer.Width, AContainer.Height));
end;

function TCard.ResizeBestFit(const OldFit: TBestFit; const AContainer: TRectF): TBestFit;
var
  DesiredAspect: Single;
begin
  DesiredAspect := AContainer.Width / AContainer.Height;
  Result := BestFit(fWidth, fHeight, OldFit.Columns, OldFit.Rows, DesiredAspect);
end;

end.

