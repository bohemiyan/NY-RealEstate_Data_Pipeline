#!/bin/bash
LOG_FILE=/var/log/real-estate-sync.log
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
cd /path/to/real-estate-sync
echo "[$TIMESTAMP] Starting data sync" >> $LOG_FILE
npm run start >> $LOG_FILE 2>&1
echo "[$TIMESTAMP] Data sync completed" >> $LOG_FILE
