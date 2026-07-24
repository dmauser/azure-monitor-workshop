// =============================================================================
// alerts/service-health.alerts.bicep
// Scope: resourceGroup
//
// Activity Log alert for Azure Service Health notifications.
// Catches all ServiceHealth events (Incidents, Maintenance, Advisories) on the
// subscription and notifies via email through a dedicated action group.
// Reference: https://learn.microsoft.com/en-us/azure/service-health/alerts-activity-log-service-notifications-bicep
// Cost: $0 — Activity Log alerts and email notifications are free.
// =============================================================================

targetScope = 'resourceGroup'

@description('Email address to notify on Service Health events.')
param emailAddress string

@description('Short prefix used to build resource names.')
param namePrefix string = 'amlab'

@description('Action group short name (max 12 characters).')
@maxLength(12)
param actionGroupShortName string = 'amlabSvcHlth'

// ---------------------------------------------------------------------------
// Action Group — location MUST be Global for Service Health alerts
// ---------------------------------------------------------------------------
resource actionGroup 'microsoft.insights/actionGroups@2019-06-01' = {
  name: 'ag-${namePrefix}-service-health'
  location: 'Global'
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: '${namePrefix}-email'
        emailAddress: emailAddress
        useCommonAlertSchema: false
      }
    ]
    smsReceivers: []
    webhookReceivers: []
  }
}

// ---------------------------------------------------------------------------
// Activity Log Alert — location MUST be Global; scope = subscription
// condition: category == ServiceHealth (all event types)
// ---------------------------------------------------------------------------
resource serviceHealthAlert 'microsoft.insights/activityLogAlerts@2017-04-01' = {
  name: 'alert-${namePrefix}-service-health'
  location: 'Global'
  properties: {
    description: 'Fires on any Azure Service Health event (Incident / Maintenance / Advisory / Security) for subscription ${subscription().subscriptionId}.'
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
          webhookProperties: {}
        }
      ]
    }
    enabled: true
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
@description('Resource ID of the Service Health action group.')
output actionGroupId string = actionGroup.id

@description('Resource ID of the Service Health activity log alert.')
output alertId string = serviceHealthAlert.id

@description('Name of the activity log alert.')
output alertName string = serviceHealthAlert.name

@description('Name of the action group.')
output actionGroupName string = actionGroup.name
