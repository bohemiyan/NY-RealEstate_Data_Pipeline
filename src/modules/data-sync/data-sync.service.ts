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
private readonly now = new Date();
private readonly month = String(this.now.getMonth() + 1).padStart(2, '0');
private readonly year = String(this.now.getFullYear()).slice(-2);
private readonly downloadUrl = process.env.Governance_URL ? `${process.env.Governance_URL}/${this.month}${this.year}_CUR.ZIP` : 'http://swcf.orpts.nv.gov/download/0122_CUR.ZIP';
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
