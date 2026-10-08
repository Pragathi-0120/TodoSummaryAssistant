# Todo Summary Assistant

## DevOps enablement changes

- Backend database, Cohere, Slack, and CORS settings are supplied through environment variables; no real values belong in the repository.
- The frontend API origin is read from `REACT_APP_API_URL` at build time.
- `Frontend/todo/src/services/todoService.js` now reads the API base URL from `REACT_APP_API_URL` instead of a hardcoded localhost address.
- The Nginx frontend proxies `/api/` requests to the Compose backend. Production can leave `REACT_APP_API_URL` empty, so no EC2 address is baked into the frontend image; local development can still use `http://localhost:8080`.
- CORS is configured for `/api/**` using `CORS_ALLOWED_ORIGINS` (comma-separated origins; defaults to `http://localhost:3000`).
- Removed the hardcoded `@CrossOrigin` annotation from `TodoController.java` so CORS is controlled only by `WebConfig` and the `CORS_ALLOWED_ORIGINS` environment variable. No business logic changed.
- The REST API path prefix is `/api/todos`.
- Spring Boot Actuator and Micrometer Prometheus expose `/actuator/health` and `/actuator/prometheus`. No Spring Security dependency or authentication filter is configured, so these paths are unauthenticated.
- Docker builds use a Maven/JRE multi-stage backend image and a Node/unprivileged Nginx multi-stage frontend image. Pass the frontend API origin at build time with `docker build --build-arg REACT_APP_API_URL=https://api.example.com -t todo-frontend .` from `Frontend/todo`; React embeds this value in its static files during `npm run build`.
- Copy `.env.example` to `.env`, replace the placeholders, then run `docker compose --profile local up --build`. The `local` profile starts MySQL for local testing; production should set `DB_URL` to the private RDS endpoint and omit `--profile local`. Open the frontend at `http://localhost:3000`, Prometheus at `http://localhost:9090`, and Grafana at `http://localhost:3001`.
- These are configuration and deployment changes only; application business logic is unchanged.

## CI/CD pipeline

The workflow is in `.github/workflows/ci-cd.yml`. It uses three simple jobs:

1. **Build and test (all branches and pull requests):** Maven tests the Java backend, while npm installs dependencies, runs the frontend test command, and builds the React bundle. Failures stop the workflow before publishing.
2. **Build and publish (pushes to `main` only):** Docker builds backend and frontend images, tags each with the full commit SHA and `latest`, then pushes both tags to Docker Hub.
3. **Deploy (after publishing on `main` only):** GitHub Actions assumes a narrowly scoped AWS role through OIDC, then uses SSM Run Command on the configured EC2 instance. EC2 fetches the exact commit from this public repository; the deploy script reads SecureStrings from SSM, starts the SHA images, retries the health check, and restores the prior successful tag on failure.

Create these repository Actions secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `AWS_ROLE_ARN`, `AWS_REGION`, and `EC2_INSTANCE_ID`. See [aws/aws-setup.md](aws/aws-setup.md) for creating them and the EC2/RDS resources.

SSM avoids opening SSH to GitHub's changing hosted-runner IPs and removes SSH keys from GitHub Secrets.
OIDC gives the deploy job short-lived AWS credentials restricted to this repository's `main` branch.

The images are expected to be public Docker Hub repositories so EC2 can pull them without storing Docker Hub credentials on the instance. If the first deployment is unhealthy, it fails with a clear message and skips rollback because no previous tag exists; after a healthy deployment, the script saves `.deployed_tag` for subsequent rollbacks.

A full-stack application to manage personal to-do items, summarize pending tasks using Cohere LLM, and send the summary to a Slack channel.

## Table of Contents

* [Features](#features)
* [Tech Stack](#tech-stack)
* [Setup Instructions](#setup-instructions)
    * [Prerequisites](#prerequisites)
    * [Backend Setup](#backend-setup)
    * [Frontend Setup](#frontend-setup)
* [LLM (Cohere) Setup](#llm-cohere-setup)
* [Slack Integration Setup](#slack-integration-setup)
* [Design/Architecture Decisions](#designarchitecture-decisions)


## Features

* **Create, Edit, Delete To-Do Items:** Full CRUD operations for personal to-do items.
* **View To-Do List:** Display current to-do items with their status.
* **Summarize Pending To-Dos:** Utilizes Cohere LLM to generate a concise summary of all pending to-do items.
* **Send Summary to Slack:** Automatically posts the generated summary to a configured Slack channel using Incoming Webhooks.
* **Notifications:** Provides success/failure messages for Slack operations.

## Tech Stack

* **Frontend:** HTML, CSS, Javascript, React, Axios(for API calls), 
* **Backend:** Spring Boot (Java 17+), Maven
* **Database:** MySQL (via Spring Data JPA and Hibernate)
* **LLM:** Cohere API
* **Messaging:** Slack Incoming Webhooks
* **HTTP Client:** OkHttp (for Cohere and Slack API calls in backend)

## Setup Instructions

### Prerequisites

- Docker Engine/Desktop with Docker Compose v2.
- Cohere and Slack credentials only if you use those integrations.

### Run locally

1. Copy `.env.example` to `.env` and replace the placeholders. Keep `.env` local; it is ignored by Git.
2. From the repository root, run:

   ```bash
   docker compose --profile local up --build
   ```

3. Open the app at `http://localhost:3000`, backend health at `http://localhost:8080/actuator/health`, Prometheus at `http://localhost:9090`, and Grafana at `http://localhost:3001`.
4. Press `Ctrl+C` to stop, or run `docker compose --profile local down`. Use `docker compose --profile local down -v` only when you also want to delete local MySQL and monitoring data volumes.

The `local` profile is the only Compose profile that starts MySQL. When `REACT_APP_API_URL` is empty, Nginx proxies `/api/` to the backend; a direct API origin can still be supplied as a frontend build argument.

## LLM (Cohere) Setup

1.  **Create a Cohere Account:** Visit [Cohere.ai](https://cohere.ai/) and sign up for a free account.
2.  **Obtain API Key:** Once logged in, navigate to your dashboard or API keys section to find your API key.
3.  **Configure locally:** Put your Cohere key in the ignored root `.env` as `COHERE_API_KEY`; do not put it in `application.properties`.

## Slack Integration Setup

1.  **Create a Slack App:**
    * Go to [api.slack.com/apps](https://api.slack.com/apps).
    * Click "Create New App" and choose "From scratch".
    * Give your app a name (e.g., "Todo Summary Bot") and select your Slack workspace.
2.  **Activate Incoming Webhooks:**
    * From your app's settings page, navigate to "Features" -> "Incoming Webhooks".
    * Toggle the "Activate Incoming Webhooks" switch to "On".
    * Scroll down and click the "Add New Webhook to Workspace" button.
    * Select the specific channel where you want the to-do summaries to be posted (e.g., `#general`, `#todos`, or a new channel).
    * Click "Allow".
3.  **Copy Webhook URL:**
    * A unique Webhook URL will be generated. Copy this URL.
4.  **Configure locally:** Put the webhook URL in the ignored root `.env` as `SLACK_WEBHOOK_URL`; do not put it in `application.properties`.

## Design/Architecture Decisions

* **Separation of Concerns:** The project is cleanly separated into frontend (React) and backend (Spring Boot) directories, allowing independent development and deployment.
* **RESTful API:** The backend exposes standard RESTful endpoints for managing todos, ensuring clear and predictable communication with the frontend.
* **Spring Data JPA:** Leveraged for efficient and simplified database interactions with MySQL, reducing boilerplate code for data access.
* **Service Layer:** Business logic (CRUD operations, LLM calls, Slack calls) is encapsulated within dedicated service classes, promoting modularity and testability.
* **External API Integration:** `OkHttp` was chosen as a lightweight and efficient HTTP client for making external API calls to Cohere and Slack.
* **CORS Configuration:** Explicit CORS configuration in Spring Boot ensures that the React frontend can communicate with the backend.
* **Error Handling:** Basic error handling is implemented on both frontend and backend to provide user feedback and log issues.
* **LLM Prompt Engineering:** A simple prompt is used for Cohere to instruct it on summarizing the list of to-do items. This can be further refined for better results.
* **Notification System:** A simple notification component in React provides immediate feedback to the user about operations.

## Demo Images

![Screenshot (1146)](https://github.com/user-attachments/assets/53fe53e3-b527-4659-9ab6-b462ae034fbd)

![Screenshot (1144)](https://github.com/user-attachments/assets/474b1a46-36c8-4407-8bf9-a46ca911603b)

![Screenshot (1143)](https://github.com/user-attachments/assets/1e9f8783-d0df-42ce-a3f8-ec7ca5e7c078)
