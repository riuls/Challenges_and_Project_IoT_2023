if (msg.payload == "START") {
    global.set("initialized", 1)
} else if(msg.payload != "END") {
    const obj = JSON.parse(msg.payload)
    var p = obj.payload
} else {
    global.set("initialized", 0)
}

let temps_count = global.get("temperatures_received")

if (p !== undefined) {
    if (p["unit"] == "C") {
        temps_count = temps_count + 1
        global.set("temperatures_receives", temps_count)

        let temp_msg = {}
        temp_msg.payload = p["range"][1]
        
        return [msg, temp_msg];
    }
}
