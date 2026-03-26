# Module 01: Resource Configuration

This module demonstrates how to configure Kueue resources to enable fair resource sharing between teams.

## Overview

In this module, you'll create:
1. **ResourceFlavors** - Define types of resources available in the cluster
2. **ClusterQueue** - Create a cluster-wide resource pool
3. **LocalQueues** - Create team-specific queues that map to the ClusterQueue

## Architecture

```
ResourceFlavor (default-flavor)
         ↓
ClusterQueue (cluster-total)
    ├── Quota: 10 CPUs, 20Gi memory
    │
    ├──→ LocalQueue (team-alpha-queue)
    │    └── Namespace: team-alpha
    │         Guaranteed: 6 CPUs, 12Gi memory
    │
    └──→ LocalQueue (team-beta-queue)
         └── Namespace: team-beta
              Guaranteed: 4 CPUs, 8Gi memory
```

## Step 1: Create Namespaces

First, create separate namespaces for each team:

```bash
oc create namespace team-alpha
oc create namespace team-beta
```

## Step 2: Create ResourceFlavor

A ResourceFlavor represents a type of resource in your cluster. For this demo, we'll create a single "default-flavor" representing standard CPU/memory nodes.

```bash
oc apply -f resourceflavor.yaml
```

**resourceflavor.yaml** defines:
- Name: `default-flavor`
- No node selectors (uses any available nodes)

In production, you might create multiple flavors for:
- GPU nodes (`gpu-flavor`)
- High-memory nodes (`highmem-flavor`)
- Specific zones (`zone-a-flavor`)

View the created ResourceFlavor:
```bash
oc get resourceflavor
oc describe resourceflavor default-flavor
```

## Step 3: Create ClusterQueue

The ClusterQueue defines the total pool of resources available for sharing. It references ResourceFlavors and sets quota limits.

```bash
oc apply -f clusterqueue.yaml
```

**clusterqueue.yaml** defines:
- Name: `cluster-total`
- Resource limits:
  - CPU: 10 cores
  - Memory: 20Gi
- Uses ResourceFlavor: `default-flavor`
- Preemption: Enabled with `LowerPriority` policy

Key concepts:
- **Nominal Quota**: Guaranteed resources for each flavor
- **Borrowing**: Can borrow unused resources from other queues (disabled in this demo)
- **Preemption**: Can evict lower-priority workloads when needed

View the ClusterQueue status:
```bash
oc get clusterqueue
oc describe clusterqueue cluster-total
```

The status shows:
- Total resources
- Used resources
- Admitted workloads
- Pending workloads

## Step 4: Create LocalQueues

LocalQueues are namespace-scoped and map to a ClusterQueue. Teams submit jobs to their LocalQueue.

```bash
oc apply -f localqueue-team-alpha.yaml
oc apply -f localqueue-team-beta.yaml
```

**LocalQueue Configuration:**

**team-alpha-queue:**
- Namespace: `team-alpha`
- ClusterQueue: `cluster-total`
- Higher allocation (60% of cluster resources)

**team-beta-queue:**
- Namespace: `team-beta`
- ClusterQueue: `cluster-total`
- Lower allocation (40% of cluster resources)

Note: LocalQueues don't define quotas themselves; they inherit from the ClusterQueue and compete fairly based on the ClusterQueue's fairness policy.

View LocalQueues:
```bash
oc get localqueue -n team-alpha
oc get localqueue -n team-beta
oc describe localqueue team-alpha-queue -n team-alpha
```

## Step 5: Verify Configuration

Check that all resources are properly configured:

```bash
# List all Kueue resources
oc get resourceflavor
oc get clusterqueue
oc get localqueue -A

# Detailed status
oc describe clusterqueue cluster-total
```

Expected output:
```
NAME            COHORT   PENDING WORKLOADS   ADMITTED WORKLOADS
cluster-total            0                   0
```

## Understanding Resource Allocation

### Fair Sharing Model

Kueue doesn't "pre-allocate" resources to each LocalQueue. Instead:
1. Jobs from any LocalQueue can use available resources
2. When resources are limited, Kueue ensures fair distribution
3. Priority and preemption rules apply
4. Resources are allocated dynamically as jobs are submitted

### Example Scenario

If team-alpha submits jobs requesting 15 CPUs when only 10 are available:
1. First 10 CPUs worth of jobs are admitted
2. Remaining jobs wait in queue
3. When team-beta's jobs complete, freed resources go to waiting jobs
4. If both teams have pending jobs, resources are shared fairly

## Configuration Files Reference

| File | Purpose | Scope |
|------|---------|-------|
| `resourceflavor.yaml` | Defines resource types | Cluster |
| `clusterqueue.yaml` | Creates resource pool | Cluster |
| `localqueue-team-alpha.yaml` | Team Alpha's queue | Namespace |
| `localqueue-team-beta.yaml` | Team Beta's queue | Namespace |

## Advanced Options (Not Covered)

For production use, consider:
- **WorkloadPriorityClasses**: Define priority levels
- **AdmissionChecks**: Add approval gates
- **Multiple ResourceFlavors**: Separate GPU, CPU, memory tiers
- **Cohorts**: Share resources between multiple ClusterQueues
- **Borrowing**: Allow temporary over-quota usage

## Troubleshooting

### ClusterQueue not ready

```bash
oc get clusterqueue cluster-total -o yaml
# Check status.conditions for errors
```

### LocalQueue not mapping to ClusterQueue

```bash
oc describe localqueue team-alpha-queue -n team-alpha
# Verify spec.clusterQueue matches ClusterQueue name
```

### ResourceFlavor not found

```bash
oc get resourceflavor
# Ensure ResourceFlavor exists before creating ClusterQueue
```

## Next Steps

Now that your resource configuration is complete, proceed to [02-workloads](../02-workloads/README.md) to submit sample jobs and see Kueue in action!

## Additional Resources

- [Kueue Resource Concepts](https://kueue.sigs.k8s.io/docs/concepts/)
- [ClusterQueue Configuration](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/)
- [ResourceFlavor Documentation](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)
