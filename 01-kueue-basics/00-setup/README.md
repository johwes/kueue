# Setup: Resource Configuration

Configure ResourceFlavors, ClusterQueues, and LocalQueues to enable fair resource sharing between ML training and inference workloads.

## Prerequisites

- Module 00 (Operator installation) complete
- Cluster-admin access to OpenShift

---

## What This Creates

| Resource | Name | Purpose |
|----------|------|---------|
| Namespace | ml-training | Training workload namespace |
| Namespace | ml-inference | Inference workload namespace |
| ResourceFlavor | default-flavor | Standard CPU/memory nodes |
| ClusterQueue | cluster-total | Total resource pool (5 CPUs, 2Gi memory) |
| LocalQueue | ml-training-queue | Training team's queue |
| LocalQueue | ml-inference-queue | Inference team's queue |

---

## Setup Instructions

### Step 1: Create Namespaces

```bash
oc create namespace ml-training
oc create namespace ml-inference
```

### Step 2: Apply All Configuration

```bash
cd 00-setup

# Apply all resources at once
oc apply -f .
```

This creates:
- ResourceFlavor (`default-flavor`)
- ClusterQueue (`cluster-total`) with 5 CPU, 2Gi memory quota
- LocalQueues in both namespaces

### Step 3: Verify Configuration

```bash
# Check all resources created
oc get resourceflavor
oc get clusterqueue
oc get localqueue -A
```

Expected output:
```
NAME             AGE
default-flavor   10s

NAME            COHORT   PENDING WORKLOADS
cluster-total            0

NAMESPACE      NAME                 CLUSTERQUEUE    PENDING WORKLOADS
ml-inference   ml-inference-queue   cluster-total   0
ml-training    ml-training-queue    cluster-total   0
```

---

## Configuration Details

### ResourceFlavor

Defines a type of resource (CPU/memory nodes in this demo):

```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: default-flavor
```

### ClusterQueue

Total resource pool with quota:

```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: cluster-total
spec:
  resourceGroups:
  - flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 5      # 5 CPUs total
      - name: memory
        nominalQuota: 2Gi    # 2Gi memory total
```

### LocalQueues

Namespace-scoped queues for each team:

**Training Queue:**
```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: ml-training-queue
  namespace: ml-training
spec:
  clusterQueue: cluster-total
```

**Inference Queue:**
```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: ml-inference-queue
  namespace: ml-inference
spec:
  clusterQueue: cluster-total
```

---

## Understanding Fair Sharing

Kueue doesn't "pre-allocate" resources to each LocalQueue. Instead:

1. Jobs from any LocalQueue can use available resources
2. When resources are limited, Kueue ensures fair distribution
3. Priority and preemption rules apply
4. Resources are allocated dynamically as jobs are submitted

**Example:** If training submits 6 CPUs worth of jobs but only 5 CPUs exist:
- First 5 CPUs worth are admitted
- Remaining jobs wait in queue
- When production inference arrives, resources are balanced fairly

---

## Troubleshooting

### ClusterQueue Not Ready

```bash
oc get clusterqueue cluster-total -o yaml
# Check status.conditions for errors
```

### LocalQueue Not Mapping

```bash
oc describe localqueue ml-training-queue -n ml-training
# Verify spec.clusterQueue matches ClusterQueue name
```

### ResourceFlavor Not Found

```bash
oc get resourceflavor
# Ensure ResourceFlavor exists before creating ClusterQueue
```

---

## Next Steps

Setup complete! Now run the demos:
1. [01-demo-fair-sharing](../01-demo-fair-sharing/) - Training workloads
2. [02-demo-priorities](../02-demo-priorities/) - Production workloads

---

## Production Considerations

For production deployments:
- Use actual GPU ResourceFlavors (`nvidia.com/gpu`)
- Set quotas based on actual node capacity
- Consider WorkloadPriorityClasses for priority handling
- Enable admission checks for approval workflows
- Use cohorts for resource borrowing between teams

See [Module 02: Borrowing & Preemption](../../02-borrowing-preemption/) for advanced features.
