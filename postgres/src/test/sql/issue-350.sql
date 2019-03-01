--- test_data->test_var
create schema test_data_join_var;
CREATE TABLE test_data_join_var.test_data
(
  pk_id     bigserial NOT NULL,
  custodian text,
  fulltext  fulltext_with_shingles,
  CONSTRAINT test_data_pkey PRIMARY KEY (pk_id)
)
  WITH (OIDS= FALSE);
ALTER TABLE test_data_join_var.test_data
  OWNER TO cvuser;

CREATE TABLE test_data_join_var.test_var
(
  pk_var_id bigserial NOT NULL,
  var_field text,
  CONSTRAINT test_var_pkey PRIMARY KEY (pk_var_id)
)
  WITH (OIDS= FALSE);
ALTER TABLE test_data_join_var.test_var
  OWNER TO cvuser;

CREATE OR REPLACE VIEW test_data_join_var.test_view AS
SELECT test_data.pk_id,
       test_data.custodian,
       test_data.fulltext,
       test_var.var_field,
       zdb('test_data_join_var.test_data' ::regclass, test_data.ctid) AS zdb
FROM test_data_join_var.test_data
       JOIN test_data_join_var.test_var ON test_data.pk_id = test_var.pk_var_id;

CREATE INDEX es_test_data_join_var_test_data ON test_data_join_var.test_data USING zombodb (zdb('test_data_join_var.test_data'::regclass, ctid),
                                                                                            zdb(test_data.*)) WITH (url='http://localhost:9200/', shards='1', replicas='1', options ='pk_id = <test_var.es_test_data_join_var_test_var>pk_var_id');
CREATE INDEX es_test_data_join_var_test_var ON test_data_join_var.test_var USING zombodb (zdb('test_data_join_var.test_var'::regclass, ctid),
                                                                                          zdb(test_var.*)) WITH (url='http://localhost:9200/', shards='1', replicas='1');


-- test_var->test_data
create schema test_var_join_data;
CREATE TABLE test_var_join_data.test_data
(
  pk_id     bigserial NOT NULL,
  custodian text,
  fulltext  fulltext_with_shingles,
  CONSTRAINT test_data_pkey PRIMARY KEY (pk_id)
)
  WITH (OIDS= FALSE);
ALTER TABLE test_var_join_data.test_data
  OWNER TO cvuser;

CREATE TABLE test_var_join_data.test_var
(
  pk_var_id bigserial NOT NULL,
  var_field text,
  CONSTRAINT test_var_pkey PRIMARY KEY (pk_var_id)
)
  WITH (OIDS= FALSE);
ALTER TABLE test_var_join_data.test_var
  OWNER TO cvuser;

CREATE OR REPLACE VIEW test_var_join_data.test_view AS
SELECT test_var.pk_var_id,
       test_var.var_field,
       test_data.custodian,
       test_data.fulltext,
       zdb('test_var_join_data.test_var'::regclass, test_var.ctid) AS zdb
FROM test_var_join_data.test_var
       JOIN test_var_join_data.test_data ON test_var.pk_var_id = test_data.pk_id;

CREATE INDEX es_test_var_join_data_test_var ON test_var_join_data.test_var USING zombodb (zdb('test_var_join_data.test_var'::regclass, ctid),
                                                                                          zdb(test_var.*)) WITH (url='http://localhost:9200/', shards='1', replicas='1', options ='pk_var_id = <test_data.es_test_var_join_data_test_data>pk_id');
CREATE INDEX es_test_var_join_data_test_data ON test_var_join_data.test_data USING zombodb (zdb('test_var_join_data.test_data'::regclass, ctid),
                                                                                            zdb(test_data.*)) WITH (url='http://localhost:9200/', shards='1', replicas='1');


-- data
INSERT INTO test_data_join_var.test_data(pk_id, custodian, fulltext)
VALUES (1, 'custodian 1', 'The giraffe is tall'),
       (2, 'custodian 2', 'The giraffe is tall'),
       (3, 'custodian 1', 'The monkey is tall');

INSERT INTO test_data_join_var.test_var(pk_var_id, var_field)
VALUES (1, 'dog'),
       (2, 'cat'),
       (3, 'squirrel');

INSERT INTO test_var_join_data.test_data(pk_id, custodian, fulltext)
VALUES (1, 'custodian 1', 'The giraffe is tall'),
       (2, 'custodian 2', 'The giraffe is tall'),
       (3, 'custodian 1', 'The monkey is tall');

INSERT INTO test_var_join_data.test_var(pk_var_id, var_field)
VALUES (1, 'dog'),
       (2, 'cat'),
       (3, 'squirrel');


SELECT *
FROM zdb_highlight('test_var_join_data.test_view'::REGCLASS, '( ( fulltext : giraffe ) )'::TEXT,
                   'pk_var_id IN (''1'')'::TEXT, '{"fulltext"}'::TEXT[])
ORDER BY "primaryKey", "fieldName", "arrayIndex", "position";

DROP SCHEMA test_data_join_var cascade;
DROP SCHEMA test_var_join_data cascade;

