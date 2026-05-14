#!/bin/bash

nekoi_config_lib_dir() {
  local source_path="${BASH_SOURCE[0]}"
  local source_dir
  source_dir="$(cd "$(dirname "$source_path")" && pwd -P)"
  printf '%s' "$source_dir"
}

NEKOI_CONFIG_LIB_DIR="$(nekoi_config_lib_dir)"
NEKOI_HOOKS_DIR="$(cd "$NEKOI_CONFIG_LIB_DIR/.." && pwd -P)"
NEKOI_PACKAGE_ROOT="$(cd "$NEKOI_HOOKS_DIR/.." && pwd -P)"

nekoi_default_config_file() {
  if [ -n "${NEKOI_CLAUDE_CONFIG:-}" ] && [ -f "$NEKOI_CLAUDE_CONFIG" ]; then
    printf '%s' "$NEKOI_CLAUDE_CONFIG"
    return 0
  fi

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/config/nekoi-claude.ini" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR/.claude/config/nekoi-claude.ini"
    return 0
  fi

  if [ -f "$NEKOI_PACKAGE_ROOT/config/nekoi-claude.ini" ]; then
    printf '%s' "$NEKOI_PACKAGE_ROOT/config/nekoi-claude.ini"
    return 0
  fi

  printf '%s' ""
}

NEKOI_CONFIG_FILE="$(nekoi_default_config_file)"

nekoi_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

nekoi_expand_config_value() {
  local value="$1"
  local claude_project="${CLAUDE_PROJECT_DIR:-$NEKOI_PACKAGE_ROOT}"
  local home_dir="${HOME:-}"
  local userprofile="${USERPROFILE:-}"

  value="${value//\$\{CLAUDE_PROJECT_DIR\}/$claude_project}"
  value="${value//\$CLAUDE_PROJECT_DIR/$claude_project}"
  value="${value//\$\{NEKOI_PACKAGE_ROOT\}/$NEKOI_PACKAGE_ROOT}"
  value="${value//\$NEKOI_PACKAGE_ROOT/$NEKOI_PACKAGE_ROOT}"
  value="${value//\$\{HOME\}/$home_dir}"
  value="${value//\$HOME/$home_dir}"
  value="${value//\$\{USERPROFILE\}/$userprofile}"
  value="${value//\$USERPROFILE/$userprofile}"

  printf '%s' "$value"
}

nekoi_config_get() {
  local wanted_section="$1"
  local wanted_key="$2"
  local default_value="${3:-}"
  local current_section=""
  local line key value

  if [ -z "$NEKOI_CONFIG_FILE" ] || [ ! -f "$NEKOI_CONFIG_FILE" ]; then
    printf '%s' "$default_value"
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(nekoi_trim "$line")"

    case "$line" in
      ""|\#*|\;*)
        continue
        ;;
      \[*\])
        current_section="${line#[}"
        current_section="${current_section%]}"
        current_section="$(nekoi_trim "$current_section")"
        continue
        ;;
    esac

    if [ "$current_section" != "$wanted_section" ]; then
      continue
    fi

    case "$line" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        key="$(nekoi_trim "$key")"
        value="$(nekoi_trim "$value")"
        if [ "$key" = "$wanted_key" ]; then
          nekoi_expand_config_value "$value"
          return 0
        fi
        ;;
    esac
  done < "$NEKOI_CONFIG_FILE"

  printf '%s' "$default_value"
}

nekoi_dirname() {
  local path="$1"
  if [ -z "$path" ] || [ "$path" = "${path%/*}" ]; then
    printf '%s' ""
    return 0
  fi
  printf '%s' "${path%/*}"
}

nekoi_sessions_dir() {
  local transcript_path="${1:-}"
  local configured_sessions="${2:-}"
  local transcript_dir

  if [ -n "$configured_sessions" ]; then
    printf '%s' "$configured_sessions"
    return 0
  fi

  transcript_dir="$(nekoi_dirname "$transcript_path")"
  if [ -n "$transcript_dir" ] && [ -d "$transcript_dir" ]; then
    printf '%s' "$transcript_dir"
    return 0
  fi

  if [ -n "${HOME:-}" ] && [ -d "$HOME/.claude/projects" ]; then
    printf '%s' "$HOME/.claude/projects"
    return 0
  fi

  printf '%s' ""
}
