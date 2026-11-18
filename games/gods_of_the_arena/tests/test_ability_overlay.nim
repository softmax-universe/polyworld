## Production HUD clicks keep learning controls separate from ability use.
import std/[importutils, os]
import opengl, windy/internal
import polyworld/[assets, common, soundassets, viewers]
import ../replays

var playedSounds: seq[SoundCue]

proc playSound(cue: SoundCue) =
  ## Records the HUD response without opening a sound device.
  playedSounds.add cue

include ../ui
privateAccess(Window)

let window = newWindow(
  "GotA ability overlay",
  ivec2(1600, 1000),
  visible = false
)
window.makeContextCurrent()
loadExtensions()
let builder = newHudAtlas(2048)
builder.addDefaultFonts()
builder.addFont(DefaultFontPath, "HeroVersus", 24.0)
doAssert builder.addImage(
  HeroPortraitKeys[VanguardKnight],
  readImage(HeroPortraitPaths[VanguardKnight])
)
for slot in HeroAbilitySlot:
  let ability = heroAbility(VanguardKnight, slot)
  doAssert builder.addImage(
    abilityIconKey(ability),
    readImage(DataRoot / "abilities" / (ability.abilitySpec.icon & ".png"))
      .resize(128, 128)
  )
let
  sk = newSilky(window, builder.atlasImage, builder.atlas)
sk.applyThemePatches()
sk.uiScale = 1
run = newGame(
  generateMap(7),
  100000,
  10,
  false,
  ReplayData(),
  drafting = false,
  activeSeats = @[0]
)
run.networked = true
run.replayData.config.players.setLen(1)
run.replayData.config.maxTicks = 10000
let hero = run.world.heroes[0]
hero.class = VanguardKnight
hero.level = HeroMaxLevel
hero.mana = 10000
hero.maxMana = 10000
hero.abilityLevels = [1'i32, 1, 1, 1]
hero.charges = [1'i32, 1, 1, 1]
options.playerSlot = 1
customBindingsEnabled = true
inputBindings = DefaultBindings
configureSounds(true, 100, 100, 100, 100)
var
  transport = initPlayer(live = true, durationTicks = 1000, playing = true)
  primaryId = hero.id
  selectedIds = @[hero.id]
  followSelection, focusPlayerHero, attackMoveArmed: bool
  director = initActionCam()

proc takeCommands(): seq[ReplayAction] =
  ## Reads the same outbound action queue used by network matches.
  run.flushPlayerCommands()
  for submission in run.submissions:
    result.add submission.action
  run.submissions.setLen(0)

proc click(point: Vec2, shift = false) =
  ## Sends a native mouse press through the complete production HUD.
  clearHudTooltip()
  window.state.perFrame = PerFrame(buttonPressed: {MouseLeft})
  window.state.buttonDown =
    if shift: {MouseLeft, KeyLeftShift}
    else: {MouseLeft}
  playedSounds.setLen(0)
  sk.beginUi(window, window.size)
  sk.mousePos = point
  sk.drawUi(
    window,
    transport,
    vec3(0),
    80,
    0,
    primaryId,
    selectedIds,
    followSelection,
    director,
    focusPlayerHero,
    attackMoveArmed,
    false
  )
  sk.endUi()

let
  ranks = hero.abilityLevels
  points = hero.abilityPoints
  panels = currentChrome(window).details.detailsPanels()
for slot in HeroAbilitySlot:
  doAssert hero.abilityLevelError(slot) == NoActionError,
    "The learning plus must be available for the tested ability"
  let
    well = panels.abilities[slot.ord]
    center = well.origin + well.size / 2
    plus = well.origin + vec2(well.size.x - 12, 12)
  click(center)
  let casts = takeCommands()
  if heroAbility(hero.class, slot).abilitySpec.casting == SelfCast:
    doAssert casts.len == 1 and casts[0].kind == ActionCastTarget
    doAssert casts[0].slot == slot.ord and casts[0].first == hero.id
  else:
    doAssert casts.len == 0 and armedAbility == slot.ord
  doAssert SelectSound in playedSounds and ErrorSound notin playedSounds,
    "Clicking the learned icon must activate successfully beneath its plus"
  doAssert hero.abilityLevels == ranks and hero.abilityPoints == points
  for target in [plus, center]:
    click(target, shift = target == center)
    let upgrades = takeCommands()
    doAssert upgrades.len == 1 and upgrades[0].kind == ActionLevelAbility
    doAssert upgrades[0].slot == slot.ord and armedAbility == -1
    doAssert hero.abilityLevels == ranks and hero.abilityPoints == points,
      "Learning clicks must queue authority rather than mutate local ranks"
clearPlayerCommands()
window.close()
echo "PASS production HUD: learned icons cast, plus and Shift-click learn"
