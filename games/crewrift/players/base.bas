' Crewrift reference crew and imposter policy.
'
' One isolated BASIC program runs for each bot every simulation tick.
' Globals and arrays persist between decisions. Nim supplies observations,
' validates commands, and follows paths; all tactical choices live here.
'
' Playing is phase 1, Voting is phase 2. Our role is 0 for crew, 1 for imposter.
' Hidden players have coordinates and alive state -1. Other roles are unknown
' except an imposter's teammates. Body observations contain only visible bodies.
' sendChat(-2, text$) speaks to the meeting; dead players cannot speak.
' pressUse creates an interaction edge; holdUse keeps working at a task.
' moveTo(x, y) follows a path, and voteFor(playerTotal) skips the vote.

dim suspects(15)
dim suspectRooms$(15)
dim seenBodies(15)

if initialized = 0 then
  initialized = 1
  task = -1
  meeting = -1
  vote = -1
  suspect = -1
  accuser = -1
end if

sub observe()
  location$ = ownRoom$()
  for body = 0 to bodyTotal - 1
    identity = bodyId(body)
    if identity >= 0 and identity <= 15 then
      if seenBodies(identity) = 0 then
        for other = 0 to playerTotal - 1
          if other <> selfSlot and playerVisible(other) <> 0 then
            if playerAlive(other) > 0 then
              dx = playerX(other) - bodyX(body)
              dy = playerY(other) - bodyY(body)
              distance = dx * dx + dy * dy
              if distance <= killRange * killRange and bodyAge(body) <= 2 then
                suspects(other) = suspects(other) + 3
                suspectRooms$(other) = bodyRoom$(body)
              elseif distance <= reportRange * reportRange * 4 then
                if suspects(other) < 1 then
                  suspects(other) = 1
                end if
                suspectRooms$(other) = bodyRoom$(body)
              end if
            end if
          end if
        next other
        seenBodies(identity) = 1
      end if
    end if
  next body
end sub

sub beginDiscussion()
  meeting = voteTimer + worldTick
  vote = playerTotal
  suspect = -1
  accuser = -1
  chatRound = 0
  evidence = 0
  for other = 0 to playerTotal - 1
    if other <> selfSlot and playerAlive(other) > 0 then
      if suspects(other) > evidence then
        evidence = suspects(other)
        suspect = other
      end if
    end if
  next other
  if evidence >= 3 then
    vote = suspect
  end if
  if myRole = 1 then
    best = 2147483647
    for other = 0 to playerTotal - 1
      if playerAlive(other) > 0 and playerRole(other) <> 1 then
        if playerVisible(other) <> 0 then
          dx = myX - playerX(other)
          dy = myY - playerY(other)
          distance = dx * dx + dy * dy
          if distance < best then
            best = distance
            suspect = other
          end if
        end if
      end if
    next other
    if suspect >= 0 then
      vote = suspect
    end if
  end if
end sub

sub discussionMessage()
  if location$ = "" then
    location$ = "the corridor"
  end if
  if chatRound = 0 then
    if selfSlot = meetingCaller and meetingKind = 2 then
      message$ = "I found " + meetingBodyName$() + " in "
      message$ = message$ + meetingBodyRoom$() + "."
      if myRole = 0 and suspect >= 0 then
        message$ = message$ + " I suspect " + playerName$(suspect)
        message$ = message$ + "; I saw them next to the body."
      else
        message$ = message$ + " Who was nearby?"
      end if
      exit sub
    end if
    if suspect >= 0 then
      name$ = playerName$(suspect)
      if myRole = 1 then
        message$ = "I suspect " + name$ + ". They were hanging around"
        message$ = message$ + " instead of doing tasks."
      elseif suspects(suspect) >= 3 then
        message$ = "I saw " + name$ + " beside a fresh body in "
        message$ = message$ + suspectRooms$(suspect) + ". I suspect "
        message$ = message$ + name$ + "."
      else
        message$ = "I suspect " + name$ + ". I saw them near the body in "
        message$ = message$ + suspectRooms$(suspect)
        message$ = message$ + ". Did anyone else see them?"
      end if
      exit sub
    end if
    select case selfSlot mod 3
    case 0
      message$ = "I was working on tasks in " + location$
      message$ = message$ + ". Who was with the victim?"
    case 1
      message$ = "I was in " + location$ + " doing tasks."
      message$ = message$ + " Did anyone see who left the body?"
    case else
      message$ = "I came from " + location$ + ". I didn't see the kill."
      message$ = message$ + " Where was everyone else?"
    end select
  elseif chatRound = 1 then
    if accuser >= 0 then
      message$ = playerName$(accuser) + ", that wasn't me."
      message$ = message$ + " I was doing tasks in " + location$
      message$ = message$ + ". Being nearby doesn't prove a kill."
      exit sub
    end if
    if suspect >= 0 then
      message$ = playerName$(suspect) + ", where were you before the report?"
      message$ = message$ + " Can anyone confirm your story?"
      exit sub
    end if
    if meetingCaller >= 0 and meetingCaller <> selfSlot then
      select case selfSlot mod 3
      case 0
        message$ = "Being near a body isn't enough."
        message$ = message$ + " Did anyone see a kill or a vent?"
      case 1
        message$ = playerName$(meetingCaller) + ", did you see anyone leave?"
        message$ = message$ + " I can't confirm a killer."
      case else
        message$ = "Can someone confirm who was doing tasks?"
        message$ = message$ + " We need a witness."
      end select
    else
      message$ = "Please share what you actually saw."
      message$ = message$ + " Who can confirm an alibi?"
    end if
  else
    if vote < playerTotal then
      message$ = "I'm voting for " + playerName$(vote)
      if myRole = 1 then
        message$ = message$ + ". Their story doesn't add up."
      else
        message$ = message$ + ". I saw them beside the fresh body."
      end if
    elseif suspect >= 0 then
      message$ = "I'm suspicious of " + playerName$(suspect)
      message$ = message$ + ", but I didn't see a kill."
      message$ = message$ + " Skipping without stronger evidence."
    else
      message$ = "I haven't seen enough evidence."
      message$ = message$ + " I'll skip and keep doing tasks."
    end if
  end if
end sub

sub discuss()
  if meeting <> voteTimer + worldTick and voteFinalize = 0 then
    call beginDiscussion()
  end if
  for messageIndex = 0 to chatTotal - 1
    sender = chatSender(messageIndex)
    if sender <> selfSlot then
      accusation$ = "i suspect " + lcase$(playerName$(selfSlot))
      if instr(lcase$(chatText$(messageIndex)), accusation$) > 0 then
        accuser = sender
      end if
    end if
  next messageIndex
  living = 0
  rank = 0
  for other = 0 to playerTotal - 1
    if playerAlive(other) > 0 then
      living = living + 1
      if other < selfSlot and other <> meetingCaller then
        rank = rank + 1
      end if
    end if
  next other
  if meetingCaller >= 0 then
    if playerAlive(meetingCaller) > 0 then
      if selfSlot = meetingCaller then
        rank = 0
      else
        rank = rank + 1
      end if
    end if
  end if
  interval = voteDuration \ (living * 4)
  if interval > tickRate then
    interval = tickRate
  end if
  if interval < 6 then
    interval = 6
  end if
  roundTicks = living * interval
  if roundTicks < chatCooldown + 1 then
    roundTicks = chatCooldown + 1
  end if
  elapsed = voteDuration - voteTimer
  scheduled = tickRate \ 2 + rank * interval + chatRound * roundTicks
  voteAfter = 3 * roundTicks + tickRate
  if voteAfter < tickRate * 18 then
    voteAfter = tickRate * 18
  end if
  if voteAfter > voteDuration - tickRate * 2 then
    voteAfter = voteDuration - tickRate * 2
  end if
  if chatRound < 3 and elapsed >= scheduled then
    if worldTick - myLastChatTick >= chatCooldown then
      call discussionMessage()
      if sendChat(-2, message$) <> 0 then
        chatRound = chatRound + 1
      end if
    end if
  end if
  if elapsed >= voteAfter and myVote = -1 then
    discardResult = voteFor(vote)
  end if
end sub

sub chooseTask()
  task = -1
  if myRole = 1 then
    if taskTotal > 0 then
      task = randomInt(taskTotal)
    end if
    exit sub
  end if
  best = 2147483647
  for assignment = 0 to assignmentTotal - 1
    candidate = assignedTask(assignment)
    if candidate >= 0 then
      if taskDone(candidate) = 0 and taskX(candidate) >= 0 then
        dx = myX - taskX(candidate)
        dy = myY - taskY(candidate)
        distance = dx * dx + dy * dy
        if distance < best then
          best = distance
          task = candidate
        end if
      end if
    end if
  next assignment
end sub

if phase = 2 then
  if myAlive <> 0 then
    call discuss()
  end if
  stop
end if
if phase <> 1 then
  stop
end if

call observe()

if myAlive <> 0 then
  for body = 0 to bodyTotal - 1
    dx = myX - bodyX(body)
    dy = myY - bodyY(body)
    if dx * dx + dy * dy <= reportRange * reportRange then
      discardResult = pressUse()
      stop
    end if
  next body
  if myRole = 1 and myKillCooldown = 0 then
    for other = 0 to playerTotal - 1
      if other <> selfSlot and playerVisible(other) <> 0 then
        if playerAlive(other) > 0 and playerRole(other) <> 1 then
          dx = myX - playerX(other)
          dy = myY - playerY(other)
          if dx * dx + dy * dy <= killRange * killRange then
            discardResult = pressUse()
            stop
          end if
        end if
      end if
    next other
  end if
elseif myRole = 1 then
  stop
end if

choose = task < 0 or routeLength = 0 or routeStuck > tickRate * 2
if task >= 0 and myRole = 0 then
  if taskDone(task) <> 0 then
    choose = 1
  end if
end if
if choose <> 0 then
  call chooseTask()
end if
if task < 0 then
  stop
end if
if atTask(task) <> 0 then
  discardResult = holdUse()
  if myRole = 1 then
    task = -1
  end if
  stop
end if
discardResult = moveTo(taskX(task), taskY(task))
