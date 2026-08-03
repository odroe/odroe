UPDATE posts
SET title = 'Odroe post 42'
WHERE id = 42 AND title IN ('D1 post 42', 'SQLite post 42');

CREATE INDEX posts_title ON posts(title);
