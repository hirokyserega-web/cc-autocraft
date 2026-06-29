-- Network protocol wrapper
local net = {}

net.PROTOCOL = "cc_autocraft"
net.VERSION = "1.0"

function net.send(id, msgType, data)
    local packet = {
        protocol = net.PROTOCOL,
        version = net.VERSION,
        type = msgType,
        data = data,
        timestamp = os.epoch("utc")
    }
    rednet.send(id, packet, net.PROTOCOL)
end

function net.broadcast(msgType, data)
    local packet = {
        protocol = net.PROTOCOL,
        version = net.VERSION,
        type = msgType,
        data = data,
        timestamp = os.epoch("utc")
    }
    rednet.broadcast(packet, net.PROTOCOL)
end

function net.receive(timeout)
    local id, packet = rednet.receive(net.PROTOCOL, timeout)
    if id and type(packet) == "table" and packet.protocol == net.PROTOCOL then
        return id, packet.type, packet.data
    end
    return nil
end

return net
