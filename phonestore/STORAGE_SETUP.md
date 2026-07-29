# Supabase Storage setup

Create **one public bucket** called `shop-images`, organized by folder — simpler to manage than
four separate buckets, and folder policies give you the same control.

## 1. Create the bucket
Dashboard → Storage → New bucket
- Name: `shop-images`
- Public bucket: **ON** (so the app can display images with a plain URL, no signed URLs needed)

## 2. Folder structure (convention, enforced by your app's upload paths)
```
shop-images/
  categories/{category_id}.jpg
  product-types/{type_id}.jpg
  marques/{marque_id}.jpg
  products/{product_id}.jpg
```

## 3. Storage policies (SQL editor)
```sql
-- anyone authenticated can read
create policy "public read shop-images"
on storage.objects for select
using (bucket_id = 'shop-images');

-- only admins can upload/update/delete
create policy "admin write shop-images"
on storage.objects for insert
with check (
  bucket_id = 'shop-images'
  and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

create policy "admin update shop-images"
on storage.objects for update
using (
  bucket_id = 'shop-images'
  and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

create policy "admin delete shop-images"
on storage.objects for delete
using (
  bucket_id = 'shop-images'
  and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);
```

## 4. Getting a public URL in Flutter
```dart
final url = supabase.storage.from('shop-images').getPublicUrl('products/12.jpg');
```

## 5. Uploading in Flutter (used by SupabaseService.uploadImage)
```dart
await supabase.storage.from('shop-images').upload(
  'products/12.jpg',
  file,
  fileOptions: const FileOptions(upsert: true),
);
```

Store the resulting public URL string directly in the relevant table's `image_url` column —
that's what the app reads to render `Image.network(...)`.
