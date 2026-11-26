proc uploadTerrainMesh()
  ## Uploads the baked ground mesh to the selected renderer.
proc uploadWaterMesh()
  ## Uploads the baked water mesh to the selected renderer.
proc uploadTreeMesh()
  ## Uploads the baked tree mesh to the selected renderer.
proc uploadPropMesh()
  ## Uploads the baked colored prop mesh to the selected renderer.
proc uploadTexturedBatch(batch: var TexturedBatch)
  ## Uploads one changed textured prop batch.
proc updateTerrainMeshRange(offset, count: int)
  ## Refreshes a contiguous range of ground vertex values.
proc releaseTexturedBatch(batch: var TexturedBatch)
  ## Releases a batch's geometry without deleting its shared textures.
proc releasePropModel(model: PropModel)
  ## Releases the GPU geometry owned by a prop model.
proc uploadTerrainData(texture: var Texture, values: seq[float32]): Vec2
  ## Uploads packed material records and returns their texture dimensions.
proc uploadTerrainVisibility*(values: openArray[uint8], size = GridTiles)
  ## Uploads one visibility byte per tile to the selected renderer.
proc initTerrainPrograms()
  ## Compiles all terrain shader programs for the selected renderer.
proc initTerrainBuffers()
  ## Creates the terrain renderer's geometry resources.
proc initTerrainVisibility()
  ## Creates the initial visibility texture for the terrain renderer.
