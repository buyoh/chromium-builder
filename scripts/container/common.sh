# Definitions shared by the scripts in this directory.

# depot_tools_revision <DEPS file>
# Print the depot_tools commit pinned by the DEPS file.
depot_tools_revision() {
  local revision
  revision=$(sed -n '/\/chromium\/tools\/depot_tools\.git/ { s/.*[^0-9a-f]\([0-9a-f]\{40\}\)[^0-9a-f].*/\1/; T; p; q }' "$1")
  if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: depot_tools revision not found in $1" >&2
    return 1
  fi
  echo "$revision"
}
