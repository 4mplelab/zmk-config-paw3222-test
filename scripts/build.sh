#!/usr/bin/env bash
set -euo pipefail

# ========= 共通環境 初期化 =========
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEST_WS="${ROOT_DIR}/_west"
CONFIG_DIR="${ROOT_DIR}"
OUTPUT_DIR="${ROOT_DIR}/firmware_builds"

command -v west >/dev/null 2>&1 || { echo "west not found"; exit 1; }
command -v yq   >/dev/null 2>&1 || { echo "yq not found"; exit 1; }

# ワークスペース確認
if [ ! -d "${WEST_WS}/.west" ]; then
  echo "West workspace not initialized at ${WEST_WS}. Run 'make setup-west'."
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

export ROOT_DIR WEST_WS CONFIG_DIR OUTPUT_DIR

# ========= ヘルパー関数 =========

# uf2 優先で firmware_builds/ へコピー（なければ bin）
copy_artifacts() {
  local build_dir="${1:?build_dir required}"
  local name="${2:?artifact name required}"
  local uf2="${build_dir}/zephyr/zmk.uf2"
  local bin="${build_dir}/zephyr/zmk.bin"

  if [ -f "${uf2}" ]; then
    cp "${uf2}" "${OUTPUT_DIR}/${name}.uf2"
    echo "✅ ${OUTPUT_DIR}/${name}.uf2"
  elif [ -f "${bin}" ]; then
    cp "${bin}" "${OUTPUT_DIR}/${name}.bin"
    echo "✅ ${OUTPUT_DIR}/${name}.bin"
  else
    echo "❌ No firmware found for ${name}"
    return 1
  fi
}

# ========= ビルド処理（先頭のみ） =========

BUILD_MATRIX_PATH="${ROOT_DIR}/build.yaml"
COUNT="$(yq -r '.include | length' "${BUILD_MATRIX_PATH}")"
[ "${COUNT}" -gt 0 ] || { echo "No builds defined in ${BUILD_MATRIX_PATH}"; exit 1; }

i=0
echo "Building the first preset (1/${COUNT}) from build.yaml..."

BOARD="$(yq -r ".include[${i}].board" "${BUILD_MATRIX_PATH}")"
SHIELDS_LINE_RAW="$(yq -r ".include[${i}].shield // \"\"" "${BUILD_MATRIX_PATH}")"
ARTIFACT_NAME_CFG="$(yq -r ".include[${i}].[\"artifact-name\"] // \"\"" "${BUILD_MATRIX_PATH}")"
SNIPPET="$(yq -r ".include[${i}].snippet // \"\"" "${BUILD_MATRIX_PATH}")"

[ -n "${BOARD}" ] || { echo "Entry ${i}: 'board' is required"; exit 1; }

BUILD_DIR="$(mktemp -d)"

# west の追加引数
EXTRA_WEST_ARGS=()
[ -n "${SNIPPET}" ] && EXTRA_WEST_ARGS+=( -S "${SNIPPET}" )

# CMake 引数（配列で保持）
CM_ARGS=()
CM_ARGS+=( -DZMK_CONFIG="${CONFIG_DIR}" )

# SHIELD を正規化して重複除去、-D SHIELD=... を追加
SHIELDS_LINE="$(echo "${SHIELDS_LINE_RAW}" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
if [ -n "${SHIELDS_LINE}" ]; then
  declare -A _seen=()
  # shellcheck disable=SC2206
  read -r -a _items <<<"${SHIELDS_LINE}"
  uniq_items=()
  for it in "${_items[@]}"; do
    [ -z "${it}" ] && continue
    if [ -z "${_seen[${it}]+x}" ]; then
      uniq_items+=( "${it}" )
      _seen["${it}"]=1
    fi
  done
  SHIELD_VALUE="$(IFS=' ' ; echo "${uniq_items[*]}")"
  CM_ARGS+=( -D "SHIELD=${SHIELD_VALUE}" )
fi

# 追加 cmake-args
CMAKE_ARGS_CFG_RAW="$(yq -r ".include[${i}].[\"cmake-args\"] // \"\"" "${BUILD_MATRIX_PATH}")"
if [ -n "${CMAKE_ARGS_CFG_RAW}" ]; then
  # shellcheck disable=SC2206
  read -r -a cmargs <<<"${CMAKE_ARGS_CFG_RAW}"
  CM_ARGS+=( "${cmargs[@]}" )
fi

# west build を配列のまま直接実行
cmd=( west build -s zmk/app -d "${BUILD_DIR}" -b "${BOARD}" )
cmd+=( "${EXTRA_WEST_ARGS[@]}" )
cmd+=( -- )
cmd+=( "${CM_ARGS[@]}" )

(
  cd "${WEST_WS}"
  set -x
  "${cmd[@]}"
  set +x
)

# アーティファクト名
ARTIFACT_NAME="${ARTIFACT_NAME_CFG}"
if [ -z "${ARTIFACT_NAME}" ] && [ -n "${SHIELDS_LINE}" ]; then
  ARTIFACT_NAME="$(echo "${SHIELDS_LINE}" | tr ' ' '-' )-${BOARD}-zmk"
elif [ -z "${ARTIFACT_NAME}" ]; then
  ARTIFACT_NAME="${BOARD}-zmk"
fi

copy_artifacts "${BUILD_DIR}" "${ARTIFACT_NAME}"

echo "Build completed. Artifact is in: ${OUTPUT_DIR}"
