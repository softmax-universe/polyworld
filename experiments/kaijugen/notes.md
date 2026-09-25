# Kaijugen

Run from the Polyworld root:

```sh
nim r experiments/kaijugen/kaijugen.nim
```

The first preset is the green garden kaiju with a yellow belly, coral dorsal
plates, golden eyes, and dark claws. The generated mesh has named body, head,
eye, tail, and spike groups. The head, spike, and eye choices are explicit enums
with one implemented choice each, ready for additional presets.


The body, skull, jaw, haunches, and feet use authored cross-sections. Bent
arms and the curled tail use variable elliptical sections. The yellow jaw
and belly share geometry with the skin, and the eye artwork is projected
onto the actual sculpted facial triangles. Horns and plates have beveled,
swept volume. These profiles are in `src/polyworld/kaijus.nim`.

The viewer uses Chargen's Silky controls and Polyworld's toon renderer. It has
orthographic front, side, back, and three-quarter views, a turntable, and a
wireframe overlay. Shape controls adjust the head, eye, plate, and tail sizes
and the mix of smooth and flat normals. Colors are independent for the skin,
belly, spikes, iris, and claws. The eye artwork keeps pupils and glints clipped
inside the eyelids.

The Shading tab exposes soft toon and cel ramps, band threshold and softness,
shadow depth, rim strength, light direction and height, and cast shadows.
Shading controls are viewer settings. They are not part of the saved recipe.

Controls:

- Left drag to orbit. Right or middle drag to pan. Scroll to zoom.
- Space toggles the turntable. F fits the model. W toggles wireframe.
- 1, 2, and 3 select Shape, Colors, and Shading. C toggles soft toon and cel.
- Tab hides or shows the controls. Escape closes the tool.
- Save and Load use `tmp/kaijugen/custom.json`.
- Export GLB writes `tmp/kaijugen/kaiju.glb`.

Exported GLBs contain editable meshes, solid materials, and embedded eye
textures. The toon lighting and studio floor belong to the viewer. This first
model is a static procedural model without a skeleton or animation clips.

Reproducible renders and exports:

```sh
nim c -o:tmp/kaijugen/kaijugen experiments/kaijugen/kaijugen.nim
tmp/kaijugen/kaijugen --screenshot=tmp/kaijugen/viewer.png
tmp/kaijugen/kaijugen --no-panel --yaw=1.5708 --pitch=0.12 \
  --screenshot=tmp/kaijugen/side.png
tmp/kaijugen/kaijugen --export=tmp/kaijugen/kaiju.glb
tmp/kaijugen/kaijugen --load=tmp/kaijugen/custom.json
nim r tests/test_kaijus.nim
```

Screenshot and smoke runs use a hidden window and exit after four frames.
`--frames=N` overrides that count. Export runs do not create a window.
