import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { DataSyncModule } from '../data-sync/data-sync.module';
import { CronService } from './cron.service';

@Module({
  imports: [ScheduleModule.forRoot(), DataSyncModule],
  providers: [CronService],
})
export class CronModule {}
