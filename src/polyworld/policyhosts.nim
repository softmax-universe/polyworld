## Shared policy capabilities; game builders add only their game-specific API.
import bassy, annotations, mailboxes
when defined(coworld):
  import coworld

proc initPolicyHost*(slot = -1): Host =
  ## Schema hosts omit the seat. Hosts without an output destination stay usable.
  result = initHost()
  when defined(coworld):
    result.addAnnotationFunctions(playerAnnotations(slot))
  else:
    result.addAnnotationFunctions()

proc pullMailboxString*(runtime: var Runtime, inbox: Mailbox): Value =
  ## Copy before popping so a BASIC string limit leaves the message unread.
  if inbox.count == 0:
    result = runtime.putString("")
  else:
    result = runtime.putString(inbox.messages[inbox.first])
  discard inbox.pop()
