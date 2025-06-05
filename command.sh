#!/bin/bash

# Create project directory structure
mkdir -p {src/{config,modules/{data-sync,cron},entities},sql}

# Create sql/schema.sql
cat << 'EOF' > sql/schema.sql
CREATE TABLE IF NOT EXISTS counties (
    county_id SERIAL PRIMARY KEY,
    county_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS sales_records (
    record_id SERIAL PRIMARY KEY,
    county_id INT REFERENCES counties(county_id) ON DELETE CASCADE,
    sale_date DATE NOT NULL,
    sale_price DECIMAL(15, 2),
    property_address VARCHAR(255),
    city VARCHAR(100),
    zip_code VARCHAR(10),
    parcel_id VARCHAR(50) NOT NULL,
    record_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (county_id, parcel_id, sale_date)
);

-- Valid PostgreSQL index creation
CREATE INDEX idx_parcel_id ON sales_records (parcel_id);
CREATE INDEX idx_record_hash ON sales_records (record_hash);
CREATE INDEX idx_sales_county_date ON sales_records (county_id, sale_date);
EOF

# Create src/config/database.ts
cat << 'EOF' > src/config/database.ts
import { TypeOrmModuleOptions } from '@nestjs/typeorm';

export const databaseConfig: TypeOrmModuleOptions = {
  type: 'postgres',
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT) || 5432,
  username: process.env.DB_USERNAME || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'real_estate_db',
  entities: [__dirname + '/../**/*.entity{.ts,.js}'],
  synchronize: false,
  logging: true,
};
EOF

# Create src/entities/sales-record.entity.ts
cat << 'EOF' > src/entities/sales-record.entity.ts
import { Entity, Column, PrimaryGeneratedColumn, ManyToOne, JoinColumn, Index, CreateDateColumn, UpdateDateColumn } from 'typeorm';
import { County } from './county.entity';

@Entity('sales_records')
@Index('idx_parcel_id', ['parcel_id'])
@Index('idx_record_hash', ['record_hash'])
@Index('idx_sales_county_date', ['county', 'sale_date'])
export class SalesRecord {
  @PrimaryGeneratedColumn()
  record_id: number;

  @ManyToOne(() => County, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'county_id' })
  county: County;

  @Column({ type: 'date' })
  sale_date: Date;

  @Column({ type: 'decimal', precision: 15, scale: 2, nullable: true })
  sale_price: number;

  @Column({ type: 'varchar', length: 255, nullable: true })
  property_address: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  city: string;

  @Column({ type: 'varchar', length: 10, nullable: true })
  zip_code: string;

  @Column({ type: 'varchar', length: 50 })
  parcel_id: string;

  @Column({ type: 'varchar', length: 64 })
  record_hash: string;

  @CreateDateColumn()
  created_at: Date;

  @UpdateDateColumn()
  updated_at: Date;
}
EOF

# Create src/entities/county.entity.ts
cat << 'EOF' > src/entities/county.entity.ts
import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity('counties')
export class County {
  @PrimaryGeneratedColumn()
  county_id: number;

  @Column({ type: 'varchar', length: 100, unique: true })
  county_name: string;
}
EOF

# Create src/modules/data-sync/data-sync.module.ts
cat << 'EOF' > src/modules/data-sync/data-sync.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DataSyncService } from './data-sync.service';
import { DataSyncController } from './data-sync.controller';
import { HttpModule } from '@nestjs/axios';
import { SalesRecord } from '../../entities/sales-record.entity';
import { County } from '../../entities/county.entity';

@Module({
  imports: [TypeOrmModule.forFeature([SalesRecord, County]), HttpModule],
  providers: [DataSyncService],
  controllers: [DataSyncController],
  exports: [DataSyncService], 
})
export class DataSyncModule {}
EOF

# Create src/modules/data-sync/data-sync.service.ts
cat << 'EOF' > src/modules/data-sync/data-sync.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as fs from 'fs';
import * as path from 'path';
import * as unzipper from 'unzipper';
import * as csvParser from 'csv-parser';
import * as crypto from 'crypto';
import { SalesRecord } from '../../entities/sales-record.entity';
import { County } from '../../entities/county.entity';
import { firstValueFrom } from 'rxjs';

@Injectable()
export class DataSyncService {
  private readonly logger = new Logger(DataSyncService.name);
  private readonly downloadUrl = 'http://swcf.orpts.nv.gov/download/0122 CUR.ZIP';
  private readonly tempDir = path.join(__dirname, '../../../temp');

  constructor(
    private httpService: HttpService,
    @InjectRepository(SalesRecord)
    private salesRepository: Repository<SalesRecord>,
    @InjectRepository(County)
    private countyRepository: Repository<County>,
  ) {}

  async syncData(): Promise<void> {
    try {
      await this.downloadAndUnzip();
      const csvData = await this.parseCsv();
      await this.syncWithDatabase(csvData);
      this.logger.log('Data sync completed successfully');
    } catch (error) {
      this.logger.error('Data sync failed', error.stack);
      throw error;
    }
  }

  private async downloadAndUnzip(): Promise<void> {
    if (!fs.existsSync(this.tempDir)) {
      fs.mkdirSync(this.tempDir, { recursive: true });
    }
    const zipPath = path.join(this.tempDir, 'data.zip');
    const response = await firstValueFrom(this.httpService.get(this.downloadUrl, { responseType: 'arraybuffer' }));
    fs.writeFileSync(zipPath, response.data);
    await fs.createReadStream(zipPath)
      .pipe(unzipper.Extract({ path: this.tempDir }))
      .promise();
  }

  private async parseCsv(): Promise<SalesRecord[]> {
    const results: SalesRecord[] = [];
    const csvFile = fs.readdirSync(this.tempDir).find(file => file.endsWith('.csv'));
    if (!csvFile) throw new Error('No CSV file found in ZIP');

    return new Promise((resolve, reject) => {
      fs.createReadStream(path.join(this.tempDir, csvFile))
        .pipe(csvParser())
        .on('data', async (data) => {
          let county = await this.countyRepository.findOne({ where: { county_name: data.county } });
          if (!county) {
            county = this.countyRepository.create({ county_name: data.county });
            await this.countyRepository.save(county);
          }
          const record: SalesRecord = {
            county,
            sale_date: new Date(data.sale_date),
            sale_price: parseFloat(data.sale_price),
            property_address: data.property_address,
            city: data.city,
            zip_code: data.zip_code,
            parcel_id: data.parcel_id,
            record_hash: this.calculateHash(data),
            record_id: 0,
            created_at: new Date(),
            updated_at: new Date(),
          };
          results.push(record);
        })
        .on('end', () => resolve(results))
        .on('error', (error) => reject(error));
    });
  }

  private calculateHash(data: any): string {
    return crypto
      .createHash('sha256')
      .update(JSON.stringify(data))
      .digest('hex');
  }

  private async syncWithDatabase(records: SalesRecord[]): Promise<void> {
    const existingRecords = await this.salesRepository.find({ select: ['record_hash', 'parcel_id'] });
    const existingHashes = new Set(existingRecords.map(r => r.record_hash));
    const existingParcelIds = new Set(existingRecords.map(r => r.parcel_id));

    const toInsert: SalesRecord[] = [];
    const toUpdate: SalesRecord[] = [];

    for (const record of records) {
      if (!existingParcelIds.has(record.parcel_id)) {
        toInsert.push(record);
      } else if (!existingHashes.has(record.record_hash)) {
        toUpdate.push(record);
      }
    }

    const toDelete = existingRecords
      .filter(r => !records.some(newRecord => newRecord.parcel_id === r.parcel_id))
      .map(r => r.parcel_id);

    await this.salesRepository.manager.transaction(async (transactionalEntityManager) => {
      if (toInsert.length) {
        await transactionalEntityManager
          .createQueryBuilder()
          .insert()
          .into(SalesRecord)
          .values(toInsert)
          .execute();
      }
      if (toUpdate.length) {
        for (const record of toUpdate) {
          await transactionalEntityManager
            .createQueryBuilder()
            .update(SalesRecord)
            .set({
              county: record.county,
              sale_date: record.sale_date,
              sale_price: record.sale_price,
              property_address: record.property_address,
              city: record.city,
              zip_code: record.zip_code,
              record_hash: record.record_hash,
              updated_at: new Date(),
            })
            .where('parcel_id = :parcel_id', { parcel_id: record.parcel_id })
            .execute();
        }
      }
      if (toDelete.length) {
        await transactionalEntityManager
          .createQueryBuilder()
          .delete()
          .from(SalesRecord)
          .where('parcel_id IN (:...parcel_ids)', { parcel_ids: toDelete })
          .execute();
      }
    });
  }
}
EOF

# Create src/modules/data-sync/data-sync.controller.ts
cat << 'EOF' > src/modules/data-sync/data-sync.controller.ts
import { Controller, Post } from '@nestjs/common';
import { DataSyncService } from './data-sync.service';

@Controller('data-sync')
export class DataSyncController {
  constructor(private readonly dataSyncService: DataSyncService) {}

  @Post('sync')
  async triggerSync() {
    await this.dataSyncService.syncData();
    return { message: 'Data sync triggered successfully' };
  }
}
EOF

# Create src/modules/cron/cron.module.ts
cat << 'EOF' > src/modules/cron/cron.module.ts
import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { DataSyncModule } from '../data-sync/data-sync.module';
import { CronService } from './cron.service';

@Module({
  imports: [ScheduleModule.forRoot(), DataSyncModule],
  providers: [CronService],
})
export class CronModule {}
EOF

# Create src/modules/cron/cron.service.ts
cat << 'EOF' > src/modules/cron/cron.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DataSyncService } from '../data-sync/data-sync.service';

@Injectable()
export class CronService {
  private readonly logger = new Logger(CronService.name);

  constructor(private readonly dataSyncService: DataSyncService) {}

  @Cron(CronExpression.EVERY_WEEK)
  async handleCron() {
    this.logger.debug('Running weekly data sync');
    try {
      await this.dataSyncService.syncData();
      this.logger.log('Weekly data sync completed');
    } catch (error) {
      this.logger.error('Weekly data sync failed', error.stack);
    }
  }
}
EOF

# Create src/app.module.ts
cat << 'EOF' > src/app.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DataSyncModule } from './modules/data-sync/data-sync.module';
import { CronModule } from './modules/cron/cron.module';
import { databaseConfig } from './config/database';

@Module({
  imports: [
    TypeOrmModule.forRoot(databaseConfig),
    DataSyncModule,
    CronModule,
  ],
})
export class AppModule {}
EOF

# Create src/main.ts
cat << 'EOF' > src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { Logger } from '@nestjs/common';

async function bootstrap() {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create(AppModule);
  await app.listen(3000);
  logger.log('Application is running on port 3000');
}
bootstrap();
EOF

# Create package.json
cat << 'EOF' > package.json
{
  "name": "real-estate-sync",
  "version": "1.0.0",
  "description": "Data sync pipeline for NY county sales data",
  "main": "dist/main.js",
  "scripts": {
    "start": "nest start",
    "build": "nest build"
  },
  "dependencies": {
    "@nestjs/axios": "^3.0.0",
    "@nestjs/common": "^10.0.0",
    "@nestjs/core": "^10.0.0",
    "@nestjs/platform-express": "^10.0.0",
    "@nestjs/schedule": "^4.0.0",
    "@nestjs/typeorm": "^10.0.0",
    "axios": "^1.6.0",
    "csv-parser": "^3.0.0",
    "dotenv": "^16.5.0",
    "pg": "^8.11.0",
    "typeorm": "^0.3.17",
    "unzipper": "^0.10.11"
  },
  "devDependencies": {
    "@nestjs/cli": "^10.0.0",
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

# Create tsconfig.json
cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "module": "commonjs",
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "es2017",
    "sourceMap": true,
    "outDir": "./dist",
    "baseUrl": "./",
    "incremental": true
  }
}
EOF

# Create cron-job.sh
cat << 'EOF' > cron-job.sh
#!/bin/bash
LOG_FILE=/var/log/real-estate-sync.log
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
cd /path/to/real-estate-sync
echo "[$TIMESTAMP] Starting data sync" >> $LOG_FILE
npm run start >> $LOG_FILE 2>&1
echo "[$TIMESTAMP] Data sync completed" >> $LOG_FILE
EOF

# Make cron-job.sh executable
chmod +x cron-job.sh

# Create README.md
cat << 'EOF' > README.md
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
EOF

# Create Dockerfile
cat << 'EOF' > Dockerfile
FROM node:18

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN npm run build

EXPOSE 3000

CMD ["npm", "run", "start"]
EOF

# Create .env
cat << 'EOF' > .env
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=postgres
DB_NAME=real_estate_db
EOF