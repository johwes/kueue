# Demo: Fair Sharing - Training Workloads

This demo shows how Kueue manages multiple training workloads competing for shared resources.

## Prerequisites

- Module 01 setup (00-setup) complete
- LocalQueue `ml-training-queue` exists in `ml-training` namespace

---

## Training Workloads

This directory contains realistic ML training jobs:

| Job | CPUs | Memory | Duration | Description |
|-----|------|--------|----------|-------------|
| `job-train-resnet-model.yaml` | 2 | 256Mi | ~2min | Training ResNet-50 for image classification |
| `job-finetune-llm.yaml` | 3 | 512Mi | ~2min | Fine-tuning a large language model |
| `job-hyperparameter-tuning.yaml` | 1 | 128Mi | ~1min | Running hyperparameter optimization |

**Total if submitted together:** 6 CPUs (exceeds 5 CPU quota)

---

## Demo Scenarios

### Scenario 1: Single Job Lifecycle

Watch a single job from submission to completion (Note, hit CTRL+C to break the watch and log commands):

```bash
# Submit one job
oc apply -f jobs/job-hyperparameter-tuning.yaml

# Watch lifecycle
watch -n 2 "oc get workload,job -n ml-training"

# View logs
oc logs -n ml-training -l app=hyperparameter-tuning -f

# Delete all training jobs
oc delete jobs --all -n ml-training

# Verify clean state
oc get workload -n ml-training
```

**Expected:** Job admits immediately, runs for ~60s, completes successfully.

---

### Scenario 2: Queueing When Resources Exhausted

Submit all jobs to see queueing in action:

```bash
# Submit all training jobs
oc apply -f jobs/

# Check what was admitted
oc get workload -n ml-training

# Monitor queue
watch -n 2 "oc get workload -n ml-training"

# Delete all training jobs
oc delete jobs --all -n ml-training

# Verify clean state
oc get workload -n ml-training
```

**Expected:**
- 2 jobs admitted immediately (4 CPUs used)
- 1 job queued (needs 2 more CPUs)
- When first job completes, queued job auto-admits

---

### Scenario 3: Resource Accounting

See how Kueue tracks resource usage:

```bash
# Submit all jobs
oc apply -f jobs/

# Get jobs in queue
sleep 2
oc get workload -n ml-training

# Check ClusterQueue utilization
oc get clusterqueue cluster-total -o json | \
  jq '.status.flavorsReservation[0].resources'

# Delete all training jobs
oc delete jobs --all -n ml-training

# Verify clean state
oc get workload -n ml-training
```

**Expected Output:**
```json
[
  {
    "name": "cpu",
    "total": "4"      // 4 CPUs currently allocated
  },
  {
    "name": "memory",
    "total": "640Mi"  // Memory for running jobs
  }
]
```

---

## Understanding the Jobs

All jobs follow the same pattern:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-train-resnet-model
  namespace: ml-training
  labels:
    kueue.x-k8s.io/queue-name: ml-training-queue  # Routes to training queue
spec:
  suspend: true  # Kueue controls admission
  template:
    spec:
      containers:
      - name: trainer
        resources:
          requests:
            cpu: "2"        # Counted toward quota
            memory: "256Mi"
```

**Key Elements:**
1. `kueue.x-k8s.io/queue-name` label - specifies which queue
2. `suspend: true` - lets Kueue control when it starts
3. `resources.requests` - Kueue uses these for quota calculation

---

## Cleanup

After experimenting:

```bash
# Delete all training jobs
oc delete jobs --all -n ml-training

# Verify clean state
oc get workload -n ml-training
```

---

## Next Steps

After exploring training workloads, proceed to [02-demo-priorities](../02-demo-priorities/) to see how production workloads interact with training.

---

## Troubleshooting

### Job Created But No Workload

**Check:**
```bash
oc get job <job-name> -n ml-training -o yaml | grep -A 5 labels
```

**Fix:** Ensure `kueue.x-k8s.io/queue-name` label exists

### Workload Never Admitted

**Check:**
```bash
oc describe workload <workload-name> -n ml-training
```

**Reason:** Usually quota exhausted or job requests exceed total quota

### Pods Not Starting

**Check:**
```bash
oc get events -n ml-training --sort-by='.lastTimestamp'
```

**Reason:** Workload admitted but actual node capacity insufficient

---

## What You Learned

✅ How to submit Kueue-managed jobs
✅ How queueing works when resources are exhausted
✅ How to monitor workload status
✅ How resources are automatically allocated and released
