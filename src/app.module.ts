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
