# Cortex AI Gateway + LangChain Agent + MCP

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-gateway/cortex-ai-gateway-presentation.html)

An enablement module demonstrating Snowflake's Cortex AI Gateway as a centralized LLM inference layer, combined with a LangChain agent that queries Snowflake data through the Model Context Protocol (MCP).

## Audience

SEs, Solution Architects, Platform Engineers, and customers evaluating centralized AI governance and observability.

## Topics Covered

- **AI Gateway fundamentals** — auto-provisioned per account, OpenAI-compatible API, model allowlists, logging and payload capture
- **LangChain integration** — `ChatOpenAI` pointed at the gateway inference endpoint with PAT authentication
- **MCP Server** — Snowflake-native MCP server exposing Cortex Analyst, Cortex Search, and SQL execution as tools (no Cortex Agent wrapper needed)
- **Agent tool chaining** — Cortex Analyst generates SQL, `execute_sql` runs it and returns data, Cortex Search provides RAG over documents
- **Observability** — `AGENT_TRACE_TABLE('SNOWFLAKE')` for per-request OpenTelemetry traces with full conversation chain reconstruction; `AI_GATEWAY_USAGE_HISTORY` for token/credit metering
- **Admin controls** — model restriction (`'*'` vs `'claude-*'`), role grants (USAGE vs MONITOR), usage quotas with block enforcement

## Contents

| File | Description |
|------|-------------|
| `setup.sql` | SQL setup script — database, tables, semantic view, Cortex Search service, MCP server, gateway spec |
| `cortex-ai-gateway-langchain-mcp.ipynb` | Hands-on notebook — gateway + LangChain + MCP end-to-end with observability queries |
| `cortex-ai-gateway-presentation.html` | 10-slide presentation covering architecture, benefits, and demo walkthrough |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   LangChain Agent (ReAct)                    │
│                                                              │
│  LLM: ChatOpenAI → AI Gateway → GPT-5.4 (Snowflake-hosted) │
│                                                              │
│  Tools: MCP Client → Snowflake MCP Server (MARKETING_MCP)   │
│         ├── query_campaigns  (Cortex Analyst → SQL)          │
│         ├── execute_sql      (runs the SQL, returns rows)    │
│         └── search_strategy_docs (Cortex Search → RAG)       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
          AGENT_TRACE_TABLE('SNOWFLAKE')  — per-request traces
          AI_GATEWAY_USAGE_HISTORY       — token/credit metering
```

## Key URLs

The AI Gateway uses two distinct URL paths:

| Path | Purpose |
|------|---------|
| `/api/v2/aigateways/snowflake/v1/chat/completions` | Inference (OpenAI-compatible) |
| `/api/v2/aigateways/snowflake/v1/messages` | Inference (Anthropic-compatible) |
| `/api/v2/aigateways/SNOWFLAKE` | Admin (spec management, SHOW, ALTER) |
| `/api/v2/databases/<db>/schemas/<schema>/mcp-servers/<name>` | MCP (streamable HTTP) |

**Note:** Hostnames must use hyphens, not underscores, for valid SSL certificates (e.g., `perickson-aws1` not `perickson_aws1`).

## Hands-On Lab

### Prerequisites

- A Snowflake account with ACCOUNTADMIN (or CREATE DATABASE + CREATE WAREHOUSE privileges)
- A Personal Access Token (PAT) stored in `~/.snowflake/connections.toml`
- Python 3.11+ with `langchain-openai`, `langchain-mcp-adapters`, `langgraph`, `snowflake-connector-python`
- Cross-region inference enabled (for model access)

### Steps

1. Run `setup.sql` in your Snowflake account to create all objects
2. Verify: `SHOW AI GATEWAYS` and `SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC`
3. Open `cortex-ai-gateway-langchain-mcp.ipynb` and run cells sequentially
4. The notebook connects to the gateway, loads MCP tools, runs agent queries, and queries observability data

### What the notebook demonstrates

1. **Gateway inference** — `ChatOpenAI` pointed at `/api/v2/aigateways/snowflake/v1` with PAT auth
2. **MCP tool loading** — `MultiServerMCPClient` with streamable HTTP transport, no npx bridge
3. **Agent queries** — structured data (Analyst → execute_sql), unstructured search (Cortex Search), and hybrid questions using both
4. **Observability** — trace table queries showing per-span token counts, conversation chain reconstruction from `gen_ai.input.messages`/`gen_ai.output.messages`, and credit usage from `AI_GATEWAY_USAGE_HISTORY`

## Cleanup

```sql
DROP DATABASE IF EXISTS CORTEX_GATEWAY_LAB;
DROP WAREHOUSE IF EXISTS GATEWAY_LAB_WH;
-- The AI Gateway is account-level and shared; only reset if needed:
-- ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$ models: [{name: '*'}] $$;
```
