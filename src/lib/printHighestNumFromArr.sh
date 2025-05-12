function printHighestNumFromArr() { # array
  local -n numbers=${1} # must be an array
  local highest
  local number

  # Initialize a variable to hold the highest number
  highest=${numbers[0]}  # Start with the first element

  # Loop through the array
  for number in "${numbers[@]}"; do
    if (( number > highest )); then
      highest=$number  # Update highest if the current number is greater
    fi
  done
  printf '%s' "${highest}"
}