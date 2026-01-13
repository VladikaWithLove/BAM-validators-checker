# BAM-validators-checker
#
# The script is under active development. This is far from the final version. Stay tuned!
#
# Bash script to display Jito-stake, BAM-stake and all Eligible BAM validators and their stake 🥩 value's. The script also shows from which epoch the validator became Eligible for BAM delegation. 
# Data is taken from the Jito BAM API
#
# Plans to add JIP-31 BAM Early Adopter Incentive data
# USAGE
# 1. Move file check-bam-validators.sh to your server  
# 2. chmod u+x ./check-bam-validators.sh
# 3. ./check-bam-validators.sh <epoch_number> - run this script on your server. If you do not specify an epoch number, the data for the current epoch will be returned. However, it should be remembered that the Jito API is updated with a large delay, and the data for the current epoch becomes available after about half an epoch.
# If the data for the current epoch is not available, the script displays the data for the previous epoch.
