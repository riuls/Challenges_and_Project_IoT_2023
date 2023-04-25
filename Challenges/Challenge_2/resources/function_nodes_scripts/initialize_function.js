function sleep(milliseconds) {
    const date = Date.now();
    let currentDate = null;
    do {
        currentDate = Date.now();
    } while (currentDate - date < milliseconds);
}

sleep(1000)

global.set("csv_file", [])
global.set("count", 0)
global.set("initialized", 0)
global.set("temperatures_received", 0)
global.set("max_temperature", 0)

return msg;
