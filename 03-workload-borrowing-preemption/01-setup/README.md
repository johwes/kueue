# Setup: Cohorts, Borrowing, and Priority

This setup creates the foundation for resource borrowing and preemption between Training and Inference teams.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Cohort: "ml-shared-pool"                                   │
│  (Resource-sharing club for Training and Inference)         │
└────────────────────┬────────────────────────────────────────┘
                     │
            ┌────────┴────────┐
            │                 │
┌───────────▼──────────┐  ┌───▼──────────────┐
│ ClusterQueue         │  │ ClusterQueue     │
│ training-cluster     │  │ inference-cluster│
│                      │  │                  │
│ Nominal: 3 CPUs      │  │ Nominal: 2 CPUs  │
│ Can borrow from      │  │ Can borrow from  │
│ inference            │  │ training         │
│                      │  │                  │
│ Priority: Low jobs   │  │ Priority: High   │
│ (can be preempted)   │  │ (can preempt)    │
└──────────┬───────────┘  └────┬─────────────┘
           │                   │
    ┌──────▼─────┐      ┌──────▼─────┐
    │LocalQueue  │      │LocalQueue  │
    │ml-training │      │ml-inference│
    └────────────┘      └────────────┘
```

**Key Design:**
- **Total Cluster Capacity:** 5 CPUs (mimics 10 GPUs in production)
- **Training Nominal:** 3 CPUs (60% of cluster)
- **Inference Nominal:** 2 CPUs (40% of cluster)
- **Borrowing Enabled:** Both can borrow from each other within cohort
- **Preemption Enabled:** High-priority inference can reclaim resources

---

## Configuration Components

### 1. Cohort (Resource-Sharing Club)

A Cohort allows multiple ClusterQueues to share resources:

**File:** `cohort.yaml`

**What it does:**
- Defines "ml-shared-pool" as a resource-sharing group
- ClusterQueues in this cohort can borrow each other's idle quota
- Enables preemption when borrowed resources need to be reclaimed

**Note:** The cohort itself doesn't have a YAML file - it's referenced by name in ClusterQueue configurations.

---

### 2. ClusterQueue: training-cluster-queue

**File:** `clusterqueue-training.yaml`

**Configuration:**
- **Nominal Quota:** 3 CPUs, 512Mi memory
- **Cohort:** ml-shared-pool
- **Borrowing Policy:** Can borrow idle resources from inference
- **Preemption:** Can be preempted by higher-priority workloads

**Borrowing Behavior:**
```
Scenario 1: Inference idle (2 CPUs available to borrow)
  Training can use: 3 (own) + 2 (borrowed) = 5 CPUs total

Scenario 2: Inference busy (0 CPUs available)
  Training limited to: 3 CPUs (own quota only)
```

---

### 3. ClusterQueue: inference-cluster-queue

**File:** `clusterqueue-inference.yaml`

**Configuration:**
- **Nominal Quota:** 2 CPUs, 256Mi memory
- **Cohort:** ml-shared-pool
- **Borrowing Policy:** Can borrow idle resources from training
- **Preemption:** Can preempt lower-priority workloads to reclaim resources

**Borrowing Behavior:**
```
Scenario 1: Training idle (3 CPUs available to borrow)
  Inference can use: 2 (own) + 3 (borrowed) = 5 CPUs total

Scenario 2: Training using borrowed resources
  Inference can reclaim by preempting training jobs
```

---

### 4. WorkloadPriorityClass: low-priority

**File:** `workloadpriorityclass-low.yaml`

**Configuration:**
- **Name:** low-priority
- **Value:** 100
- **Description:** Training experiments (can be preempted)

**Usage:** Assign to training jobs that can tolerate interruption:
```yaml
metadata:
  labels:
    kueue.x-k8s.io/priority-class: low-priority
```

---

### 5. WorkloadPriorityClass: high-priority

**File:** `workloadpriorityclass-high.yaml`

**Configuration:**
- **Name:** high-priority
- **Value:** 1000
- **Description:** Production inference (can preempt others)

**Usage:** Assign to production inference jobs that need guaranteed resources:
```yaml
metadata:
  labels:
    kueue.x-k8s.io/priority-class: high-priority
```

**Priority Comparison:**
```
high-priority (1000) > low-priority (100)

When resources are limited:
- High-priority jobs can preempt low-priority jobs
- Low-priority jobs cannot preempt high-priority jobs
```

---

### 6. PersistentVolumeClaim: training-checkpoint-pvc

**File:** `pvc-checkpoint.yaml`

**Configuration:**
- **Name:** training-checkpoint-pvc
- **Namespace:** ml-training
- **Size:** 100Mi (tiny - just for text logfiles)
- **Access Mode:** ReadWriteOnce

**Purpose:**
- Store training checkpoint data (progress logs)
- Enable job resume after preemption
- Survive pod deletion and restart

**Cost-Efficient Design:**
- Uses minimal storage (100Mi = $0.01/month)
- Shared across multiple training jobs via subpaths
- Automatically provisioned via dynamic PVC

---

## Setup Instructions

### Step 1: Verify Prerequisites

Ensure Module 01 & 02 setup is complete:

```bash
# Verify namespaces exist
oc get namespace ml-training ml-inference

# Verify previous ClusterQueue and LocalQueues exist
oc get clusterqueue cluster-total
oc get localqueue -n ml-training
oc get localqueue -n ml-inference
```

**Important:** Module 03 creates **new** ClusterQueues. You'll temporarily have 2 different cluster configurations:
- Module 02: `cluster-total` (single ClusterQueue, no borrowing)
- Module 03: `training-cluster-queue` + `inference-cluster-queue` (cohort-based, with borrowing)

---

### Step 2: Create Cohort-Based ClusterQueues

```bash
cd 01-setup

# Create training ClusterQueue (3 CPUs, can borrow)
oc apply -f clusterqueue-training.yaml

# Create inference ClusterQueue (2 CPUs, can preempt)
oc apply -f clusterqueue-inference.yaml

# Verify both ClusterQueues are active
oc get clusterqueue
```

Expected output:
```
NAME                      COHORT           PENDING WORKLOADS
cluster-total                              0                    ← From Module 02
training-cluster-queue    ml-shared-pool   0                    ← New!
inference-cluster-queue   ml-shared-pool   0                    ← New!
```

**Key observation:** Both new ClusterQueues show the same COHORT name, enabling resource sharing.

---

### Step 3: Create LocalQueues Pointing to New ClusterQueues

We need to update the LocalQueues to point to the cohort-based ClusterQueues:

```bash
# Update training LocalQueue to use new ClusterQueue
oc patch localqueue ml-training-queue -n ml-training --type='merge' -p '{"spec":{"clusterQueue":"training-cluster-queue"}}'

# Update inference LocalQueue to use new ClusterQueue
oc patch localqueue ml-inference-queue -n ml-inference --type='merge' -p '{"spec":{"clusterQueue":"inference-cluster-queue"}}'

# Verify the updates
oc get localqueue -n ml-training -o yaml | grep clusterQueue
oc get localqueue -n ml-inference -o yaml | grep clusterQueue
```

Expected output:
```
clusterQueue: training-cluster-queue
clusterQueue: inference-cluster-queue
```

---

### Step 4: Create WorkloadPriorityClasses

```bash
# Create low-priority class (for training)
oc apply -f workloadpriorityclass-low.yaml

# Create high-priority class (for inference)
oc apply -f workloadpriorityclass-high.yaml

# Verify priority classes
oc get workloadpriorityclass
```

Expected output:
```
NAME             VALUE
low-priority     100
high-priority    1000
```

**Priority Rules:**
- Higher value = higher priority
- Jobs with `high-priority` (1000) can preempt jobs with `low-priority` (100)

---

### Step 5: Create Checkpoint Storage

```bash
# Create PVC for training checkpoints
oc apply -f pvc-checkpoint.yaml

# Verify PVC is bound
oc get pvc -n ml-training
```

Expected output:
```
NAME                        STATUS   VOLUME                    CAPACITY   ACCESS MODES
training-checkpoint-pvc     Bound    pvc-xxxxx-xxxx-xxxx       100Mi      RWO
```

**Note:** If STATUS shows "Pending", your cluster might not have dynamic provisioning. Check with your cluster administrator.

---

### Step 6: Verify Complete Setup

```bash
# Check all Kueue resources
echo "=== ClusterQueues ==="
oc get clusterqueue

echo ""
echo "=== LocalQueues ==="
oc get localqueue -A

echo ""
echo "=== WorkloadPriorityClasses ==="
oc get workloadpriorityclass

echo ""
echo "=== Checkpoint PVC ==="
oc get pvc -n ml-training training-checkpoint-pvc
```

Expected summary:
```
✅ 3 ClusterQueues (cluster-total + 2 cohort-based)
✅ 2 LocalQueues pointing to cohort ClusterQueues
✅ 2 WorkloadPriorityClasses (low=100, high=1000)
✅ 1 PVC bound and ready
```

---

## Understanding the Configuration

### Cohort Resource Sharing

**Total Available Resources:**
```
training-cluster-queue: 3 CPUs
inference-cluster-queue: 2 CPUs
Total in cohort: 5 CPUs
```

**Borrowing Matrix:**

| Team | Nominal Quota | Can Borrow Up To | Max Possible |
|------|---------------|------------------|--------------|
| Training | 3 CPUs | 2 CPUs (from inference) | 5 CPUs |
| Inference | 2 CPUs | 3 CPUs (from training) | 5 CPUs |

**Important:** Both teams **cannot** borrow simultaneously. The cohort has 5 CPUs total.

---

### Preemption Policies

**Defined in ClusterQueues:**

```yaml
preemption:
  reclaimWithinCohort: Any          # Can reclaim borrowed resources
  borrowWithinCohort:
    policy: Never                   # Conservative borrowing
  withinClusterQueue: LowerPriority # Preempt within own queue by priority
```

**What this means:**

1. **reclaimWithinCohort: Any**
   - Inference can reclaim its 2 CPUs from Training at any time
   - Training can reclaim its 3 CPUs from Inference at any time

2. **borrowWithinCohort: Never**
   - Conservative: don't preempt other queues' nominal quota
   - Only use truly idle resources

3. **withinClusterQueue: LowerPriority**
   - Within same queue, high-priority jobs preempt low-priority jobs

---

### Memory Efficiency Note

**All memory requests kept minimal for cost efficiency:**
- Training jobs: 128Mi per job
- Inference jobs: 64Mi per job
- Checkpoint PVC: 100Mi total

**Why this matters:**
- At scale (100 users): Only 6-12GB memory total
- Vs. 512Mi/job: Would be 50-100GB (8x more expensive!)
- Keeps workshop costs low while teaching concepts

---

## Troubleshooting

### LocalQueue Not Updating

**Problem:** LocalQueue still points to old ClusterQueue

**Solution:**
```bash
# Force delete and recreate
oc delete localqueue ml-training-queue -n ml-training
oc apply -f ../01-resource-configuration/localqueue-ml-training.yaml

# Update clusterQueue field
oc patch localqueue ml-training-queue -n ml-training --type='merge' -p '{"spec":{"clusterQueue":"training-cluster-queue"}}'
```

### PVC Pending

**Problem:** PVC stuck in "Pending" status

**Diagnosis:**
```bash
oc describe pvc training-checkpoint-pvc -n ml-training
```

**Common causes:**
- No dynamic provisioning available
- No storage class defined
- Insufficient cluster storage

**Workaround:** Use emptyDir instead (loses data on pod restart, but works for demo):
```yaml
volumes:
- name: checkpoint
  emptyDir: {}
```

### Cohort Not Working

**Problem:** Borrowing not happening

**Check:**
```bash
# Verify both ClusterQueues have same cohort name
oc get clusterqueue training-cluster-queue -o jsonpath='{.spec.cohort}'
oc get clusterqueue inference-cluster-queue -o jsonpath='{.spec.cohort}'

# Both should output: ml-shared-pool
```

---

## Next Steps

Setup complete! Proceed to [02-demo-borrowing](../02-demo-borrowing/README.md) to see resource borrowing in action.

---

## Configuration Files Reference

| File | Purpose | Scope |
|------|---------|-------|
| `clusterqueue-training.yaml` | Training team's queue (3 CPUs) | Cluster |
| `clusterqueue-inference.yaml` | Inference team's queue (2 CPUs) | Cluster |
| `workloadpriorityclass-low.yaml` | Priority for training (100) | Cluster |
| `workloadpriorityclass-high.yaml` | Priority for inference (1000) | Cluster |
| `pvc-checkpoint.yaml` | Storage for checkpoints (100Mi) | ml-training namespace |
