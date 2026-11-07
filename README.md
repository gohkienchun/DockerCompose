# Docker Compose stacks

Local development infrastructure. Each directory is one stack with its own `docker-compose` file. Start the directory that matches the system you are building against, and leave the others stopped.

These files are for a laptop or a dev VM. Passwords are fixed, nothing is persisted to a named volume, and the host timezone is mounted into each container. `docker compose down` throws the data away. Do not point a real environment at them.

You need Docker with Compose v2 (`docker compose`, not the older `docker-compose` binary).

## How to run a stack

```bash
cd <directory>
docker compose up -d
docker compose ps
docker compose logs -f
```

Stop it, and delete the containers, with:

```bash
docker compose down
```

Host ports do not overlap, so more than one stack can run at the same time. The Confluent stack and the 3-broker Kafka cluster together are heavy. Start both only when you actually need them.

## Which one to use

| You need | Directory |
|---|---|
| A 3-broker Kafka cluster, to try replication, partitions, or a broker going away | `kafka-cluster` |
| Schema Registry, Kafka Connect, ksqlDB, REST Proxy, or Control Center | `confluent-kafka` |
| RabbitMQ, ActiveMQ, or both message brokers side by side | `rabbitmq-activemq` |
| MySQL with a writer and a read-only replica | `mysql-master-slave` |

Use `kafka-cluster` when the broker topology is the thing under test. Use `confluent-kafka` when you need the rest of the Confluent platform and a single broker is enough.

## `kafka-cluster`

A Kafka cluster: 3 ZooKeeper nodes and 3 brokers. Every topic is created with 6 partitions, a replication factor of 3, and `min.insync.replicas=2`.

Use this when an app, consumer group, or Streams job must talk to more than one broker. Use it when you want to watch replication or stop one broker and see the cluster keep serving. Skip it when you only need Schema Registry, Connect, or ksqlDB. That platform lives in `confluent-kafka`, and this file does not include it.

From the host, the bootstrap servers are:

```text
localhost:29092,localhost:29093,localhost:29094
```

From another container on this compose network:

```text
kafka1:9092,kafka2:9093,kafka3:9094
```

| Service | Host port | Role |
|---|---|---|
| `zookeeper1` | 22181 | ZooKeeper |
| `zookeeper2` | 32181 | ZooKeeper |
| `zookeeper3` | 42181 | ZooKeeper |
| `kafka1` | 29092 | Broker 1 |
| `kafka2` | 29093 | Broker 2 |
| `kafka3` | 29094 | Broker 3 |

ZooKeeper is only there for the brokers. Application code should use the Kafka bootstrap servers above.

## `confluent-kafka`

One Kafka broker plus the Confluent pieces around it: ZooKeeper, Schema Registry, Kafka Connect (with the datagen connector), Control Center, ksqlDB, and the REST Proxy.

Use this when you are trying Avro schemas, a connector, a ksqlDB query, or the Control Center UI. Skip it when you need more than one broker. This file runs a single broker with replication factor 1, so it cannot show broker failure or under-replicated partitions. Use `kafka-cluster` for that.

| Service | Host port | What to open |
|---|---|---|
| `zookeeper` | 2181 | ZooKeeper, used by the broker |
| `kafka` | 9092 | Bootstrap server for clients on the host. JMX is on 9101 |
| `schema-registry` | 8081 | http://localhost:8081 |
| `rest-proxy` | 8082 | http://localhost:8082 |
| `connect` | 8083 | http://localhost:8083 |
| `ksqldb-server` | 8088 | http://localhost:8088 |
| `control-center` | 9021 | http://localhost:9021 |

Clients on the host use `localhost:9092`. Services inside this compose file use `kafka:29092`.

Control Center takes the longest to become useful. Wait until `docker compose ps` shows it running, then open http://localhost:9021.

Open a ksqlDB prompt with:

```bash
docker compose exec ksqldb-cli ksql http://ksqldb-server:8088
```

`ksql-datagen` only waits until Kafka and Schema Registry are up, then it stays idle. It does not generate rows by itself. Start a datagen connector or a ksqlDB query when you want data.

## `rabbitmq-activemq`

RabbitMQ and ActiveMQ in one file, so an app can be pointed at either broker without editing the compose file.

Use RabbitMQ for AMQP. Use ActiveMQ for OpenWire / JMS. Start the whole file even if you only need one of them. Stopping a single service is `docker compose stop rabbitmq` or `docker compose stop activemq`.

| Service | Host port | What it is |
|---|---|---|
| `rabbitmq` | 5672 | AMQP |
| `rabbitmq` | 15672 | Management UI at http://localhost:15672 |
| `activemq` | 61616 | OpenWire |
| `activemq` | 8161 | Web console at http://localhost:8161 |

RabbitMQ logs in as `guest` / `guest`.

An AMQP URL from the host:

```text
amqp://guest:guest@localhost:5672/
```

ActiveMQ clients on the host use `tcp://localhost:61616`.

## `mysql-master-slave`

MySQL 8.4 with a master and one read-only replica. The replica uses GTID auto-positioning, so it picks up the master's binary log without a hand-copied file and position.

Use this when an app writes to one database and reads from another, or when you want to see replication and a read-only server. Skip it for a single local database. A plain `mysql` container is enough for that, and this stack rejects writes on the replica.

| Service | Host port | Login | Writes |
|---|---|---|---|
| `masterdb` | 23306 | `root` / `password` | yes |
| `slavedb` | 23307 | `root` / `password` | no (`super_read_only`) |

The replication account is `repl` / `replpass`. The master creates it on first start. The replica waits until that login works, then starts replication. The first boot is slower than a later `docker compose up`, because both data directories have to initialize.

Connect from the host:

```bash
mysql -h 127.0.0.1 -P 23306 -uroot -ppassword
mysql -h 127.0.0.1 -P 23307 -uroot -ppassword
```

Check that the replica is caught up:

```bash
docker compose exec slavedb mysql -uroot -ppassword -e "SHOW REPLICA STATUS\G"
```

`Replica_IO_Running` and `Replica_SQL_Running` should both be `Yes`. Create a table on port 23306 and read it on port 23307. An `INSERT` on port 23307 fails, which is what read-only is for.

`docker compose down` removes both data directories. The next `up` initializes replication again.
