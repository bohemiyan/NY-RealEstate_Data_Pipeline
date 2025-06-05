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
