-- Isolated ClientCallback regression: no network, server, accounts or recordings on disk.
local real_dofile = dofile
dofile = function() end
fk = {}
FileIO = { pwd = function() return "isolated-test" end }
string.endsWith = function(value, suffix) return value:sub(-#suffix) == suffix end
string.startsWith = function(value, prefix) return value:sub(1, #prefix) == prefix end
table.contains = function(values, target)
  for _, value in ipairs(values) do if value == target then return true end end
  return false
end
os.getms = function() return 12345 end
cbor = { decode = function(value) return value end }
local received = {}
ClientInstance = {
  recording = true, replaying = false, record = {}, callbacks = {},
  notifyUI = function(_, command, data)
    received[#received + 1] = { command = command, data = data }
  end,
}
assert(loadfile(CLIENT_SOURCE))()
dofile = real_dofile

local messages = {
  "RoomInviteSettings", "RoomInvitePlayers", "RoomInviteResult",
  "RoomInvitation", "RoomInvitationClosed",
}
for _, command in ipairs(messages) do
  local payload = { token = "live-only", value = command }
  ClientCallback(nil, command, payload, false)
  assert(received[#received].command == command)
  assert(received[#received].data == payload)
end
assert(#received == 5, "live invite messages must reach the QML bridge")
assert(#ClientInstance.record == 0, "live invites must not leak into game recordings")
ClientCallback(nil, "Chat", { msg = "ordinary" }, false)
assert(#received == 6 and #ClientInstance.record == 1, "ordinary recording behavior must remain")
ClientInstance.replaying = true
for _, command in ipairs(messages) do ClientCallback(nil, command, {}, false) end
assert(#received == 6, "legacy invite packets in a replay must never reach live UI")
assert(#ClientInstance.record == 1)
print("PASS: live invite forwarding, recording exclusion, replay suppression")
