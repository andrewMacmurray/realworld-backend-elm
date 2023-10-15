-- FUNCTIONS

-- JSON_ARRAY

CREATE FUNCTION json_array(element anyelement) RETURNS JSON AS
$$
SELECT COALESCE(element, '[]'::json)
$$ LANGUAGE SQL;


-- SLUGIFY

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION slugify(value TEXT)
RETURNS TEXT AS $$
  -- removes accents (diacritic signs) from a given string --
  WITH unaccented AS (SELECT unaccent(value) AS value),
  -- lowercases the string
  lowercase AS (
    SELECT lower(value) AS value
    FROM unaccented
  ),
  -- replaces anything that's not a letter, number, hyphen('-'), or underscore('_') with a hyphen('-')
  hyphenated AS (
    SELECT regexp_replace(value, '[^a-z0-9\\-_]+', '-', 'gi') AS value
    FROM lowercase
  ),
  -- trims hyphens('-') if they exist on the head or tail of the string
  trimmed AS (
    SELECT trim(regexp_replace(regexp_replace(value, '\\-+$', ''), '^\\-', '')) AS value
    FROM hyphenated
  )
  SELECT value FROM trimmed;
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- TAGIFY

CREATE OR REPLACE FUNCTION tagify(value TEXT)
RETURNS TEXT AS $$
  SELECT regexp_replace(slugify(value), '\-', ' ', 'gi')
$$ LANGUAGE SQL STRICT IMMUTABLE;


-- TABLES

CREATE TABLE users (
	id serial PRIMARY KEY,
	username text NOT NULL UNIQUE,
	email text NOT NULL UNIQUE,
	password text NOT NULL,
	bio text,
	image text,
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp
);

CREATE TABLE articles (
	id serial PRIMARY KEY,
	title text NOT NULL,
	slug text GENERATED ALWAYS AS (slugify(title)) STORED,
	description text NOT NULL,
	body text,
	user_id integer NOT NULL REFERENCES users (id),
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp NOT NULL DEFAULT now(),
	CONSTRAINT unique_article UNIQUE title
);

CREATE TABLE favorites (
	id serial PRIMARY KEY,
	article_id integer NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users (id),
	CONSTRAINT unique_favourite UNIQUE (article_id, user_id)
);

CREATE TABLE follows (
	id serial PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id),
	following integer NOT NULL REFERENCES users (id),
	CONSTRAINT unique_follow UNIQUE (user_id, following)
);

CREATE TABLE tags (
	id serial PRIMARY KEY,
	tag text UNIQUE
);

CREATE TABLE articles_tags (
	id serial PRIMARY KEY,
	article_id integer REFERENCES articles (id) ON DELETE CASCADE,
	tag_id integer REFERENCES tags (id) ON DELETE CASCADE,
	CONSTRAINT unique_article_tag UNIQUE (article_id, tag_id)
);

CREATE TABLE comments (
	id serial PRIMARY KEY,
	body text NOT NULL,
	article_id integer NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users (id),
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp NOT NULL DEFAULT now()
);


