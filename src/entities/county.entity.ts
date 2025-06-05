import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity('counties')
export class County {
  @PrimaryGeneratedColumn()
  county_id: number;

  @Column({ type: 'varchar', length: 100, unique: true })
  county_name: string;
}
