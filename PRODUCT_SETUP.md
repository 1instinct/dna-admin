# Product Import Setup

## For Aaron (or any developer):

### 1. AWS Setup - Use Shared Bucket
- Update `.env.development` with shared bucket:
  ```
  AWS_ACCESS_KEY_ID=your-real-key
  AWS_SECRET_ACCESS_KEY=your-real-secret
  AWS_BUCKET_NAME=dna-admin-dev-jon-12345
  ```

### 2. Import Products
```shell
# Clear existing products (optional)
docker-compose exec web rails products:cleanup

# Import products with images
docker-compose exec web bash -c "export AWS_BUCKET_NAME=dna-admin-dev-jon-12345 && rails products:import CSV_FILE=/dna/db/seed_data/products.csv IMAGES_PATH=/dna/db/seed_data/images"
```

### 3. Files Included
- `db/seed_data/products.csv` - Product data
- `lib/tasks/product_import.rake` - Import script
- `lib/tasks/product_cleanup.rake` - Cleanup script

### 4. Notes
- Images are already uploaded to `dna-admin-dev-jon-12345`
- No need to upload images again
- Everyone shares the same S3 bucket and images