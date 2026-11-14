CREATE TABLE bench_tasks (
  id          INTEGER CONSTRAINT bench_tasks_pkey PRIMARY KEY,
  title       TEXT    NOT NULL,
  done        INTEGER NOT NULL,
  due_on      TEXT,
  created_at  TEXT    NOT NULL,
  score       REAL    NOT NULL
);

-- down
DROP TABLE bench_tasks;
