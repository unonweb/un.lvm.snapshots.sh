function trim() {
  local str="$1"

  # remove leading whitespace characters
  str="${str#"${str%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  str="${str%"${str##*[![:space:]]}"}"

  printf '%s' "$str"
}