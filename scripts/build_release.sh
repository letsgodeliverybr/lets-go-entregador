#!/usr/bin/env bash
# Gera o AAB de release com as credenciais do Supabase injetadas via
# --dart-define-from-file. Existe pra nunca mais esquecer essa flag na mão
# (causa raiz do build 47 quebrado: rodar `flutter build appbundle --release`
# sozinho gera um app com SUPABASE_URL/SUPABASE_ANON_KEY vazios — o app
# compila normal, só quebra em runtime na tela de login).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFINE_FILE=".dart_define.json"

if [ ! -f "$DEFINE_FILE" ]; then
  echo "❌ $DEFINE_FILE não existe. Copia de .dart_define.json.example e preenche com os valores reais do Supabase antes de gerar o build." >&2
  exit 1
fi

# Confere que as duas chaves obrigatórias existem e não estão vazias —
# pega tanto "arquivo esquecido" quanto "arquivo presente mas com valor em
# branco", que teria o mesmo sintoma silencioso do bug original.
for key in SUPABASE_URL SUPABASE_ANON_KEY; do
  val=$(python3 -c "import json,sys; print(json.load(open('$DEFINE_FILE')).get('$key',''))")
  if [ -z "$val" ]; then
    echo "❌ $DEFINE_FILE existe mas a chave '$key' está vazia ou ausente." >&2
    exit 1
  fi
done

echo "✅ $DEFINE_FILE ok (SUPABASE_URL e SUPABASE_ANON_KEY presentes). Gerando AAB..."
flutter build appbundle --release --dart-define-from-file="$DEFINE_FILE"

AAB="build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "✅ Build concluído: $AAB"
echo "   Versão: $(grep '^version:' pubspec.yaml)"
