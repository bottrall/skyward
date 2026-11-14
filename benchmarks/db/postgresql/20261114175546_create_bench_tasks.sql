CREATE TABLE bench_tasks (
  id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT bench_tasks_pkey PRIMARY KEY,
  title       text             NOT NULL,
  done        boolean          NOT NULL,
  due_on      date,
  created_at  timestamptz      NOT NULL,
  score       double precision NOT NULL
);

-- down
DROP TABLE bench_tasks;
