import
  std/strutils,
  vmath,
  polyworld/[pathing, terrainreliefs]

const
  MapSize* = 128
  MapHalf* = MapSize.float32 / 2
  TickRate* = 30
  MaxActions* = 12
  MaxMessages* = 256
  MaxLessons* = 64
  CarryLimit* = 6
  VillagerCarryLimit* = 2
  VillageWorkReserves* = [4, 6, 4, 6, 4, 6]
    ## Sizes pooled food and fuel reserves plus the finite stone reserve.
  HouseholdFoodReserve* = 4
  VillagerHungerRate* = 0.3'f
  MealRelief* = 45'f
  MealHunger* = 50'f
  BedtimeHunger* = 35'f
  GatherSeconds* = [6'f, 8'f, 10'f, 10'f, 12'f, 12'f]
  RegrowthSeconds* = [60'f, 30'f, 60'f, 60'f, 90'f, 0'f]
  AttackDamage* = 35'f
  AttackRange* = 1.5'f
  AttackWindup* = 0.8'f
  AttackTimeout* = 90'f
  FrightDuration* = 15'f
  InitialFear* = 35'f
  PanicFear* = 60'f
  HitDuration* = 0.45'f
  InitialSleepiness* = 20'f
  NightSleepThreshold* = 25'f
  DaySleepThreshold* = 85'f
  UrgentHunger* = 80'f
  VillageIds* = ["village", "bracken", "reedbank"]
  SourceIds* = ["berries", "farm", "fish", "pine", "oak", "stone",
    "bracken_farm", "reedbank_farm", "north_berries", "south_fish",
    "north_pine", "south_oak", "quarry"]
  HouseholdIds* = ["miller_hut", "weaver_hut", "mason_hut",
    "bracken_hut1", "bracken_hut2", "bracken_hut3",
    "reedbank_hut1", "reedbank_hut2", "reedbank_hut3"]
  VillagerIds* = ["ada", "ben", "clara", "dara", "eli", "finn",
    "bracken_iris", "bracken_jory", "bracken_kira", "bracken_leo",
    "bracken_mina", "bracken_ned", "reedbank_ora", "reedbank_pax",
    "reedbank_rosa", "reedbank_seth", "reedbank_tess", "reedbank_uri"]
  DeliveryIds* = ["village", "hall", "miller_hut", "weaver_hut",
    "mason_hut", "ada", "ben", "clara", "dara", "eli", "finn",
    "bracken", "reedbank", "bracken_hut1", "bracken_hut2", "bracken_hut3",
    "reedbank_hut1", "reedbank_hut2", "reedbank_hut3", "bracken_iris",
    "bracken_jory", "bracken_kira", "bracken_leo", "bracken_mina",
    "bracken_ned", "reedbank_ora", "reedbank_pax", "reedbank_rosa",
    "reedbank_seth", "reedbank_tess", "reedbank_uri"]

type
  MonsterError* = object of CatchableError
  ActionKind* = enum
    MoveAction, GatherAction, GiveAction, EatAction, RestAction,
    DanceAction, StopAction, WaitAction, AttackAction
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
  Village* = object
    id*, name*: string
    position*: Vec2
    stock*: Inventory
    harvested*, gifts*: int
    alarm*: float32
    health*: float32 = 100
  ResourceSource* = object
    id*, name*: string
    position*: Vec2
    resource*: ResourceKind
    owner*: int
    amount*, capacity*: int
    elapsed*: float32
    destroyed*: bool
  Household* = object
    id*, name*: string
    position*: Vec2
    stock*: Inventory
    village*: int
    integrity*, fuel*: float32
  VillagerTask* = enum
    IdleTask, GatherTask, WithdrawTask, DeliverTask, EatTask,
    RefuelTask, RepairTask, FleeTask, SleepTask, ChoreTask, WanderTask,
    ChatTask
  Villager* = object
    id*, name*: string
    home*: int
    position*: Vec2
    facing*: float32
    moving*: bool
    cargo*: Inventory
    hunger*: float32
    sleepiness*: float32
    sleeping*: bool
    health*, fear*, hitTime*: float32
    trust*: float32
    fearLevel*: float32 = InitialFear
    activity*, target*: string
    task*: VillagerTask
    resource*: ResourceKind
    path*: seq[Vec2]
    waypoint*: int
    elapsed*, retry*: float32
    supplyingHall*: bool
  Creature* = object
    position*: Vec2
    facing*: float32
    moving*: bool
    cargo*: Inventory
    energy*: float32
    health*: float32 = 100
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
    actionTime*: float32
    villages*: seq[Village]
    sources*: seq[ResourceSource]
    households*: seq[Household]
    villagers*: seq[Villager]
    status*: string
    events*: seq[string]
    problems*: seq[string]

proc isStopCommand*(text: string): bool =
  ## Recognizes urgent stop commands without waiting for model inference.
  text.strip().toLowerAscii() in ["stop", "stop!", "stop.",
    "stop attacking", "stop attacking!", "stop attacking."]

proc attitude*(person: Villager): string {.raises: [].} =
  ## Summarizes a resident's lasting relationship with Moss.
  if person.fear > 0 or person.fearLevel >= PanicFear: "Terrified"
  elif person.trust >= 75: "Allied"
  elif person.trust >= 45: "Friendly"
  elif person.trust >= 20: "Neutral"
  else: "Wary"
