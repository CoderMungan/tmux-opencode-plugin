#!/usr/bin/env bash

opencode_db_sessions() {
  local limit where now stale busy background
  limit="$(opencode_safe_integer "$(opencode_max_sessions)" 50)"
  now="$(opencode_now_epoch)"
  stale="$(opencode_safe_integer "$(opencode_stale_minutes)" 240)"
  busy=5
  background=30

  where=""
  if ! opencode_is_true "$(opencode_show_archived)"; then
    where="where time_archived is null"
  fi

  opencode_sqlite "
    select
      id,
      replace(coalesce(title,''), char(10), ' '),
      coalesce(directory,''),
      coalesce(path,''),
      coalesce(parent_id,''),
      cast(coalesce(time_updated, 0) as integer),
      cast(coalesce(time_created, 0) as integer),
      cast(coalesce(time_archived, 0) as integer),
      coalesce(agent,''),
      coalesce(model,'')
    from session
    ${where}
    order by cast(time_updated as integer) desc
    limit ${limit};
  " | awk -F'\t' -v now="$now" -v stale_min="$stale" -v busy_min="$busy" -v background_min="$background" '
    BEGIN { OFS="\t" }
    {
      updated = ($6 ~ /^[0-9]+$/ ? $6 : 0)
      archived = ($8 ~ /^[0-9]+$/ ? $8 : 0)
      if (updated > 1000000000000) updated = int(updated / 1000)
      if (archived > 1000000000000) archived = int(archived / 1000)
      age = (updated > 0 ? int((now - updated) / 60) : -1)
      status = "idle"
      if (archived > 0) {
        status = "archived"
      } else if (age >= 0 && age <= busy_min) {
        status = "busy"
      } else if (age >= 0 && age <= background_min) {
        status = "background"
      } else if (age >= 0 && age > stale_min) {
        status = "stale"
      }

      print "db", $1, $2, $3, $4, status, updated, age, "0", "", "", "", $9, $10, archived, $5
    }
  '
}

opencode_tmux_sessions() {
  if ! opencode_has tmux; then
    return 0
  fi

  tmux list-panes -a -F '#{session_id}	#{window_id}	#{pane_id}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}	#{pane_title}' 2>/dev/null |
    awk -F'\t' '
      BEGIN { OFS="\t" }
      {
        pid = $4
        command = tolower($5)
        title = tolower($7)
        proc = ""
        session_id = ""
        if (pid ~ /^[0-9]+$/) {
          cmd = "ps -p " pid " -o command= 2>/dev/null"
          cmd | getline proc
          close(cmd)
          proc = tolower(proc)
          if (match(proc, /--session[= ][A-Za-z0-9_]+/)) {
            session_id = substr(proc, RSTART, RLENGTH)
            sub(/^--session[= ]/, "", session_id)
          } else if (match(proc, /-s[ ]+[A-Za-z0-9_]+/)) {
            session_id = substr(proc, RSTART, RLENGTH)
            sub(/^-s[ ]+/, "", session_id)
          }
        }

        if (command ~ /(^|\/)(opencode)$/ || command ~ /^opencode$/ || title ~ /opencode/ || proc ~ /(^|[[:space:]\/])opencode([[:space:]]|$)/) {
          print "tmux", session_id, "", $6, "", "attached", 0, 0, "1", $3, $2, $1, "", "", 0, ""
        }
      }
    '
}

opencode_merge_sessions() {
  local tmp_db tmp_tmux tmp_db_idx
  tmp_db="$(mktemp)"
  tmp_tmux="$(mktemp)"
  tmp_db_idx="$(mktemp)"
  opencode_db_sessions >"$tmp_db" || true
  opencode_tmux_sessions >"$tmp_tmux" || true

  awk -F'\t' 'BEGIN { OFS="\t" } $1=="db" { key = $4; if (!(key in seen)) { seen[key] = $2; print key, $2 } }' "$tmp_db" >"$tmp_db_idx"

  awk -F'\t' -v db="$tmp_db" -v idx="$tmp_db_idx" '
    BEGIN {
      OFS="\t"
      while ((getline line < db) > 0) {
        split(line, f, "\t")
        raw[f[2]] = line
        parent[f[2]] = f[16]
      }
      close(db)
      while ((getline line < idx) > 0) {
        split(line, f, "\t")
        pathId[f[1]] = f[2]
      }
      close(idx)
    }
    function root_id(id, r) {
      r = id
      while (parent[r] != "" && parent[r] != r && (parent[r] in raw)) r = parent[r]
      return r
    }
    function priority(status) {
      if (status == "attached") return 6
      if (status == "busy") return 5
      if (status == "background") return 4
      if (status == "idle") return 3
      if (status == "stale") return 2
      if (status == "archived") return 1
      return 0
    }
    function merge_status(a, b) { return (priority(b) > priority(a) ? b : a) }
    function add_summary(root, status) {
      if (summary[root] == "") summary[root] = status
      else summary[root] = summary[root] "," status
      child_count[root]++
    }
    {
      tmuxId = $2
      path = $4
      pane = $10
      win = $11
      sess = $12
      if (tmuxId != "" && (tmuxId in raw)) {
        id = tmuxId
      } else if (path in pathId) {
        id = pathId[path]
      } else {
        print "tmux-only", "pane:" pane, "Active tmux pane", path, path, "attached", 0, 0, "1", pane, win, sess, "", "", 0, "", 0, "", "tmux-only"
        next
      }

      split(raw[id], f, "\t")
      root = root_id(id)
      if (id == root) {
        f[6] = "attached"
        f[9] = "1"
        f[10] = pane
        f[11] = win
        f[12] = sess
        raw[id] = f[1]
        for (i = 2; i <= 16; i++) raw[id] = raw[id] OFS f[i]
        attached[root] = 1
      } else {
        child_status[id] = "attached"
        child_pane[id] = pane
        child_win[id] = win
        child_sess[id] = sess
      }
    }
    END {
      for (id in raw) {
        root = root_id(id)
        if (root != id) continue
        split(raw[id], f, "\t")
        status = f[6]
        pane = f[10]
        win = f[11]
        sess = f[12]
        summary[root] = ""
        child_count[root] = 0
        for (child in parent) {
          if (parent[child] != id) continue
          add_summary(root, (child_status[child] == "" ? "idle" : child_status[child]))
          status = merge_status(status, (child_status[child] == "" ? "idle" : child_status[child]))
          if (child_status[child] == "attached") {
            if (pane == "") pane = child_pane[child]
            if (win == "") win = child_win[child]
            if (sess == "") sess = child_sess[child]
          }
        }
        if (attached[root]) status = "attached"
        f[6] = status
        f[9] = (status == "attached" ? "1" : f[9])
        f[10] = pane
        f[11] = win
        f[12] = sess
        f[17] = child_count[root] + 0
        f[18] = summary[root]
        f[19] = root
        line = f[1]
        for (i = 2; i <= 19; i++) line = line OFS f[i]
        print line
      }
    }
  ' "$tmp_tmux" | sort -t $'\t' -k7,7nr -k2,2

  rm -f "$tmp_db" "$tmp_tmux" "$tmp_db_idx"
}

opencode_list_sessions() {
  opencode_merge_sessions
}

opencode_status_segment() {
  local rows total attached busy background idle stale archived color enabled reset
  rows="$(opencode_merge_sessions 2>/dev/null || true)"
  if [ -z "$rows" ]; then
    printf 'OC:0'
    return 0
  fi

  total=$(printf '%s\n' "$rows" | awk 'END { print NR + 0 }')
  attached=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="attached"{c++} END{print c+0}')
  busy=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="busy"{c++} END{print c+0}')
  background=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="background"{c++} END{print c+0}')
  idle=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="idle"{c++} END{print c+0}')
  stale=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="stale"{c++} END{print c+0}')
  archived=$(printf '%s\n' "$rows" | awk -F'\t' '$6=="archived"{c++} END{print c+0}')

  enabled="$(opencode_status_colors)"
  if opencode_is_true "$enabled"; then
    reset='#[default]'
    printf '#[fg=cyan]OC:%s%s #[fg=green]A:%s%s #[fg=yellow]B:%s%s #[fg=white]I:%s%s #[fg=red]S:%s%s #[fg=colour8]C:%s%s' \
      "$total" "$reset" "$attached" "$reset" "$((busy + background))" "$reset" "$idle" "$reset" "$stale" "$reset" "$archived" "$reset"
  else
    printf 'OC:%s A:%s B:%s I:%s S:%s C:%s' "$total" "$attached" "$((busy + background))" "$idle" "$stale" "$archived"
  fi
}

opencode_latest_session_id() {
  opencode_sqlite "select id from session where time_archived is null order by cast(time_updated as integer) desc limit 1;" 2>/dev/null | head -n1
}
