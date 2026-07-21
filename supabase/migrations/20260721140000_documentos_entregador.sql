-- Upload de documentos do entregador (Foto de Perfil, CNH, CRLV, Comprovante
-- de Residência). Nenhuma dessas colunas/bucket existia antes — o painel já
-- tinha UI esperando esses campos (com fallback em vários nomes possíveis),
-- mas o schema real nunca foi criado; o upload de foto de perfil que já
-- existia no app era um no-op silencioso porque o bucket que ele usava
-- (fotos-cadastro) nunca chegou a existir.
--
-- Bucket privado (não público como cardapio-fotos): só o próprio entregador
-- (via auth.uid() == primeira pasta do path) pode ler/gravar os próprios
-- documentos. Visualização no painel é feita via Edge Function
-- get-documento-signed-url (service_role + segredo compartilhado), não por
-- leitura direta do bucket.

alter table public.entregadores
  add column if not exists foto_perfil text,
  add column if not exists foto_cnh text,
  add column if not exists foto_crlv text,
  add column if not exists foto_comprovante_residencia text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos-entregador', 'documentos-entregador', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "entregador_insert_proprios_documentos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'documentos-entregador'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "entregador_update_proprios_documentos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'documentos-entregador'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "entregador_select_proprios_documentos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'documentos-entregador'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
