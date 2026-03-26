# Module 01: Resource Configuration

This module demonstrates how to configure Kueue resources to solve the GPU sharing challenge between ML training and inference workloads.

## The Resource Allocation Challenge

Your organization has invested in GPU infrastructure for ML workloads. The challenge: **How do you allocate these expensive resources fairly between two competing needs?**

### ML Training (Experimentation)
- **Needs**: Large resource bursts for model training
- **Pattern**: Unpredictable, bursty workload
- **Tolerance**: Can wait in queue during busy periods
- **Priority**: Lower (innovation vs. production)

### ML Inference (Production)
- **Needs**: Guaranteed resources for customer SLAs
- **Pattern**: Predictable, scheduled batch jobs
- **Tolerance**: Cannot be starved of resources
- **Priority**: Higher (production-critical)

## Resource Configuration Strategy

We'll configure Kueue to solve this by:
1. **Total GPU pool**: Defined in ClusterQueue with fixed quota
2. **Production guarantee**: Inference workloads get priority access
3. **Fair sharing**: Training uses idle capacity without blocking production
4. **Transparent queueing**: Visibility into admission decisions

## Overview

In this module, you'll create:
1. **ResourceFlavors** - Define GPU/CPU resource types
2. **ClusterQueue** - Total resource pool available for ML workloads
3. **LocalQueues** - Separate queues for training vs. inference with different priorities

## Architecture

```
ResourceFlavor (default-flavor)
         ↓
ClusterQueue (gpu-cluster-total)
    ├── Total: 5 CPUs, 2Gi memory
    │   (In production: GPUs would be managed here)
    │
    ├──→ LocalQueue (ml-training-queue)
    │    └── Namespace: ml-training
    │         Purpose: Model training, experiments
    │         Can tolerate queueing
    │
    └──→ LocalQueue (ml-inference-queue)
         └── Namespace: ml-inference
              Purpose: Production batch inference
              Needs guaranteed access
```

**Note:** This demo uses CPU resources for portability. In production, you'd configure GPU ResourceFlavors (e.g., `nvidia.com/gpu`) using the same Kueue patterns.

## Step 1: Create Namespaces

Create separate namespaces for ML training and inference workloads:

```bash
oc create namespace ml-training
oc create namespace ml-inference
```

**Important:** Namespaces must have the label `kueue.openshift.io/managed=true` for Kueue to process workloads in them. Our YAML files include this label.

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
  - CPU: 5 cores (primary resource for queueing demonstration)
  - Memory: 2Gi (kept minimal for cost efficiency at scale)
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
oc apply -f localqueue-ml-training.yaml
oc apply -f localqueue-ml-inference.yaml
```

**LocalQueue Configuration:**

**ml-training-queue:**
- Namespace: `ml-training`
- ClusterQueue: `cluster-total`
- Purpose: Experimentation, model training, hyperparameter tuning
- Behavior: Can use idle resources, tolerates queueing

**ml-inference-queue:**
- Namespace: `ml-inference`
- ClusterQueue: `cluster-total`
- Purpose: Production batch inference, customer-facing workloads
- Behavior: Priority access to ensure SLA compliance

Note: LocalQueues don't define quotas themselves; they inherit from the ClusterQueue and compete fairly based on the ClusterQueue's fairness and priority policies.

View LocalQueues:
```bash
oc get localqueue -n ml-training
oc get localqueue -n ml-inference
oc describe localqueue ml-training-queue -n ml-training
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

### Example Scenario: Production vs. Training

**Scenario 1: Training Saturates the Cluster**
If ML training team submits multiple training jobs (6 CPUs total) when only 5 CPUs are available:
1. First 5 CPUs worth of training jobs are admitted
2. Remaining training jobs wait in queue
3. When production inference job arrives, Kueue admits it fairly
4. Resources are balanced between production and training needs

**Scenario 2: Production Gets Priority**
If production inference jobs need guaranteed resources:
1. Configure WorkloadPriorityClasses (covered in advanced usage)
2. Production jobs can preempt lower-priority training jobs
3. Training experiments resume when production workload completes
4. This ensures SLA compliance for customer-facing workloads

## Configuration Files Reference

| File | Purpose | Scope |
|------|---------|-------|
| `resourceflavor.yaml` | Defines resource types (GPU/CPU) | Cluster |
| `clusterqueue.yaml` | Total ML resource pool | Cluster |
| `localqueue-ml-training.yaml` | Training workload queue | Namespace |
| `localqueue-ml-inference.yaml` | Inference workload queue | Namespace |

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
oc describe localqueue ml-training-queue -n ml-training
# Verify spec.clusterQueue matches ClusterQueue name
```

### ResourceFlavor not found

```bash
oc get resourceflavor
# Ensure ResourceFlavor exists before creating ClusterQueue
```

## Next Steps

Now that your resource configuration is complete, proceed to [02-workload-kueue-basics](../02-workload-kueue-basics/README.md) to submit sample jobs and see Kueue in action!

## Additional Resources

- [Kueue Resource Concepts](https://kueue.sigs.k8s.io/docs/concepts/)
- [ClusterQueue Configuration](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/)
- [ResourceFlavor Documentation](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)
