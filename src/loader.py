"""
Загрузчик CSV-файлов в PostgreSQL.

Берёт два файла из sample/:
  - tender_data.csv     -> raw_tenders
  - USD_RUB_exchange_rate.csv -> raw_usd_rub

Перед запуском в DBeaver применить sql/01_schema.sql, чтобы таблицы существовали.

Запуск:
    python src/loader.py
"""
from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

# Корень проекта = на уровень выше src/
ROOT = Path(__file__).resolve().parent.parent
SAMPLE_DIR = ROOT / "sample"


def get_engine():
    """Строит SQLAlchemy engine на основе .env."""
    load_dotenv(ROOT / ".env")
    user = os.getenv("POSTGRES_USER", "zakupki")
    password = os.getenv("POSTGRES_PASSWORD", "zakupki_pass")
    host = os.getenv("POSTGRES_HOST", "localhost")
    # ВАЖНО: после смены порта на 5433 (из-за конфликта с нативным Postgres),
    # либо обновить .env, либо переопределить здесь.
    port = os.getenv("POSTGRES_PORT", "5433")
    db = os.getenv("POSTGRES_DB", "zakupki")
    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}"
    log.info("Подключаюсь к %s:%s/%s как %s", host, port, db, user)
    return create_engine(url)


def load_tenders(engine) -> int:
    """Грузит tender_data.csv в raw_tenders. Возвращает число строк."""
    csv_path = SAMPLE_DIR / "tender_data.csv"
    log.info("Читаю %s", csv_path)
    df = pd.read_csv(
        csv_path,
        dtype={
            "tender_id": "string",
            "tender_name": "string",
            "advance_money": "string",
            "currency": "string",
            "selection_phase": "string",
            "legislation": "string",
            "url": "string",
            "procedure": "string",
            "customer_region_code": "string",
            "customer_region": "string",
            "customer_name": "string",
            "customer_inn": "string",
            "winner_name": "string",
            "winner_inn": "string",
            "final_price": "string",
        },
        parse_dates=["publication_date"],
    )

    # for_small_business в csv лежит как "TRUE"/"FALSE" - явно к bool
    df["for_small_business"] = (
        df["for_small_business"].astype("string").str.upper() == "TRUE"
    )

    # Чистим возможные дубли по tender_id (они ломают PRIMARY KEY)
    before = len(df)
    df = df.drop_duplicates(subset="tender_id", keep="first")
    if before != len(df):
        log.warning("Удалено %d дублей по tender_id", before - len(df))

    log.info("Записываю %d строк в raw_tenders", len(df))
    df.to_sql("raw_tenders", engine, if_exists="append", index=False, method="multi", chunksize=500)
    return len(df)


def load_fx(engine) -> int:
    """Грузит USD_RUB_exchange_rate.csv в raw_usd_rub."""
    csv_path = SAMPLE_DIR / "USD_RUB_exchange_rate.csv"
    log.info("Читаю %s", csv_path)
    df = pd.read_csv(csv_path, parse_dates=["date"])
    df["date"] = df["date"].dt.date  # без таймзоны
    df = df.drop_duplicates(subset="date", keep="first")
    log.info("Записываю %d строк в raw_usd_rub", len(df))
    df.to_sql("raw_usd_rub", engine, if_exists="append", index=False, method="multi", chunksize=500)
    return len(df)


def main():
    if not SAMPLE_DIR.exists():
        log.error("Папка %s не найдена", SAMPLE_DIR)
        sys.exit(1)

    engine = get_engine()
    n_tenders = load_tenders(engine)
    n_fx = load_fx(engine)

    log.info("Готово. tenders=%d, usd_rub=%d", n_tenders, n_fx)
    log.info("Дальше: применить sql/02_marts.sql в DBeaver, чтобы построить витрины.")


if __name__ == "__main__":
    main()
