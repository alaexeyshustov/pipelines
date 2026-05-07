# Connectors

This document describes the external connectors used by the application to ingest data and export results.

## Email Connectors

The application uses `Async` to concurrently fetch emails from multiple providers. Adapters are located in `lib/emails/adapters/`.

### Gmail

The Gmail connector uses the Google API to fetch and manage emails.

-   **Implementation**: `Emails::Adapters::GmailAdapter`
-   **Authentication**: OAuth 2.0
-   **Configuration**:
    -   `GMAIL_CREDENTIALS_PATH`: Path to `credentials.json` (defaults to root).
    -   `GMAIL_TOKEN_PATH`: Path to `token.yaml` where OAuth tokens are stored (defaults to root).
-   **Features**:
    -   Searching messages with Gmail-specific queries.
    -   Label management (create, add, remove labels).
    -   Unread count tracking.

### Yahoo Mail

The Yahoo connector uses IMAP with App Passwords to access mailboxes.

-   **Implementation**: `Emails::Adapters::YahooAdapter`
-   **Authentication**: IMAP with App Password.
-   **Configuration**:
    -   `YAHOO_USERNAME`: Your Yahoo email address.
    -   `YAHOO_APP_PASSWORD`: An App Password generated in Yahoo Account Security settings.
-   **Features**:
    -   IMAP-based message fetching.
    -   Flag management (mapping Yahoo-specific flags to IMAP flags).

## Export Connectors

### GitHub (Gists)

The GitHub connector is used to export processed data (like the job interview tracker) to GitHub Gists.

-   **Implementation**: `GistUploader`
-   **Authentication**: Personal Access Token (PAT).
-   **Configuration**:
    -   `GITHUB_TOKEN`: Your GitHub Personal Access Token with `gist` scope.
    -   `GIST_ID`: (Optional) The ID of an existing Gist to update. If not provided, a new Gist will be created.
-   **Features**:
    -   Creating new private Gists.
    -   Updating existing Gists.
    -   CSV export support (via `Interviews::GistExportService`).
