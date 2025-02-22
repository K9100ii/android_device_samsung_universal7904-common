#!/bin/bash
#
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d ${MY_DIR} ]]; then MY_DIR="${PWD}"; fi

LINEAGE_ROOT="${MY_DIR}"/../../..

HELPER="${LINEAGE_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
	echo "Unable to find helper script at ${HELPER}"
	exit 1
fi
source "${HELPER}"

function blob_fixup {
	case "$1" in
	vendor/lib*/libhifills.so)
		grep -q libunwindstack.so "$2" || "$PATCHELF" --add-needed "libunwindstack.so" "$2"
		;;
	vendor/lib*/hw/camera.exynos7904.so)
		"$PATCHELF" --replace-needed "libcamera_client.so" "libcamera_metadata_helper.so" "$2"
		;;
	vendor/lib*/libexynoscamera.so | vendor/lib*/libexynoscamera3.so)
		"$PATCHELF" --remove-needed "libcamera_client.so" "$2"
		"$PATCHELF" --remove-needed "libgui.so" "$2"
		;;
	vendor/lib*/libsensorlistener.so)
		grep -q libshim_sensorndkbridge.so "$2" || "$PATCHELF" --add-needed "libshim_sensorndkbridge.so" "$2"
		;;
	vendor/bin/hw/rild | vendor/lib*/libsec-ril*.so)
		"$PATCHELF" --replace-needed libril.so libril-samsung.so "$2"

		# Pass an empty value to SecRil::RequestComplete in OnGetSmscAddressDone
		xxd -p -c0 "${2}" | sed "s/600e40f9820c805224008052e10315aae30314aa/600e40f9820c805224008052e10315aa030080d2/g" | xxd -r -p > "${2}".patched
		mv "${2}".patched "${2}"
		;;
        vendor/lib/libaudio_soundtrigger.so | vendor/lib/soundfx/libaudioeffectoffload.so | vendor/lib64/soundfx/libaudioeffectoffload.so)
		"$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.universal7904.so "$2"
		;;
	vendor/lib/hw/audio.primary.exynos7904.so)
		"$PATCHELF" --replace-needed libaudioroute.so libaudioroute.universal7904.so "$2"
		"$PATCHELF" --replace-needed libtinyalsa.so libtinyalsa.universal7904.so "$2"
		grep -q libshim_audioparams.so "$2" || "$PATCHELF" --add-needed libshim_audioparams.so "$2"
		sed -i 's/str_parms_get_str/str_parms_get_mod/g' "$2"
		;;
	vendor/lib/libwvhidl.so)
		"$PATCHELF" --replace-needed "libprotobuf-cpp-lite-3.9.1.so" "libprotobuf-cpp-full-3.9.1.so" "$2"
		;;
	esac
}

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_TARGET=
SECTION=
KANG=

while [ "${#}" -gt 0 ]; do
	case "${1}" in
	--only-common)
		ONLY_COMMON=true
		;;
	--only-target)
		ONLY_TARGET=true
		;;
	-n | --no-cleanup)
		CLEAN_VENDOR=false
		;;
	-k | --kang)
		KANG="--kang"
		;;
	-s | --section)
		SECTION="${2}"
		shift
		CLEAN_VENDOR=false
		;;
	*)
		SRC="${1}"
		;;
	esac
	shift
done

if [ -z "${SRC}" ]; then
	SRC="adb"
fi

# Initialize the helper for common device
if [ -z "${ONLY_TARGET}" ]; then
	# Initialize the helper for common device
	setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${LINEAGE_ROOT}" true "${CLEAN_VENDOR}"

	extract "${MY_DIR}/proprietary-files.txt" "${SRC}" \
		"${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
	# Reinitialize the helper for device
	source "${MY_DIR}/../${DEVICE}/extract-files.sh"
	setup_vendor "${DEVICE}" "${VENDOR}" "${LINEAGE_ROOT}" false "${CLEAN_VENDOR}"

	extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" \
		"${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/setup-makefiles.sh"
