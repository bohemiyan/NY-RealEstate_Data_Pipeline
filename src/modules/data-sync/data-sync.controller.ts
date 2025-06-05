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
