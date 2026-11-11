#!/usr/bin/env bash
#
# Empaqueta el ERP en un archivo tar.gz listo para transportar.
# La base de datos NO se incluye: se crea y siembra automáticamente al iniciar.

set -euo pipefail

BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${ERP_BUNDLE_OUTPUT:-${BUNDLE_ROOT}/erp-licores-standalone.tar.gz}"
NAME="erp-licores"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p "${STAGE}/${NAME}/shared/data"
mkdir -p "${STAGE}/${NAME}/shared/utils"
mkdir -p "${STAGE}/${NAME}/model"
mkdir -p "${STAGE}/${NAME}/api"
mkdir -p "${STAGE}/${NAME}/frontend/assets"
mkdir -p "${STAGE}/${NAME}/frontend/views"
mkdir -p "${STAGE}/${NAME}/frontend/cli"
mkdir -p "${STAGE}/${NAME}/tools"

cp "${BUNDLE_ROOT}/config.sh" \
   "${BUNDLE_ROOT}/erp.sh" \
   "${BUNDLE_ROOT}/server.sh" \
   "${BUNDLE_ROOT}/router.sh" \
   "${BUNDLE_ROOT}/ejercicio-4.sh" \
   "${STAGE}/${NAME}/"

cp "${BUNDLE_ROOT}/model/"*.sh "${STAGE}/${NAME}/model/"
cp "${BUNDLE_ROOT}/api/"*.sh "${STAGE}/${NAME}/api/"
cp "${BUNDLE_ROOT}/frontend/router.sh" "${STAGE}/${NAME}/frontend/"
cp "${BUNDLE_ROOT}/frontend/assets/"* "${STAGE}/${NAME}/frontend/assets/"
cp "${BUNDLE_ROOT}/frontend/views/"*.sh "${STAGE}/${NAME}/frontend/views/"
cp "${BUNDLE_ROOT}/frontend/cli/"*.sh "${STAGE}/${NAME}/frontend/cli/"
cp "${BUNDLE_ROOT}/tools/sqlite3_shim.py" "${STAGE}/${NAME}/tools/"

cp "${BUNDLE_ROOT}/shared/utils/json.sh" \
   "${BUNDLE_ROOT}/shared/utils/http.sh" \
   "${BUNDLE_ROOT}/shared/utils/helpers.sh" \
   "${BUNDLE_ROOT}/shared/utils/validations.sh" \
   "${STAGE}/${NAME}/shared/utils/"

chmod +x "${STAGE}/${NAME}/erp.sh" \
         "${STAGE}/${NAME}/server.sh" \
         "${STAGE}/${NAME}/router.sh" \
         "${STAGE}/${NAME}/frontend/router.sh" \
         "${STAGE}/${NAME}/frontend/cli/menu.sh" \
         "${STAGE}/${NAME}/tools/sqlite3_shim.py" \
         "${STAGE}/${NAME}/ejercicio-4.sh"

rm -f "${OUTPUT}"
tar -czf "${OUTPUT}" -C "${STAGE}" "${NAME}"

printf 'Paquete generado: %s\n' "${OUTPUT}"
printf 'Para ejecutarlo:\n'
printf '  tar -xzf %s\n' "$(basename "${OUTPUT}")"
printf '  cd %s && ./erp.sh\n' "${NAME}"
