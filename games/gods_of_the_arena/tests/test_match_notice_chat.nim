import ../chats

let message = HumanChatMessage(system: true, tick: 48, ordinal: -1,
  text: "3 minutes remain")
doAssert message.chatDisplayText() == "[System] 3 minutes remain"
doAssert HumanChatMessage(sender: "Alice", text: "hello").chatDisplayText() == "[All] Alice: hello"
var history: seq[HumanChatMessage]
history.appendHumanChat(message)
history.appendHumanChat(message)
doAssert history.len == 1

echo "PASS system notice has no human attribution and shares deduplicated human match log"
