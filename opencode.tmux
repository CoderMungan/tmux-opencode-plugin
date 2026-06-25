if-shell -F '#{==:#{@opencode-key},}' 'set-option -gq @opencode-key O'
if-shell -F '#{==:#{@opencode-status-position},}' 'set-option -gq @opencode-status-position right'
if-shell -F '#{==:#{@opencode-popup-width},}' 'set-option -gq @opencode-popup-width 90%'
if-shell -F '#{==:#{@opencode-popup-height},}' 'set-option -gq @opencode-popup-height 80%'
if-shell -F '#{==:#{@opencode-stale-minutes},}' 'set-option -gq @opencode-stale-minutes 240'
if-shell -F '#{==:#{@opencode-show-archived},}' 'set-option -gq @opencode-show-archived false'
if-shell -F '#{==:#{@opencode-max-sessions},}' 'set-option -gq @opencode-max-sessions 50'
if-shell -F '#{==:#{@opencode-resume-target},}' 'set-option -gq @opencode-resume-target window'
if-shell -F '#{==:#{@opencode-status-colors},}' 'set-option -gq @opencode-status-colors true'

run-shell -b "key=\$(tmux show-option -gqv @opencode-key); width=\$(tmux show-option -gqv @opencode-popup-width); height=\$(tmux show-option -gqv @opencode-popup-height); tmux unbind-key \"\$key\" 2>/dev/null; tmux bind-key \"\$key\" display-popup -E -w \"\$width\" -h \"\$height\" \"#{d:current_file}/scripts/popup-run.sh\""
