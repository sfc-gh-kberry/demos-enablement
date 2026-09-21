# CoCo Getting Started — Data Engineering Lab

A 30-minute hands-on lab demonstrating how Cortex Code (CoCo) accelerates data engineering workflows, from initial exploration through production pipeline deployment.

## Overview

Acme Financial ingests transaction data from multiple payment processors, each delivering data in a different format — varying date formats, amount representations, column names, and quality levels. This lab walks through three tiers of increasing sophistication to standardize that data using CoCo.

| Tier | Surface | Focus |
|------|---------|-------|
| 1 — Beginner | Snowsight + CoCo sidebar | Explore raw data, profile tables, identify quality issues |
| 2 — Intermediate | Snowsight + CoCo sidebar | Generate standardization SQL, build staging views, create dynamic table |
| 3 — Advanced | CoCo CLI (terminal) | Create a reusable skill that outputs dbt models for any new vendor table |

## Setup

1. Run `setup.sql` in a Snowsight worksheet — creates the `COCO_DE_LAB` database with 4 vendor tables (~500 rows each)
2. Verify: `SELECT * FROM COCO_DE_LAB.RAW.VENDOR_A_TRANSACTIONS LIMIT 5;`

## Contents

| File | Description |
|------|-------------|
| [`presentations/coco-data-engineering.html`](https://sfc-gh-perickson.github.io/demos-enablement/coco-getting-started/presentations/coco-data-engineering.html) | 8-slide presentation deck |
| `presentations/coco-data-engineering-speaker-notes.md` | Per-slide talking points and CoCo prompts |
| `setup.sql` | Database, schemas, and synthetic vendor data |
| `skills/dbt-ingest-pipeline/skill.md` | CoCo skill for generating dbt staging models |

## Sample Data

`COCO_DE_LAB.RAW` contains 4 tables simulating payment processor feeds:

| Table | Vendor | Quirks |
|-------|--------|--------|
| `VENDOR_A_TRANSACTIONS` | PayRight | Dates `MM/DD/YYYY`, amounts `$1,234.56`, merchants ALL CAPS |
| `VENDOR_B_TRANSACTIONS` | SwiftPay | Dates `YYYY-MM-DD`, amounts decimal, merchants Title Case |
| `VENDOR_C_TRANSACTIONS` | QuickSettle | Dates `DD-Mon-YY`, amounts in cents, merchants lowercase + extra whitespace |
| `VENDOR_D_TRANSACTIONS` | ClearCharge | Epoch timestamps, mixed nulls, amounts as messy strings |
