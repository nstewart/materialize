# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

$ set-arg-default single-replica-cluster=quickstart
#
# Test basic create and drop functionality

$ set schema={
    "name": "row",
    "type": "record",
    "fields": [
      {"name": "X", "type": "long"},
      {"name": "Y", "type": "long"}
    ]
  }

$ kafka-create-topic topic=data

> CREATE CONNECTION kafka_conn
  TO KAFKA (BROKER '${testdrive.kafka-addr}', SECURITY PROTOCOL PLAINTEXT);

> CREATE SOURCE s
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

$ kafka-ingest format=avro topic=data schema=${schema}
{"X": 1, "Y": 1}
{"X": 2, "Y": 1}
{"X": 3, "Y": 1}
{"X": 1, "Y": 2}

> CREATE MATERIALIZED VIEW v AS SELECT 42 AS a

> CREATE MATERIALIZED VIEW v2 AS SELECT 0 AS x

> CREATE INDEX i ON v(a)

> CREATE INDEX j on s("X");

# Test that creating objects of the same name does not work

! CREATE MATERIALIZED VIEW i AS SELECT 1.5 AS c
contains:index "materialize.public.i" already exists

! CREATE INDEX i ON s("Y")
contains:index "materialize.public.i" already exists

! CREATE INDEX j on v2(x)
contains:index "materialize.public.j" already exists

! CREATE INDEX v ON v2(x)
contains:materialized view "materialize.public.v" already exists

$ set dummy={
    "type": "record",
    "name": "envelope",
    "fields": [
      {
        "name": "before",
        "type": [
          {
            "name": "row",
            "type": "record",
            "fields": [
              {"name": "X",
               "type": {
                  "type": "bytes",
                  "scale": 3,
                  "precision": 10,
                  "logicalType": "decimal"
                }}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] }
    ]
  }

! CREATE SOURCE v2
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${dummy}'
contains:materialized view "materialize.public.v2" already exists

! CREATE SOURCE i
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${dummy}'
contains:index "materialize.public.i" already exists

! CREATE INDEX s ON v2(x)
contains:source "materialize.public.s" already exists

! CREATE MATERIALIZED VIEW s AS SELECT 'bloop' AS d
contains:source "materialize.public.s" already exists

# Test that objects do not get dropped if the drop command does not specify the correct type
! DROP SOURCE v
exact:v is a materialized view not a source

! DROP SOURCE IF EXISTS v
exact:v is a materialized view not a source

! DROP INDEX v
exact:v is a materialized view not an index

! DROP INDEX IF EXISTS v
exact:v is a materialized view not an index

! DROP SOURCE i
exact:i is an index not a source

! DROP SOURCE IF EXISTS i
exact:i is an index not a source

! DROP VIEW i
exact:i is an index not a view

! DROP VIEW IF EXISTS i
exact:i is an index not a view

! DROP INDEX s
exact:s is a source not an index

! DROP INDEX IF EXISTS s
exact:s is a source not an index

! DROP VIEW s
exact:s is a source not a view

! DROP VIEW IF EXISTS s
exact:s is a source not a view

# Delete objects

> DROP INDEX j

> DROP INDEX i

> DROP MATERIALIZED VIEW v

> DROP SOURCE s CASCADE

# test that the names of the deleted objects can be used to create objects of other types
> CREATE MATERIALIZED VIEW s AS SELECT 84 AS b

> CREATE SOURCE i
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

> CREATE INDEX v ON s(b)

# Test that if exists works when the referred objects exist

> DROP INDEX IF EXISTS v

> DROP MATERIALIZED VIEW IF EXISTS s

> DROP SOURCE IF EXISTS i CASCADE

# Test that if exists works when the referred objects do not exist

> DROP INDEX IF EXISTS nonexistent

> DROP VIEW IF EXISTS nonexistent

> DROP SOURCE IF EXISTS nonexistent CASCADE

# Test that drop without if exists does not work if the object does not exist

! DROP INDEX nonexistent
contains:unknown catalog item 'nonexistent'

! DROP VIEW nonexistent
contains:unknown catalog item 'nonexistent'

! DROP SOURCE nonexistent
contains:unknown catalog item 'nonexistent'

# Test CREATE VIEW IF NOT EXISTS
> CREATE VIEW IF NOT EXISTS test1 AS SELECT 42 AS a

! CREATE VIEW test1 AS SELECT 43 AS b
contains:view "materialize.public.test1" already exists

> SELECT * FROM test1
a
-----------
42

> CREATE VIEW IF NOT EXISTS test1 AS SELECT 42 AS a

> DROP VIEW test1
