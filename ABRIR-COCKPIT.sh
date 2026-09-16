#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
export CEREBRO_TELEMETRY=off

case "$(uname -s)" in
  Darwin) bootstrap_script='scripts/bootstrap-node-macos.sh' ;;
  Linux) bootstrap_script='scripts/bootstrap-node-linux.sh' ;;
  *)
    printf '\nSistema não suportado por este atalho: %s. No Windows, use ABRIR-COCKPIT.cmd.\n' "$(uname -s)" >&2
    printf 'Pressione Enter para fechar... ' >&2
    read -r _ || true
    exit 1
    ;;
esac

if ! node_bin="$(bash "$bootstrap_script" --print-node)"; then
  printf '\nNão foi possível preparar o Node.js. Veja o erro acima e tente novamente.\n' >&2
  printf 'Pressione Enter para fechar... ' >&2
  read -r _ || true
  exit 1
fi

export PATH="$(dirname "$node_bin"):$PATH"
exec "$node_bin" scripts/cockpit.mjs "$@"
