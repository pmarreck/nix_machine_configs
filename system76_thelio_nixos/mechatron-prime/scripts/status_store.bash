#!/usr/bin/env bash
# Transactional CI result ledger. The worker is the sole writer; badge and ops
# readers may query concurrently through SQLite's WAL snapshots.

sql_quote() {
	local value="${1:-}"
	value="${value//\'/\'\'}"
	printf "'%s'" "$value"
}

initialize_status_store() {
	local database="${1:-}"
	[ -n "$database" ] || return 1
	sqlite3 -bail "$database" >/dev/null <<'SQL'
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
CREATE TABLE IF NOT EXISTS ci_runs (
	run_id TEXT PRIMARY KEY,
	delivery_id TEXT NOT NULL,
	repository TEXT NOT NULL,
	ref TEXT NOT NULL,
	commit_sha TEXT NOT NULL,
	default_branch TEXT NOT NULL,
	started_at TEXT NOT NULL,
	finished_at TEXT NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('success', 'failure', 'stopped')),
	failure_stage TEXT NOT NULL,
	failure_detail TEXT NOT NULL,
	log_path TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ci_runs_repository_commit
	ON ci_runs (repository, commit_sha);
CREATE INDEX IF NOT EXISTS ci_runs_repository_finished
	ON ci_runs (repository, finished_at DESC);
CREATE TABLE IF NOT EXISTS ledger_metadata (
	key TEXT PRIMARY KEY,
	value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ci_targets (
	run_id TEXT NOT NULL REFERENCES ci_runs(run_id) ON DELETE CASCADE,
	ordinal INTEGER NOT NULL CHECK (ordinal > 0),
	target TEXT NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('success', 'failure', 'stopped')),
	output_paths_json TEXT NOT NULL CHECK (json_valid(output_paths_json)),
	PRIMARY KEY (run_id, ordinal),
	UNIQUE (run_id, target)
);
SQL
	local status=$?
	[ "$status" -eq 0 ] || return "$status"
	# The version stamp deliberately lives in the upgrade step, not above. If
	# the create block stamped it, an existing v1 ledger would be relabelled as
	# v2 while still carrying v1's narrower CHECK constraint, and the rebuild
	# would then be skipped as already done.
	upgrade_status_store "$database" || return 1
	chmod 0640 "$database"
}

# Widen the run and target status vocabulary from ('success','failure') to
# include 'stopped'. SQLite cannot alter a CHECK constraint in place, so each
# table is rebuilt and its rows copied. CREATE TABLE IF NOT EXISTS above is a
# no-op on an existing ledger, which is precisely why this exists: a v1 file
# keeps its narrow constraint until it is rebuilt here.
upgrade_status_store() {
	local database="${1:-}"
	local version
	[ -n "$database" ] || return 1
	version="$(sqlite3 -bail "$database" 'PRAGMA user_version;')" || return 1
	case "$version" in
		2) return 0 ;;
		# A freshly created ledger already carries the widened constraint and
		# needs only its version stamp.
		0) sqlite3 -bail "$database" 'PRAGMA user_version = 2;' >/dev/null; return $? ;;
		1) ;;
		*) return 1 ;;
	esac
	sqlite3 -bail "$database" >/dev/null <<'SQL'
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
CREATE TABLE ci_runs_upgraded (
	run_id TEXT PRIMARY KEY,
	delivery_id TEXT NOT NULL,
	repository TEXT NOT NULL,
	ref TEXT NOT NULL,
	commit_sha TEXT NOT NULL,
	default_branch TEXT NOT NULL,
	started_at TEXT NOT NULL,
	finished_at TEXT NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('success', 'failure', 'stopped')),
	failure_stage TEXT NOT NULL,
	failure_detail TEXT NOT NULL,
	log_path TEXT NOT NULL
);
INSERT INTO ci_runs_upgraded SELECT * FROM ci_runs;
DROP TABLE ci_runs;
ALTER TABLE ci_runs_upgraded RENAME TO ci_runs;
CREATE INDEX IF NOT EXISTS ci_runs_repository_commit
	ON ci_runs (repository, commit_sha);
CREATE INDEX IF NOT EXISTS ci_runs_repository_finished
	ON ci_runs (repository, finished_at DESC);
CREATE TABLE ci_targets_upgraded (
	run_id TEXT NOT NULL REFERENCES ci_runs(run_id) ON DELETE CASCADE,
	ordinal INTEGER NOT NULL CHECK (ordinal > 0),
	target TEXT NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('success', 'failure', 'stopped')),
	output_paths_json TEXT NOT NULL CHECK (json_valid(output_paths_json)),
	PRIMARY KEY (run_id, ordinal),
	UNIQUE (run_id, target)
);
INSERT INTO ci_targets_upgraded SELECT * FROM ci_targets;
DROP TABLE ci_targets;
ALTER TABLE ci_targets_upgraded RENAME TO ci_targets;
PRAGMA user_version = 2;
COMMIT;
PRAGMA foreign_keys = ON;
SQL
}

migrate_legacy_results() {
	local database="${1:-}"
	local legacy_results="${2:-}"
	local badge_dir="${3:-}"
	local marker
	local empty_targets
	local line_number=0
	local started_at
	local finished_at
	local delivery
	local repo
	local ref
	local sha
	local status
	local failure_stage
	local failure_detail
	local log_path
	local run_id
	local badge_state

	[ -f "$database" ] && [ -f "$legacy_results" ] && [ -d "$badge_dir" ] || return 1
	marker="$(sqlite3 "$database" "SELECT value FROM ledger_metadata WHERE key = 'legacy_ndjson_v1';")" || return 1
	[ "$marker" = complete ] && return 0
	empty_targets="$(mktemp "${TMPDIR:-/tmp}/mechatron-legacy-targets.XXXXXX.ndjson")" || return 1
	: > "$empty_targets"
	while IFS= read -r legacy_result; do
		[ -n "$legacy_result" ] || continue
		line_number=$((line_number + 1))
		if ! jq -e 'type == "object"' <<< "$legacy_result" >/dev/null 2>&1; then
			rm -f "$empty_targets"
			return 1
		fi
		started_at="$(jq -er '.started_at // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		finished_at="$(jq -er '.finished_at // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		delivery="$(jq -er '.delivery // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		repo="$(jq -er '.repo // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		ref="$(jq -er '.ref // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		sha="$(jq -er '.sha // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		status="$(jq -er '.status // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		failure_stage="$(jq -er '.failure_stage // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		failure_detail="$(jq -er '.failure_detail // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		log_path="$(jq -er '.log // "" | strings' <<< "$legacy_result")" || { rm -f "$empty_targets"; return 1; }
		case "$status" in success) badge_state=PASSING ;; failure) badge_state=FAILING ;; *) rm -f "$empty_targets"; return 1 ;; esac
		run_id="legacy-$line_number-${sha:0:12}"
		record_ci_result "$database" "$run_id" "$delivery" "$repo" "$ref" "$sha" '' \
			"$started_at" "$finished_at" "$status" "$failure_stage" "$failure_detail" \
			"$log_path" "$empty_targets" || { rm -f "$empty_targets"; return 1; }
		if valid_repo_full_name "$repo" && valid_commit_sha "$sha"; then
			write_badge_status "$badge_dir" "$repo" "$badge_state" "$sha" || { rm -f "$empty_targets"; return 1; }
		fi
	done < "$legacy_results"
	rm -f "$empty_targets"
	sqlite3 -bail "$database" \
		"INSERT INTO ledger_metadata (key, value) VALUES ('legacy_ndjson_v1', 'complete') ON CONFLICT(key) DO UPDATE SET value = excluded.value;" \
		>/dev/null
}

record_ci_result() {
	local database="${1:-}"
	local run_id="${2:-}"
	local delivery="${3:-}"
	local repo="${4:-}"
	local ref="${5:-}"
	local sha="${6:-}"
	local default_branch="${7:-}"
	local started_at="${8:-}"
	local finished_at="${9:-}"
	local status="${10:-}"
	local failure_stage="${11:-}"
	local failure_detail="${12:-}"
	local log_path="${13:-}"
	local target_results_file="${14:-}"
	local sql_file
	local ordinal
	local target
	local target_status
	local output_paths_json
	local render_status=0

	case "$status" in success|failure|stopped) ;; *) return 1 ;; esac
	[ -n "$database" ] && [ -n "$run_id" ] && [ -f "$target_results_file" ] || return 1
	sql_file="$(mktemp "${TMPDIR:-/tmp}/mechatron-status.XXXXXX.sql")" || return 1
	{
		printf 'PRAGMA foreign_keys = ON;\nPRAGMA busy_timeout = 5000;\nBEGIN IMMEDIATE;\n'
		printf 'INSERT INTO ci_runs (run_id, delivery_id, repository, ref, commit_sha, default_branch, started_at, finished_at, status, failure_stage, failure_detail, log_path) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT(run_id) DO UPDATE SET delivery_id=excluded.delivery_id, repository=excluded.repository, ref=excluded.ref, commit_sha=excluded.commit_sha, default_branch=excluded.default_branch, started_at=excluded.started_at, finished_at=excluded.finished_at, status=excluded.status, failure_stage=excluded.failure_stage, failure_detail=excluded.failure_detail, log_path=excluded.log_path;\n' \
			"$(sql_quote "$run_id")" "$(sql_quote "$delivery")" "$(sql_quote "$repo")" \
			"$(sql_quote "$ref")" "$(sql_quote "$sha")" "$(sql_quote "$default_branch")" \
			"$(sql_quote "$started_at")" "$(sql_quote "$finished_at")" "$(sql_quote "$status")" \
			"$(sql_quote "$failure_stage")" "$(sql_quote "$failure_detail")" "$(sql_quote "$log_path")"
		printf 'DELETE FROM ci_targets WHERE run_id = %s;\n' "$(sql_quote "$run_id")"
		while IFS= read -r target_result; do
			[ -n "$target_result" ] || continue
			ordinal="$(jq -er '.ordinal | numbers' <<< "$target_result")" || { render_status=1; break; }
			target="$(jq -er '.target | strings' <<< "$target_result")" || { render_status=1; break; }
			target_status="$(jq -er '.status | strings' <<< "$target_result")" || { render_status=1; break; }
			output_paths_json="$(jq -ec '.output_paths | arrays' <<< "$target_result")" || { render_status=1; break; }
			valid_nix_target "$target" || { render_status=1; break; }
			case "$target_status" in success|failure|stopped) ;; *) render_status=1; break ;; esac
			printf 'INSERT INTO ci_targets (run_id, ordinal, target, status, output_paths_json) VALUES (%s, %s, %s, %s, %s);\n' \
				"$(sql_quote "$run_id")" "$ordinal" "$(sql_quote "$target")" \
				"$(sql_quote "$target_status")" "$(sql_quote "$output_paths_json")"
		done < "$target_results_file"
		[ "$render_status" -eq 0 ] && printf 'COMMIT;\n'
	} > "$sql_file"
	if [ "$render_status" -ne 0 ]; then
		rm -f "$sql_file"
		return "$render_status"
	fi
	sqlite3 -bail "$database" < "$sql_file" >/dev/null
	local sqlite_status=$?
	rm -f "$sql_file"
	[ "$sqlite_status" -eq 0 ] || return "$sqlite_status"
	chmod 0640 "$database"
}
