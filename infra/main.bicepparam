using './main.bicep'

param location = 'southcentralus'
param namePrefix = 'amlab'
// principalId: set at deploy time via --parameters principalId=<objectId>
//              or leave empty to skip Monitor Metrics Publisher role assignment
