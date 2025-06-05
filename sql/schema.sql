CREATE TABLE IF NOT EXISTS counties (
    county_id SERIAL PRIMARY KEY,
    county_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS sales_records (
    record_id SERIAL PRIMARY KEY,
    county_id INT NOT NULL REFERENCES counties(county_id) ON DELETE CASCADE,
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

CREATE INDEX idx_parcel_id ON sales_records (parcel_id);
CREATE INDEX idx_record_hash ON sales_records (record_hash);
CREATE INDEX idx_sales_county_date ON sales_records (county_id, sale_date);