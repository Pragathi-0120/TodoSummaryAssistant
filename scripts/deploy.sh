#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

IMAGE_TAG="${1:?Usage: deploy.sh <commit-sha>}"
: "${AWS_REGION:?Set AWS_REGION for SSM Parameter Store}"
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME}"

get_parameter() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/todo-app/$1" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

cleanup_temp_files() {
  rm -f .env.tmp .deployed_tag.tmp
}
trap cleanup_temp_files EXIT

write_env() {
  local key="$1" value="$2"
  case "$value" in
    *$'\n'*|*$'\r'*) echo "Parameter $key contains a newline; refusing to write .env" >&2; return 1 ;;
  esac
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  printf "%s='%s'\n" "$key" "$value" >> .env.tmp
}

previous_tag=""
if [[ -f .deployed_tag ]]; then
  previous_tag="$(cat .deployed_tag)"
elif container_id="$(docker compose ps -q backend 2>/dev/null)" && [[ -n "$container_id" ]]; then
  previous_image="$(docker inspect --format '{{.Config.Image}}' "$container_id")"
  previous_tag="${previous_image##*:}"
fi

umask 077
: > .env.tmp
db_url="$(get_parameter db-url)"
db_username="$(get_parameter db-username)"
db_password="$(get_parameter db-password)"
cohere_api_key="$(get_parameter cohere-api-key)"
slack_webhook_url="$(get_parameter slack-webhook-url)"
grafana_admin_user="$(get_parameter grafana-admin-user)"
grafana_admin_password="$(get_parameter grafana-admin-password)"
write_env DOCKERHUB_USERNAME "$DOCKERHUB_USERNAME"
write_env IMAGE_TAG "$IMAGE_TAG"
write_env DB_URL "$db_url"
write_env DB_USERNAME "$db_username"
write_env DB_PASSWORD "$db_password"
write_env COHERE_API_KEY "$cohere_api_key"
write_env SLACK_WEBHOOK_URL "$slack_webhook_url"
write_env GRAFANA_ADMIN_USER "$grafana_admin_user"
write_env GRAFANA_ADMIN_PASSWORD "$grafana_admin_password"
write_env CORS_ALLOWED_ORIGINS "*"
write_env REACT_APP_API_URL ""
mv .env.tmp .env
chmod 600 .env

export AWS_REGION DOCKERHUB_USERNAME IMAGE_TAG

rollback() {
  local deploy_status=$?
  cleanup_temp_files
  if (( deploy_status != 0 )); then
    if [[ -z "$previous_tag" ]]; then
      echo "Deployment failed on the first deployment; no previous successful tag exists, so rollback is skipped." >&2
      exit "$deploy_status"
    fi
    echo "Deployment or health check failed; rolling back to the previous successful tag." >&2
    echo "Restoring previous image tag: $previous_tag" >&2
    IMAGE_TAG="$previous_tag" docker compose pull backend frontend || true
    if IMAGE_TAG="$previous_tag" docker compose up -d --no-build backend frontend; then
      for attempt in {1..12}; do
        if curl --fail --silent --show-error http://127.0.0.1:8080/actuator/health | grep -q '"status":"UP"'; then
          echo "Rollback health check passed." >&2
          exit "$deploy_status"
        fi
        sleep 10
      done
      echo "Rollback was attempted but the health check did not recover." >&2
    else
      echo "Rollback compose command failed." >&2
    fi
    exit "$deploy_status"
  fi
}
trap rollback EXIT

docker compose pull backend frontend
docker compose up -d --no-build --remove-orphans

for attempt in {1..18}; do
  if curl --fail --silent --show-error http://127.0.0.1:8080/actuator/health | grep -q '"status":"UP"'; then
    printf '%s\n' "$IMAGE_TAG" > .deployed_tag.tmp
    chmod 600 .deployed_tag.tmp
    mv .deployed_tag.tmp .deployed_tag
    echo "Deployment $IMAGE_TAG is healthy."
    exit 0
  fi
  echo "Health check attempt $attempt/18 failed; retrying in 10 seconds."
  sleep 10
done

echo "Backend health check failed after 18 attempts." >&2
exit 1
