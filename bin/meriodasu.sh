#!/bin/bash

# meriodasu - Automatized datamining for Nanatsu No Taizai: Grand Cross (JP)
#
# STAGESQL
#   Dump main SQLite database in the APK and exhaustively compare it with
#   a previous stage's one. As we search by the ID, we are far more accurate
#   in getting relevant diffs, at the expense of time. For stages 2030 and up,
#   decrypting the database with erizabeth.sh is nesecarry first.
# STAGE1
#   Check AssetBundles for double-header corruption (fix if present),
#   balance bundles into multiple folders, so AssetStudio doesn't eat 24GB
#   of RAM and potentially crash because Wine Mono can't handle an assert.
#   If required, only prepare new bundles comapred to a previous stage,
#   instead of the whole distro.
# STAGES
#   Extract stage with AssetStudio. This step cannot be fully automatized,
#   becuase AS doesn't have CLI support. Load a part folder and extract all
#   part folders to the same extracted stage folder. Extract AnimationClip,
#   Animator, AudioClip, Mesh, TextAsset, Texture2D, with export options set
#   to 'group by container path' and everything else default.
#   At the moment we actually only process Mesh and Texture2D asset categories.
# STAGE3
#   Compare extracted stages. We are interested in new files and potentially
#   changed existing ones. Backups are discarded. Render models, extract
#   images, create a HTML report of the new changes and push it to our git repo.
#
# Author: calmadios, 2020
# License: MIT

# Runs completely on Linux-based systems. (No Windows exchange necessary.)
# DEPENDENCIES
#   - bash (incl. awk, sed, find, basename, dirname, realpath, printf, echo, mv, cp, rm, rev, cut, mkdir)
#   - chkufs, fixufs (source included, build with running 'make chkufs' and 'make fixufs')
#   - Blender 2.83+
#   - Wine with Mono
#   - AssetStudio 0.15.23+
#   - sqlite
#   - Android Studio (with ADV emulator and SDK tools)
#   - ImageMagick (for convert)
#   - cwebp
#   - js-beautify
#   - 20GB+ for extracted and 4GB for compressed assets per release

# Settings
APP="com.netmarble.nanatsunotaizai"
MAX_FILES_PER_PART=4096 # ~10GB
AS_VER="v0.15.23"
PREV_STAGE=2072
CUR_STAGE=2083

# Paths
EXECROOT="$(realpath ~/meriodasu)"                      # binaries for this toolchain operation
ANDROID_SDK="$(realpath ~/Android/Sdk)"                 # Android SDK binaries
ABSROOT="$(realpath ~/nnt/datamine)"                    # root of all datamine operations
NNTDAT_ROOT="${ABSROOT}/nntdata"                        # root of nntdata repo
STAGE1_ROOT="${ABSROOT}/${APP}-${CUR_STAGE}/files/bm/"  # stage1 operations (gather assetbundles from here)
STAGES_ROOT="${ABSROOT}/${CUR_STAGE}-S"                 # split assets from stage1, to be used as inputs for AS
STAGEX_ROOT="${ABSROOT}/${CUR_STAGE}-X"                 # extracted assets from AS
STAGE2_ROOT="${ABSROOT}/${CUR_STAGE}-2"                 # new assets
STAGE3_ROOT="${ABSROOT}/${CUR_STAGE}-3"                 # processed new assets
REPORT_ROOT="${ABSROOT}/report-${CUR_STAGE}"            # final report

# Programs
CHKUFS="${EXECROOT}/chkufs"
FIXUFS="${EXECROOT}/fixufs"
SQLDIFF="${EXECROOT}/sqldiff.sh"
GCFBX="blender --background --python ${EXECROOT}/gcfbx.py"
ADVNNT="emulator/emulator -avd nnt"

# Regex strings
STAGE2_REGEX1=".* #[0-9]*.*"
STAGE3_REGEX1=".*(hero|weapon)(_[a-z]*)+(_(body|head))?_[0-9]{4}"
STAGE3_REGEX2=".*(hero|weapon)(_[a-z]*)+_[0-9]{4}"

# Main asset addresses
PRES="${STAGE2_ROOT}/assets/sevensins/patchresources"
P1RES="${STAGE2_ROOT}/assets/sevensins/patch1resources"
SQLRES_OLD="${ABSROOT}/${APP}-${PREV_STAGE}/files/SqliteData/LocalizeString.sqlite"
SQLRES_NEW="${ABSROOT}/${APP}-${CUR_STAGE}/files/SqliteData/LocalizeString.sqlite"

# Asset categories paths
UIIMG="$P1RES/ui/image"
CHARACTERS_ROOT="$P1RES/character/"
CHAPTER_ROOT="$UIIMG/chapter/"
STATUS_EFF_ROOT="$UIIMG/icon/buff/"
COSTUMES_ROOT="$UIIMG/icon/costume/"
WEAPONS_ROOT="$UIIMG/icon/heroweapon/"
UNIT_ICONS_ROOT="$UIIMG/icon/hero/"
SKILLS_ROOT="$UIIMG/icon/skillactive"
PASSIVES_ROOT="$UIIMG/icon/skillpassive"
STAMPS_ROOT="$UIIMG/icon/stamp"
STORYREPLAY_ROOT="$UIIMG/icon/storyreplay"
WEAPONS_MODELS_ROOT="$P1RES/weapon/prefabs/"
SKILL_INFO_ROOT="$PRES/character/"
GACHA_ROOT="$PRES/ui/image/gachabackground/gachabackground_ja/"
COSTUMESHOP_ROOT="$PRES/ui/image/eventbanner/eventbanner_ja/"
BANNERS_ROOT="$PRES/ui/image/firsteventbanner/firsteventbanner_ja/"

# Init all required directories
# TODO: Add safeguard to not wipe actual (full) dirs
dir_init() {
	mkdir -p "${STAGE1_ROOT}"
	#rm -rf   "${STAGES_ROOT}"
	mkdir -p "${STAGES_ROOT}"
	#rm -rf   "${STAGEX_ROOT}"
	mkdir -p "${STAGEX_ROOT}"
	#rm -rf   "${STAGE2_ROOT}"
	mkdir -p "${STAGE2_ROOT}"
	#rm -rf   "${STAGE3_ROOT}"
	mkdir -p "${STAGE3_ROOT}"
	#rm -rf   "${REPORT_ROOT}"
	mkdir -p "${REPORT_ROOT}/sql"
	mkdir -p "${REPORT_ROOT}/models"
}

# Assert all needed binaries are present
assert_bins() {
	echo
}

# Extract assets from emulator ;P
# FIXME: Doesn't work rn, do it manually
stageemulator() {
	echo "STAGE EMULATOR ..."
	# Launch ADV emulator on the nnt virtual device
	# (API 30 x86, Pixel 5, 1080x2200, 8GB RAM, 24GB storage)
	${ANDROID_SDK}/${ADVNNT} &

	# Get root adb and pull game files
	# The pull should be fast at 60 MB/s+, so sub-60s total
	# FIXME: Wait for device to be ready
	adb root
	adb root
	cd "${ABSROOT}"
	adb pull "/sdcard/Android/data/${APP}"
	mv -fv "${ABSROOT}/${APP}" "${ABSROOT}/${APP}-${CUR_STAGE}"

	# TODO: Terminate the emulator properly

	echo "STAGE EMULATOR COMPLETE."
}

# TODO: Filter out new asset containers and repair them.
# Fixes double UnityFS headers, so files are readable by AssetStudio
stage1() {
	FC=0; CDIDX=0
	echo "STAGE 1 ..."
	cd "${STAGE1_ROOT}"
	# TODO: Remove bashism
	find {jal,jas,jau,m} -not -type d | sort -u | while read -r CUR_FILE; do
		[ -f .${ABSROOT} ] || continue
		FC=$((FC + 1))
		if [ $FC -eq $MAX_FILES_PER_PART ]; then
			FC=0
			CDIDX=$((CDIDX + 1))
		fi
		mkdir -p "${STAGES_ROOT}/$CDIDX/$(dirname "${CUR_FILE}")"
		printf "%s" "${CUR_FILE}"
		if ! ${CHKUFS} < "${CUR_FILE}"; then
			printf "\t%s" "CORRUPT"
			${FIXUFS} < "${CUR_FILE}" > "${STAGES_ROOT}/$CDIDX/${CUR_FILE}"
			printf "\t%s\n" "FIXED"
		else
			cp "${CUR_FILE}" "${STAGES_ROOT}/$CDIDX/${CUR_FILE}"
			printf "\t%s\n" "OK"
		fi
	done
	echo "STAGE 1 COMPLETE."
}

# Extract assets from containers with AssetStudio.
# NOTE: Mandatory user interaction required.
# NOTE: This will take quite some time.
assetstudio_run() {
	echo "Extract all assets with AssetStudio ..."
	echo "'${STAGES_ROOT}/0' to '${STAGEX_ROOT}'"
	echo "'${STAGES_ROOT}/1' to '${STAGEX_ROOT}'"
	echo "'${STAGES_ROOT}/2' to '${STAGEX_ROOT}'"
	wine64 "${EXECROOT}/AssetStudio.${AS_VER}/AssetStudioGUI.exe"
	# TODO: Add option to rerun AS, in case of a crash
	read -n 1 -p "Press any key when done extracting all split folders."
}

# Search for new assets
stage2() {
	echo "STAGE 2 ..."
	cd "${STAGEX_ROOT}"
	find . -regextype grep -not -regex "${STAGE2_REGEX1}" -not -type d | sort -u > "${ABSROOT}/.${CUR_STAGE}_files"
	while IFS= read -r L; do
		L="$(printf "%s" "$L" | awk '{print substr($0, 3, length($0))}')"
		if [ ! -e "${ABSROOT}/${PREV_STAGE}-X/$L" ]; then
			mkdir -p "${STAGE2_ROOT}/$(dirname "$L")"
			cp -v "$L" "${STAGE2_ROOT}/$L"
		fi
	done < "${ABSROOT}/.${CUR_STAGE}_files"
	echo "STAGE 2 DONE."
}

# Diff previous and current SQLite DBs
# NOTE: This will take quite some time, as it is single-threaded at the moment.
diffsql() {
	echo "DUMPING AND DIFFING SQL DATABASES ..."
	sqlite3 "${SQLRES_OLD}" .dump > ".${PREV_STAGE}.dump"
	sqlite3 "${SQLRES_NEW}" .dump > ".${CUR_STAGE}.dump"
	#${SQLDIFF} "${PREV_STAGE}" "${CUR_STAGE}" > "${PREV_STAGE}-${CUR_STAGE}.sqldiff"
	#sort "${PREV_STAGE}-${CUR_STAGE}.sqldiff" > "${PREV_STAGE}-${CUR_STAGE}.sqldiff.sort"
	mv -f "${PREV_STAGE}-${CUR_STAGE}.sqldiff"* "${REPORT_ROOT}/sql/"
	#rm -f ".${PREV_STAGE}.dump" ".${CUR_STAGE}.dump"
	echo "SQL DIFFING COMLPETE."
}

# Analyze new assets
stage3() {
	render_models
	build_report
}

# Render new models (Mesh)
# TODO: Convert for-find loops into find-file-while loops
render_models() {
	# Process new unit models
	# NOTE: We cannot diff between actual new units and just new costumes at this moment.
	for UNIT_DIR in $(find "${CHARACTERS_ROOT}" -type d); do
		[ -d "${UNIT_DIR}/prefabs" ] || continue;
		for UNIT_MODEL in $(find "${UNIT_DIR}/prefabs" -depth -type d -regextype posix-extended -regex "${STAGE3_REGEX1}"); do
			UNIT_MODEL_D="${UNIT_MODEL}"
			UNIT_MODEL=$(basename "${UNIT_MODEL}" | rev | cut -f 2- -d '.' | rev)
			[ ! -f "${UNIT_MODEL_D}/${UNIT_MODEL}.fbx" ] && continue
			case "${UNIT_MODEL}" in
				*weapon*) UNIT_MODEL_NAME=$(echo "${UNIT_MODEL}" | awk '{print substr($0, 8, length($0) - 12)}') ;;
				*hero*)   UNIT_MODEL_NAME=$(echo "${UNIT_MODEL}" | awk '{print substr($0, 6, length($0) - 15)}') ;;
			esac
			UNIT_MODEL_NUMB=$(echo "${UNIT_MODEL}" | awk '{print substr($0, length($0) - 3, 4)}')
			printf "%s\t%s\n" "New model (FBX) found" "${UNIT_MODEL}"
			mkdir -p "${STAGE3_ROOT}/models/hero_${UNIT_MODEL_NAME}_${UNIT_MODEL_NUMB}"
			cp -f "${UNIT_MODEL_D}"/* "${STAGE3_ROOT}/models/hero_${UNIT_MODEL_NAME}_${UNIT_MODEL_NUMB}/"
		done
	done

	# TODO: Somewhere down the road put OBJ weapons in FBX models dir and render them together where possible
	for WEAPON_DIR in $(find "${WEAPONS_MODELS_ROOT}" -type d -regextype posix-extended -regex ".*[a-z](_[a-z])*"); do
		WEAPON_WIELDER=$(echo "${WEAPON_DIR}" | awk -F'/' '{print $NF}')
		mkdir -p "${STAGE3_ROOT}/weapons/hero_${WEAPON_WIELDER}"
		# Weapons in folders
		for WEAPON_MODEL in $(find "${WEAPON_DIR}" -depth -type d -regextype posix-extended -regex "${STAGE3_REGEX2}"); do
			WEAPON_MODEL_D="${WEAPON_MODEL}"
			WEAPON_MODEL=$(basename "${WEAPON_MODEL}" | rev | cut -f 2- -d '.' | rev)
			[ ! -f "${WEAPON_MODEL_D}/${WEAPON_MODEL}.obj" ] && continue
			printf "%s\t%s\n" "New weapon (OBJ) found" "$(basename "${WEAPON_MODEL_D}" | rev | cut -f 2- -d '.' | rev)"
			cp -f "${WEAPON_MODEL_D}"/* "${STAGE3_ROOT}/weapons/hero_${WEAPON_WIELDER}"
		done
		# Weapons in unit root
		# TODO: Be more precise what files to copy (especially for aux UVs)
		for WEAPON_MODEL in $(find "${WEAPON_DIR}" -type f); do
			WEAPON_MODEL_F="${WEAPON_MODEL}"
			WEAPON_MODEL=$(basename "${WEAPON_MODEL}" | rev | cut -f 2- -d '.' | rev)
			case "$(basename "${WEAPON_MODEL_F}")" in
				*weapon*.obj) printf "%s\t%s\n" "New weapon (OBJ) found" "$(basename "${WEAPON_MODEL}" | rev | cut -f 2- -d '.' | rev)" ;;
			esac
			cp -f "${WEAPON_MODEL_F}" "${STAGE3_ROOT}/weapons/hero_${WEAPON_WIELDER}" 2>&1 > /dev/null
		done
		find "${STAGE3_ROOT}/weapons/hero_${WEAPON_WIELDER}" -name "*.obj" -exec sed -i 's/-\.\./0\.0/' {} \;
	done

	#return

	# Invoke gcfbx on models and produce renders (4 sides)
	if [ -d "${STAGE3_ROOT}/models" ]; then
		for UNIT_MODEL in $(find "${STAGE3_ROOT}/models/" -depth -type d \
			-regextype posix-extended -regex "${STAGE3_REGEX2}"); do
			printf "%s\t%s\n" "Rendering model" "${UNIT_MODEL}"
			UNIT_MODEL_D="${UNIT_MODEL}"
			UNIT_MODEL=$(basename "${UNIT_MODEL}" | rev | cut -f 2- -d '.' | rev)
			UNIT_MODEL_NAME=$(echo "${UNIT_MODEL}" | awk '{print substr($0, 6, length($0) - 10)}')
			UNIT_MODEL_NUMB=$(echo "${UNIT_MODEL}" | awk '{print substr($0, length($0) - 3, 4)}')
			${GCFBX} -- "${UNIT_MODEL_D}" "${REPORT_ROOT}/models" "${UNIT_MODEL_NAME}" "${UNIT_MODEL_NUMB}"
			[ $? -eq 1 ] && printf "\t%s\n" "[ERROR] No FBX body model found."
		done
	fi

	# TODO: Render OBJ

	# Convert the PNG renders to WebP (~1-1.5MB to only max 60kB)
	for RENDER in $(find . -type f -name "*.png"); do
		convert "$RENDER" -strip "$RENDER.2"
		cwebp -q 90 "$RENDER.2" -o "$RENDER.3"
		mv -f "$RENDER.3" "$(echo "$RENDER" | rev | cut -f 2- -d '.' | rev).webp"
		rm -f "$RENDER" "$RENDER.2"
	done
}

# For starters, the report will focus on renders, audio filenames
# and SQL changes, cause these work right now.
build_report() {
	echo "BUILDING REPORT FOR ${CUR_STAGE} ..."

	mkdir -p "${REPORT_ROOT}/sql"
	mkdir -p "${REPORT_ROOT}/models"
	mkdir -p "${REPORT_ROOT}/icon/status"

	# Renders
	ROW_CTX=0
	find "${REPORT_ROOT}/models/" -type f -name "*.webp" | sort -u > "${REPORT_ROOT}/.model_files"
	if [ -f "${REPORT_ROOT}/.model_files" ]; then
		while IFS= read -r RENDER; do
			UNIT_MODEL=$(basename "${RENDER}" | rev | cut -f 2- -d '.' | rev)
			UNIT_MODEL_NAME=$(echo "${UNIT_MODEL}" | awk '{print substr($0, 0, length($0) - 3)}')

			if [ $((ROW_CTX % 4)) -eq 0 ]; then
				MODEL_HTML_CONTENT="${MODEL_HTML_CONTENT}<div class=\"row\"><div class=\"col-lg-12\"><h4 class=\"whitetext mb-2\"><code>${UNIT_MODEL_NAME}</code></h4></div></div>"
			fi
			if [ $((ROW_CTX % 2)) -eq 0 ]; then
				MODEL_HTML_CONTENT="${MODEL_HTML_CONTENT}<div class=\"row\">"
			fi
			MODEL_HTML_CONTENT="${MODEL_HTML_CONTENT}<div class=\"mb-4 col-lg-6\"><img class=\"img-fluid\" src=\"report-${CUR_STAGE}/models/${UNIT_MODEL}.webp\"></div>"
			ROW_CTX=$((ROW_CTX + 1))
			if [ $((ROW_CTX % 2)) -eq 0 ]; then
				MODEL_HTML_CONTENT="${MODEL_HTML_CONTENT}</div>"
			fi
		done < "${REPORT_ROOT}/.model_files"
		rm -f "${REPORT_ROOT}/.model_files"
	else
		MODEL_HTML_CONTENT="<div class=\"row\"><h5 class=\"whitetext\"><b>No new models</b></h5></div>"
	fi

	# Audio files
	AUDIO_HTML_CONTENT="<div class=\"row\"><ul>"
	(
		cd "${P1RES}/sound" && find . -type f -name "*.wav" | awk '{print substr($0, 3, length($0))}' > "${REPORT_ROOT}/.audio_files"
		cd "${PRES}/sound" &&  find . -type f -name "*.wav" | awk '{print substr($0, 3, length($0))}' >> "${REPORT_ROOT}/.audio_files"
	)
	[ -f "${REPORT_ROOT}/.audio_files" ] && sort -u < "${REPORT_ROOT}/.audio_files" > "${REPORT_ROOT}/.audio_files_"
	if [ -f "${REPORT_ROOT}/.audio_files_" ]; then
		while IFS= read -r AUDIO_FILE; do
			AFILE=$(echo "${AUDIO_FILE}" | rev | cut -f 2- -d '.' | rev)
			AUDIO_HTML_CONTENT="${AUDIO_HTML_CONTENT}<li><code>${AFILE}</code></li>"
		done < "${REPORT_ROOT}/.audio_files_"
		AUDIO_HTML_CONTENT="${AUDIO_HTML_CONTENT}</ul></div>"
		rm -f "${REPORT_ROOT}/.audio_files" "${REPORT_ROOT}/.audio_files_"
	fi

	# SQL diff
	# TODO: Have 2 HTML_CONTENT strings for changes and additions
	PREV_SQLDIFF_SYM=""
	SQL_HTML_CONTENT="<div class=\"row\"><h4 class=\"whitetext\">Changes</h4></div><div class=\"row\">"
	while IFS= read -r L; do
		CUR_SYM="$(echo "$L" | cut -d$'\t' -f 1)"
		CUROWID="$(echo "$L" | cut -d$'\t' -f 2)"
		OLD_VAL="$(echo "$L" | cut -d$'\t' -f 3)"
		NEW_VAL="$(echo "$L" | cut -d$'\t' -f 4)"
		if [ "$PREV_SQLDIFF_SYM" != "$CUR_SYM" ]; then
			if [ "$CUR_SYM" == "~~~" ]; then
				SQL_HTML_CONTENT="${SQL_HTML_CONTENT}<table class=\"table table-dark table-bordered\" style=\"margin-bottom: 0; font-size: 1rem\"><tr><th>RowID</th><th>Old Value</th><th>New Value</th></tr><tbody>"
			elif [ "$CUR_SYM" == "~~~" ]; then
				SQL_HTML_CONTENT="${SQL_HTML_CONTENT}</tbody></table></div><div class=\"row\"><h4 class=\"whitetext\">Additions</h4></div><div class=\"row\"><table class=\"table table-dark table-bordered\" style=\"margin-bottom: 0; font-size: 1rem\"><tr><th>RowID</th><th>New Value</th></tr><tbody>"
			fi
		fi
		if [ "$CUR_SYM" == "~~~" ]; then
			SQL_HTML_CONTENT="${SQL_HTML_CONTENT}<tr><td><code>${CUROWID}</code></td><td>${OLD_VAL}</td><td>${NEW_VAL}</td></tr>"
		elif [ "$CUR_SYM" == "+++" ]; then
			SQL_HTML_CONTENT="${SQL_HTML_CONTENT}<tr><td><code>${CUROWID}</code></td><td>${NEW_VAL}</td></tr>"
		fi
	done < "${REPORT_ROOT}/sql/${PREV_STAGE}-${CUR_STAGE}.sqldiff"
	SQL_HTML_CONTENT="$SQL_HTML_CONTENT</tbody></table></div>"

	# TODO: Status Effects
	STAT_EFF_HTML_CONTENT="<div class=\"row\"><table class=\"table table-dark table-bordered\" style=\"margin-bottom: 0; font-size: 1rem\"><tr><th>Icon</th><th>Filename</th></tr><tbody>"
	for STAT_EFF in $(find "${STATUS_EFF_ROOT}" -type f -name "*.png"); do
		STAT_EFF_NAME=$(basename "${STAT_EFF}" | rev | cut -f 2- -d '.' | rev)
		cwebp -q 100 -lossless "${STAT_EFF}" -o "${REPORT_ROOT}/icon/status/${STAT_EFF_NAME}.webp"
		STAT_EFF_HTML_CONTENT="${STAT_EFF_HTML_CONTENT}<tr><td><img src=\"report-${CUR_STAGE}/icon/status/${STAT_EFF_NAME}.webp\" width="32"></td><td></td></tr>"
	done
	STAT_EFF_HTML_CONTENT="${STAT_EFF_HTML_CONTENT}</tbody></table></div>"

	# TODO: Gacha tickets

	# TODO: Character illustrations

	# TODO: all other stuff lol

	# Put everything together
	cat > "${REPORT_ROOT}/report-${CUR_STAGE}.html" <<- EOF
		<!DOCTYPE html>
		<html lang="en">
			<head>
				<meta charset="utf-8">
				<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
				<meta name="description" content="Early data previews for Seven Deadly Sins: Grand Cross [七つの大罪: 光と闇の交戦]">
				<title>nntdata - Report for NNT:GC stage ${CUR_STAGE}</title>
				<link href="lib/css/bootstrap.min.css" rel="stylesheet">
				<link href="lib/css/custom.css" rel="stylesheet">
			</head>
			<body class="darktheme">
				<div class="container">
					<div class="row">
						<div class="titlebox col-lg-12">
							<h1 class="whitetext mb-4">Early Data Report for Stage <code>${CUR_STAGE}</code></h1>
						</div>
					</div>
					<div class="row">
						<div class="titlebox col-lg-12">
							<h3 class="whitetext mb-4">Units and costumes</h3>
						</div>
					</div>
					${MODEL_HTML_CONTENT}
					<div class="row">
						<div class="titlebox col-lg-12">
							<h3 class="whitetext mb-4">Audio</h3>
						</div>
					</div>
					${AUDIO_HTML_CONTENT}
					<div class="row">
						<div class="titlebox col-lg-12">
							<a href="report-${CUR_STAGE}/sql/${PREV_STAGE}-${CUR_STAGE}.sqldiff"><h3 class="whitetext mb-4">SQL Database</h3></a>
						</div>
					</div>
					${SQL_HTML_CONTENT}
					<div class="row">
						<div class="titlebox col-lg-12">
							<h3 class="whitetext mb-4">Status Effects</h3>
						</div>
					</div>
					${STAT_EFF_HTML_CONTENT}
				</div>
			</body>
		</html>
	EOF
	cp -rf "${REPORT_ROOT}" "${NNTDAT_ROOT}/"
	js-beautify --type html "${NNTDAT_ROOT}/report-${CUR_STAGE}/report-${CUR_STAGE}.html" > "${NNTDAT_ROOT}/${CUR_STAGE}.html"
	rm -f "${NNTDAT_ROOT}/report-${CUR_STAGE}/report-${CUR_STAGE}.html"

	echo "REPORT BUILT."
}


dir_init
stageemulator
stage1
assetstudio_run
stage2
diffsql
stage3
render_models
build_report