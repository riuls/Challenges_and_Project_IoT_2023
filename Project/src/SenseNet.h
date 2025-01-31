#ifndef SENSE_NET_H
#define SENSE_NET_H

#define SENSOR_NODES 5
#define SERVER_NODE 8

typedef nx_struct sense_msg {
  nx_uint8_t type;  // Data type is defined 0 for data messages and 1 for ACK messages
  nx_uint16_t msg_id; // Packet sequence number 
  nx_uint16_t data; // Randomly generated data
  nx_uint16_t sender; // Sender node address
  nx_uint16_t destination; // Destination node address
} sense_msg_t;

typedef struct last_message_transmitted {
  sense_msg_t sense_msg;
  bool ack_received;
} last_message_transmitted;

typedef struct last_message_received {
  uint16_t msg_id;
  uint16_t gateway;
  bool retransmitted;
} last_message_received;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif