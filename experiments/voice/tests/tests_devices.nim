import ../devices

echo "Testing read-only audio device enumeration"
for input in [true, false]:
  let devices = audioDevices(input)
  doAssert devices.len > 0
  doAssert devices[0].uid == ""
  doAssert devices[0].isDefault
  for i in 1 ..< devices.len:
    let device = devices[i]
    doAssert device.uid.len > 0
    doAssert device.name.len > 0
    doAssert device.id > 0
    doAssert audioDeviceId(device.uid, input) == device.id
    for j in 1 ..< i:
      doAssert devices[j].uid != device.uid
  echo (if input: "Inputs: " else: "Outputs: "), devices.len - 1

when defined(macosx):
  var rejected = false
  try:
    discard audioDeviceId("polyworld-device-that-does-not-exist", true)
  except VoiceDeviceError:
    rejected = true
  doAssert rejected

echo "Audio device checks passed"
