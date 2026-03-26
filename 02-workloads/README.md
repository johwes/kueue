# Module 02: Workloads

This module demonstrates the real-world scenario: **ML training experiments competing with production inference workloads for shared GPU resources**.

## The Scenario

Your organization runs all ML workloads on a shared GPU cluster due to the high cost of GPU infrastructure. Two teams submit jobs to this cluster:

### ML Training Team (Experimentation)
**Goal**: Train and improve ML models through experimentation

**Workloads**:
- `job-train-resnet-model.yaml` - Training ResNet-50 for image classification (2 CPU, 256Mi memory)
- `job-finetune-llm.yaml` - Fine-tuning a large language model (3 CPU, 512Mi memory)
- `job-hyperparameter-tuning.yaml` - Running hyperparameter optimization (1 CPU, 128Mi memory)

**Characteristics**:
- Unpredictable submission times
- Variable duration (hours to days)
- Can tolerate queueing delays
- Innovation-focused, not time-critical

### ML Inference Team (Production)
**Goal**: Serve customer-facing ML predictions with SLA guarantees

**Workloads**:
- `job-batch-customer-inference.yaml` - Production batch predictions for customers (1 CPU, 256Mi memory)
- `job-model-validation.yaml` - Pre-production model validation (2 CPU, 256Mi memory)
- `job-feature-extraction.yaml` - Batch embedding generation (1 CPU, 128Mi memory)

**Characteristics**:
- Predictable, scheduled submission
- Time-sensitive with SLA requirements
- Cannot be starved of resources
- Customer-impacting, production-critical

## The Problem Without Kueue

**Before implementing Kueue**, this scenario leads to conflicts:

1. **Resource Starvation**: Training jobs consume all GPUs at 2 AM, blocking morning inference batch jobs
2. **SLA Breaches**: Production inference delayed, customers experience degraded service
3. **Manual Intervention**: Engineers manually kill training jobs to free resources
4. **Wasted Resources**: GPUs sit idle when training is killed, then saturated when training resumes
5. **Team Friction**: Training team vs. Inference team conflicts over resource priority

## The Solution With Kueue

**After implementing Kueue**, resource sharing becomes automatic:

1. **Fair Queueing**: Training and inference workloads share resources fairly
2. **Production Priority**: Inference workloads get admitted even when training saturates cluster
3. **Efficient Utilization**: Training uses idle capacity without blocking production
4. **Visibility**: Teams can see queue depth and admission status
5. **Automatic**: No manual intervention required

## How Jobs Work with Kueue

### Standard Kubernetes Job (Without Kueue)
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-training-job
spec:
  template:
    spec:
      containers:
      - name: trainer
        image: my-ml-image
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
      restartPolicy: Never
```
**Problem**: This job runs immediately, potentially starving production workloads.

### Kueue-Managed Job
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-training-job
  labels:
    kueue.x-k8s.io/queue-name: ml-training-queue  # ← Routes to training queue
spec:
  suspend: true  # ← Kueue controls when it starts
  template:
    spec:
      containers:
      - name: trainer
        image: my-ml-image
        resources:
          requests:
            cpu: "4"
            memory: "8Gi"
      restartPolicy: Never
```
**Solution**: Kueue queues this job and admits it when resources are available without impacting production.

**Key Differences**:
1. **Queue Label**: `kueue.x-k8s.io/queue-name` specifies which LocalQueue (training vs inference)
2. **Suspend**: `suspend: true` lets Kueue control admission
3. **Resource Requests**: Required for Kueue to calculate quota usage

## Demo Scenario 1: Training Fills the Cluster

This scenario demonstrates **queueing in action**. The cluster has only 5 CPUs available, but we'll submit 3 training jobs requesting 6 CPUs total (2+3+1). This forces at least one job to wait in queue.

### Resource Math
- **Available quota**: 5 CPUs, 2Gi memory
- **Training jobs requesting**:
  - ResNet training: 2 CPU, 256Mi
  - LLM fine-tuning: 3 CPU, 512Mi
  - Hyperparameter tuning: 1 CPU, 128Mi
  - **Total**: 6 CPU, 896Mi (CPU exceeds quota!)

### Step-by-Step Walkthrough

**Step 1: Check initial cluster state (before submitting jobs)**

```bash
# Verify the cluster queue is empty
oc get clusterqueue cluster-total -o wide

# Check resource availability
oc get clusterqueue cluster-total -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources}' | jq
```

Expected output:
```
NAME            COHORT   STRATEGY         PENDING WORKLOADS   ADMITTED WORKLOADS
cluster-total            BestEffortFIFO   0                   0
```

This shows the cluster is ready with no pending workloads.

---

**Step 2: Submit all training jobs at once**

```bash
# Submit all 3 training jobs
oc apply -f ml-training/

# Immediately check what jobs were created
oc get jobs -n ml-training
```

Expected output:
```
NAME                        STATUS      COMPLETIONS   DURATION   AGE
job-finetune-llm            Running     0/1           3s         4s
job-hyperparameter-tuning   Running     0/1           3s         3s
job-train-resnet-model      Suspended   0/1                      3s
```

**What's happening**: Jobs that are immediately admitted show STATUS "Running", while jobs waiting in queue show "Suspended". Admission happens within 1-2 seconds.

---

**Step 3: Check Workload objects (Kueue's admission control)**

```bash
# List all workloads in ml-training namespace
oc get workload -n ml-training
```

Expected output (wait ~10 seconds after job creation):
```
NAME                                  QUEUE               RESERVED IN     ADMITTED   AGE
job-job-finetune-llm-xxxxx           ml-training-queue   cluster-total   True       15s
job-job-hyperparameter-tuning-xxxxx  ml-training-queue   cluster-total   True       15s
job-job-train-resnet-model-xxxxx     ml-training-queue                              15s
```

**KEY OBSERVATION**:
- ✅ **2 jobs ADMITTED** (LLM + Hyperparameter = 4 CPUs, 640Mi)
- ⏳ **1 job PENDING** (ResNet waiting for resources)

**Note**: Jobs are admitted in creation order (FIFO). When using `oc apply -f ml-training/`, files are processed alphabetically:
1. job-**f**inetune-llm (3 CPU) - admitted first
2. job-**h**yperparameter-tuning (1 CPU) - admitted second (total: 4 CPU)
3. job-**t**rain-resnet-model (2 CPU) - **queued** (would need 6 CPU total)

---

**Step 4: Verify which jobs are actually running**

```bash
# Check job status
oc get jobs -n ml-training

# Check if pods are running for admitted jobs
oc get pods -n ml-training
```

Expected output:
```
NAME                        STATUS      COMPLETIONS   DURATION   AGE
job-finetune-llm            Running     0/1           30s        1m
job-hyperparameter-tuning   Running     0/1           30s        1m
job-train-resnet-model      Suspended   0/1                      1m    ← Still suspended!
```

You should see pods running for LLM and Hyperparameter jobs, but NO pods for ResNet because it's still queued.

---

**Step 5: Check ClusterQueue utilization**

```bash
# Show detailed resource usage
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output:
```json
[
  {
    "borrowed": "0",
    "name": "cpu",
    "total": "4"       ← Currently allocated CPUs (LLM 3 + Hyperparameter 1)
  },
  {
    "borrowed": "0",
    "name": "memory",
    "total": "640Mi"   ← Currently allocated memory (512Mi + 128Mi)
  }
]
```

**This proves**: 4 out of 5 CPUs are allocated. ResNet job needs 2 CPUs but only 1 is available (5 - 4 = 1), so it must wait.

**Note**: The "total" field shows **currently allocated resources**, not the maximum quota. To see the maximum quota, use the command from Step 1.

---

**Step 6: Describe the queued workload to see why it's waiting**

```bash
# Find the pending workload name
PENDING_WORKLOAD=$(oc get workload -n ml-training -o json | jq -r '.items[] | select(.status.admission == null) | .metadata.name')

# Describe it to see the reason
oc describe workload -n ml-training $PENDING_WORKLOAD
```

Look for the **Conditions** section:
```
Conditions:
  Type:                QuotaReserved
  Status:              False
  Reason:              Pending
  Message:             couldn't assign flavors to pod set main: insufficient unused quota
                       for cpu in flavor default-flavor, 1 more needed
```

**This explains**: The ResNet job needs 2 CPUs, but only 1 CPU is available (5 total - 4 used = 1 available). It needs "1 more" to be admitted.

---

**Step 7: Watch the queue admission when a job completes**

Open a monitoring window:
```bash
# In Terminal 1: Watch workloads
watch -n 2 "oc get workload -n ml-training"

# In Terminal 2: Watch the ClusterQueue
watch -n 2 "oc get clusterqueue cluster-total"
```

**Wait for one of the running jobs to complete** (~1 minute for the Hyperparameter job, ~2 minutes for LLM job).

**What you'll observe**:
1. When Hyperparameter job completes → resources released (4 CPUs → 3 CPUs used)
2. Queued ResNet job immediately admitted (3 CPUs → 5 CPUs used)
3. The ResNet job transitions from `ADMITTED=(blank)` to `ADMITTED=True`
4. ResNet job status changes from `Suspended` to `Running`
5. Pods start for the ResNet job

---

**Step 8: Verify the lifecycle**

```bash
# Check final status of all workloads
oc get workload -n ml-training

# Check which jobs completed
oc get jobs -n ml-training
```

Expected progression:
```
NAME                                  QUEUE               RESERVED IN     ADMITTED   FINISHED   AGE
job-job-finetune-llm-xxxxx           ml-training-queue   cluster-total   True                  5m    ← Still running
job-job-hyperparameter-tuning-xxxxx  ml-training-queue   cluster-total   True       True       5m    ← Completed!
job-job-train-resnet-model-xxxxx     ml-training-queue   cluster-total   True                  5m    ← Now admitted and running!
```

All jobs have now been admitted. The Hyperparameter job finished first, releasing resources for the ResNet job to be admitted.

---

### What You Just Learned

✅ **Queueing in action**: When quota is exhausted, jobs wait in queue
✅ **Automatic admission**: As resources free up, queued jobs are automatically admitted
✅ **Resource accounting**: Kueue tracks exactly how much quota is used
✅ **Transparency**: You can see why jobs are pending and when they'll be admitted

### Key Commands Summary

```bash
# See which jobs are admitted vs pending
oc get workload -n ml-training

# Check cluster capacity and usage
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'

# See why a workload is pending
oc describe workload -n ml-training <workload-name>

# Monitor in real-time
watch -n 2 "oc get workload -n ml-training"
```

## Demo Scenario 2: Fair Sharing Between Training and Production

This scenario demonstrates **fair resource sharing** when both training and production workloads compete for the same cluster resources. You'll see how Kueue ensures both teams get their fair share, preventing production starvation.

### The Scenario

Training experiments are running and have saturated the cluster. A production inference job arrives and needs resources immediately. Without Kueue, production would be blocked. With Kueue, resources are shared fairly.

### Step-by-Step Walkthrough

**Step 1: Clean up from Demo 1 (if needed)**

```bash
# Delete any existing jobs from previous demos
oc delete jobs --all -n ml-training
oc delete jobs --all -n ml-inference

# Verify cluster is clean
oc get clusterqueue cluster-total
```

Expected output:
```
NAME            COHORT   PENDING WORKLOADS
cluster-total            0
```

---

**Step 2: Submit training jobs to saturate the cluster**

```bash
# Submit all training jobs
oc apply -f ml-training/

# Immediately check what was created
oc get jobs -n ml-training
```

Expected output:
```
NAME                        STATUS      COMPLETIONS   DURATION   AGE
job-finetune-llm            Running     0/1           2s         3s
job-hyperparameter-tuning   Running     0/1           2s         2s
job-train-resnet-model      Suspended   0/1                      2s
```

Training team's jobs are consuming cluster resources (4 CPUs allocated, 1 CPU available).

---

**Step 3: Production inference job arrives (needs resources NOW)**

```bash
# Production team submits their job while training is running
oc apply -f ml-inference/job-batch-customer-inference.yaml

# Check job status
oc get jobs -n ml-inference
```

Expected output:
```
NAME                           STATUS    COMPLETIONS   DURATION   AGE
job-batch-customer-inference   Running   0/1           2s         2s
```

**Great news**: The production job is admitted immediately! Even though training jobs are running, Kueue ensures the inference job gets the available CPU (1 CPU available out of 5 total).

---

**Step 4: Watch fair sharing in action**

```bash
# Monitor workloads across both namespaces
oc get workload -A
```

Expected output:
```
NAMESPACE      NAME                                       QUEUE               RESERVED IN     ADMITTED   AGE
ml-inference   job-job-batch-customer-inference-xxxxx    ml-inference-queue   cluster-total   True       10s
ml-training    job-job-finetune-llm-xxxxx                ml-training-queue   cluster-total   True        15s
ml-training    job-job-hyperparameter-tuning-xxxxx       ml-training-queue   cluster-total   True        15s
ml-training    job-job-train-resnet-model-xxxxx          ml-training-queue                               15s
```

**Current state - Fair Sharing in Action**:
- **Training queue**: 2 jobs admitted (LLM 3 CPU + Hyperparameter 1 CPU = 4 CPUs)
- **Inference queue**: 1 job admitted (Batch inference 1 CPU)
- **Total**: 5 CPUs allocated (quota fully utilized!)
- **Waiting**: ResNet training job (needs 2 CPUs)

**Key observation**: Both queues are running jobs simultaneously! Production inference got immediate access despite training saturating most of the cluster.

---

**Step 5: Observe automatic fair sharing**

```bash
# Watch as jobs complete and resources are redistributed
watch -n 2 "oc get workload -n ml-inference -n ml-training"

# In another terminal, watch the jobs
watch -n 2 "oc get jobs -n ml-inference -n ml-training"
```

**What you'll observe** (wait ~60 seconds):

When either the Hyperparameter training job (~60s) or Batch inference job (~70s) completes:
1. Resources are freed
2. ResNet training job (waiting, needs 2 CPUs) gets evaluated
3. When enough resources are available, ResNet is automatically admitted

**Timeline**:
- **t=0s**: Hyperparameter (1 CPU) + LLM (3 CPU) + Inference (1 CPU) running, ResNet queued
- **t=60s**: Hyperparameter completes → 1 CPU freed (4 CPUs remain: LLM 3 + Inference 1)
  - ResNet still needs 2 CPUs but only 1 available → remains queued
- **t=70s**: Inference completes → another 1 CPU freed (3 CPUs remain: LLM only)
  - ResNet needs 2 CPUs, now 2 available (5 - 3 = 2) → **ResNet admitted!**

**Fair sharing demonstrated**:
```
NAMESPACE      NAME                                    STATUS
ml-inference   job-batch-customer-inference           Complete   ← Finished first
ml-training    job-finetune-llm                        Running    ← Still running
ml-training    job-hyperparameter-tuning               Complete   ← Finished, freed resources
ml-training    job-train-resnet-model                  Running    ← Now admitted!
```

**Key insight**: Both queues got their jobs admitted and completed successfully. No starvation!

---

**Step 6: Verify resource distribution**

```bash
# Check how resources are distributed between queues
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation[0].resources'
```

Expected output (when all 3 jobs running initially):
```json
[
  {
    "borrowed": "0",
    "name": "cpu",
    "total": "5"       ← All 5 CPUs allocated!
  },
  {
    "borrowed": "0",
    "name": "memory",
    "total": "896Mi"   ← Memory for all 3 running jobs
  }
]
```

**Resource distribution over time**:

**Phase 1** (initial state):
- **Training**: LLM (3 CPU) + Hyperparameter (1 CPU) = 4 CPUs
- **Inference**: Batch inference (1 CPU) = 1 CPU
- **Total**: 5 CPUs (quota fully utilized)
- **Queued**: ResNet (2 CPU)

**Phase 2** (after jobs complete):
- **Training**: LLM (3 CPU) + ResNet (2 CPU) = 5 CPUs
- **Inference**: None running (completed)
- **Fair sharing**: Both queues got their jobs completed!

---

### What You Just Learned

✅ **No production starvation**: Production inference job got resources even though training saturated cluster first

✅ **Fair resource sharing**: Both training and inference queues get their share of resources

✅ **Automatic balancing**: Kueue manages admission without manual intervention

✅ **Queue independence**: Each team submits to their own queue, Kueue handles the rest

### Key Insight

**Without Kueue**: Production inference would be blocked until training manually killed their jobs.

**With Kueue**: Resources are automatically shared fairly. Production gets guaranteed access while training experiments still make progress.

## Demo Scenario 3: Complete Lifecycle

This scenario follows a **single job** through its complete lifecycle from creation to completion, showing every state transition.

### Step-by-Step Walkthrough

**Step 1: Clean up and start fresh**

```bash
# Delete any existing jobs
oc delete jobs --all -n ml-training

# Verify clean state
oc get workload -n ml-training
```

Expected: No workloads found.

---

**Step 2: Submit a single job and watch the lifecycle**

Open **three terminals** to observe different aspects:

**Terminal 1 - Watch Workload status**:
```bash
oc get workload -n ml-training -w
```

**Terminal 2 - Watch Job status**:
```bash
oc get job -n ml-training -w
```

**Terminal 3 - Submit the job**:
```bash
oc apply -f ml-training/job-hyperparameter-tuning.yaml
```

---

**Step 3: Observe the lifecycle progression**

**Terminal 1 (Workload)** - You'll see:
```
NAME                                  QUEUE               RESERVED IN     ADMITTED   FINISHED   AGE
job-job-hyperparameter-tuning-xxxxx  ml-training-queue   cluster-total   True                  0s
                                                                         ^^^^
                                                                         Immediately admitted!
```

**Terminal 2 (Job)** - You'll see:
```
NAME                        STATUS      COMPLETIONS   DURATION   AGE
job-hyperparameter-tuning   Running     0/1           2s         3s
                            ^^^^^^^
                            Started running immediately
```

After ~60 seconds:
```
NAME                        STATUS     COMPLETIONS   DURATION   AGE
job-hyperparameter-tuning   Complete   1/1           60s        62s
                            ^^^^^^^^
                            Job finished!
```

**Terminal 1 (Workload)** - Final state:
```
NAME                                  QUEUE               RESERVED IN     ADMITTED   FINISHED   AGE
job-job-hyperparameter-tuning-xxxxx  ml-training-queue   cluster-total   True       True       65s
                                                                                    ^^^^
                                                                                    Marked finished
```

---

**Step 4: View job logs**

```bash
# Follow logs as job runs (run this right after submitting job)
oc logs -n ml-training -l app=hyperparameter-tuning -f
```

You'll see the job's output:
```
==========================================
ML Experimentation: Hyperparameter Tuning
==========================================
Job: job-hyperparameter-tuning-xxxxx-xxxxx
Started: Wed Mar 26 11:30:00 UTC 2026

Search space: learning_rate, batch_size, dropout
Running Bayesian optimization...

Trial 1/6 - lr=0.001, batch=32, dropout=0.2 → val_acc=0.68
Trial 2/6 - lr=0.005, batch=64, dropout=0.3 → val_acc=0.71
Trial 3/6 - lr=0.002, batch=32, dropout=0.1 → val_acc=0.74

Best configuration found:
  Learning rate: 0.002
  Batch size: 32
  Dropout: 0.1
  Validation accuracy: 74.2%

Saving results to experiment tracking...
Hyperparameter tuning complete: Wed Mar 26 11:31:00 UTC 2026
==========================================
```

---

### Lifecycle Stages Observed

1. **Job Created** (suspend: true) → Workload object created automatically
2. **Workload Evaluated** → Kueue checks quota availability
3. **Workload Admitted** → Resources available, quota reserved
4. **Job Unsuspended** → Job transitions from Suspended → Running
5. **Pods Created** → Kubernetes creates pods for the job
6. **Pods Running** → Containers execute the workload
7. **Job Complete** → All pods finish successfully
8. **Workload Finished** → Workload marked as finished, resources released

**Total time**: ~60 seconds for this job.

---

### What You Just Learned

✅ **Automatic workload creation**: Kueue creates Workload objects for every Job

✅ **Instant admission**: When quota is available, jobs are admitted in < 1 second

✅ **Seamless integration**: Jobs run normally once admitted - no changes to pod behavior

✅ **Resource cleanup**: When jobs complete, resources are immediately released for other workloads

✅ **Observable lifecycle**: Every state is visible through kubectl/oc commands

## Understanding Workload Objects

Kueue creates a Workload object for each Job to manage admission:

```bash
# List workloads across both namespaces
oc get workload -A

# Describe a specific workload
oc describe workload -n ml-training <workload-name>
```

**Key Fields**:
- **spec.queueName**: Which LocalQueue this workload belongs to
- **spec.podSets**: Resource requests for the job
- **status.admission**: If admitted, shows assigned resources
- **status.conditions**: Admission status and reasons

Example:
```bash
oc get workload -n ml-training job-job-train-resnet-model-xxxxx -o yaml
```

## Demonstrating Fair Sharing

To see fair sharing in action, saturate both queues simultaneously:

**Setup: Clean up first**
```bash
# Delete any existing jobs
oc delete jobs --all -n ml-training
oc delete jobs --all -n ml-inference
```

**Demo: Saturate both queues**

```bash
# Terminal 1: Monitor overall status
watch -n 2 "oc get workload -A && echo '' && oc get clusterqueue"

# Terminal 2: Submit all training jobs
oc apply -f ml-training/

# Terminal 3: Submit all inference jobs
oc apply -f ml-inference/
```

**What you'll observe**:
- Total cluster quota: 5 CPUs, 2Gi memory
- Training jobs: 6 CPUs requested (2+3+1)
- Inference jobs: 4 CPUs requested (1+2+1)
- **Total requested**: 10 CPUs (twice the quota!)
- **Kueue admits**: ~5 CPUs worth of jobs from both queues
- Both queues compete for the same resources (CPU is the limiting factor)
- Kueue ensures fair distribution between queues
- Neither queue is completely starved
- Resources are allocated dynamically as jobs complete
- As training jobs finish, both training and inference queued jobs get admitted fairly

**Expected state after submission**:
```
NAMESPACE      NAME                               ADMITTED
ml-training    job-job-finetune-llm-xxxxx        True      (3 CPU)
ml-training    job-job-hyperparameter-tuning-x   True      (1 CPU)
ml-training    job-job-train-resnet-model-x                 (queued, needs 2 CPU)
ml-inference   job-job-batch-customer-inference-x           (queued, needs 1 CPU)
ml-inference   job-job-model-validation-xxxxx                (queued, needs 2 CPU)
ml-inference   job-job-feature-extraction-xxxxx             (queued, needs 1 CPU)
```

4 CPUs admitted, 6 CPUs worth of jobs waiting. Fair sharing ensures both queues get resources as they become available.

**Note**: Memory requests are kept minimal (128Mi-512Mi) for cost efficiency at scale. CPU quota is the primary resource being demonstrated.

## Production vs. Training Priority (Advanced)

For production SLA guarantees, you can configure priority:

**Step 1**: Create WorkloadPriorityClasses (not included in basic demo):
```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: production-critical
spec:
  value: 1000
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: WorkloadPriorityClass
metadata:
  name: training-experimental
spec:
  value: 100
```

**Step 2**: Reference in jobs:
```yaml
metadata:
  labels:
    kueue.x-k8s.io/priority-class: production-critical
```

**Result**: Production jobs can preempt lower-priority training jobs when necessary.

## Common Workload States

| Condition | Meaning |
|-----------|---------|
| **QuotaReserved=True** | Resources allocated, workload can run |
| **QuotaReserved=False** | Waiting for resources, queued |
| **Admitted=True** | Workload is running or has run |
| **Finished=True** | Workload completed successfully |
| **Evicted=True** | Workload was preempted by higher priority |

Check workload conditions:
```bash
oc get workload -n ml-training <name> -o jsonpath='{.status.conditions}' | jq
```

## Cleaning Up Completed Jobs

After experimentation:

```bash
# Delete all jobs in ml-training
oc delete jobs --all -n ml-training

# Delete all jobs in ml-inference
oc delete jobs --all -n ml-inference

# Or delete specific jobs
oc delete job job-train-resnet-model -n ml-training
```

**Note**: Deleting a Job automatically deletes its associated Workload object.

## Troubleshooting

### Job Created But No Workload Appears

**Problem**: Job exists but no Workload object created

**Diagnosis**:
```bash
# Check job labels
oc get job <job-name> -n ml-training -o yaml | grep -A 5 labels

# Check namespace label
oc get namespace ml-training -o jsonpath='{.metadata.labels}'
```

**Common Causes**:
1. Missing `kueue.x-k8s.io/queue-name` label on Job
2. Namespace missing `kueue.openshift.io/managed=true` label
3. Job not created with `suspend: true`

**Solution**: Ensure all three requirements are met.

### Workload Stuck in Pending

**Problem**: Workload never gets admitted

**Diagnosis**:
```bash
# Check workload status
oc describe workload -n ml-training <workload-name>

# Check cluster queue capacity
oc get clusterqueue cluster-total -o json | jq '.status.flavorsReservation'
```

**Common Causes**:
1. Cluster quota exhausted (all resources in use)
2. Job requests more resources than total quota
3. LocalQueue not properly mapped to ClusterQueue

### Pods Not Starting Despite Admitted Workload

**Problem**: Workload admitted but pods don't appear

**Diagnosis**:
```bash
# Check events
oc get events -n ml-training --sort-by='.lastTimestamp'

# Check job status
oc describe job <job-name> -n ml-training
```

**Common Causes**:
1. Actual node capacity less than Kueue quota (nodes don't have enough CPU/memory)
2. Image pull errors
3. Pod security policies blocking pod creation

## What You've Learned

By completing this module, you've seen:

✅ **Real-world ML scenario**: Training vs. production inference competing for GPUs  
✅ **Fair resource sharing**: Both workload types get their fair share  
✅ **Queue management**: Automatic admission control without manual intervention  
✅ **Workload lifecycle**: From creation to admission to completion  
✅ **Visibility**: Clear view of queue status and resource allocation  

## Next Steps

Proceed to [03-monitoring](../03-monitoring/README.md) to learn:
- How to monitor queue health
- Track resource utilization
- Verify production SLAs are met
- Troubleshoot resource contention

## Key Takeaway

**Before Kueue**: Manual intervention required to prevent training from starving production.  
**With Kueue**: Automatic fair sharing ensures both innovation (training) and reliability (production) coexist.
