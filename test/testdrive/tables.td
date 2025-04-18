# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

$ set-arg-default single-replica-cluster=quickstart

$ set-regex match=cluster1|quickstart replacement=<CLUSTER_NAME>

! INSERT INTO t VALUES (1, 'a');
contains:unknown catalog item 't'

! SHOW CREATE TABLE t;
contains:unknown catalog item 't'

> CREATE TABLE t (a int, b text NOT NULL)

> SHOW CREATE TABLE t;
name   create_sql
------------------------
materialize.public.t  "CREATE TABLE materialize.public.t (a pg_catalog.int4, b pg_catalog.text NOT NULL);"

> CREATE TABLE s (a int DEFAULT 1)
> DROP TABLE s;

> CREATE TABLE s (a int DEFAULT (1))
> DROP TABLE s;

> CREATE TABLE s (a date DEFAULT now())
> DROP TABLE s;

> CREATE TABLE s (a date DEFAULT now() + interval '1 day');
> DROP TABLE s;

> CREATE TABLE s (a int NOT NULL DEFAULT NULL)
> DROP TABLE s;

! CREATE TABLE s (a date DEFAULT 42)
contains:DEFAULT expression does not support casting from integer to date

! CREATE TABLE s (a int, b int DEFAULT a + 3)
contains:column "a" does not exist

! CREATE TABLE t (a int, b int, a int);
contains:column "a" specified more than once

> SELECT * FROM t;

> SHOW TABLES;
name  comment
-------------
t     ""

> SHOW SOURCES;
name    type  cluster  comment
------------------------------

> SHOW INDEXES ON t;

> CREATE DEFAULT INDEX on t

> SHOW INDEXES ON t
name            on          cluster         key    comment
-----------------------------------------------------------------------------------
t_primary_idx   t           <CLUSTER_NAME>  {a,b}  ""

> DROP INDEX t_primary_idx

> SHOW COLUMNS in t;
name       nullable  type      comment
--------------------------------------
a          true       integer  ""
b          false      text     ""

> SHOW COLUMNS in t WHERE name = 'a'
a  true  integer ""

> SHOW COLUMNS in t LIKE 'b%'
b  false  text ""

> INSERT INTO t VALUES (1, 'a');

> SELECT * FROM t;
a    b
---------
1    "a"

$ set schema={
    "name": "row",
    "type": "record",
    "fields": [
      {"name": "id", "type": "string"},
      {"name": "a", "type": "long"},
      {"name": "b", "type": "long"}
    ]
  }

$ kafka-create-topic topic=data

$ kafka-ingest format=avro topic=data schema=${schema} timestamp=1
{"id": "valid1", "a": 2, "b": 1}

> CREATE CONNECTION kafka_conn
  TO KAFKA (BROKER '${testdrive.kafka-addr}', SECURITY PROTOCOL PLAINTEXT);

> CREATE SOURCE data
  IN CLUSTER ${arg.single-replica-cluster}
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')

> CREATE TABLE data_tbl FROM SOURCE data (REFERENCE "testdrive-data-${testdrive.seed}")
  FORMAT AVRO USING SCHEMA '${schema}'

> SELECT * FROM t CROSS JOIN data_tbl
1  a  valid1  2  1

# We don't actually care about these results. We just want to ensure that
# joining a table with a logging source selects some reasonable timestamp,
# rather than e.g. blocking forever, or producing an error about being
# unable to select a timestamp.

# In case the environment has other replicas
> SET cluster_replica = r1

> SELECT * FROM t CROSS JOIN mz_introspection.mz_dataflow_operators LIMIT 0

> DROP SOURCE data CASCADE

# Ensure that tables work after creating a custom index, and that the custom
# index is not subject to the same no-drop restriction as the default index.
> CREATE INDEX t_custom_idx ON t (b)
> SELECT * FROM t;
a    b
---------
1    "a"
> DROP INDEX t_custom_idx

> INSERT INTO t VALUES (2, 'b'), (NULL, 'c');

> SELECT * FROM t;
a      b
----------
1      "a"
2      "b"
<null> "c"

> INSERT INTO t SELECT * FROM t WHERE a IS NULL;

! INSERT INTO t VALUES (1);
contains:null value in column "b" violates not-null constraint

! INSERT INTO t VALUES (1, NULL);
contains:null value in column "b" violates not-null constraint

! INSERT INTO t VALUES ('d', 4);
contains:invalid input syntax for type integer: invalid digit found in string: "d"

# Test that the INSERT body can be a SELECT query.
> INSERT INTO t SELECT 3, 'd'

# Test that literal coercion occurs in simple VALUES clauses....
> INSERT INTO t VALUES ('4', 'e')

# ...but not in complicated VALUES clauses, per PostgreSQL.
! INSERT INTO t VALUES ('5', 'f') LIMIT 0
contains:column "a" is of type integer but expression is of type text

# Test that assignment casts occur when possible...
> INSERT INTO t VALUES (5.0, 'f');
> INSERT INTO t VALUES (6.7::float8, 'g')

# ...but not when impossible.
! INSERT INTO t VALUES (DATE '2020-01-01', 'bad')
contains:column "a" is of type integer but expression is of type date
! INSERT INTO t (b, a) VALUES ('bad', DATE '2020-01-01')
contains:column "a" is of type integer but expression is of type date

# Attempting to insert JSON into an int column is particularly interesting.
# While there is an "explicit" cast from `jsonb` to `int`, there is no
# "assignment" cast, and INSERT is only allowed to use assignment/implicit
# casts.
! INSERT INTO t VALUES (JSON '1', 'bad')
contains:column "a" is of type integer but expression is of type jsonb

> SELECT * FROM t;
a       b
------------
1       "a"
2       "b"
<null>  "c"
<null>  "c"
3       "d"
4       "e"
5       "f"
7       "g"

> CREATE TABLE s (a int NOT NULL);

! INSERT INTO s VALUES (1 + NULL);
contains:null value in column "a" violates not-null constraint

! INSERT INTO s VALUES (case when now() = now() then NULL else 2 end);
contains:null value in column "a" violates not-null constraint

! INSERT INTO s SELECT (case when now() = now() then NULL else 2 end);
contains:null value in column "a" violates not-null constraint

> CREATE TABLE n (a int);

> INSERT INTO n VALUES (NULL);

! INSERT INTO s SELECT * FROM n;
contains:null value in column "a" violates not-null constraint

> DROP TABLE n

> CREATE TABLE v (a timestamptz);
> INSERT INTO v VALUES (now());

! CREATE INDEX ON v (now())
contains:cannot materialize call to current_timestamp

! CREATE INDEX ON v (mz_now())
contains:cannot materialize call to mz_now

! CREATE INDEX ON v (mz_version())
contains:cannot materialize call to mz_version

> DROP TABLE IF EXISTS s;

> DROP TABLE t;

> DROP TABLE IF EXISTS t;

! SELECT * from t;
contains:unknown catalog item 't'

! SHOW INDEXES ON t;
contains:unknown catalog item 't'

> SHOW TABLES;
name  comment
-------------
v     ""

> SHOW TABLES LIKE 'foo'
> SHOW TABLES LIKE 'v%'
v ""
> SHOW TABLES WHERE name = 'v'
v ""

> SHOW SOURCES;
name    type   cluster   comment
--------------------------------

> CREATE TABLE t (a int, b text NOT NULL)

> SELECT * FROM t;

> CREATE VIEW view AS SELECT 1
! INSERT INTO view VALUES (1)
contains:cannot insert into view 'materialize.public.view'

! INSERT INTO mz_kafka_sinks VALUES ('bad', 'bad')
contains:cannot insert into system table 'mz_catalog.mz_kafka_sinks'

> CREATE TABLE j (time TIMESTAMP NOT NULL);

# Verify that INSERT value is desugared.
> INSERT INTO j VALUES ((TIMESTAMP '2020-08-28 15:08:00'));

# Test that a fairly large INSERT completes.
> CREATE TABLE large (a int)
> INSERT INTO large VALUES
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128),
    (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30), (31), (32), (33), (34), (35), (36), (37), (38), (39), (40), (41), (42), (43), (44), (45), (46), (47), (48), (49), (50), (51), (52), (53), (54), (55), (56), (57), (58), (59), (60), (61), (62), (63), (64), (65), (66), (67), (68), (69), (70), (71), (72), (73), (74), (75), (76), (77), (78), (79), (80), (81), (82), (83), (84), (85), (86), (87), (88), (89), (90), (91), (92), (93), (94), (95), (96), (97), (98), (99), (100), (101), (102), (103), (104), (105), (106), (107), (108), (109), (110), (111), (112), (113), (114), (115), (116), (117), (118), (119), (120), (121), (122), (123), (124), (125), (126), (127), (128);

# Test INSERT with default values
> DROP TABLE IF EXISTS t;
> CREATE TABLE t (a int DEFAULT 4, b int DEFAULT 6 * 7)

> INSERT INTO t (a) VALUES (1);
> INSERT INTO t DEFAULT VALUES;

> SELECT * FROM t;
a  b
------
1  42
4  42

# Test INSERT with column specifiers
> DROP TABLE IF EXISTS t;
> CREATE TABLE t (a int, b text not null, c int)
> INSERT INTO t (b, c, a) VALUES ('a', 2, 1), ('b', NULL, 3);

> select * from t;
a      b    c
-------------------
1      "a"  2
3      "b"  <null>

> INSERT INTO t (b) VALUES ('c');

> select * from t;
a      b    c
-------------------
1      "a"  2
3      "b"  <null>
<null> "c"  <null>

! INSERT INTO t (notpresent, a, c) VALUES ('str', 1, 2);
contains:column "notpresent" of relation "materialize.public.t" does not exist

! INSERT INTO t (a, b, c) VALUES ('str', 1, 2);
contains:invalid input syntax for type integer: invalid digit found in string: "str"

! INSERT INTO t (b, a, c) VALUES (1, 'str', 2);
contains:invalid input syntax for type integer: invalid digit found in string: "str"

! INSERT INTO t (d, c, b, a) VALUES (1, 1, 1, 'str');
contains:column "d" of relation "materialize.public.t" does not exist

! INSERT INTO t (a) VALUES (1);
contains:null value in column "b" violates not-null constraint

! INSERT INTO t (a) VALUES (1, 'str');
contains:INSERT has more expressions than target columns

! INSERT INTO t (a, b, c) VALUES (1);
contains:INSERT has more target columns than expressions

! INSERT INTO t (a, a) VALUES (1, 'str')
contains:column "a" specified more than once

# Test pg_table_is_visible.
> CREATE SCHEMA non_default
> CREATE TABLE non_default.hidden (dummy int)
> SELECT name, pg_table_is_visible(oid) AS visible FROM mz_tables WHERE schema_id != 'u1' AND id LIKE 'u%'
name    visible
---------------
hidden  false
j       true
large   true
t       true
v       true

# As in PostgreSQL, tables with no columns are permitted, but they are
# pretty useless.
> CREATE TABLE nocols ();
! INSERT INTO nocols VALUES (1)
contains:INSERT has more expressions than target columns
> SELECT count(*) FROM nocols
0
> INSERT INTO nocols SELECT UNION ALL SELECT
> SELECT count(*) FROM nocols
2
! SELECT DISTINCT * FROM nocols
contains:SELECT DISTINCT must have at least one column


# Test that show columns preserves the column order
> CREATE TABLE column_order (b int, a int);
> SHOW COLUMNS FROM column_order
name nullable type     comment
------------------------------
b    true     integer  ""
a    true     integer  ""


# Test that the underlying Persist shard gets cleaned up on DROP.
> CREATE TABLE shard_drop_test (a int, b text);
> INSERT INTO shard_drop_test VALUES (1, 'hello');

> CREATE TABLE shard_drop_test_empty (a int, b text);

$ set-from-sql var=shard-drop-test-id
SELECT id FROM mz_tables WHERE name = 'shard_drop_test';

$ set-from-sql var=shard-drop-test-empty-id
SELECT id FROM mz_tables WHERE name = 'shard_drop_test_empty';

# Wait for the mz_storage_shards table to get updated.
> SELECT COUNT(shard_id) FROM mz_internal.mz_storage_shards WHERE object_id IN ('${shard-drop-test-id}', '${shard-drop-test-empty-id}');
2

$ set-from-sql var=shard-drop-test-shard-id
SELECT shard_id FROM mz_internal.mz_storage_shards WHERE object_id = '${shard-drop-test-id}';

$ set-from-sql var=shard-drop-test-empty-shard-id
SELECT shard_id FROM mz_internal.mz_storage_shards WHERE object_id = '${shard-drop-test-empty-id}';

> DROP TABLE shard_drop_test;
> DROP TABLE shard_drop_test_empty;

> SELECT COUNT(*) FROM mz_internal.mz_storage_shards WHERE object_id IN ('${shard-drop-test-id}', '${shard-drop-test-empty-id}');
0

$ check-shard-tombstone shard-id=${shard-drop-test-shard-id}

# TODO(parkmycar): The since and upper of the shard are empty, but the controller still has it's handle registered.
# $ check-shard-tombstone shard-id=${shard-drop-test-empty-shard-id}
