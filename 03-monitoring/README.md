# Module 03: Monitoring and Observability

This module covers how to monitor Kueue resources, troubleshoot issues, and understand the state of your queues and workloads.

## Overview

Learn how to:
1. Monitor ClusterQueue and LocalQueue status
2. Track workload admission and lifecycle
3. Diagnose pending workloads
4. View resource utilization
5. Troubleshoot common issues

## Quick Monitoring Commands

### ClusterQueue Status

```bash
# List all ClusterQueues
oc get clusterqueue

# Detailed ClusterQueue status
oc describe clusterqueue cluster-total

# Watch ClusterQueue in real-time
watch -n 2 "oc get clusterqueue"

# Get ClusterQueue YAML with status
oc get clusterqueue cluster-total -o yaml
```

Key status fields:
- **admittedWorkloads**: Number of currently running workloads
- **pendingWorkloads**: Number of workloads waiting for resources
- **reservingWorkloads**: Workloads with reserved quota
- **flavorsReservation**: Resources used per ResourceFlavor
- **conditions**: Health and readiness status

### LocalQueue Status

```bash
# List LocalQueues in all namespaces
oc get localqueue -A

# List LocalQueues in specific namespace
oc get localqueue -n team-alpha

# Detailed LocalQueue status
oc describe localqueue team-alpha-queue -n team-alpha

# Watch LocalQueues
watch -n 2 "oc get localqueue -A"
```

Key information:
- **ClusterQueue**: Which ClusterQueue this LocalQueue maps to
- **PendingWorkloads**: Number of queued workloads
- **AdmittedWorkloads**: Number of active workloads
- **Conditions**: Connection status to ClusterQueue

### Workload Status

```bash
# List all workloads across namespaces
oc get workload -A

# List workloads in specific namespace
oc get workload -n team-alpha

# Detailed workload information
oc describe workload -n team-alpha <workload-name>

# Watch workload changes
watch -n 2 "oc get workload -A"

# Get workload conditions
oc get workload -n team-alpha <workload-name> -o jsonpath='{.status.conditions}' | jq
```

Workload states:
- **QuotaReserved**: Resources have been allocated
- **Admitted**: Workload can run (pods can be created)
- **Finished**: Workload has completed
- **Evicted**: Workload was preempted

### Jobs and Pods

```bash
# List jobs in namespace
oc get jobs -n team-alpha

# Watch job status
watch -n 2 "oc get jobs -n team-alpha"

# List pods for a specific job
oc get pods -n team-alpha -l job-name=job-data-processing

# View pod logs
oc logs -n team-alpha <pod-name>

# Follow pod logs in real-time
oc logs -f -n team-alpha <pod-name>
```

## Monitoring Scripts

We provide helper scripts for common monitoring tasks.

### monitor.sh - Interactive Dashboard

Displays a real-time overview of all Kueue resources:

```bash
./monitor.sh
```

Shows:
- ClusterQueue status and utilization
- LocalQueue status for all namespaces
- Active and pending workloads
- Recent job activity

### check-queue-status.sh - Queue Health Check

Checks the health of queues and reports any issues:

```bash
./check-queue-status.sh
```

Reports:
- ClusterQueue readiness
- LocalQueue connectivity
- Pending workload reasons
- Resource availability

### watch-workloads.sh - Workload Tracker

Tracks workload lifecycle with timestamps:

```bash
./watch-workloads.sh [namespace]
```

Displays:
- Workload creation time
- Admission status
- Resource requests
- Queue assignment

## Understanding Resource Utilization

### View ClusterQueue Resource Usage

```bash
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'
```

Example output:
```json
[
  {
    "name": "default-flavor",
    "resources": [
      {
        "name": "cpu",
        "total": "10",
        "borrowed": "0",
        "used": "6"
      },
      {
        "name": "memory",
        "total": "20Gi",
        "borrowed": "0",
        "used": "12Gi"
      }
    ]
  }
]
```

This shows:
- **total**: Total quota available
- **used**: Currently allocated resources
- **borrowed**: Resources borrowed from other queues (if enabled)

### Calculate Available Resources

```bash
# CPU available
oc get clusterqueue cluster-total -o jsonpath='{.status.flavorsReservation[0].resources[?(@.name=="cpu")]}' | jq

# Memory available
oc get clusterqueue cluster-total -o jsonpath='{.status.flavorsReservation[0].resources[?(@.name=="memory")]}' | jq
```

## Troubleshooting Workflows

### Why is my workload pending?

**Step 1**: Check workload status
```bash
oc describe workload -n team-alpha <workload-name>
```

Look for conditions explaining why it's pending:
- `ClusterQueueNotFound`: LocalQueue references non-existent ClusterQueue
- `NotNominatedByClusterQueue`: Insufficient resources in ClusterQueue
- `CheckNotAvailable`: AdmissionCheck is blocking admission

**Step 2**: Check ClusterQueue capacity
```bash
oc describe clusterqueue cluster-total
```

Look at `flavorsReservation` to see if quota is exhausted.

**Step 3**: Check LocalQueue connection
```bash
oc describe localqueue team-alpha-queue -n team-alpha
```

Ensure the LocalQueue is properly connected to the ClusterQueue.

### Why did my workload get evicted?

**Check preemption events**:
```bash
oc get events -n team-alpha --sort-by='.lastTimestamp' | grep -i preempt
```

**Check workload history**:
```bash
oc describe workload -n team-alpha <workload-name>
```

Look for `Evicted` condition with reason (e.g., `Preempted`, `PodsReadyTimeout`).

Common reasons:
- Higher-priority workload needed resources
- ClusterQueue reconfiguration
- Admitted workload failed to start pods in time

### Why aren't my pods starting?

**Even if workload is admitted, pods might not start due to**:

1. **Insufficient actual cluster resources**
```bash
oc get nodes
oc describe node <node-name>
```

Kueue reserves quota, but actual node capacity might be exhausted.

2. **Image pull issues**
```bash
oc describe pod -n team-alpha <pod-name>
```

3. **Security policies**
```bash
oc get events -n team-alpha --sort-by='.lastTimestamp'
```

## Monitoring Best Practices

### Regular Health Checks

```bash
# Daily queue status check
oc get clusterqueue
oc get localqueue -A

# Check for stuck workloads (pending >10 minutes)
oc get workload -A -o json | jq '.items[] | select(.status.conditions[] | select(.type=="QuotaReserved" and .status=="False")) | {name: .metadata.name, namespace: .metadata.namespace, age: .metadata.creationTimestamp}'
```

### Set Up Alerts

For production environments, consider monitoring:
- ClusterQueue utilization >90%
- Workloads pending >30 minutes
- Eviction rate
- Failed job rate

### Logging and Events

```bash
# Kueue controller logs
oc logs -n openshift-operators deployment/kueue-controller-manager -c manager

# Recent events across all namespaces
oc get events -A --sort-by='.lastTimestamp' | grep -i kueue

# Events for specific resource
oc describe clusterqueue cluster-total
```

## Useful One-Liners

```bash
# Count pending workloads per namespace
oc get workload -A -o json | jq -r '.items[] | select(.status.admission == null) | .metadata.namespace' | sort | uniq -c

# List all jobs with their queue assignment
oc get jobs -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) -> \(.metadata.labels["kueue.x-k8s.io/queue-name"] // "no-queue")"'

# Show resource requests for all admitted workloads
oc get workload -A -o json | jq -r '.items[] | select(.status.admission != null) | {name: .metadata.name, cpu: .spec.podSets[0].count, requests: .status.admission.podSetAssignments[0].resourceUsage}'

# Find workloads in a specific ClusterQueue
oc get workload -A -o json | jq -r '.items[] | select(.status.admission.clusterQueue == "cluster-total") | "\(.metadata.namespace)/\(.metadata.name)"'

# List all ResourceFlavors with their resources
oc get resourceflavor -o json | jq -r '.items[] | {name: .metadata.name, nodeLabels: .spec.nodeLabels}'
```

## Cleanup Commands

```bash
# Delete all completed jobs in team-alpha
oc delete jobs -n team-alpha --field-selector status.successful=1

# Delete all jobs in team-beta
oc delete jobs -n team-beta --all

# Clean up all demo resources
cd ../01-resource-configuration
oc delete -f .
```

## Performance Metrics

Track Kueue performance:

```bash
# Time from job creation to admission
oc get workload -A -o json | jq -r '.items[] | select(.status.admission != null) | {name: .metadata.name, created: .metadata.creationTimestamp, admitted: .status.conditions[] | select(.type=="Admitted") | .lastTransitionTime}'

# Average queue time
# (requires manual calculation or external monitoring)
```

## Advanced Monitoring

### Prometheus Metrics

If Prometheus is enabled, Kueue exposes metrics:
- `kueue_admission_wait_time_seconds`
- `kueue_cluster_queue_resource_usage`
- `kueue_pending_workloads`
- `kueue_admitted_workloads_total`

### Custom Dashboard

Create a custom dashboard script combining multiple views:
```bash
./monitor.sh
```

## Next Steps

You've completed the Kueue learning path! You now understand:
- How to install Red Hat Build of Kueue
- How to configure ResourceFlavors, ClusterQueues, and LocalQueues
- How to submit jobs to Kueue-managed queues
- How to monitor and troubleshoot Kueue resources

### Further Exploration

- Implement WorkloadPriorityClasses for priority-based scheduling
- Configure AdmissionChecks for approval workflows
- Set up Cohorts for resource sharing between ClusterQueues
- Enable borrowing for flexible resource allocation
- Integrate with OpenShift AI workloads

## Additional Resources

- [Kueue Monitoring Documentation](https://kueue.sigs.k8s.io/docs/tasks/manage/monitor_pending_workloads/)
- [Kueue Troubleshooting Guide](https://kueue.sigs.k8s.io/docs/tasks/troubleshooting/)
- [OpenShift Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html)
