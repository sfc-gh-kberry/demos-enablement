#!/bin/bash
# Build and push the djev SPCS image to Snowflake registry.
#
# Usage:
#   ./deploy.sh <repository_url>
#
# Example:
#   ./deploy.sh myorg-myacct.registry.snowflakecomputing.com/djev_demo/inference/djev_repo
#
# Prerequisites:
#   - Docker Desktop running
#   - snow CLI installed and authenticated
#   - Run `SHOW IMAGE REPOSITORIES LIKE 'DJEV_REPO' IN SCHEMA DJEV_DEMO.INFERENCE;`
#     to get the repository_url
# sfsenorthamerica-perickson-aws1.registry.snowflakecomputing.com/djev_demo/inference/djev_repo

set -euo pipefail

REPO_URL="${1:?Usage: ./deploy.sh <repository_url>}"
IMAGE_TAG="${REPO_URL}/decision-spcs:latest"

echo "=== Logging into Snowflake image registry ==="
snow spcs image-registry login

echo "=== Building Docker image (linux/amd64) ==="
docker build \
    --rm \
    --platform linux/amd64 \
    -t "${IMAGE_TAG}" \
    -f Dockerfile \
    .

echo "=== Pushing image to Snowflake registry ==="
docker push "${IMAGE_TAG}"

echo "=== Done ==="
echo "Image pushed: ${IMAGE_TAG}"
echo ""
echo "Next steps:"
echo "  1. Run spcs/setup.sql to create the service"
echo "  2. Monitor with: SELECT SYSTEM\$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DJEV_SERVICE');"
echo "  3. Run spcs/demo.sql to test predictions"
