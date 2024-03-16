// PreCalcMeshColorPatterns is the core function of gradient calculations


<...>

	TFantomMesh = class(TEntity)
		private const
			FPropagateDepth = 4;

		private type
			TGLMeshList = TObjectList<TGLMesh>;


			TGLMeshListHelper = class helper for TGLMeshList
				public
					class procedure Copy(var Dest: TGLMeshList; const Src: TGLMeshList);
			end;

		private
			FDrawTranslucentAsOpaque                 : Boolean;
			FMeshList                                : TGLMeshList;
			FTransparentList                         : TGLMeshList;
			FSilhouette                              : Boolean;
			FFantomHighlights, FFantomHighlightsCache: TFantomHighlights;
			FbZonesUpdateStarted                     : Boolean;
			FbSmoothEnabled                          : Boolean;
			FbOutlineEnabled                         : Boolean;
			FbForceUpdateCache                       : Boolean;
			FMeshResName                             : string;

			procedure PreCalcMeshColorPatterns(bSupportOutline, bSupportSmooth: Boolean);
			procedure AssignMaskColors;
			procedure AssignSilhouetteColors;


		public
			function GetZoneCount: Integer;
			constructor Create;
			procedure LoadFromRes(const MeshResName: string);
			procedure Assign(Source: TPersistent); override;
			destructor Destroy; override;
			procedure ZonesUpdateBegin;
			procedure ZoneUpdate(Zone: Integer; Color: TColor; bSolid: Boolean = False);
			procedure ZonesUpdateEnd;
			procedure Redraw; override;
			procedure RedrawMasked; override;
			function GetMaskZone(const cl: TGLColor): Integer;

			procedure GLBind; override;
			procedure GLRelease; override;

			property  Silhouette: Boolean
				read  FSilhouette
				write FSilhouette;
			property  DrawTranslucentAsOpaque: Boolean
				read  FDrawTranslucentAsOpaque
				write FDrawTranslucentAsOpaque;
			property  ZoneCount: Integer
				read  GetZoneCount;
	end;


<...>

procedure Scale;
var
	Mesh   : TGLMesh;
	MaxDist: Single;
begin
	MaxDist := 0;
	for Mesh in FMeshList do
		MaxDist := max(MaxDist, Mesh.MaxSize);
	for Mesh in FTransparentList do
		MaxDist := max(MaxDist, Mesh.MaxSize);

	if MaxDist > 0 then begin
		for Mesh in FMeshList do
			Mesh.Scale(1.0 / MaxDist);

		for Mesh in FTransparentList do
			Mesh.Scale(1.0 / MaxDist);
	end;
end;


<...>

begin
	Scale;
	AssignMaskColors;
	AssignSilhouetteColors;

	PreCalcMeshColorPatterns(FbOutlineEnabled, FbSmoothEnabled);
end;


procedure TFantomMesh.Assign(Source: TPersistent);
var
	S: TFantomMesh;
begin
	inherited;
	if Source is TFantomMesh then begin
		S := TFantomMesh(Source);
		FDrawTranslucentAsOpaque := S.FDrawTranslucentAsOpaque;
		FbSmoothEnabled := S.FbSmoothEnabled;
		FbOutlineEnabled := S.FbOutlineEnabled;
		FSilhouette := S.FSilhouette;

		TGLMeshList.Copy(FMeshList, S.FMeshList);
		TGLMeshList.Copy(FTransparentList, S.FTransparentList);

		FFantomHighlights := Copy(S.FFantomHighlights);
		FFantomHighlightsCache := Copy(S.FFantomHighlightsCache);

		FbZonesUpdateStarted := S.FbZonesUpdateStarted;
		FbForceUpdateCache := S.FbForceUpdateCache;
		FMeshResName := S.FMeshResName;
	end;
end;


procedure TFantomMesh.AssignMaskColors;
var
	i   : Integer;
	Mesh: TGLMesh;
	cl  : TGLColor;
begin
	for i := 0 to FMeshList.Count - 1 do begin
		Mesh := FMeshList[i];
		cl.V := i * 10;
		Mesh.SetMaskColor(cl);
	end;
end;


procedure TFantomMesh.AssignSilhouetteColors;
var
	Mesh: TGLMesh;
begin
	for Mesh in FTransparentList do
		Mesh.SetSolidVertexColors(clSilhouette);
end;


constructor TFantomMesh.Create;
begin
	inherited;

	FDrawTranslucentAsOpaque := False;
	FbSmoothEnabled := False;
	FbOutlineEnabled := False;
	FFantomHighlights := nil;
	FFantomHighlightsCache := nil;

	FMeshList := TGLMeshList.Create;
	FTransparentList := TGLMeshList.Create;

	FMeshResName := '';
end;


function TFantomMesh.GetMaskZone(const cl: TGLColor): Integer;
begin
	Result := cl.V div 10;
end;


procedure TFantomMesh.PreCalcMeshColorPatterns(bSupportOutline, bSupportSmooth: Boolean);
var
	i, j       : Integer;
	FntFillInfo: TFantomFillInfo;
begin
	if not bSupportOutline and not bSupportSmooth then
		Exit;

	FntFillInfo := nil;
	SetLength(FntFillInfo, FMeshList.Count);

	// Add inner weight
	for i := 0 to FMeshList.Count - 1 do begin
		FMeshList[i].CalculateBoundingShape;
		FMeshList[i].FillPrepVertices(i, FntFillInfo[i].Verts);
	end;


	// Create cross mesh links, excluding self-self
	for i := 0 to FMeshList.Count - 1 do
		for j := 0 to i - 1 do begin
			if FMeshList[i].HasIntersects(FMeshList[j],
				AppPrefs.FantomsGraphics.SmoothingMaxRange) then begin
				FMeshList[i].FillDetectCrossLinks(i, j, FMeshList[i], FMeshList[j],
					FntFillInfo[i], FntFillInfo[j],
					AppPrefs.FantomsGraphics.SmoothingMaxRange);
			end;

		end;

	if bSupportSmooth then begin
		// Propagate inner links & crosslinks
		for j := 0 to FPropagateDepth - 1 do begin
			for i := 0 to FMeshList.Count - 1 do
				FMeshList[i].FillPropagateInner(FntFillInfo[i].Verts);
			for i := 0 to FMeshList.Count - 1 do
				FMeshList[i].FillPropagateCross(FntFillInfo, i);
		end;

		// Finally calculate weights of links
		for i := 0 to FMeshList.Count - 1 do
			FMeshList[i].FillEstimateWeights(FntFillInfo[i].Verts);
	end;


	// And detect edges for segment fantoms
	if bSupportOutline then begin
		for i := 0 to FMeshList.Count - 1 do
			FMeshList[i].FillDetectEdges(FntFillInfo[i]);
	end;

	// Set propagated links to meshes
	for i := 0 to FMeshList.Count - 1 do begin
		FMeshList[i].FillSet(FntFillInfo[i], bSupportOutline, bSupportSmooth);
	end;
end;


procedure TFantomMesh.ZonesUpdateBegin;
var
	i: Integer;
begin
	Assert(not FbZonesUpdateStarted);

	FbZonesUpdateStarted := true;
	SetLength(FFantomHighlights, FMeshList.Count);
	for i := 0 to high(FFantomHighlights) do begin
		FFantomHighlights[i].bSolid := true;
		FFantomHighlights[i].Color := clMeshDefault;
	end;

end;


procedure TFantomMesh.ZoneUpdate(Zone: Integer; Color: TColor; bSolid: Boolean = False);
var
	R, G, B  : Byte;
	HighLight: TMeshHighlight;
begin
	Assert(InRange(Zone, 0, FMeshList.Count - 1));
	Assert(FbZonesUpdateStarted);

	R := GetRValue(Color);
	G := GetGValue(Color);
	B := GetBValue(Color);

	// Highlight matches background
	if FMeshList[Zone].bTransparent and (R + G + B > 240 * 3) then
		HighLight.Color := clMeshDefault
	else
		HighLight.Color.V := Color;
	HighLight.bSolid := bSolid;

	FFantomHighlights[Zone] := HighLight;
end;


procedure TFantomMesh.ZonesUpdateEnd;
var
	Zone: Integer;
	sz  : Integer;
begin
	if FbZonesUpdateStarted then
		FbZonesUpdateStarted := False
	else
		Assert(False);


	sz := sizeof(TMeshHighlight) * Length(FFantomHighlights);
	if Length(FFantomHighlightsCache) = Length(FFantomHighlights) then
		if CompareMem(FFantomHighlightsCache, FFantomHighlights, sz) then
			if not FbForceUpdateCache then
				Exit
			else
				FbForceUpdateCache := False;

	for Zone := 0 to high(FFantomHighlights) do
		if AppPrefs.FantomsGraphics.UseSmoothing and FbSmoothEnabled and
			(not FFantomHighlights[Zone].bSolid) then
			FMeshList[Zone].SetSmoothVertexColors(FFantomHighlights,
				not AppPrefs.FantomsGraphics.DebugShowWire)
		else
			FMeshList[Zone].SetSolidVertexColors(FFantomHighlights[Zone].Color);

	FFantomHighlightsCache := Copy(FFantomHighlights);
end;


function TFantomMesh.GetZoneCount: Integer;
begin
	Result := FMeshList.Count;
end;


procedure TFantomMesh.Redraw;
type
	TMeshDesc = (mdTRANSPARENTS, mdSOLIDS);

	procedure DrawSilhouette;
	var
		TrMesh: TGLMesh;
	begin
		for TrMesh in FTransparentList do begin
			TrMesh.SetColorMode(cmSILHOUETTE);
			TrMesh.Redraw;
		end;
	end;

	procedure DrawMeshes(ToDraw: TMeshDesc);
	var
		Mesh: TGLMesh;
	begin
		for Mesh in FMeshList do begin
			if (ToDraw = mdSOLIDS) and Mesh.bTransparent then
				continue;
			if (ToDraw = mdTRANSPARENTS) and not Mesh.bTransparent then
				continue;

			if (ToDraw = mdSOLIDS) then
				Mesh.SetColorMode(cmNORMAL);

			if (ToDraw = mdTRANSPARENTS) then
				Mesh.SetColorMode(cmINVERTED);

			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
			Mesh.Redraw;

			if AppPrefs.FantomsGraphics.DebugShowWire then begin
				glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
				Mesh.SetColorMode(cmINVERTED);
				Mesh.Redraw;
			end;
		end;

	end;


begin

	// glDisable(GL_CULL_FACE); //Some model bug requres this
	// glCullFace(GL_FRONT);

	glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_COLOR);

	glDisable(GL_BLEND);

	DrawMeshes(mdSOLIDS);

	glEnable(GL_BLEND);
	glDepthMask(GL_FALSE);

	DrawMeshes(mdTRANSPARENTS);

	if FSilhouette then
		DrawSilhouette;

	glDepthMask(GL_TRUE);
end;


procedure TFantomMesh.RedrawMasked;
var
	Mesh: TGLMesh;
begin
	glDisable(GL_BLEND);
	glDisable(GL_LIGHTING);

	for Mesh in FMeshList do
		Mesh.Redraw(true);

	glEnable(GL_LIGHTING);
	glEnable(GL_BLEND);
end;


procedure TFantomMesh.GLBind;
var
	Mesh: TGLMesh;
begin
	for Mesh in FMeshList do
		Mesh.CreateVertexBuffers;
	for Mesh in FTransparentList do
		Mesh.CreateVertexBuffers;
end;


procedure TFantomMesh.GLRelease;
var
	Mesh: TGLMesh;
begin
	for Mesh in FMeshList do
		Mesh.FreeVertexBuffers;
end;


<...>