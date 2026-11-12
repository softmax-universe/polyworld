import
  vmath,
  polyworld/[pathing, terrainreliefs]

const
  MapSize* = 64
  MapHalf* = MapSize.float32 / 2
  TickRate* = 30
  MaxActions* = 12
  MaxMessages* = 256
  MaxLessons* = 64

type
  MonsterError* = object of CatchableError
  ActionKind* = enum
    MoveAction, GatherAction, GiveAction, EatAction, RestAction,
    DanceAction, StopAction, WaitAction
  CreatureAction* = object
    kind*: ActionKind
    target*: string
    x*, z*: float32
    duration*: float32
  MessageRole* = enum
    PlayerMessage, CreatureMessage, EventMessage, FeedbackMessage
  Message* = object
    role*: MessageRole
    text*: string
  BrainReply* = object
    speech*: string
    actions*: seq[CreatureAction]
    lessons*: seq[string]
  LandmarkKind* = enum
    VillageLandmark, BerryLandmark, FarmLandmark, HomeLandmark,
    RiverLandmark, ForestLandmark
  Landmark* = object
    id*, name*: string
    kind*: LandmarkKind
    position*: Vec2
  Scenery* = object
    prop*: string
    position*: Vec2
    yaw*, size*: float32
  MonsterMap* = object
    seed*: int
    ground*: QuadLayer
    relief*: TerrainRelief
    blocked*: seq[bool]
    landmarks*: seq[Landmark]
    props*: seq[Scenery]
  Creature* = object
    position*: Vec2
    facing*: float32
    moving*: bool
    food*: int
    energy*: float32
  World* = object
    map*: MonsterMap
    creature*: Creature
    tick*: int32
    actions*: seq[CreatureAction]
    current*: CreatureAction
    active*: bool
    path*: seq[Vec2]
    waypoint*: int
    elapsed*: float32
    villageFood*, berryFood*, farmFood*: int
    status*: string
    events*: seq[string]
    problems*: seq[string]
