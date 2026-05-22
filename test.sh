#!/usr/bin/env bash
set -u

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
	echo "usage: $0 <executable> <tests_dir> [profile]" >&2
	exit 2
fi

EXE="$1"
DIR="$2"
MODE="${3:-normal}"

if [ "$MODE" != "normal" ] && [ "$MODE" != "profile" ]; then
	echo "error: third argument must be 'profile' or omitted" >&2
	exit 2
fi

if [ ! -x "$EXE" ]; then
	echo "error: '$EXE' is not an executable file" >&2
	exit 2
fi

if [ ! -d "$DIR" ]; then
	echo "error: '$DIR' is not a directory" >&2
	exit 2
fi

PROFILE_RUNS=10

if [ -t 1 ]; then
	C_PASS=$'\033[32m'; C_FAIL=$'\033[31m'; C_RST=$'\033[0m'
else
	C_PASS=''; C_FAIL=''; C_RST=''
fi

fmt_ns() {
	local ns=$1
	awk -v ns="$ns" 'BEGIN {
		if (ns < 1000)            { printf "%dns", ns; exit }
		if (ns < 1000000)         { printf "%.3gus", ns/1000; exit }
		if (ns < 1000000000)      { printf "%.3gms", ns/1000000; exit }
		if (ns < 60000000000)     { printf "%.3gs",  ns/1000000000; exit }
		if (ns < 3600000000000)   {
			m = int(ns/60000000000)
			s = (ns - m*60000000000) / 1000000000
			printf "%dm%.1fs", m, s; exit
		}
		h = int(ns/3600000000000)
		m = (ns - h*3600000000000) / 60000000000
		printf "%dh%.1fm", h, m
	}'
}

now_ns() {
	date +%s%N
}

normalize() {
	sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' | grep -v '^$'
}

extract_expected() {
	awk '
		/^[[:space:]]*#/ { sub(/^[[:space:]]*#[[:space:]]?/, ""); print; next }
		/^[[:space:]]*$/ { next }
		{ exit }
	' "$1"
}

extract_actual() {
	awk '
		/^done: optimization found/ { in_block = 1; next }
		/^statistics:/              { in_block = 0 }
		in_block                    { print }
	'
}

total=0
passed=0
failed=0
total_ns=0
failed_names=()

shopt -s nullglob
tests=("$DIR"/*.s)
shopt -u nullglob

if [ ${#tests[@]} -eq 0 ]; then
	echo "no .s tests found in '$DIR'" >&2
	exit 1
fi

max_name_len=0
for t in "${tests[@]}"; do
	n=$(basename "$t")
	[ ${#n} -gt $max_name_len ] && max_name_len=${#n}
done

if [ "$MODE" = "profile" ]; then
	echo "profile mode: $PROFILE_RUNS runs per test"
	echo
fi

for test in "${tests[@]}"; do
	total=$((total + 1))
	name=$(basename "$test")

	expected=$(extract_expected "$test" | normalize)
	if [ -z "$expected" ]; then
		printf 'SKIP %-*s  (no expected output)\n' "$max_name_len" "$name"
		continue
	fi

	# determine how many runs and what to do with them
	runs=1
	if [ "$MODE" = "profile" ]; then runs=$PROFILE_RUNS; fi

	test_total_ns=0
	any_fail=0
	last_output=""
	last_rc=0

	for ((r = 0; r < runs; ++r)); do
		t0=$(now_ns)
		last_output=$("$EXE" "$test" 2>/dev/null)
		last_rc=$?
		t1=$(now_ns)
		test_total_ns=$((test_total_ns + (t1 - t0)))

		if [ "$last_rc" -ne 0 ]; then any_fail=1; break; fi
	done

	# average across the runs that actually completed
	completed=$([ "$any_fail" -eq 1 ] && echo $((r + 1)) || echo "$runs")
	avg_ns=$((test_total_ns / completed))
	total_ns=$((total_ns + test_total_ns))

	dt_fmt=$(fmt_ns "$avg_ns")
	if [ "$MODE" = "profile" ]; then
		dt_label="avg $dt_fmt over $runs runs"
	else
		dt_label="$dt_fmt"
	fi

	if [ "$any_fail" -eq 1 ]; then
		printf '%sFAIL%s %-*s  %s  (exit %d)\n' \
			"$C_FAIL" "$C_RST" "$max_name_len" "$name" "$dt_label" "$last_rc"
		failed=$((failed + 1))
		failed_names+=("$name")
		continue
	fi

	actual=$(printf '%s\n' "$last_output" | extract_actual | normalize)

	if [ "$expected" = "$actual" ]; then
		printf '%sPASS%s %-*s  %s\n' \
			"$C_PASS" "$C_RST" "$max_name_len" "$name" "$dt_label"
		passed=$((passed + 1))
	else
		printf '%sFAIL%s %-*s  %s\n' \
			"$C_FAIL" "$C_RST" "$max_name_len" "$name" "$dt_label"
		printf '  expected:\n'
		printf '%s\n' "$expected" | sed 's/^/    /'
		printf '  actual:\n'
		if [ -z "$actual" ]; then
			printf '    (no "done: optimization found" block in output)\n'
		else
			printf '%s\n' "$actual" | sed 's/^/    /'
		fi
		failed=$((failed + 1))
		failed_names+=("$name")
	fi
done

total_fmt=$(fmt_ns "$total_ns")

echo
printf 'tests: %d passed: %s%d%s failed: %s%d%s time: %s\n' \
	"$total" "$C_PASS" "$passed" "$C_RST" "$C_FAIL" "$failed" "$C_RST" "$total_fmt"

if [ "$failed" -gt 0 ]; then
	echo "failed tests:"
	for n in "${failed_names[@]}"; do
		echo "  - $n"
	done
	exit 1
fi

exit 0