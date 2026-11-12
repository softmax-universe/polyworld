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
  CarryLimit* = 6
  VillagerCarryLimit* = 2
  SourceIds* = ["berries", "farm", "fish", "pine", "oak", "stone"]
  HouseholdIds* = ["miller_hut", "weaver_hut", "mason_hut"]
  VillagerIds* = ["ada", "ben", "clara", "dara", "eli", "finn"]
  DeliveryIds* = ["village", "hall", "miller_hut", "weaver_hut",
    "mason_hut", "ada", "ben", "clara", "dara", "eli", "finn"]

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
    RiverLandmark, ForestLandmark, ResourceLandmark, HouseholdLandmark
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
  ResourceKind* = enum
    BerriesResource, GrainResource, FishResource, SoftwoodResource,
    HardwoodResource, StoneResource
  Inventory* = array[ResourceKind, int]
  ResourceSource* = object
    id*, name*: string
    position*: Vec2
    resource*: ResourceKind
    amount*, capacity*: int
    elapsed*: float32
  Household* = object
    id*, name*: string
    position*: Vec2
    stock*: Inventory
    integrity*, fuel*: float32
  VillagerTask* = enum
    IdleTask, GatherTask, WithdrawTask, DeliverTask, EatTask,
    RefuelTask, RepairTask
  Villager* = object
    id*, name*: string
    home*: int
    position*: Vec2
    facing*: float32
    moving*: bool
    cargo*: Inventory
    hunger*: float32
    activity*, target*: string
    task*: VillagerTask
    resource*: ResourceKind
    path*: seq[Vec2]
    waypoint*: int
    elapsed*, retry*: float32
  Creature* = object
    position*: Vec2
    facing*: float32
    moving*: bool
    cargo*: Inventory
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
    stock*: Inventory
    sources*: seq[ResourceSource]
    households*: seq[Household]
    villagers*: seq[Villager]
    status*: string
    events*: seq[string]
    problems*: seq[string]
