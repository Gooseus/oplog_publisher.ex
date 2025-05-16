# OplogPublisher

A MongoDB oplog publisher that streams changes to NATS.

## Working environment

### Elixir

```zsh
$ iex -v 
Erlang/OTP 27 [erts-15.2.3] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit] [dtrace]

IEx 1.18.3 (compiled with Erlang/OTP 27)
```

### Docker

```zsh
$ docker -v
Docker version 28.0.4, build b8034c0
```

```zsh
$ cat docker-compose.yml
```

```yaml
services:
  mongo:
    image: mongo:latest # v8.x
    container_name: mongo
    restart: always
    ports:
      - "27017:27017"
    # Mount the init script to initiate the single‑node replica set
    volumes:
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    # Enable replica‑set mode and bind on all interfaces
    command: ["--replSet", "rs0", "--bind_ip_all"]

  nats:
    image: nats:latest # v2.11.x
    container_name: nats
    restart: always
    ports:
      - "4222:4222"   # client port
      - "8222:8222"   # monitoring port
    # Mount a custom server config that turns on JetStream and defines our stream
    volumes:
      - ./nats-server.conf:/etc/nats/nats-server.conf:ro
    command: ["-c", "/etc/nats/nats-server.conf"]
```

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd oplog_publisher
```

2. Install dependencies:
```bash
mix deps.get
```

3. Start the required services using Docker Compose:
```bash
docker-compose up -d
```

This will start the MongoDB and NATS containers with the given configurations.

## Issue

Running `mix test` after starting the docker services should demonstrate the issue, though to watch it in action you can:

1. Run `mix run --no-halt` to start the app
2. Open a connection to the `oplogtest` database of the Mongo running in docker (i.e. Run `mongosh`)
3. Run `nats sub "oplog.>"` with the NATS CLI to subscribe to the firehose of oplog events

Everything should be running in an idle state at this point and should run as expected:

1. Create new document in the `users` collection of the `oplogtest` database in Mongo
2. Observe the app handling the change to the collection and the message received from NATS on the `oplog.oplogtest.users.created` subject.
3. Any other change operations on the collection should also come through on `oplog.oplogtest.users.<operation>`.

Great. Exit the app and try this:

1. Create new document in the `users` collection of the `oplogtest` database in Mongo
2. Run `mix run --no-halt` to start the app
3. Observe an infinite loop in the app and the same message being published repeatedly in NATS

Why?
