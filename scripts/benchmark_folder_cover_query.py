#!/usr/bin/env python3
"""Benchmark Project: Title's folder-cover SQLite predicate.

This is a host-side SQLite proxy, not a KOReader device benchmark. It validates
that the production range predicate uses the directory portion of the composite
index and compares it with the former parameterized LIKE predicate.
It also compares a proposed page-level UNION batch with repeated indexed range
queries; the production code intentionally keeps the faster measured shape.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sqlite3
import statistics
import time

LIKE_SQL = """
SELECT directory, filename FROM bookinfo
WHERE has_cover = 'Y' AND in_progress = 0 AND ignore_cover IS NULL
  AND directory LIKE ?
ORDER BY directory ASC, filename ASC
"""


def production_sql() -> tuple[str, str]:
    source = (Path(__file__).resolve().parents[1] / "bookinfomanager.lua").read_text()
    index_match = re.search(
        r"CREATE INDEX IF NOT EXISTS folder_cover_candidates\s+"
        r"ON bookinfo\([^;]+\);",
        source,
    )
    range_match = re.search(
        r"local BOOKINFO_FOLDER_COVER_SUBTREE_SQL = \[\[(.*?)\]\]",
        source,
        re.DOTALL,
    )
    if not index_match or not range_match:
        raise RuntimeError("could not extract production folder-cover SQL")
    return index_match.group(0), range_match.group(1).strip()


def build_database(row_count: int, index_sql: str) -> sqlite3.Connection:
    connection = sqlite3.connect(":memory:")
    connection.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE bookinfo (
            has_cover TEXT,
            in_progress INTEGER,
            ignore_cover TEXT,
            directory TEXT NOT NULL,
            filename TEXT NOT NULL
        );
        """
    )
    rows = [
        ("Y", 0, None, f"/library/{index:08d}", "book.epub")
        for index in range(row_count)
    ]
    rows.extend(
        (
            "Y",
            0,
            None,
            f"/zz-target-{folder:02d}/subfolder",
            f"target-{index:03d}.epub",
        )
        for folder in range(9)
        for index in range(64)
    )
    connection.executemany(
        "INSERT INTO bookinfo VALUES (?, ?, ?, ?, ?)",
        rows,
    )
    connection.execute(index_sql)
    connection.execute("ANALYZE")
    return connection


def query_plan(
    connection: sqlite3.Connection, sql: str, parameters: tuple[str, ...]
) -> list[str]:
    return [
        row[3]
        for row in connection.execute("EXPLAIN QUERY PLAN " + sql, parameters)
    ]


def median_query_us(
    connection: sqlite3.Connection,
    sql: str,
    parameters: tuple[str, ...],
    iterations: int,
    expected_rows: int = 64,
) -> float:
    samples = []
    for _ in range(iterations):
        start = time.perf_counter_ns()
        rows = connection.execute(sql, parameters).fetchmany(expected_rows)
        samples.append((time.perf_counter_ns() - start) / 1_000)
        if len(rows) != expected_rows:
            raise RuntimeError(
                f"expected {expected_rows} target rows, got {len(rows)}"
            )
    return statistics.median(samples)


def batch_sql(folder_count: int) -> str:
    parts = []
    for index in range(folder_count):
        parts.append(
            f"""
            SELECT {index + 1} AS folder_index, directory, filename FROM (
                SELECT directory, filename FROM bookinfo
                WHERE has_cover = 'Y' AND in_progress=0 AND ignore_cover IS NULL
                  AND directory>=? AND directory<?
                ORDER BY directory ASC, filename ASC
                LIMIT 64
            )
            """
        )
    return " UNION ALL ".join(parts)


def median_serial_page_us(
    connection: sqlite3.Connection,
    range_sql: str,
    parameter_pairs: list[tuple[str, str]],
    iterations: int,
) -> float:
    samples = []
    for _ in range(iterations):
        start = time.perf_counter_ns()
        for parameters in parameter_pairs:
            rows = connection.execute(range_sql, parameters).fetchmany(64)
            if len(rows) != 64:
                raise RuntimeError(f"expected 64 target rows, got {len(rows)}")
        samples.append((time.perf_counter_ns() - start) / 1_000)
    return statistics.median(samples)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=100_000)
    parser.add_argument("--iterations", type=int, default=200)
    args = parser.parse_args()

    index_sql, range_sql = production_sql()
    connection = build_database(args.rows, index_sql)
    range_parameters = ("/zz-target-00/", "/zz-target-000")
    like_parameters = ("/zz-target-00/%",)
    range_plan = query_plan(connection, range_sql, range_parameters)
    like_plan = query_plan(connection, LIKE_SQL, like_parameters)

    range_plan_text = " ".join(range_plan)
    if "directory>?" not in range_plan_text or "directory<?" not in range_plan_text:
        raise RuntimeError(f"range query is not directory-index bounded: {range_plan}")

    range_us = median_query_us(
        connection, range_sql, range_parameters, args.iterations
    )
    like_us = median_query_us(connection, LIKE_SQL, like_parameters, args.iterations)
    page_batch_sql = batch_sql(9)
    page_parameter_pairs = [
        (f"/zz-target-{folder:02d}/", f"/zz-target-{folder:02d}0")
        for folder in range(9)
    ]
    page_batch_parameters = tuple(
        value for pair in page_parameter_pairs for value in pair
    )
    page_batch_plan = query_plan(
        connection, page_batch_sql, page_batch_parameters
    )
    bounded_branches = sum(
        "directory>?" in step and "directory<?" in step
        for step in page_batch_plan
    )
    if bounded_branches != 9:
        raise RuntimeError(
            f"expected 9 directory-bounded batch branches, got {bounded_branches}: "
            f"{page_batch_plan}"
        )
    page_batch_us = median_query_us(
        connection,
        page_batch_sql,
        page_batch_parameters,
        args.iterations,
        expected_rows=9 * 64,
    )
    page_serial_us = median_serial_page_us(
        connection, range_sql, page_parameter_pairs, args.iterations
    )
    print(
        json.dumps(
            {
                "rows": args.rows,
                "iterations": args.iterations,
                "range_plan": range_plan,
                "like_plan": like_plan,
                "range_median_us": round(range_us, 2),
                "like_median_us": round(like_us, 2),
                "like_over_range_ratio": round(like_us / range_us, 2),
                "page_batch_plan": page_batch_plan,
                "page_batch_median_us": round(page_batch_us, 2),
                "page_serial_median_us": round(page_serial_us, 2),
                "batch_over_serial_ratio": round(page_batch_us / page_serial_us, 2),
                "page_batch_status": "evaluated alternative; not used in production",
                "scope": "host SQLite proxy; not a KOReader device benchmark",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
