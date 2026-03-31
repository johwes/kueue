# Demo 1: Resource Borrowing in Action

This demo demonstrates how Training can use Inference's idle resources through **borrowing**.

## The Scenario

**Setup:**
- Training ClusterQueue: 3 CPUs nominal quota
- Inference ClusterQueue: 2 CPUs nominal quota
- Both in same cohort: `ml-shared-pool`

**Challenge:**
Training team wants to run a large experiment needing **5 CPUs** (more than their 3 CPU quota).

**Without Cohorts:** Job would be rejected or queued forever.

**With Cohorts + Borrowing:** Training can borrow Inference's idle 2 CPUs!

---

## Step-by-Step Walkthrough

### Step 1: Verify Initial State

Check that both ClusterQueues are empty:

```bash
# Check ClusterQueue status
oc get clusterqueue training-cluster-queue inference-cluster-queue
```

Expected output:
```
NAME                      COHORT           PENDING WORKLOADS
training-cluster-queue    ml-shared-pool   0
inference-cluster-queue   ml-shared-pool   0
```

Both queues show 0 pending workloads - resources are idle.

---

### Step 2: Check Available Resources in Each Queue

```bash
# Training queue capacity
oc get clusterqueue training-cluster-queue -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources}' | jq

# Inference queue capacity
oc get clusterqueue inference-cluster-queue -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources}' | jq
```

Expected output:
```json
Training queue:
[
  {"name": "cpu", "nominalQuota": "3"},
  {"name": "memory", "nominalQuota": "512Mi"}
]

Inference queue:
[
  {"name": "cpu", "nominalQuota": "2"},
  {"name": "memory", "nominalQuota": "256Mi"}
]
```

**Total available for borrowing:** 3 + 2 = 5 CPUs

---

### Step 3: Submit Large Training Job (Needs 5 CPUs)

Submit a training job that needs more resources than training's nominal quota:

```bash
cd 02-demo-borrowing

# Submit job requiring 5 CPUs (more than training's 3 CPU quota)
oc apply -f jobs/training-large-borrow.yaml

# Immediately check workload status
oc get workload -n ml-training
```

Expected output (wait ~2 seconds):
```
NAME                                QUEUE               RESERVED IN              ADMITTED   AGE
job-training-large-borrow-xxxxx    ml-training-queue   training-cluster-queue   True       3s
                                                                                ^^^^
                                                                                Admitted immediately!
```

**KEY OBSERVATION:** Job was admitted even though it needs 5 CPUs and training only has 3 CPUs quota!

---

### Step 4: Verify Borrowing Happened

Check how resources are allocated:

```bash
# Check training ClusterQueue resource usage
oc get clusterqueue training-cluster-queue -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output:
```json
[
  {
    "borrowed": "2",        ← Borrowed 2 CPUs from inference!
    "name": "cpu",
    "total": "5"            ← Using 5 CPUs total (3 own + 2 borrowed)
  },
  {
    "borrowed": "0",
    "name": "memory",
    "total": "128Mi"
  }
]
```

**This proves:**
- Training is using **5 CPUs total**
- **2 CPUs are borrowed** from inference-cluster-queue
- Training's nominal quota: 3 CPUs
- Borrowed from inference: 2 CPUs

---

### Step 5: Verify Job is Running

```bash
# Check job status
oc get job training-large-borrow -n ml-training

# Check pod status
oc get pods -n ml-training

# View job logs
oc logs -n ml-training -l app=large-training -f
```

Expected output:
```
NAME                      STATUS    COMPLETIONS   DURATION   AGE
training-large-borrow     Running   0/1           10s        12s

Pod logs:
==========================================
Large-Scale Training: Borrowing Demo
==========================================
Job: training-large-borrow-xxxxx-xxxxx
Started: Thu Mar 27 10:15:00 UTC 2026

Resource allocation:
- Requested: 5 CPUs, 128Mi memory
- Status: Using borrowed resources from inference queue

Training large model with 5 CPUs...
Epoch 1/10 - Loss: 2.456
Epoch 2/10 - Loss: 2.103
...
```

---

### Step 6: Check Inference Queue (Should Show Borrowed Resources)

```bash
# Check inference ClusterQueue usage
oc get clusterqueue inference-cluster-queue -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output:
```json
[
  {
    "borrowed": "0",
    "name": "cpu",
    "total": "0"            ← Inference using 0 CPUs (all idle)
  },
  {
    "borrowed": "0",
    "name": "memory",
    "total": "0"
  }
]
```

**This shows:**
- Inference is using **0 CPUs** (completely idle)
- Training borrowed those idle 2 CPUs
- No active workloads in inference queue

---

### Step 7: Monitor Until Completion

Watch the job complete:

```bash
# Monitor job completion
watch -n 5 "oc get job,workload -n ml-training"
```

Expected progression (~2 minutes):
```
NAME                                STATUS      COMPLETIONS   DURATION   AGE
job.batch/training-large-borrow     Running     0/1           30s        32s

... (wait ~90 seconds) ...

NAME                                STATUS      COMPLETIONS   DURATION   AGE
job.batch/training-large-borrow     Complete    1/1           120s       122s
```

---

### Step 8: Verify Resources Released After Completion

After job completes, check that borrowed resources are released:

```bash
# Check training queue (should show 0 usage)
oc get clusterqueue training-cluster-queue -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output:
```json
[
  {
    "borrowed": "0",
    "name": "cpu",
    "total": "0"            ← Resources released!
  }
]
```

**This proves:**
- Job completed successfully
- All 5 CPUs released (3 own + 2 borrowed)
- Borrowed resources returned to inference queue
- Cohort is back to idle state

---

## What You Just Learned

✅ **Borrowing Basics:** Training used 5 CPUs despite having only 3 CPU quota

✅ **Idle Detection:** Kueue automatically detected inference's 2 idle CPUs

✅ **Transparent Borrowing:** Job admitted instantly without manual intervention

✅ **Resource Accounting:** `.status.flavorsReservation[].borrowed` shows borrowed resources

✅ **Automatic Cleanup:** Borrowed resources automatically released after job completes

---

## Understanding the Borrowing Metrics

### Key Fields in ClusterQueue Status

```bash
oc get clusterqueue training-cluster-queue -o json | jq '.status.flavorsReservation[0].resources[0]'
```

Output explanation:
```json
{
  "borrowed": "2",        // CPUs borrowed from other queues in cohort
  "name": "cpu",          // Resource type
  "total": "5"            // Total allocated (nominal + borrowed)
}
```

**Formula:**
```
total = nominal + borrowed
5 CPUs = 3 CPUs (nominal quota) + 2 CPUs (borrowed from inference)
```

---

## Borrowing Scenarios

### Scenario A: Inference Completely Idle

```
Training nominal: 3 CPUs
Inference idle: 2 CPUs available
Training can use: 3 + 2 = 5 CPUs total
```

**This demo!** Training borrowed all of inference's quota.

---

### Scenario B: Inference Partially Busy

```
Training nominal: 3 CPUs
Inference using: 1 CPU (1 CPU idle)
Training can borrow: 1 CPU
Training can use: 3 + 1 = 4 CPUs total
```

Training can only borrow what's actually idle.

---

### Scenario C: Inference Fully Busy

```
Training nominal: 3 CPUs
Inference using: 2 CPUs (0 CPUs idle)
Training can borrow: 0 CPUs
Training limited to: 3 CPUs (nominal only)
```

When inference is busy, training can't borrow.

---

### Scenario D: Both Try to Borrow (Not Possible)

```
Total cluster: 5 CPUs
Training wants: 5 CPUs (borrow 2 from inference)
Inference wants: 5 CPUs (borrow 3 from training)
```

**Can't both borrow simultaneously!** The cohort has 5 CPUs total.
- First-come-first-served (FIFO)
- Or use preemption (Demo 2)

---

## Cleanup

```bash
# Delete the large training job
oc delete job training-large-borrow -n ml-training

# Verify resources are freed
oc get clusterqueue training-cluster-queue inference-cluster-queue
```

Expected:
```
NAME                      COHORT           PENDING WORKLOADS
training-cluster-queue    ml-shared-pool   0
inference-cluster-queue   ml-shared-pool   0
```

---

## Key Takeaways

### Before Cohorts (Hard Partitioning)
```
Training: 3 CPUs (fixed)
Inference: 2 CPUs (fixed)
Large job needing 5 CPUs: ❌ REJECTED or QUEUED FOREVER
Utilization: Training 60% idle, but can't use inference's capacity
```

### After Cohorts (Dynamic Borrowing)
```
Training: 3 CPUs nominal, can borrow up to 2 more
Inference: 2 CPUs nominal, can borrow up to 3 more
Large job needing 5 CPUs: ✅ ADMITTED via borrowing
Utilization: 95%+ (training uses idle inference capacity)
```

**Business Impact:**
- Faster experiment iteration (5 CPUs vs. 3 CPUs = 1.67x speedup)
- Better resource utilization (95% vs. 65%)
- Lower cost per experiment (maximize ROI on expensive GPUs)

---

## Next Steps

Now that you've seen borrowing in action, proceed to [03-demo-preemption-checkpoint](../02-demo-preemption-checkpoint/README.md) to learn what happens when inference needs its resources back!

**Key Question for Demo 2:** What happens if inference needs resources while training is using borrowed CPUs? Answer: **Preemption**!
