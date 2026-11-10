CREATE TABLE lists (
  id    bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT lists_pkey PRIMARY KEY,
  name  text NOT NULL
);

CREATE TABLE todos (
  id        bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT todos_pkey PRIMARY KEY,
  list_id   bigint  CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE CASCADE,
  title     text    NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200),
  priority  text    NOT NULL DEFAULT 'normal' CONSTRAINT todos_priority_check CHECK (priority IN ('low', 'normal', 'high')),
  due_on    date,
  done      boolean NOT NULL DEFAULT false
);
CREATE INDEX todos_list_id_done_index ON todos (list_id, done);

-- down
DROP TABLE todos;
DROP TABLE lists;
