# CoCo Data Engineering Lab — Speaker Notes

## Account Context

Acme Financial is a payment and credit card services company that ingests transaction data from multiple payment processors. Each vendor delivers data in a different format — varying date formats, amount representations, column names, and quality levels. This lab demonstrates how Cortex Code (CoCo) accelerates the data engineering workflow from initial exploration through production pipeline deployment, condensed into a 30-minute hands-on session with three tiers of increasing sophistication.

---

## Slide: Hero

**Talking Points:**
- Frame the problem — Acme Financial receives transaction data from multiple payment processors, each with different formats
- Manual standardization is slow and error-prone: different date formats, amounts in cents vs. dollars, inconsistent merchant naming
- This lab shows how CoCo accelerates that workflow from exploration to production pipeline
- 30-minute format, 3 tiers increasing in sophistication: Explore → Transform → Skill

**CoCo Prompts to Demo:**
- N/A (title slide)

**References:**
- N/A

---

## Slide: The Challenge

**Talking Points:**
- Walk through each vendor's quirks:
  - Vendor A: dollar amounts with `$` and commas, standard ISO dates
  - Vendor B: amounts in cents (integer), dates as epoch timestamps
  - Vendor C: amounts as text with currency codes, dates in DD-Mon-YY format
- Emphasize these are real-world patterns — vendors rarely conform to your schema
- The cost of manual onboarding: days of SQL writing, testing, debugging for each new vendor
- Show: Quick peek at raw data to see the mess

**CoCo Prompts to Demo:**
- Show a quick `SELECT * FROM COCO_DE_LAB.RAW.VENDOR_A_TRANSACTIONS LIMIT 5` in Snowsight to illustrate the raw data

**References:**
- N/A

---

## Slide: Lab Setup

**Talking Points:**
- One-time setup, takes ~30 seconds
- Creates database `COCO_DE_LAB`, 3 schemas (RAW, STAGING, MART)
- Loads ~500 synthetic transactions per vendor
- Each vendor table has intentionally different column names, formats, and quality issues

**CoCo Prompts to Demo:**
- Run `setup.sql` in a Snowsight worksheet
- Verify with: "Show me the schemas in COCO_DE_LAB"

**References:**
- N/A

---

## Slide: Tier 1 — Explore (Beginner)

**Talking Points:**
- This is where most teams start — understanding what you've received
- CoCo eliminates the "stare at INFORMATION_SCHEMA" step
- It generates profiling queries, identifies nulls, detects format patterns
- No SQL expertise needed to understand the data landscape

**CoCo Prompts to Demo:**
1. "What tables are in COCO_DE_LAB.RAW?"
2. "Profile VENDOR_A_TRANSACTIONS — show me row counts, nulls, and sample values"
3. "Compare the schemas across all 3 vendor tables"
4. "What data quality issues do you see in VENDOR_C_TRANSACTIONS?"

**Key Moment:** When CoCo identifies that amounts are in cents and dates use DD-Mon-YY format without being told explicitly.

**References:**
- N/A

---

## Slide: Tier 2 — Transform (Intermediate)

**Talking Points:**
- Now we fix it. CoCo generates the transformation SQL iteratively
- You refine with natural language — no need to memorize TRY_TO_DATE format strings
- The context carries forward — you don't re-explain the schema each turn
- Dynamic tables keep the pipeline fresh without orchestration overhead

**CoCo Prompts to Demo:**
1. "Create a staging view that cleans VENDOR_A_TRANSACTIONS: parse dates to DATE, strip $ and commas from amounts to get a NUMBER, title-case merchant names"
2. "Do the same for VENDOR_B and VENDOR_C, mapping to the same output schema as VENDOR_A's staging view"
3. "Union all 3 staging views into a dynamic table called FACT_TRANSACTION in the MART schema with a 1-hour target lag"

**Key Moment:** When CoCo handles the cents-to-dollars conversion and DD-Mon-YY date parsing for Vendor C correctly because it remembers the profiling results from Tier 1.

**References:**
- N/A

---

## Slide: Tier 3 — Skill (Advanced)

**Talking Points:**
- The real value — making this repeatable
- Instead of asking CoCo the same questions every time a new vendor arrives, we encode the pattern as a skill
- The skill knows: profile the raw table, generate a dbt staging model, add schema tests, create source definition
- Switch to terminal for CoCo CLI demonstration

**CoCo Prompts to Demo (in CLI):**
1. Show the skill directory structure: `ls skills/dbt-ingest-pipeline/`
2. Walk through `skill.md` — what it instructs CoCo to do
3. Invoke: "$dbt-ingest-pipeline" then describe a hypothetical vendor_d table
4. Show the generated dbt model files

**Key Moment:** The skill produces production-ready dbt artifacts, not just one-off SQL.

**References:**
- CoCo skill development docs: https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-skills

---

## Slide: What We Built

**Talking Points:**
- Recap the full pipeline: RAW → STAGING → MART
- The beginner explored (Tier 1), the intermediate built (Tier 2), the advanced codified (Tier 3)
- This is the repeatable pattern for every future vendor
- Emphasis: The skill is the durable artifact — it encodes the team's institutional knowledge about how vendors should be onboarded
- The pipeline is self-documenting: schema tests serve as contracts, source freshness checks catch delivery failures

**CoCo Prompts to Demo:**
- N/A (recap slide)

**References:**
- N/A

---

## Slide: Takeaway

**Talking Points:**
- Three levels of CoCo value:
  1. Explore data without SQL expertise
  2. Build transformations conversationally
  3. Package patterns as reusable skills
- The progression mirrors how a team matures: from ad-hoc to standardized
- Close: "The next vendor that comes in? Run the skill. 5 minutes to production-ready dbt models."

**CoCo Prompts to Demo:**
- N/A (closing slide)

**References:**
- N/A
