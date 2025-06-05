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
