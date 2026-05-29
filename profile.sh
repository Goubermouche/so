#!/usr/bin/env bash
set -u

if [ $# -ne 2 ]; then
	echo "usage: $0 <executable> <N>" >&2
	exit 2
fi

EXE="$1"
N="$2"

if [ ! -x "$EXE" ]; then
	echo "error: '$EXE' is not an executable file" >&2
	exit 2
fi

if ! [[ "$N" =~ ^[1-9][0-9]*$ ]]; then
	echo "error: N must be a positive integer, got '$N'" >&2
	exit 2
fi

parse_ms() {
	local label="$1" output="$2"
	printf '%s\n' "$output" | awk -v lbl="$label" '
		$0 ~ lbl {
			for (i = 1; i <= NF; i++) {
				tok = $i; sub(/^\(/, "", tok)
				if (tok ~ /^[0-9]+(\.[0-9]+)?ms$/) {
					sub(/ms$/, "", tok); print tok; exit
				}
			}
		}
	'
}

parse_mps() {
	local label="$1" output="$2"
	printf '%s\n' "$output" | awk -v lbl="$label" '
		$0 ~ lbl {
			for (i = 1; i <= NF; i++) {
				tok = $i; sub(/^\(/, "", tok)
				if (tok ~ /^[0-9]+(\.[0-9]+)?M$/) {
					sub(/M$/, "", tok); print tok; exit
				}
			}
		}
	'
}

parse_cands() {
	local output="$1"
	printf '%s\n' "$output" | awk '
		/candidates:/ {
			for (i = 1; i <= NF; i++) {
				tok = $i; sub(/^\(/, "", tok)
				if (tok ~ /^[0-9]+(\.[0-9]+)?M$/) {
					sub(/M$/, "", tok); print tok; exit
				}
			}
		}
	'
}

make_program() {
	local n="$1"
	for ((i = 1; i <= n - 1; i++)); do
		printf 'xori x%d, x1, %d\n' $((i + 1)) "$i"
	done
	printf 'add x0, x0, x0\n'
}

avg_of() {
	printf '%s\n' "$@" | awk '
		BEGIN { s = 0; n = 0 }
		{ s += $1; n++ }
		END { printf "%.2f\n", (n ? s/n : 0) }
	'
}

WL=6
WC=12
WE=12
WP=16
WF=12
WQ=16
WT=12

SEP_WIDTH=$(( WL + WC + WE + WP + WF + WQ + WT + 12 ))

print_row() {
	printf '%*s  %*s  %*s  %*s  %*s  %*s  %*s\n' \
		$WL "$1"  $WC "$2"  $WE "$3"  $WP "$4"  $WF "$5"  $WQ "$6"  $WT "$7"
}

print_row "N" "cands (M)" "enum (ms)" "enum (M cand/s)" "filter (ms)" "filter (M cand/s)" "total (ms)"

TMPFILE=$(mktemp /tmp/profile_prog_XXXXXX.s)
trap 'rm -f "$TMPFILE"' EXIT
declare -a a_cands a_enum a_emps a_filt a_fmps a_total

for ((n = 1; n <= N; n++)); do
	make_program "$n" > "$TMPFILE"

	output=$("$EXE" "$TMPFILE" 2>/dev/null)
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "error: optimizer exited with code $rc on depth $d" >&2
		echo "program was:" >&2
		cat "$TMPFILE" >&2
		exit 1
	fi

	cands=$(   parse_cands "$output")
	enum_ms=$( parse_ms  "enum time"   "$output")
	enum_mps=$(parse_mps "enum time"   "$output")
	filt_ms=$( parse_ms  "filter time" "$output")
	filt_mps=$(parse_mps "filter time" "$output")
	total_ms=$(parse_ms  "total time"  "$output")

	a_cands+=("$cands")
	a_enum+=("$enum_ms")
	a_emps+=("$enum_mps")
	a_filt+=("$filt_ms")
	a_fmps+=("$filt_mps")
	a_total+=("$total_ms")

	print_row "$n" \
		"$cands" \
		"$enum_ms" "$enum_mps" \
		"$filt_ms" "$filt_mps" \
		"$total_ms"
done

print_row "avg" \
	"$(avg_of "${a_cands[@]}")" \
	"$(avg_of "${a_enum[@]}")"  "$(avg_of "${a_emps[@]}")" \
	"$(avg_of "${a_filt[@]}")"  "$(avg_of "${a_fmps[@]}")" \
	"$(avg_of "${a_total[@]}")"

CSV_FILE="$(date +'%Y_%m_%d_%H_%M_%S').csv"

{
	echo "N,cands (M),enum (ms),enum (M cand/s),filter (ms),filter (M cand/s),total (ms)"
	
	for ((i=0; i<${#a_cands[@]}; i++)); do
		echo "$((i+1)),${a_cands[$i]},${a_enum[$i]},${a_emps[$i]},${a_filt[$i]},${a_fmps[$i]},${a_total[$i]}"
	done
	
	echo "avg,$(avg_of "${a_cands[@]}"),$(avg_of "${a_enum[@]}"),$(avg_of "${a_emps[@]}"),$(avg_of "${a_filt[@]}"),$(avg_of "${a_fmps[@]}"),$(avg_of "${a_total[@]}")"
} > "$CSV_FILE"

echo "CSV written to '$CSV_FILE'"
