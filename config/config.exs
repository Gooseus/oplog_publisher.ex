import Config

config :oplog_publisher,
  mongo_url: System.get_env("MONGO_URI"),
  nats_url:  System.get_env("NATS_URL"),
  js_stream: "OPLOG",
  js_subject_prefix: "oplog"
