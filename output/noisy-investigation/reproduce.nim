import
  std/[math, os, random, strformat],
  noisy

proc correctedSimplex(seed: int): Simplex =
  ## Shuffles one permutation, then duplicates it for wrapped lookups.
  result = initSimplex(seed)
  var
    permutation: array[256, int32]
    rng = initRand(seed)
  for i in 0 ..< permutation.len:
    permutation[i] = i.int32
  shuffle(rng, permutation)
  for i in 0 ..< result.perm.len:
    result.perm[i] = permutation[i and 255]
    result.permMod12[i] = result.perm[i] mod 12

const
  Size = 401
  Radius = 1.5'f
  F2 = ((sqrt(3.0) - 1) / 2).float32
  SliceY = 0.25'f
  SeamX = -SliceY * F2 / (1 + F2)

let
  original = initSimplex(1988)
  corrected = correctedSimplex(1988)
  outputDirectory = currentSourcePath().parentDir

var differentPairs = 0
for i in 0 ..< 256:
  if original.perm[i] != original.perm[i + 256]:
    inc differentPairs
  doAssert corrected.perm[i] == corrected.perm[i + 256]
echo "Original unequal permutation pairs: ", differentPairs, " / 256"
echo "Crossing the skewed lattice boundary at x=", SeamX, ", y=", SliceY
for epsilon in [0.001'f, 0.0001'f, 0.00001'f, 0.000001'f]:
  let
    beforeLeft = original.value(SeamX - epsilon, SliceY)
    beforeRight = original.value(SeamX + epsilon, SliceY)
    afterLeft = corrected.value(SeamX - epsilon, SliceY)
    afterRight = corrected.value(SeamX + epsilon, SliceY)
  echo &"epsilon={epsilon} original=({beforeLeft}, {beforeRight}) " &
    &"jump={abs(beforeRight - beforeLeft)} " &
    &"corrected jump={abs(afterRight - afterLeft)}"

doAssert abs(
  original.value(SeamX - 0.000001'f, SliceY) -
  original.value(SeamX + 0.000001'f, SliceY)
) > 0.4'f
doAssert abs(
  corrected.value(SeamX - 0.000001'f, SliceY) -
  corrected.value(SeamX + 0.000001'f, SliceY)
) < 0.0001'f

echo "Origin values across seeds:"
for seed in [1, 2, 42, 1988]:
  echo "seed=", seed, " value=", initSimplex(seed).value(0, 0)

let samples = open(outputDirectory / "samples.csv", fmWrite)
samples.writeLine("x,y,original,corrected")
for row in 0 ..< Size:
  let y = -Radius + 2 * Radius * row.float32 / (Size - 1).float32
  for column in 0 ..< Size:
    let x = -Radius + 2 * Radius * column.float32 / (Size - 1).float32
    samples.writeLine(
      &"{x},{y},{original.value(x, y)},{corrected.value(x, y)}"
    )
samples.close()

let slice = open(outputDirectory / "slice.csv", fmWrite)
slice.writeLine("x,original,corrected")
for i in 0 .. 1000:
  let x = SeamX - 0.01'f + 0.02'f * i.float32 / 1000
  slice.writeLine(
    &"{x},{original.value(x, SliceY)},{corrected.value(x, SliceY)}"
  )
slice.close()
echo "Reproduced the original seam and verified corrected continuity."
