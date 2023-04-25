msg.topic = "/polimi/iot2023/challenge2/10372022"
msg.payload = "START"

function sleep(milliseconds) {
    const date = Date.now();
    let currentDate = null;
    do {
        currentDate = Date.now();
    } while (currentDate - date < milliseconds);
}

sleep(2000)

return msg;
