#!/bin/bash
set -euo pipefail

if [[ "${1:-}" != "--print-node" || "$#" -ne 1 ]]; then
  printf 'Uso: bash scripts/bootstrap-node-macos.sh --print-node\n' >&2
  exit 2
fi

fail() {
  printf 'Erro ao preparar Node.js: %s\n' "$1" >&2
  exit 1
}

compatible_node() {
  local candidate="$1" version major minor
  version="$("$candidate" --version 2>/dev/null)" || return 1
  [[ "$version" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  (( major > 22 || (major == 22 && minor >= 3) ))
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
package_dir="$(cd "$script_dir/.." && pwd -P)"
runtime_base="$package_dir/.cerebro/runtime/bootstrap-node"

for guarded_dir in \
  "$package_dir/.cerebro" \
  "$package_dir/.cerebro/runtime" \
  "$runtime_base"; do
  [[ ! -L "$guarded_dir" ]] \
    || fail "a pasta $guarded_dir é um link simbólico; não vou acessar dados fora do pacote."
done

[[ "$(uname -s)" == "Darwin" ]] || fail 'este atalho é para macOS. No Windows, use ABRIR-COCKPIT.cmd.'

case "$(uname -m)" in
  arm64) arch='arm64'; expected_sha='ef28d8fab2c0e4314522d4bb1b7173270aa3937e93b92cb7de79c112ac1fa953' ;;
  x86_64) arch='x64'; expected_sha='b8da981b8a0b1241b70249204916da76c63573ddf5814dbd2d1e41069105cb81' ;;
  *) fail "arquitetura de Mac não suportada: $(uname -m)." ;;
esac

version='22.23.1'
release="node-v${version}-darwin-${arch}"
runtime_dir="$runtime_base/$release"
runtime_node="$runtime_dir/bin/node"

[[ ! -L "$runtime_dir" ]] \
  || fail "a pasta $runtime_dir é um link simbólico; não vou executar Node.js fora do pacote."

if command -v node >/dev/null 2>&1; then
  system_node="$(command -v node)"
  if compatible_node "$system_node"; then
    printf 'Usando Node.js compatível já instalado: %s\n' "$system_node" >&2
    printf '%s\n' "$system_node"
    exit 0
  fi
fi

valid_local_runtime() {
  local folder="$1" node_path="$1/bin/node" npm_path="$1/bin/npm"
  [[ -d "$folder" && ! -L "$folder" && -d "$folder/bin" && ! -L "$folder/bin" \
     && -d "$folder/lib" && ! -L "$folder/lib" \
     && -d "$folder/lib/node_modules" && ! -L "$folder/lib/node_modules" \
     && -d "$folder/lib/node_modules/npm" && ! -L "$folder/lib/node_modules/npm" \
     && -d "$folder/lib/node_modules/npm/bin" && ! -L "$folder/lib/node_modules/npm/bin" \
     && -f "$node_path" && ! -L "$node_path" && -x "$node_path" \
     && "$("$node_path" --version 2>/dev/null)" == "v$version" \
     && -L "$npm_path" && "$(readlink "$npm_path")" == '../lib/node_modules/npm/bin/npm-cli.js' \
     && -x "$npm_path" \
     && -f "$folder/lib/node_modules/npm/bin/npm-cli.js" \
     && ! -L "$folder/lib/node_modules/npm/bin/npm-cli.js" \
     && -f "$folder/lib/node_modules/npm/package.json" ]]
}

if [[ -e "$runtime_dir" ]]; then
  valid_local_runtime "$runtime_dir" \
    || fail "a instalação local em $runtime_dir está incompleta; não vou sobrescrevê-la."
  printf 'Usando Node.js e npm locais compatíveis.\n' >&2
  printf '%s\n' "$runtime_node"
  exit 0
fi

command -v curl >/dev/null 2>&1 || fail 'curl não está disponível neste Mac.'
command -v shasum >/dev/null 2>&1 || fail 'shasum não está disponível neste Mac.'
command -v tar >/dev/null 2>&1 || fail 'tar não está disponível neste Mac.'
for guarded_dir in \
  "$package_dir/.cerebro" \
  "$package_dir/.cerebro/runtime" \
  "$runtime_base"; do
  [[ ! -L "$guarded_dir" ]] \
    || fail "a pasta $guarded_dir virou um link simbólico; não vou acessar dados fora do pacote."
  if [[ ! -d "$guarded_dir" ]]; then
    [[ ! -e "$guarded_dir" ]] \
      || fail "$guarded_dir existe, mas não é uma pasta."
    mkdir "$guarded_dir" || fail "não consegui criar $guarded_dir."
  fi
  [[ ! -L "$guarded_dir" && -d "$guarded_dir" ]] \
    || fail "$guarded_dir não é uma pasta local segura."
done

lock_dir="$runtime_base/.install-${arch}.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  fail 'outra preparação pode estar em andamento. Aguarde e tente novamente.'
fi

temporary_dir=''
cleanup() {
  if [[ -n "$temporary_dir" && -d "$temporary_dir" ]]; then
    rm -rf -- "$temporary_dir"
  fi
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT

temporary_dir="$(mktemp -d "$runtime_base/.download.XXXXXXXX")" \
  || fail 'não consegui criar a pasta temporária de download.'
archive="$temporary_dir/$release.tar.gz"
url="https://nodejs.org/dist/v${version}/$release.tar.gz"

printf 'Baixando Node.js %s oficial para este Mac (uma vez só)...\n' "$version" >&2
curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 180 \
  --output "$archive" "$url" \
  || fail 'o download falhou. Verifique sua conexão com a internet e tente novamente.'

sha_output="$(shasum -a 256 "$archive")" || fail 'não consegui verificar o download.'
actual_sha="${sha_output%% *}"
[[ "$actual_sha" == "$expected_sha" ]] \
  || fail 'o arquivo baixado não passou na verificação SHA-256; nada será instalado.'

tar -xzf "$archive" -C "$temporary_dir" \
  || fail 'o arquivo verificado não pôde ser extraído.'
valid_local_runtime "$temporary_dir/$release" \
  || fail 'o pacote extraído não contém Node.js e npm esperados.'

[[ ! -e "$runtime_dir" && ! -L "$runtime_dir" ]] \
  || fail "a pasta $runtime_dir apareceu durante a instalação; não vou sobrescrevê-la."
mv "$temporary_dir/$release" "$runtime_dir" \
  || fail 'não consegui concluir a instalação local.'

printf 'Node.js instalado localmente no Cérebro e verificado.\n' >&2
printf '%s\n' "$runtime_node"
