#!/bin/bash

# Function for formatting sol
format_sol() {
    # Conversion of lamports into solans and rounding to the first digit after the decimal point
    rounded=$(printf "%.1f" "$(echo "$1 / 1000000000" | bc -l)")
    
    # Formatting with commas for digits
    formatted=$(printf "%'f" "$rounded")
    printf "${formatted:0:-5}"
}

# Getting information about the current epoch
epoch_info=$(curl -s -X POST -H "Content-Type: application/json" -d '{
   "jsonrpc": "2.0",
   "id": 1,
   "method": "getEpochInfo"
}' https://api.mainnet-beta.solana.com)

# Error checking
if [ $? -ne 0 ]; then
    echo "Error: Unable to fetch epoch information."
    exit 1
fi

# Extract epoch data
current_epoch=$(echo "$epoch_info" | jq -r '.result.epoch')

# Set the epoch number from the command line argument, or if no argument is given, use the current epoch
epoch_number="${1:-$current_epoch}"

# The epoch from which the check for Eligible status begins
start_epoch=895

# Error checking
if ! [[ "$epoch_number" =~ ^[0-9]+$ ]]; then
  echo "Error: epoch_number must be a non-negative integer."
  exit 1
fi

fetch_bam() {
  local ep="$1"
  curl -sfS "https://kobe.mainnet.jito.network/api/v1/bam_validators?epoch=$ep" 2>/dev/null
}

spinner() {
  tput civis 2>/dev/null
  while :; do
    printf "\rData processing."
    sleep 1
    printf "\rData processing.."
    sleep 1
    printf "\rData processing..."
    sleep 1
  done
}

cleanup_spinner() {
  if [[ -n "${SPIN_PID:-}" ]]; then
    kill -TERM "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    printf "\r\033[K"
    tput cnorm 2>/dev/null
    unset SPIN_PID
  fi
}

trap cleanup_spinner EXIT

# Map construction: vote_account -> first epoch eligible
declare -A earliest_epoch

response_bam_validators=$(fetch_bam "$epoch_number") || {
  echo "Error: Unable to fetch data from BAM Validators API for epoch $epoch_number."
  exit 1
}

# Pull validators
bam_validators=$(echo "$response_bam_validators" | jq '.bam_validators // []')

new_epoch=0

# Data checking in current epoch
if [ "$(echo "$bam_validators" | jq -r 'length')" -eq 0 ]; then
 
    new_epoch=1
    
    # Decremented Epoch
    epoch_number=$((epoch_number - new_epoch))
    
    response_bam_validators=$(fetch_bam "$epoch_number") || {
      echo "Error: Unable to fetch data from BAM Validators API for epoch $epoch_number."
      exit 1
    }
    
    # Pull validators
    bam_validators=$(echo "$response_bam_validators" | jq '.bam_validators // []')
fi

spinner & SPIN_PID=$!

for ((ep=start_epoch; ep<=epoch_number; ep++)); do
  resp=$(fetch_bam "$ep") || continue
  while IFS= read -r va; do
    [ -z "$va" ] && continue
    if [ -z "${earliest_epoch[$va]+x}" ]; then
      earliest_epoch["$va"]="$ep"
    fi
  done < <(echo "$resp" | jq -r '.bam_validators // [] | .[] | select(.is_eligible==true) | .vote_account')
done

cleanup_spinner

# Make a GET request to the Jito BAM Epoch Metrics API with the epoch parameter
response_epoch_metrics=$(curl -s "https://kobe.mainnet.jito.network/api/v1/bam_epoch_metrics?epoch=$epoch_number")

# Error checking
if [ $? -ne 0 ]; then
    echo "Error: Unable to fetch data from BAM Epoch Metrics API."
    exit 1
fi
# Pull metrics
bam_metrics=$(echo "$response_epoch_metrics" | jq '.bam_epoch_metrics')

# Data processing and conversion of lamports into solans and rounding to the first digit after the decimal point
available_bam_delegation_stake=$(echo "$bam_metrics" | jq -r '.available_bam_delegation_stake')
bam_stake=$(echo "$bam_metrics" | jq -r '.bam_stake')
jitosol_stake=$(echo "$bam_metrics" | jq -r '.jitosol_stake')
total_stake=$(echo "$bam_metrics" | jq -r '.total_stake')

# Processing and outputting validators
total_validators=$(echo "$bam_validators" | jq '. | length')
eligible_validators=$(echo "$bam_validators" | jq '[.[] | select(.is_eligible == true)] | length')

# Display summary statistics
echo ""
echo "-------------------------------------------------------------------------------------------------------------------------------------"
if [ $new_epoch -eq 1 ]; then
    echo "No data found for current epoch : $current_epoch"
fi
echo "Data from epoch number          : $epoch_number"
echo "-----------------------------------------------"
echo "Total BAM Validators            : $total_validators"
echo "Eligible BAM Validators         : $eligible_validators"
echo "-----------------------------------------------"
echo "Available BAM Delegation Stake  : $(format_sol $available_bam_delegation_stake)" 
echo "BAM Stake                       : $(format_sol $bam_stake)" 
echo "JitoSOL Stake                   : $(format_sol $jitosol_stake)" 
echo "Total Stake                     : $(format_sol $total_stake)"

# Output formatted table header
echo "-------------------------------------------------------------------------------------------------------------------------------------"
printf "%-5s %-47s %-47s %-15s %-15s\n" "No" "Identity Account" "Vote Account" "Stake, SOL" "Eligible from"
echo "-------------------------------------------------------------------------------------------------------------------------------------"

# Processing Eligible Validators
count=1
echo "$bam_validators" | jq -c '.[] | select(.is_eligible==true) | {identity_account, vote_account, active_stake}' | while IFS= read -r validator; do
  identity_account=$(echo "$validator" | jq -r '.identity_account')
  vote_account=$(echo "$validator" | jq -r '.vote_account')
  active_stake=$(echo "$validator" | jq -r '.active_stake')
  eligible_from="${earliest_epoch[$vote_account]:--}"

  printf "%-5s %-47s %-47s %-15s %-15s\n" "$count" "$identity_account" "$vote_account" "$(format_sol $active_stake)" "$eligible_from"
  count=$((count + 1))
done

echo "-----------------------------------------------------------------------------------------------------------------------------------"

