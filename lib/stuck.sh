#!/usr/bin/env bash
# Stuck command detection: matching and elapsed time formatting

is_stuck_command() {
  local command="$1"
  local patterns="$2"

  [[ -z "$command" || -z "$patterns" ]] && return 1

  # Tokenize the command (no local -a, incompatible with bash 3.2)
  local tokens
  local IFS=' '
  read -ra tokens <<< "$command"
  local num_tokens=${#tokens[@]}

  # Check each pattern (pipe-delimited)
  local pattern_list
  IFS='|'
  read -ra pattern_list <<< "$patterns"
  IFS=' '

  for pattern in "${pattern_list[@]}"; do
    # Count words in pattern
    local pattern_words
    read -ra pattern_words <<< "$pattern"
    local pattern_len=${#pattern_words[@]}

    if [[ $pattern_len -eq 1 ]]; then
      # Single-word pattern: match against tokens at position 1+ (skip the binary name)
      # Also handle prefix patterns (ending with -)
      for (( i=1; i<num_tokens; i++ )); do
        if [[ "$pattern" == *- ]]; then
          # Prefix match: "create-" matches "create-react-app"
          if [[ "${tokens[$i]}" == ${pattern}* ]]; then
            return 0
          fi
        else
          if [[ "${tokens[$i]}" == "$pattern" ]]; then
            return 0
          fi
        fi
      done
    else
      # Multi-word pattern: match consecutive tokens at position 1+
      for (( i=1; i<=num_tokens-pattern_len; i++ )); do
        local match=true
        for (( j=0; j<pattern_len; j++ )); do
          if [[ "${tokens[$((i+j))]}" != "${pattern_words[$j]}" ]]; then
            match=false
            break
          fi
        done
        if [[ "$match" == "true" ]]; then
          return 0
        fi
      done
    fi
  done

  return 1
}

format_elapsed() {
  local seconds="$1"
  if [[ $seconds -ge 3600 ]]; then
    echo "$((seconds / 3600))h"
  elif [[ $seconds -ge 60 ]]; then
    echo "$((seconds / 60))m"
  else
    echo "${seconds}s"
  fi
}

extract_command_keyword() {
  # Extract short keyword for tab title from a full command
  # "npm install react" → "npm"
  # "/usr/bin/npm install" → "npm"
  local command="$1"
  local tokens
  read -ra tokens <<< "$command"
  local binary="${tokens[0]}"
  # Strip path prefix
  basename "$binary"
}
