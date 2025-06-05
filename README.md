# Real Estate Data Sync Pipeline

## Overview
This project implements a data synchronization pipeline for New York State county-level real estate sales data, fetching weekly updates from a provided ZIP file, processing the CSV data, and syncing it with a local PostgreSQL database.

## Prerequisites
- Node.js (v18 or higher)
- PostgreSQL (v13 or higher)
- npm
- Docker (optional, for containerized deployment)

## Setup Instructions

1. **Install Dependencies**
   ```bash
   npm install
   ```

2. **PostgreSQL Setup**
   - Create a database named `real_estate_db`.
   - Run the SQL schema:
     ```bash
     psql -U postgres -d real_estate_db -f sql/schema.sql
     ```

3. **Environment Variables**
   Create a `.env` file in the project root:
   ```bash
   DB_HOST=localhost
   DB_PORT=5432
   DB_USERNAME=postgres
   DB_PASSWORD=postgres
   DB_NAME=real_estate_db
   ```

4. **Run the Application**
   - Build the project:
     ```bash
     npm run build
     ```
   - Start the application:
     ```bash
     npm run start
     ```

5. **Manual Sync**
   Trigger a manual sync via HTTP:
   ```bash
   curl -X POST http://localhost:3000/data-sync/sync
   ```

6. **Schedule Weekly Sync**
   - Add a cron job to run weekly (e.g., every Monday at 1 AM):
     ```bash
     crontab -e
     0 1 * * 1 /path/to/cron-job.sh
     ```
   - Ensure `cron-job.sh` is executable:
     ```bash
     chmod +x cron-job.sh
     ```

## Docker Deployment (Optional)
1. Build the Docker image:
   ```bash
   docker build -t real-estate-sync .
   ```
2. Run the container:
   ```bash
   docker run -d -p 3000:3000 --env-file .env real-estate-sync
   ```

## Notes
- The pipeline uses SHA-256 hashing to detect record changes.
- Bulk operations are handled transactionally to ensure data consistency.
- Logs are written to `/var/log/real-estate-sync.log` for cron jobs.
