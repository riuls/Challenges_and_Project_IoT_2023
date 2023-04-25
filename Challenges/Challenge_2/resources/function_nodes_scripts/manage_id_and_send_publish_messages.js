function generate_payload(previous_id, publish_payload) {
    let timestamp = "\"timestamp\": \"" + Date.now() + "\""
    let prev_id = "\"id\": \"" + previous_id + "\""
    if (publish_payload === undefined) {
        publish_payload = "{}"
    }
    let payload = "\"payload\": " + publish_payload + ""
    let m = "{ " + timestamp + ", " + prev_id + ", " + payload + " }"

    return m
}

function get_contents(content) {
    let contents = []

    if (content !== undefined) {
        contents = content.split("},")
        
        for (let i = 0; i < contents.length - 1; i++) {
            contents[i] = contents[i] + "}"
        }
    }

    return contents
}

let check = global.get("initialized")
let c = global.get("count")
let msgs = []

if (check == 1 && c < 100 && msg.payload !== "") {
    c = c + 1
    global.set("count", c)

    let ID = msg.payload["id"]
    let n = (ID + 2022) % 7711

    let frame = global.get("csv_file[" + n + "]")

    if (frame["Info"].startsWith("Publish Message")) {
        let publish_messages = frame["Info"].split(", ")
        let publish_messages_contents = get_contents(frame["Message"])

        for (let i = 0; i < publish_messages.length; i++) {
            let m = {}
            m.topic = "/polimi/iot2023/challenge2/10372022"
            m.payload = generate_payload(ID, publish_messages_contents[i])
            msgs.push(m)
        }
    }
} else if(c == 100) {
    c = c + 1
    global.set("count", c)
    msg.payload = "END"
    msg.topic = "/polimi/iot2023/challenge2/10372022"
    msgs.push(msg)
}

return [msgs];
