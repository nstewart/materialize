# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

$ set-arg-default single-replica-cluster=quickstart

$ kafka-create-topic topic=test

$ kafka-ingest topic=test format=bytes
jack,jill
goofus,gallant

> CREATE CONNECTION kafka_conn
  TO KAFKA (BROKER '${testdrive.kafka-addr}', SECURITY PROTOCOL PLAINTEXT);

> CREATE SOURCE src
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn
  (TOPIC 'testdrive-test-${testdrive.seed}')

> CREATE TABLE src_tbl
  FROM SOURCE src (REFERENCE "testdrive-test-${testdrive.seed}")
  FORMAT CSV WITH 2 COLUMNS

> CREATE MATERIALIZED VIEW v AS
  SELECT column1 || column2 AS c FROM src_tbl

> SELECT * FROM v
jackjill
goofusgallant
