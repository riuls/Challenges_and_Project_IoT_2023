let csv = global.get("csv_file")
csv.push(msg.payload)
global.set("csv_file", csv)

return msg;
