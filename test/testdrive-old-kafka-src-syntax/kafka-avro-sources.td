# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

$ set-arg-default default-storage-size=1
$ set-arg-default single-replica-cluster=quickstart

$ postgres-execute connection=postgres://mz_system:materialize@${testdrive.materialize-internal-sql-addr}
ALTER SYSTEM SET max_clusters = 20

# Test support for Avro sources without using the Confluent Schema Registry.

$ set key-schema={
    "type": "record",
    "name": "Key",
    "fields": [{"name": "a", "type": "long"}]
  }

$ set schema={
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
              {"name": "a", "type": "long"},
              {"name": "b", "type": "long"},
              {
                "name": "json",
                "type": {
                  "connect.name": "io.debezium.data.Json",
                  "type": "string"
                }
              },
              {
                "name": "c",
                "type": {
                  "type": "enum",
                  "name": "Bool",
                  "symbols": ["True", "False", "FileNotFound"]
                }
              },
              {"name": "d", "type": "Bool"},
              {"name": "e", "type": ["null",{
                "type": "record",
                "name": "nested_data_1",
                "fields": [
                    {"name": "n1_a", "type": "long"},
                    {"name": "n1_b", "type": ["null", "double", {
                        "type": "record",
                        "name": "nested_data_2",
                        "fields": [
                          {"name": "n2_a", "type": "long"},
                          {"name": "n2_b", "type": "int"}
                        ]
                      }]
                    }
                  ]
                }]
              },
              {"name": "f", "type": ["null", "nested_data_2"]}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] },
      { "name": "op", "type": "string" },
      {
        "name": "source",
        "type": {
          "type": "record",
          "name": "Source",
          "namespace": "io.debezium.connector.mysql",
          "fields": [
            {
              "name": "file",
              "type": "string"
            },
            {
              "name": "pos",
              "type": "long"
            },
            {
              "name": "row",
              "type": "int"
            },
            {
              "name": "snapshot",
              "type": [
                {
                  "type": "boolean",
                  "connect.default": false
                },
                "null"
              ],
              "default": false
            }
          ],
          "connect.name": "io.debezium.connector.mysql.Source"
        }
      }
    ]
  }

$ kafka-create-topic topic=data partitions=1

$ kafka-ingest format=avro topic=data schema=${schema} timestamp=1
{"before": null, "after": {"row": {"a": 1, "b": 1, "json": "null", "c": "True", "d": "False", "e": {"nested_data_1": {"n1_a": 42, "n1_b": {"double": 86.5}}}, "f": null}}, "source": {"file": "binlog", "pos": 0, "row": 0, "snapshot": {"boolean": false}}, "op": "c"}
{"before": null, "after": {"row": {"a": 2, "b": 3, "json": "{\"hello\": \"world\"}", "c": "False", "d": "FileNotFound", "e": {"nested_data_1": {"n1_a": 43, "n1_b":{"nested_data_2": {"n2_a": 44, "n2_b": -1}}}}, "f": {"nested_data_2": {"n2_a": 45, "n2_b": -2}}}}, "source": {"file": "binlog", "pos": 1, "row": 0, "snapshot": {"boolean": false}}, "op": "c"}
{"before": null, "after": {"row": {"a": -1, "b": 7, "json": "[1, 2, 3]", "c": "FileNotFound", "d": "True", "e": null, "f": null}}, "source": {"file": "binlog", "pos": 1, "row": 1, "snapshot": {"boolean": false}}, "op": "c"}

> CREATE CONNECTION kafka_conn
  TO KAFKA (BROKER '${testdrive.kafka-addr}', SECURITY PROTOCOL PLAINTEXT);

> SHOW SOURCES
name    type   cluster   comment
--------------------------------

# [btv] uncomment if we bring back classic debezium mode
# ! CREATE SOURCE fast_forwarded
#   IN CLUSTER ${arg.single-replica-cluster}
#   FROM KAFKA CONNECTION kafka_conn (START OFFSET=[2], TOPIC 'testdrive-data-${testdrive.seed}')
#   KEY FORMAT AVRO USING SCHEMA '${key-schema}'
#   VALUE FORMAT AVRO USING SCHEMA '${schema}'
#   ENVELOPE DEBEZIUM
# contains:START OFFSET is not supported with ENVELOPE DEBEZIUM

# Test an Avro source without a Debezium envelope.

$ set non-dbz-schema={
    "type": "record",
    "name": "cpx",
    "fields": [
      {"name": "a", "type": "long"},
      {"name": "b", "type": "long"}
    ]
  }

$ kafka-create-topic topic=non-dbz-data partitions=1

$ kafka-ingest format=avro topic=non-dbz-data schema=${non-dbz-schema} timestamp=1
{"a": 1, "b": 2}
{"a": 2, "b": 3}

> CREATE CLUSTER non_dbz_data_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data
  IN CLUSTER non_dbz_data_cluster
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-non-dbz-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data
a b
---
1 2
2 3

# test INCLUDE metadata

> CREATE CLUSTER non_dbz_data_metadata_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_metadata
  IN CLUSTER non_dbz_data_metadata_cluster
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-non-dbz-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  INCLUDE PARTITION, OFFSET
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_metadata
a b partition offset
--------------------
1 2 0         0
2 3 0         1

> CREATE CLUSTER non_dbz_data_metadata_named_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_metadata_named
  IN CLUSTER non_dbz_data_metadata_named_cluster
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-non-dbz-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  INCLUDE PARTITION as part, OFFSET as mzo
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_metadata_named
a b  part  mzo
--------------
1 2  0     0
2 3  0     1

# Test an Avro source without a Debezium envelope starting at specified partition offsets.

$ kafka-create-topic topic=non-dbz-data-multi-partition partitions=2

$ kafka-ingest format=avro topic=non-dbz-data-multi-partition schema=${non-dbz-schema} timestamp=1 partition=1
{"a": 4, "b": 1}

$ kafka-ingest format=avro topic=non-dbz-data-multi-partition schema=${non-dbz-schema} timestamp=1 partition=0
{"a": 1, "b": 2}

> CREATE CLUSTER non_dbz_data_multi_partition_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_multi_partition
  IN CLUSTER non_dbz_data_multi_partition_cluster
  FROM KAFKA CONNECTION kafka_conn (START OFFSET=[1], TOPIC 'testdrive-non-dbz-data-multi-partition-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_multi_partition
a  b
-----
4  1

> CREATE CLUSTER non_dbz_data_multi_partition_2_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_multi_partition_2
  IN CLUSTER non_dbz_data_multi_partition_2_cluster
  FROM KAFKA CONNECTION kafka_conn (START OFFSET=[0,0], TOPIC 'testdrive-non-dbz-data-multi-partition-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_multi_partition_2
a  b
-----
1  2
4  1

> CREATE CLUSTER non_dbz_data_multi_partition_fast_forwarded_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_multi_partition_fast_forwarded
  IN CLUSTER non_dbz_data_multi_partition_fast_forwarded_cluster
  FROM KAFKA CONNECTION kafka_conn (START OFFSET=[0,1], TOPIC 'testdrive-non-dbz-data-multi-partition-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_multi_partition_fast_forwarded
a  b
----
1  2

> CREATE CLUSTER non_dbz_data_multi_partition_fast_forwarded_2_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_multi_partition_fast_forwarded_2
  IN CLUSTER non_dbz_data_multi_partition_fast_forwarded_2_cluster
  FROM KAFKA CONNECTION kafka_conn (START OFFSET=[1,0], TOPIC 'testdrive-non-dbz-data-multi-partition-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_multi_partition_fast_forwarded_2
a  b
----
4  1

# Test an Avro source without a Debezium envelope with specified offsets and varying partition numbers.

$ kafka-create-topic topic=non-dbz-data-varying-partition partitions=1

$ kafka-ingest format=avro topic=non-dbz-data-varying-partition schema=${non-dbz-schema} timestamp=1 partition=0
{"a": 5, "b": 6}

> CREATE CLUSTER non_dbz_data_varying_partition_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_varying_partition
  IN CLUSTER non_dbz_data_varying_partition_cluster
  FROM KAFKA CONNECTION kafka_conn (
    TOPIC 'testdrive-non-dbz-data-varying-partition-${testdrive.seed}',
    START OFFSET=[1]
  )
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

> SELECT * FROM non_dbz_data_varying_partition

$ kafka-add-partitions topic=non-dbz-data-varying-partition total-partitions=2

# Reading data that's ingested to a new partition takes longer than the default timeout.
$ set-sql-timeout duration=180s

$ kafka-ingest format=avro topic=non-dbz-data-varying-partition schema=${non-dbz-schema} timestamp=1 partition=1
{"a": 7, "b": 8}
{"a": 9, "b": 10}

# Because the start offset for any new partitions will be 0, the first record sent to the new
# partition will be included.
> SELECT * FROM non_dbz_data_varying_partition
a  b
-----
7  8
9  10

> CREATE CLUSTER non_dbz_data_varying_partition_2_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_dbz_data_varying_partition_2
  IN CLUSTER non_dbz_data_varying_partition_2_cluster
  FROM KAFKA CONNECTION kafka_conn (
    TOPIC 'testdrive-non-dbz-data-varying-partition-${testdrive.seed}',
    START OFFSET=[1,1]
  )
  FORMAT AVRO USING SCHEMA '${non-dbz-schema}'
  ENVELOPE NONE

$ kafka-add-partitions topic=non-dbz-data-varying-partition total-partitions=3

$ kafka-ingest format=avro topic=non-dbz-data-varying-partition schema=${non-dbz-schema} timestamp=1 partition=2
{"a": 11, "b": 12}

# Because the start offset for any new partitions will be 0, the first record sent to the new
# partition will be included.
> SELECT * FROM non_dbz_data_varying_partition_2
a  b
-----
9  10
11 12

$ set-sql-timeout duration=default

# Source with new-style three-valued "snapshot".
$ set new-dbz-schema={
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
              {"name": "a", "type": "long"},
              {"name": "b", "type": "long"}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] },
      { "name": "op", "type": "string" },
      {
        "name": "source",
        "type": {
          "type": "record",
          "name": "Source",
          "namespace": "io.debezium.connector.mysql",
          "fields": [
            {
              "name": "snapshot",
              "type": [
                {
                  "type": "string",
                  "connect.version": 1,
                  "connect.parameters": {
                    "allowed": "true,last,false"
                  },
                  "connect.default": "false",
                  "connect.name": "io.debezium.data.Enum"
                },
                "null"
              ],
              "default": "false"
            },
            {
              "name": "file",
              "type": "string"
            },
            {
              "name": "pos",
              "type": "long"
            },
            {
              "name": "row",
              "type": "int"
            }
          ],
          "connect.name": "io.debezium.connector.mysql.Source"
        }
      }
    ]
  }

$ kafka-create-topic topic=new-dbz-data partitions=1

# We don't do anything sensible yet for snapshot "true" or "last", so just test that those are ingested.

# [btv] uncomment if we bring back classic debezium mode
# $ kafka-ingest format=avro topic=new-dbz-data key-format=avro key-schema=${key-schema} schema=${new-dbz-schema} timestamp=1
# {"a": 9} {"before": null, "after": {"row":{"a": 9, "b": 10}}, "source": {"file": "binlog", "pos": 0, "row": 0, "snapshot": {"string": "true"}}, "op": "r"}
# {"a": 11} {"before": null, "after": {"row":{"a": 11, "b": 11}}, "source": {"file": "binlog", "pos": 0, "row": 0, "snapshot": {"string": "last"}}, "op": "r"}
# {"a": 14} {"before": null, "after": {"row":{"a": 14, "b": 6}}, "source": {"file": "binlog", "pos": 0, "row": 0, "snapshot": null}, "op": "c"}
# {"a": 1} {"before": null, "after": {"row":{"a": 1, "b": 1}}, "source": {"file": "binlog", "pos": 0, "row": 0, "snapshot": {"string": "false"}}, "op": "c"}
# {"a": 2} {"before": null, "after": {"row":{"a": 2, "b": 3}}, "source": {"file": "binlog", "pos": 1, "row": 0, "snapshot": {"string": "false"}}, "op": "c"}
# {"a": -1} {"before": null, "after": {"row":{"a": -1, "b": 7}}, "source": {"file": "binlog", "pos": 1, "row": 1, "snapshot": {"string": "false"}}, "op": "c"}
# {"a": -1} {"before": null, "after": {"row":{"a": -1, "b": 7}}, "source": {"file": "binlog", "pos": 1, "row": 1, "snapshot": {"string": "false"}}, "op": "c"}

# > CREATE SOURCE new_dbz
#   IN CLUSTER ${arg.single-replica-cluster}
#   FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-new-dbz-data-${testdrive.seed}')
#   KEY FORMAT AVRO USING SCHEMA '${key-schema}'
#   VALUE FORMAT AVRO USING SCHEMA '${new-dbz-schema}'
#   ENVELOPE DEBEZIUM

# > SELECT * FROM new_dbz
# a b
# ---
# 9 10
# 11 11
# 14 6
# 2 3
# -1 7

$ kafka-create-topic topic=ignored partitions=1

! CREATE SOURCE recursive
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-ignored-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '{"type":"record","name":"a","fields":[{"name":"f","type":["a","null"]}]}'
contains:validating avro schema: Recursive types are not supported: .a

$ set key-schema={"type": "string"}
$ set value-schema={"type": "record", "name": "r", "fields": [{"name": "a", "type": "string"}]}

$ kafka-create-topic topic=non-subset-key

$ kafka-ingest format=avro topic=non-subset-key key-format=avro key-schema=${key-schema} schema=${value-schema}
"asdf" {"a": "asdf"}

> CREATE CONNECTION IF NOT EXISTS csr_conn TO CONFLUENT SCHEMA REGISTRY (
    URL '${testdrive.schema-registry-url}'
  );

> CREATE CLUSTER non_subset_key_cluster SIZE '${arg.default-storage-size}';
> CREATE SOURCE non_subset_key
  IN CLUSTER non_subset_key_cluster
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-non-subset-key-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  ENVELOPE NONE

> SELECT * FROM non_subset_key
a
---
"asdf"

# Test that Postgres-style sources can be ingested.
$ set pg-dbz-schema={
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
              {"name": "a", "type": "long"},
              {"name": "b", "type": "long"}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] },
      { "name": "op", "type": "string" },
      {
        "name": "source",
        "type": {
          "type": "record",
          "name": "Source",
          "namespace": "whatever",
          "fields": [
            {
              "name": "snapshot",
              "type": [
                {
                  "type": "string",
                  "connect.version": 1,
                  "connect.parameters": {
                    "allowed": "true,last,false"
                  },
                  "connect.default": "false",
                  "connect.name": "io.debezium.data.Enum"
                },
                "null"
              ],
              "default": "false"
            },
            {
              "name": "lsn",
              "type": ["long", "null"]
            },
            {
              "name": "sequence",
              "type": ["string", "null"]
            }
          ]
        }
      }
    ]
  }

# $ kafka-create-topic topic=pg-dbz-data partitions=1

# # The third and fourth records will be skipped, since `sequence` has gone backwards.
# $ kafka-ingest format=avro topic=pg-dbz-data schema=${pg-dbz-schema} timestamp=1
# {"before": null, "after": {"row":{"a": 1, "b": 1}}, "source": {"lsn": {"long": 1}, "sequence": {"string": "[\"1\", \"1\"]"}, "snapshot": {"string": "false"}}, "op": "c"}
# {"before": null, "after": {"row":{"a": 2, "b": 3}}, "source": {"lsn": {"long": 2}, "sequence": {"string": "[\"1\", \"2\"]"}, "snapshot": {"string": "false"}}, "op": "c"}
# {"before": null, "after": {"row":{"a": -1, "b": 7}}, "source": {"lsn": {"long": 0}, "sequence": {"string": "[\"0\", \"1\"]"}, "snapshot": {"string": "false"}}, "op": "c"}
# {"before": null, "after": {"row":{"a": 4, "b": 5}}, "source": {"lsn": {"long": 2}, "sequence": {"string": "[\"1\", \"2\"]"}, "snapshot": {"string": "false"}}, "op": "c"}

# > CREATE SOURCE pg_dbz
#   IN CLUSTER ${arg.single-replica-cluster}
#   FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-pg-dbz-data-${testdrive.seed}')
#   KEY FORMAT AVRO USING SCHEMA '${key-schema}'
#   VALUE FORMAT AVRO USING SCHEMA '${pg-dbz-schema}'
#   ENVELOPE DEBEZIUM

# > SELECT * FROM pg_dbz
# a b
# ---
# 1 1
# 2 3

# Test that SQL Server-style sources can be ingested.
# $ set ms-dbz-schema={
#     "connect.name": "com.materialize.test.Envelope",
#     "fields": [
#       {
#         "default": null,
#         "name": "before",
#         "type": [
#           "null",
#           {
#             "connect.name": "com.materialize.test.Value",
#             "fields": [
#               {
#                 "name": "a",
#                 "type": "int"
#               },
#               {
#                 "name": "b",
#                 "type": "int"
#               }
#             ],
#             "name": "Value",
#             "type": "record"
#           }
#         ]
#       },
#       {
#         "default": null,
#         "name": "after",
#         "type": [
#           "null",
#           "Value"
#         ]
#       },
#       { "name": "op", "type": "string" },
#       {
#         "name": "source",
#         "type": {
#           "connect.name": "io.debezium.connector.sqlserver.Source",
#           "fields": [
#             {
#               "default": "false",
#               "name": "snapshot",
#               "type": [
#                 {
#                   "connect.default": "false",
#                   "connect.name": "io.debezium.data.Enum",
#                   "connect.parameters": {
#                     "allowed": "true,last,false"
#                   },
#                   "connect.version": 1,
#                   "type": "string"
#                 },
#                 "null"
#               ]
#             },
#             {
#               "default": null,
#               "name": "change_lsn",
#               "type": [
#                 "null",
#                 "string"
#               ]
#             },
#             {
#               "default": null,
#               "name": "sequence",
#               "type": [
#                 "null",
#                 "string"
#               ]
#             },
#             {
#               "default": null,
#               "name": "event_serial_no",
#               "type": [
#                 "null",
#                 "long"
#               ]
#             }
#           ],
#           "name": "Source",
#           "namespace": "io.debezium.connector.sqlserver",
#           "type": "record"
#         }
#       }
#     ],
#     "name": "Envelope",
#     "namespace": "com.materialize.test",
#     "type": "record"
#   }

# $ kafka-create-topic topic=ms-dbz-data partitions=1

# # The third record will be skipped, since `lsn` has gone backwards.
# $ kafka-ingest format=avro topic=ms-dbz-data schema=${ms-dbz-schema} timestamp=1
# {"before": null, "after": {"Value":{"a": 1, "b": 1}}, "source": {"change_lsn": {"string": "00000025:00000728:001b"}, "sequence": null, "event_serial_no": {"long": 1}, "snapshot": {"string": "false"}}, "op": "c"}
# {"before": null, "after": {"Value":{"a": 2, "b": 3}}, "source": {"change_lsn": {"string": "00000025:00000728:001c"}, "sequence": null, "event_serial_no": {"long": 1}, "snapshot": {"string": "false"}}, "op": "c"}
# {"before": null, "after": {"Value":{"a": -1, "b": 7}}, "source": {"change_lsn": {"string": "00000025:00000728:001a"}, "sequence": null, "event_serial_no": {"long": 1}, "snapshot": {"string": "false"}}, "op": "c"}

# > CREATE SOURCE ms_dbz
#   IN CLUSTER ${arg.single-replica-cluster}
#   FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-ms-dbz-data-${testdrive.seed}')
#   KEY FORMAT AVRO USING SCHEMA '${key-schema}'
#   VALUE FORMAT AVRO USING SCHEMA '${ms-dbz-schema}'
#   ENVELOPE DEBEZIUM

# > SELECT * FROM ms_dbz
# a b
# ---
# 1 1
# 2 3

# > CREATE SOURCE ms_dbz_uncommitted
#   IN CLUSTER ${arg.single-replica-cluster}
#   FROM KAFKA CONNECTION kafka_conn (ISOLATION LEVEL = 'read_uncommitted', TOPIC 'testdrive-ms-dbz-data-${testdrive.seed}')
#   KEY FORMAT AVRO USING SCHEMA '${key-schema}'
#   VALUE FORMAT AVRO USING SCHEMA '${ms-dbz-schema}'
#   ENVELOPE DEBEZIUM

# > SELECT * FROM ms_dbz_uncommitted
# a b
# ---
# 1 1
# 2 3
