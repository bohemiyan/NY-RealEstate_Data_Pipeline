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
