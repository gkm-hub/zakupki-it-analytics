DROP TABLE IF EXISTS raw_tenders CASCADE;
DROP TABLE IF EXISTS raw_usd_rub CASCADE;

CREATE TABLE raw_tenders (
    tender_id            TEXT PRIMARY KEY,
    tender_name          TEXT,
    start_price          NUMERIC,
    tender_security      NUMERIC,
    advance_money        TEXT,
    currency             TEXT,
    publication_date     TIMESTAMP,
    selection_phase      TEXT,
    legislation          TEXT,
    url                  TEXT,
    procedure            TEXT,
    for_small_business   BOOLEAN,
    customer_region_code TEXT,
    customer_region      TEXT,
    customer_name        TEXT,
    customer_inn         TEXT,
    winner_name          TEXT,
    winner_inn           TEXT,
    final_price          TEXT
);

CREATE TABLE raw_usd_rub (
    date          DATE PRIMARY KEY,
    exchange_rate NUMERIC NOT NULL
);

COMMENT ON TABLE raw_tenders IS 'Сырые данные крупнейших тендеров (>500 млн руб) за 2014-2022';
COMMENT ON TABLE raw_usd_rub IS 'Курс USD/RUB по дням (для пересчёта в долларовый эквивалент)';
