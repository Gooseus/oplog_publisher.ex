import Config

config :oplog_publisher,
  mongo_url: "mongodb://localhost:27017/oplogtest?replicaSet=rs0",
  nats_url: "nats://localhost:4222"
