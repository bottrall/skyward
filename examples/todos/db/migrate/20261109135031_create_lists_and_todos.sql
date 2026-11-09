CREATE TABLE lists (
  id    INTEGER CONSTRAINT lists_pkey PRIMARY KEY,
  name  TEXT    NOT NULL
);

CREATE TABLE todos (
  id        INTEGER CONSTRAINT todos_pkey PRIMARY KEY,
  list_id   INTEGER CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE CASCADE,
  title     TEXT    NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200),
  priority  TEXT    NOT NULL DEFAULT 'normal' CONSTRAINT todos_priority_check CHECK (priority IN ('low', 'normal', 'high')),
  due_on    TEXT,
  done      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX todos_list_id_done_index ON todos (list_id, done);

-- down
DROP TABLE todos;
DROP TABLE lists;
