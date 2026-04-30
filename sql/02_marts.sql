DROP TABLE IF EXISTS fact_tenders CASCADE;
DROP TABLE IF EXISTS dim_customer CASCADE;
DROP TABLE IF EXISTS dim_winner   CASCADE;
DROP TABLE IF EXISTS dim_region   CASCADE;
DROP TABLE IF EXISTS dim_date     CASCADE;

-- =========================================================
-- ИЗМЕРЕНИЕ: заказчики
-- =========================================================
CREATE TABLE dim_customer AS
SELECT DISTINCT ON (customer_inn)
    customer_inn  AS inn,
    customer_name AS name
FROM raw_tenders
WHERE customer_inn IS NOT NULL
ORDER BY customer_inn, publication_date DESC;

ALTER TABLE dim_customer ADD PRIMARY KEY (inn);

-- =========================================================
-- ИЗМЕРЕНИЕ: победители (поставщики)
-- =========================================================
CREATE TABLE dim_winner AS
SELECT DISTINCT ON (winner_inn)
    winner_inn  AS inn,
    winner_name AS name
FROM raw_tenders
WHERE winner_inn IS NOT NULL AND winner_inn <> ''
ORDER BY winner_inn, publication_date DESC;

ALTER TABLE dim_winner ADD PRIMARY KEY (inn);

-- =========================================================
-- ИЗМЕРЕНИЕ: регионы
-- =========================================================
CREATE TABLE dim_region AS
SELECT DISTINCT ON (customer_region_code)
    customer_region_code AS code,
    customer_region      AS name
FROM raw_tenders
WHERE customer_region_code IS NOT NULL
ORDER BY customer_region_code, publication_date DESC;

ALTER TABLE dim_region ADD PRIMARY KEY (code);

-- =========================================================
-- ИЗМЕРЕНИЕ: дата
-- =========================================================
CREATE TABLE dim_date AS
WITH bounds AS (
    SELECT
        DATE_TRUNC('year', MIN(publication_date))::date                                AS d_min,
        (DATE_TRUNC('year', MAX(publication_date)) + INTERVAL '1 year - 1 day')::date  AS d_max
    FROM raw_tenders
),
days AS (
    SELECT generate_series(d_min, d_max, INTERVAL '1 day')::date AS date
    FROM bounds
)
SELECT
    date,
    EXTRACT(YEAR    FROM date)::int  AS year,
    EXTRACT(QUARTER FROM date)::int  AS quarter,
    EXTRACT(MONTH   FROM date)::int  AS month,
    TO_CHAR(date, 'YYYY-MM')         AS year_month,
    TO_CHAR(date, 'TMMonth')         AS month_name,
    EXTRACT(ISODOW  FROM date)::int  AS day_of_week
FROM days;

ALTER TABLE dim_date ADD PRIMARY KEY (date);

-- =========================================================
-- ФАКТ: тендеры
-- Здесь:
--   - advance_money "30.00%" -> 30.00 (число)
--   - final_price (текст) -> NUMERIC, нечисла -> NULL
--   - is_completed: победитель есть и фаза не "несостоявшаяся"
--   - discount_pct: насколько упала цена на торгах
--   - цены в долларах через курс на день публикации
-- =========================================================
CREATE TABLE fact_tenders AS
SELECT
    t.tender_id,
    t.publication_date::date            AS date,
    t.customer_inn,
    NULLIF(t.winner_inn, '')            AS winner_inn,
    t.customer_region_code              AS region_code,
    t.legislation,
    t.procedure,
    t.selection_phase,
    t.for_small_business                AS is_small_business,

    t.start_price                        AS start_price_rub,
    CASE
        WHEN t.final_price ~ '^[0-9]+(\.[0-9]+)?$'
        THEN t.final_price::numeric
    END                                  AS final_price_rub,

    CASE
        WHEN t.advance_money LIKE '%\%'
        THEN REPLACE(t.advance_money, '%', '')::numeric
    END                                  AS advance_pct,

    (t.selection_phase = 'Завершена')    AS is_completed,

    CASE
        WHEN t.start_price > 0
         AND t.final_price ~ '^[0-9]+(\.[0-9]+)?$'
        THEN ROUND(((t.start_price - t.final_price::numeric) / t.start_price * 100)::numeric, 2)
    END                                  AS discount_pct,

    CASE
        WHEN fx.exchange_rate IS NOT NULL AND fx.exchange_rate > 0
        THEN ROUND(t.start_price / fx.exchange_rate, 2)
    END                                  AS start_price_usd,
    CASE
        WHEN fx.exchange_rate IS NOT NULL AND fx.exchange_rate > 0
         AND t.final_price ~ '^[0-9]+(\.[0-9]+)?$'
        THEN ROUND(t.final_price::numeric / fx.exchange_rate, 2)
    END                                  AS final_price_usd

FROM raw_tenders t
LEFT JOIN raw_usd_rub fx ON fx.date = t.publication_date::date;

-- Первичный ключ и FK на факте
ALTER TABLE fact_tenders ADD PRIMARY KEY (tender_id);
ALTER TABLE fact_tenders ADD CONSTRAINT fk_fact_customer
    FOREIGN KEY (customer_inn) REFERENCES dim_customer(inn);
ALTER TABLE fact_tenders ADD CONSTRAINT fk_fact_winner
    FOREIGN KEY (winner_inn) REFERENCES dim_winner(inn);
ALTER TABLE fact_tenders ADD CONSTRAINT fk_fact_region
    FOREIGN KEY (region_code) REFERENCES dim_region(code);
ALTER TABLE fact_tenders ADD CONSTRAINT fk_fact_date
    FOREIGN KEY (date) REFERENCES dim_date(date);

-- Индексы под типичные запросы дашборда
CREATE INDEX idx_fact_date         ON fact_tenders(date);
CREATE INDEX idx_fact_region       ON fact_tenders(region_code);
CREATE INDEX idx_fact_customer     ON fact_tenders(customer_inn);
CREATE INDEX idx_fact_winner       ON fact_tenders(winner_inn);
CREATE INDEX idx_fact_legislation  ON fact_tenders(legislation);
CREATE INDEX idx_fact_completed    ON fact_tenders(is_completed);