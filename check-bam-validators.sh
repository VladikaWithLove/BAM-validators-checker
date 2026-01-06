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

# Make a GET request to the Jito BAM Validators API with the epoch parameter
response_bam_validators=$(curl -s "https://kobe.mainnet.jito.network/api/v1/bam_validators?epoch=$epoch_number")

# Error checking
if [ $? -ne 0 ]; then
    echo "Error: Unable to fetch data from BAM Validators API."
    exit 1
fi

# Make a GET request to the Jito BAM Epoch Metrics API with the epoch parameter
response_epoch_metrics=$(curl -s "https://kobe.mainnet.jito.network/api/v1/bam_epoch_metrics?epoch=$epoch_number")

# Error checking
if [ $? -ne 0 ]; then
    echo "Error: Unable to fetch data from BAM Epoch Metrics API."
    exit 1
fi

# Output the received answer
echo "Response from BAM Validators API with epoch $epoch_number:"
echo "$response_bam_validators" | jq .

echo ""

# Output the received answer
echo "Response from BAM Epoch Metrics API with epoch $epoch_number:"
echo "$response_epoch_metrics" | jq .

# Pull metrics
bam_metrics=$(echo "$response_epoch_metrics" | jq '.bam_epoch_metrics')

# Data processing and conversion of lamports into solans and rounding to the first digit after the decimal point
available_bam_delegation_stake=$(printf "%.1f" $(echo "$bam_metrics" | jq -r '.available_bam_delegation_stake') )
bam_stake=$(printf "%.1f" $(echo "$bam_metrics" | jq -r '.bam_stake') )
jitosol_stake=$(printf "%.1f" $(echo "$bam_metrics" | jq -r '.jitosol_stake') )
total_stake=$(printf "%.1f" $(echo "$bam_metrics" | jq -r '.total_stake') )

# Pull validators
bam_validators=$(echo "$response_bam_validators" | jq '.bam_validators')

# Checking for validators
if [ "$(echo "$bam_validators" | jq -r 'length')" -eq 0 ]; then
    echo "No BAM Validators found for epoch $epoch_number."
    exit 0
fi

# Processing and outputting validators
total_validators=$(echo "$bam_validators" | jq '. | length')
eligible_validators=$(echo "$bam_validators" | jq '[.[] | select(.is_eligible == true)] | length')

# Display summary statistics
echo ""
echo "-----------------------------------------------------------------------------------------------------------------------"
echo "Epoch number            : $epoch_number"
echo "------------------------------"
echo "Total BAM Validators    : $total_validators"
echo "Eligible BAM Validators : $eligible_validators"
echo "------------------------------"
echo "Available BAM Delegation Stake : $(format_sol $available_bam_delegation_stake)" 
echo "BAM Stake                      : $(format_sol $bam_stake)" 
echo "JitoSOL Stake                  : $(format_sol $jitosol_stake)" 
echo "Total Stake                    : $(format_sol $total_stake)"


# Output formatted table header
echo "-----------------------------------------------------------------------------------------------------------------------"
printf "%-5s %-47s %-47s %-15s\n" "No" "Identity Account" "Vote Account" "Active Stake, SOL"
echo "-----------------------------------------------------------------------------------------------------------------------"

# Processing Eligible Validators
count=1
echo "$bam_validators" | jq -c '.[] | select(.is_eligible == true) | {identity_account, vote_account, active_stake}' | while IFS= read -r validator; do
    identity_account=$(echo "$validator" | jq -r '.identity_account')
    vote_account=$(echo "$validator" | jq -r '.vote_account')
    active_stake=$(echo "$validator" | jq -r '.active_stake')
    
    printf "%-5s %-47s %-47s %-17s\n" "$count" "$identity_account" "$vote_account" "$(format_sol $active_stake)"
    ((count++))
done

echo "-----------------------------------------------------------------------------------------------------------------------"
