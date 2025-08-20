#!/usr/bin/env bash

SPECS="$1"

# See FwPackageCheckTnSpec() in edk2-nvidia/Silicon/NVIDIA/Library/FwPackageLib
checkspec() {
	local expected="$1"
	local actual="$2"

	# Return 1 (no match) if either argument is empty
	if [[ -z "$expected" || -z "$actual" ]]; then
		return 1
	fi

	# Split the strings into tokens using '-' as delimiter
	IFS='-' read -ra tokensExpected <<<"$expected"
	IFS='-' read -ra tokensActual <<<"$actual"

	# If the token counts differ, it's a mismatch
	if [[ "${#tokensExpected[@]}" -ne "${#tokensActual[@]}" ]]; then
		return 1
	fi

	# Iterate over each token index
	for i in "${!tokensExpected[@]}"; do
		local token1="${tokensExpected[i]}"
		local token2="${tokensActual[i]}"

		# If either token is empty, ignore and continue to next token
		if [[ -z "$token1" || -z "$token2" ]]; then
			continue
		fi

		# If the tokens do not match, return 1 indicating no match
		if [[ "$token1" != "$token2" ]]; then
			return 1
		fi
	done

	# All tokens match (ignoring empty tokens), return 0 for success
	return 0
}

extractboardname() {
	local spec="$1"

	# per flash.sh, spec="${BOARDID}-${FAB}-${BOARDSKU}-${BOARDREV}-${fuselevel_s}-${hwchiprev}-${ext_target_board}-";
	# and we want ext_target_board. ext_target_board has "-" in it, which makes processing this a little more annoying
	cut -d- -f7- <<<"$spec" | rev | cut -d- -f2- | rev
}

# cut -c 4- to remove the leading attributes from the efi variable
# See the warning at: https://docs.kernel.org/filesystems/efivarfs.html
PLATFORM_SPEC="$(cut -c 4- </sys/firmware/efi/efivars/TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9 | tr -d '\0')"
COMPAT_SPEC="$(cut -c 4- </sys/firmware/efi/efivars/TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9 | tr -d '\0')"

NIXOS_BOARDS=""

while read spec; do
	if checkspec "$PLATFORM_SPEC" "$spec" || checkspec "$COMPAT_SPEC" "$spec"; then
		exit 0
	fi
	NIXOS_BOARDS+="$(extractboardname "$spec")"$'\n'
done <"$SPECS"

MACHINE_BOARDS="$( (
	extractboardname "$PLATFORM_SPEC"
	extractboardname "$COMPAT_SPEC"
) | sort -u | tr '\n' ' ')"
NIXOS_BOARDS="$(echo "$NIXOS_BOARDS" | sort -u | tr '\n' ' ')"

echo "This machine is not compatible with the platform specs for this NixOS system!"
echo "This machine is a: ${MACHINE_BOARDS}"
echo "This NixOS system supports: ${NIXOS_BOARDS}"
exit 1
